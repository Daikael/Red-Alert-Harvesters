-- Physical drive for type=car harvesters on Factorio 2.0.
-- Cars are not LuaCommandable (units / spider-vehicles only). Spidertron
-- autopilot_destination does not exist on these prototypes. Movement is
-- LuaSurface.request_path + riding_state (real car physics, collisions).
-- Never vehicle.teleport / heading-step fakes.
-- Auto ON writes riding_state with an empty driver seat. A player in the
-- driver seat beats scripted riding_state (WASD/controller joyride), so
-- demote them to passenger. Pause-on-enter is the only driver-seat yield.

AutoDrive = AutoDrive or {}

-- Assignment: nearest indexed chunk on this surface (no 8-chunk / 256-tile
-- cap). Path failure uses the existing repath → other patch → home ladder.
-- 1e7 tiles is "the whole map" for find_ore_chunks distance checks.
AutoDrive.RANGE_TILES = 10000000
-- After a scoop, try nearby first, then expand to RANGE_TILES.
AutoDrive.RANGE_NEAR_TILES = 96
-- Hybrid pool + grid + tank below this → drive home for fuel (10% of 80 MJ).
AutoDrive.FUEL_LOW_J = 8000000
-- Pathfinder goal radius (tiles). Home pad is looser so a blocked chest-side
-- approach still counts; ore entity stays tight.
AutoDrive.PATH_RADIUS_ORE = 4
AutoDrive.PATH_RADIUS_ORE_ENTITY = 1.5
AutoDrive.PATH_RADIUS_HOME = 10
-- Advance to the next waypoint / declare arrival.
AutoDrive.WAYPOINT_TILES = 4.5
AutoDrive.ARRIVE_TILES = 3.0
AutoDrive.ARRIVE_ORE_ENTITY = 1.25
AutoDrive.ARRIVE_HOME = 8
-- Close enough to the refinery entity to dump/refuel (chest-side 7-tile stall).
AutoDrive.DOCK_ACCEPT_TILES = 8
-- Always path with the car collision_box at resolution 0. A biter-sized box
-- plus a coarse grid (tried in 2.2.0) returned paths the 2.8-wide car cannot
-- follow, which exhausted OnPathFail and spammed stuck alerts.
AutoDrive.LONG_PATH_TILES = 48
AutoDrive.PATH_RES_LONG = 0
AutoDrive.UNIT_PATH_BOX = {{-1.4, -1.4}, {1.4, 1.4}}
-- Trees that threaten the hull. Destroy if the trunk cannot take the wood.
AutoDrive.TREE_CLEAR_RADIUS = 8
AutoDrive.TREE_CLEAR_INTERVAL = 5
AutoDrive.TREE_CLEAR_MAX = 4
AutoDrive.TREE_TOUCH_TILES = 3.0
-- After a real stuck alert, wait before retrying so floating text does not spam.
AutoDrive.STUCK_RETRY_TICKS = 300
-- North is the dump / belt / circuit face (collision to y=-3). South is chest.
AutoDrive.DOCK_OFFSETS = {
	{0.75, -5.5},
	{0.75, -9.0},
	{-4.5, -3.5},
	{6.5, -3.5},
	{0.75, 4.0},
}
-- MiningOre: walk onto a resource if we landed off-patch.
AutoDrive.MINE_SENSE_TILES = 4
AutoDrive.ORE_RETARGET_MAX = 3
AutoDrive.ORE_NEAR_TILES = 16
-- Stuck: no 0.75-tile progress for 3 seconds @ 60 UPS.
AutoDrive.STUCK_TICKS = 180
AutoDrive.STUCK_MIN_MOVE = 0.75
-- Do not assign two trucks onto the same patch. 16 tiles = half a chunk.
AutoDrive.PEER_EXCLUDE_TILES = 16
-- Runtime / path check: keep centers ~4 tiles apart (truck is 2.8 wide).
AutoDrive.PEER_CLEARANCE_TILES = 4
AutoDrive.PATH_BLOCKER = "cncharvester-path-blocker"
AutoDrive.PEER_LAYER = "cncharvester-peer"
-- Escalation (implementer-tunable; documented in FACTORIO_2.2.md).
AutoDrive.REPATH_MAX = 3
AutoDrive.ALT_PATCH_MAX = 3
AutoDrive.HOME_REPATH_MAX = 5
AutoDrive.FAILED_CHUNK_TTL = 18000
AutoDrive.ALERT_COOLDOWN = 3600
AutoDrive.BUSY_RETRY_TICKS = 30
-- Peer pin: reverse ~1.5 s (~4–8 tiles) if the rear is clear, then repath.
AutoDrive.REVERSE_TICKS = 90
AutoDrive.REVERSE_CHECK_TILES = 6
-- Facing: orientation is 0..1. ~0.04 ≈ 14°. Above this, rotate in place
-- (tank_driving + acceleration nothing) instead of creeping forward to turn.
AutoDrive.TURN_DEADZONE = 0.04
AutoDrive.TURN_HARD = 0.12
AutoDrive.ALIGN_SPEED = 0.08

local riding_acc = defines and defines.riding and defines.riding.acceleration
local riding_dir = defines and defines.riding and defines.riding.direction

function AutoDrive.chunk_key(si, x, y)
	return tostring(si) .. ":" .. tostring(x) .. ":" .. tostring(y)
end

function AutoDrive.wrap01(v)
	v = v % 1
	if v < 0 then
		v = v + 1
	end
	return v
end

-- Signed delta in (-0.5, 0.5]. Positive = clockwise = riding.direction.right.
function AutoDrive.orientation_delta(current, target)
	local d = AutoDrive.wrap01((target or 0) - (current or 0))
	if d > 0.5 then
		d = d - 1
	end
	return d
end

-- Unit facing. orientation 0 = north; +x is east.
function AutoDrive.facing_xy(orientation)
	local ang = (orientation or 0) * 2 * math.pi
	return math.sin(ang), -math.cos(ang)
end

-- Pure riding plan: align in place, then accelerate. accel is
-- "accelerating" / "braking" / "nothing"; dir is "left" / "right" / "straight".
function AutoDrive.steer_plan(speed, delta)
	local ad = math.abs(delta or 0)
	local dir = "straight"
	if (delta or 0) > AutoDrive.TURN_DEADZONE then
		dir = "right"
	elseif (delta or 0) < -AutoDrive.TURN_DEADZONE then
		dir = "left"
	end
	if ad <= AutoDrive.TURN_DEADZONE then
		return "accelerating", dir
	end
	local spd = math.abs(speed or 0)
	if spd >= AutoDrive.ALIGN_SPEED and ad > AutoDrive.TURN_HARD then
		return "braking", dir
	end
	return "nothing", dir
end

-- request_path is the unit/biter algorithm, but the traveler is a car.
-- Always use the car box and 1-tile resolution so waypoints are driveable.
function AutoDrive.path_request_plan(start, goal, precise)
	return "car", 0
end

-- True while tank-rotating: do not treat that as a no-progress stuck.
function AutoDrive.aligning_in_place(speed, delta)
	return math.abs(delta or 0) > AutoDrive.TURN_DEADZONE
		and math.abs(speed or 0) < AutoDrive.ALIGN_SPEED
end

function AutoDrive.dock_goal(origin, try_n)
	local offsets = AutoDrive.DOCK_OFFSETS
	local i = ((try_n or 0) % #offsets) + 1
	local off = offsets[i]
	return {x = (origin.x or 0) + off[1], y = (origin.y or 0) + off[2]}
end

function AutoDrive.near_dock(pos, refinery_pos)
	if not (pos and refinery_pos) then
		return false
	end
	local dx = (pos.x or 0) - (refinery_pos.x or 0)
	local dy = (pos.y or 0) - (refinery_pos.y or 0)
	local r = AutoDrive.DOCK_ACCEPT_TILES
	return (dx * dx + dy * dy) <= (r * r)
end

-- Collision-threat flora: touching / beside, or anywhere ahead in the bubble.
function AutoDrive.tree_is_threat(dx, dy, fx, fy)
	local dist = math.sqrt((dx or 0) * (dx or 0) + (dy or 0) * (dy or 0))
	if dist < 0.05 or dist > AutoDrive.TREE_CLEAR_RADIUS then
		return false
	end
	local along = (dx * fx + dy * fy) / dist
	if dist <= AutoDrive.TREE_TOUCH_TILES then
		return along >= -0.2
	end
	return along > 0
end

-- Mine into the trunk when there is room; otherwise destroy so the hull can move.
function AutoDrive.remove_tree(tree, inv)
	if not (tree and tree.valid) then
		return false
	end
	if inv and inv.valid then
		local full = inv.is_full and inv.is_full()
		if not full then
			local ok, res = pcall(function()
				return tree.mine{inventory = inv, force = false, raise_destroyed = true}
			end)
			if ok and res then
				return true
			end
		end
	end
	if pcall(function()
		tree.destroy({raise_destroy = true})
	end) then
		return true
	end
	return pcall(function()
		tree.destroy()
	end)
end

function AutoDrive.clear_nearby_trees(vehicle, rec, tick)
	if not (vehicle and vehicle.valid) then
		return 0
	end
	if rec and rec.tree_tick and tick and (tick - rec.tree_tick) < AutoDrive.TREE_CLEAR_INTERVAL then
		return 0
	end
	if rec then
		rec.tree_tick = tick
	end
	local surface = vehicle.surface
	if not (surface and surface.find_entities_filtered) then
		return 0
	end
	local pos = vehicle.position
	local fx, fy = AutoDrive.facing_xy(vehicle.orientation)
	local ok, trees = pcall(function()
		return surface.find_entities_filtered{
			type = "tree",
			position = pos,
			radius = AutoDrive.TREE_CLEAR_RADIUS,
		}
	end)
	if not ok or not trees then
		return 0
	end
	local inv
	pcall(function()
		if vehicle.get_inventory and defines and defines.inventory then
			inv = vehicle.get_inventory(defines.inventory.car_trunk)
		end
	end)
	local n = 0
	for _, tree in pairs(trees) do
		if n >= AutoDrive.TREE_CLEAR_MAX then
			break
		end
		if tree and tree.valid and tree.position then
			local tp = tree.position
			if AutoDrive.tree_is_threat(tp.x - pos.x, tp.y - pos.y, fx, fy) then
				if AutoDrive.remove_tree(tree, inv) then
					n = n + 1
				end
			end
		end
	end
	return n
end

function AutoDrive.commandable_of(entity)
	if not (entity and entity.valid) then
		return nil
	end
	local ok, cmd = pcall(function()
		return entity.commandable
	end)
	if ok and cmd then
		return cmd
	end
	return nil
end

function AutoDrive.tib_tech_researched(force)
	if not force then
		return false
	end
	local tech = force.technologies and force.technologies["Tiberium-Harvesting"]
	return tech ~= nil and tech.researched == true
end

function AutoDrive.allow_tib(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	if vehicle.name ~= "cncharvester-type2" then
		return false
	end
	return AutoDrive.tib_tech_researched(vehicle.force)
end

-- LuaPlayer in the seat, or a character that has a connected player.
-- Do not call the LuaControl is_player method: it is only true for LuaPlayer
-- objects, and a pcall-true on the wrong object would stick occupying.
local function occupant_is_player(obj)
	if obj == nil then
		return false
	end
	if obj.object_name == "LuaPlayer" then
		return obj.valid ~= false
	end
	if obj.valid then
		local p = obj.player
		if p and p.valid then
			return true
		end
	end
	return false
end

local function seat_occupant(vehicle, getter)
	if not getter then
		return nil
	end
	local ok, occupant = pcall(function()
		return getter(vehicle)
	end)
	if ok then
		return occupant
	end
	ok, occupant = pcall(getter)
	if ok then
		return occupant
	end
	return nil
end

-- True only if a player is actually in this vehicle (driver or passenger).
function AutoDrive.player_occupying(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	if occupant_is_player(seat_occupant(vehicle, vehicle.get_driver)) then
		return true
	end
	if occupant_is_player(seat_occupant(vehicle, vehicle.get_passenger)) then
		return true
	end
	local players = game and game.connected_players
	if not players then
		return false
	end
	for _, player in pairs(players) do
		if player.valid and player.driving and player.vehicle and player.vehicle.valid and player.vehicle == vehicle then
			return true
		end
	end
	return false
end

function AutoDrive.player_is_driver(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	return occupant_is_player(seat_occupant(vehicle, vehicle.get_driver))
end

local function occupant_as_rider(obj)
	if obj == nil then
		return nil, nil
	end
	if obj.object_name == "LuaPlayer" and obj.valid ~= false then
		return obj, obj.character
	end
	if obj.valid then
		local p = obj.player
		if p and p.valid then
			return p, obj
		end
	end
	return nil, nil
end

-- Factorio gives the driver seat priority over scripted riding_state.
-- Demote the player to passenger so they stay aboard but cannot steer.
-- Never assign player.driving to false (that dumps them on the ground).
-- Returns "passenger", "ground", or false.
function AutoDrive.demote_driver_to_passenger(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	if not AutoDrive.player_is_driver(vehicle) then
		return false
	end
	local driver = seat_occupant(vehicle, vehicle.get_driver)
	local player, character = occupant_as_rider(driver)
	if not player then
		return false
	end
	local allow_passengers = true
	local ok_proto, proto = pcall(function()
		return vehicle.prototype
	end)
	if ok_proto and proto and proto.allow_passengers == false then
		allow_passengers = false
	end
	-- Empty the driver seat so AI riding_state can win. Prefer passenger
	-- immediately after; ground only if this car cannot take a passenger.
	pcall(function()
		vehicle.set_driver(nil)
	end)
	if allow_passengers then
		local rider = character or player
		pcall(function()
			vehicle.set_passenger(rider)
		end)
		if occupant_is_player(seat_occupant(vehicle, vehicle.get_passenger)) then
			if AutoDrive.player_is_driver(vehicle) then
				pcall(function()
					vehicle.set_driver(nil)
				end)
			end
			return "passenger"
		end
		pcall(function()
			vehicle.set_passenger(player)
		end)
		if occupant_is_player(seat_occupant(vehicle, vehicle.get_passenger)) then
			if AutoDrive.player_is_driver(vehicle) then
				pcall(function()
					vehicle.set_driver(nil)
				end)
			end
			return "passenger"
		end
	end
	return "ground"
end

function AutoDrive.player_driving(vehicle)
	return AutoDrive.player_occupying(vehicle)
end

-- Auto ON owns the wheel unless pause-on-enter AND a player is the driver.
-- A passenger must not block riding_state.
function AutoDrive.ai_may_steer(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local h = storage and storage.cncharvesters and vehicle.unit_number and storage.cncharvesters[vehicle.unit_number]
	local auto_on = h and h.auto_enabled ~= false
	if auto_on then
		if AutoDrive.player_is_driver(vehicle) and h.pause_on_enter == true then
			return false
		end
		return true
	end
	return not AutoDrive.player_is_driver(vehicle)
end

local function write_riding(vehicle, acceleration, direction)
	if not (vehicle and vehicle.valid and riding_acc and riding_dir) then
		return
	end
	if not AutoDrive.ai_may_steer(vehicle) then
		return
	end
	vehicle.riding_state = {
		acceleration = acceleration,
		direction = direction,
	}
end

local function write_riding_keys(vehicle, accel_key, dir_key)
	if not (riding_acc and riding_dir) then
		return
	end
	local accel = riding_acc.accelerating
	if accel_key == "braking" then
		accel = riding_acc.braking
	elseif accel_key == "nothing" then
		accel = riding_acc.nothing
	elseif accel_key == "reversing" then
		accel = riding_acc.reversing
	end
	local dir = riding_dir.straight
	if dir_key == "left" then
		dir = riding_dir.left
	elseif dir_key == "right" then
		dir = riding_dir.right
	end
	write_riding(vehicle, accel, dir)
end

function AutoDrive.stop(vehicle)
	write_riding_keys(vehicle, "braking", "straight")
end

function AutoDrive.release(vehicle)
	write_riding_keys(vehicle, "nothing", "straight")
end

function AutoDrive.collision_box(entity)
	local proto = entity and entity.valid and entity.prototype
	if proto and proto.collision_box then
		return proto.collision_box
	end
	return {{-1.4, -1.4}, {1.4, 1.4}}
end

function AutoDrive.collision_mask(entity)
	local proto = entity and entity.valid and entity.prototype
	if proto and proto.collision_mask then
		return proto.collision_mask
	end
	return nil
end

-- 2.0.77 unit pathfinder does not reliably treat type=car as obstacles
-- (off-grid vehicles). Requests union a private collision layer and we
-- spawn hidden simple-entity blockers on sibling trucks. entity_to_ignore
-- is only self — never other cncharvester / cncharvester-type2.
function AutoDrive.path_collision_mask(entity)
	local mask = AutoDrive.collision_mask(entity)
	if not mask then
		return nil
	end
	local layers = {}
	if mask.layers then
		for name, on in pairs(mask.layers) do
			layers[name] = on
		end
	end
	layers[AutoDrive.PEER_LAYER] = true
	return {layers = layers}
end

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

function AutoDrive.is_harvester_name(name)
	return name ~= nil and HARVESTER_NAMES[name] == true
end

function AutoDrive.each_peer(vehicle, fn)
	if not (vehicle and vehicle.valid and storage and storage.cncharvesters) then
		return
	end
	local self_id = vehicle.unit_number
	local surface = vehicle.surface
	for id, h in pairs(storage.cncharvesters) do
		if id ~= self_id then
			local other = h and h.vehicle
			if other and other.valid and other.surface == surface then
				fn(h, other)
			end
		end
	end
end

function AutoDrive.peer_blocks_assignment(vehicle, si, cx, cy, center)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local exclude = AutoDrive.PEER_EXCLUDE_TILES
	local exclude_sq = exclude * exclude
	local blocked = false
	AutoDrive.each_peer(vehicle, function(h, other)
		if blocked then
			return
		end
		local pos = other.position
		if center and pos then
			local dx = (pos.x or 0) - (center.x or 0)
			local dy = (pos.y or 0) - (center.y or 0)
			if dx * dx + dy * dy <= exclude_sq then
				blocked = true
				return
			end
		end
		if h.going_home then
			return
		end
		if h.assign_si == si and h.assign_cx == cx and h.assign_cy == cy then
			blocked = true
		end
	end)
	return blocked
end

function AutoDrive.clear_path_blockers(vehicle)
	local rec = storage and storage.cncharvesters and vehicle and vehicle.unit_number and storage.cncharvesters[vehicle.unit_number]
	local list = rec and rec.path_blockers
	if not list then
		return
	end
	for i = 1, #list do
		local ent = list[i]
		if ent and ent.valid then
			pcall(function()
				ent.destroy()
			end)
		end
	end
	rec.path_blockers = nil
end

function AutoDrive.destroy_orphan_blockers(surface)
	if not (surface and surface.valid) then
		return
	end
	local found = surface.find_entities_filtered{name = AutoDrive.PATH_BLOCKER}
	for _, ent in pairs(found) do
		if ent.valid then
			pcall(function()
				ent.destroy()
			end)
		end
	end
end

function AutoDrive.spawn_path_blockers(vehicle)
	AutoDrive.clear_path_blockers(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local rec = storage and storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
	if not rec then
		return
	end
	local surface = vehicle.surface
	if not (surface and surface.valid) then
		return
	end
	local list = {}
	AutoDrive.each_peer(vehicle, function(_, other)
		local pos = other.position
		local ok, ent = pcall(function()
			return surface.create_entity{
				name = AutoDrive.PATH_BLOCKER,
				position = pos,
				force = "neutral",
				create_build_effect_smoke = false,
			}
		end)
		if ok and ent and ent.valid then
			list[#list + 1] = ent
		end
	end)
	if #list > 0 then
		rec.path_blockers = list
	end
end

function AutoDrive.path_hits_peer(path, vehicle)
	if not (path and vehicle and vehicle.valid) then
		return false
	end
	local clear_sq = AutoDrive.PEER_CLEARANCE_TILES * AutoDrive.PEER_CLEARANCE_TILES
	local hit = false
	AutoDrive.each_peer(vehicle, function(_, other)
		if hit then
			return
		end
		local pos = other.position
		for i = 1, #path do
			local wp = path[i]
			if wp and wp.needs_destroy_to_reach then
				hit = true
				return
			end
			local p = wp and (wp.position or wp)
			if p and p.x ~= nil then
				local dx = p.x - pos.x
				local dy = p.y - pos.y
				if dx * dx + dy * dy <= clear_sq then
					hit = true
					return
				end
			end
		end
	end)
	if hit then
		return true
	end
	for i = 1, #path do
		if path[i] and path[i].needs_destroy_to_reach then
			return true
		end
	end
	return false
end

-- True when another harvester is in front inside the clearance bubble.
-- Brake; do not keep writing accelerating riding_state into them.
function AutoDrive.blocked_by_peer(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local pos = vehicle.position
	local fx, fy = AutoDrive.facing_xy(vehicle.orientation)
	local clear = AutoDrive.PEER_CLEARANCE_TILES
	local clear_sq = clear * clear
	local blocked = false
	AutoDrive.each_peer(vehicle, function(_, other)
		if blocked then
			return
		end
		local op = other.position
		local dx, dy = op.x - pos.x, op.y - pos.y
		local dsq = dx * dx + dy * dy
		if dsq > clear_sq or dsq < 0.01 then
			return
		end
		local dist = math.sqrt(dsq)
		local ahead = (dx * fx + dy * fy) / dist
		if ahead > 0.25 then
			blocked = true
		end
	end)
	return blocked
end

-- True when no sibling sits behind inside REVERSE_CHECK_TILES.
function AutoDrive.rear_clear(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local pos = vehicle.position
	local fx, fy = AutoDrive.facing_xy(vehicle.orientation)
	local r = AutoDrive.REVERSE_CHECK_TILES
	local r_sq = r * r
	local blocked = false
	AutoDrive.each_peer(vehicle, function(_, other)
		if blocked then
			return
		end
		local op = other.position
		local dx, dy = op.x - pos.x, op.y - pos.y
		local dsq = dx * dx + dy * dy
		if dsq > r_sq or dsq < 0.01 then
			return
		end
		local dist = math.sqrt(dsq)
		local along = (dx * fx + dy * fy) / dist
		if along < -0.2 then
			blocked = true
		end
	end)
	return not blocked
end

-- Reverse away from a peer on the right by peeling left (and vice versa).
function AutoDrive.peer_peel_direction(vehicle)
	if not (vehicle and vehicle.valid) then
		return "right"
	end
	local pos = vehicle.position
	local fx, fy = AutoDrive.facing_xy(vehicle.orientation)
	local side_sum = 0
	local r = AutoDrive.REVERSE_CHECK_TILES
	AutoDrive.each_peer(vehicle, function(_, other)
		local op = other.position
		local dx, dy = op.x - pos.x, op.y - pos.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist < 0.1 or dist > r then
			return
		end
		local along = (dx * fx + dy * fy) / dist
		if along > 0.15 then
			side_sum = side_sum + (dx * (-fy) + dy * fx)
		end
	end)
	if side_sum > 0 then
		return "left"
	end
	return "right"
end

function AutoDrive.clear_wiggle(rec)
	if not rec then
		return
	end
	rec.reverse_until = nil
	rec.reverse_steer = nil
end

function AutoDrive.steer_reverse_wiggle(vehicle, rec)
	write_riding_keys(vehicle, "reversing", rec and rec.reverse_steer or "right")
end

-- Peer pin during MovingToLocation. "reverse" / "wait" / "clear" / "repath".
function AutoDrive.tick_peer_block(rec, vehicle, tick)
	if not rec then
		return "clear"
	end
	tick = tick or 0
	if rec.reverse_until then
		if tick < rec.reverse_until then
			AutoDrive.steer_reverse_wiggle(vehicle, rec)
			return "reverse"
		end
		AutoDrive.clear_wiggle(rec)
		return "repath"
	end
	if not (vehicle and vehicle.valid) then
		return "clear"
	end
	if not AutoDrive.blocked_by_peer(vehicle) then
		return "clear"
	end
	AutoDrive.stop(vehicle)
	if AutoDrive.rear_clear(vehicle) then
		rec.reverse_until = tick + AutoDrive.REVERSE_TICKS
		rec.reverse_steer = AutoDrive.peer_peel_direction(vehicle)
		AutoDrive.steer_reverse_wiggle(vehicle, rec)
		if vehicle.position then
			AutoDrive.progress_reset(rec, vehicle.position, tick)
		end
		return "reverse"
	end
	return "wait"
end

function AutoDrive.request(surface, entity, goal, radius, opts)
	if not (surface and surface.valid and entity and entity.valid and goal) then
		return nil
	end
	local mask = AutoDrive.path_collision_mask(entity)
	if not mask then
		return nil
	end
	AutoDrive.spawn_path_blockers(entity)
	local _, res = AutoDrive.path_request_plan(entity.position, goal, opts and opts.precise)
	local box = AutoDrive.collision_box(entity)
	local ok, id = pcall(function()
		return surface.request_path{
			bounding_box = box,
			collision_mask = mask,
			start = entity.position,
			goal = goal,
			force = entity.force,
			radius = radius or AutoDrive.PATH_RADIUS_ORE,
			can_open_gates = true,
			path_resolution_modifier = res,
			max_gap_size = 0,
			entity_to_ignore = entity,
			pathfind_flags = {
				cache = false,
				prefer_straight_paths = true,
				allow_destroy_friendly_entities = false,
				allow_paths_through_own_entities = false,
			},
		}
	end)
	if ok then
		return id
	end
	AutoDrive.clear_path_blockers(entity)
	return nil
end

local function waypoint_pos(wp)
	if not wp then
		return nil
	end
	if wp.position then
		return wp.position
	end
	if wp.x ~= nil then
		return wp
	end
	return nil
end

function AutoDrive.steer_toward(vehicle, dest)
	if not (vehicle and vehicle.valid and dest) then
		return false
	end
	if not AutoDrive.ai_may_steer(vehicle) then
		return false
	end
	local pos = vehicle.position
	local dx = dest.x - pos.x
	local dy = dest.y - pos.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 0.05 then
		AutoDrive.stop(vehicle)
		return true
	end
	local want = DeltaposToOrientation({x = dx, y = dy})
	local delta = AutoDrive.orientation_delta(vehicle.orientation, want)
	local accel_key, dir_key = AutoDrive.steer_plan(vehicle.speed, delta)
	write_riding_keys(vehicle, accel_key, dir_key)
	return false
end

function AutoDrive.follow_path(vehicle, path, path_index, arrive_tiles)
	arrive_tiles = arrive_tiles or AutoDrive.ARRIVE_TILES
	if not (vehicle and vehicle.valid and path and path_index) then
		return path_index, false, true
	end
	if not AutoDrive.ai_may_steer(vehicle) then
		return path_index, false, true
	end
	local wp = waypoint_pos(path[path_index])
	while wp do
		local dist = Vector.dist(vehicle.position, wp)
		local last = path_index >= #path
		local limit = last and arrive_tiles or AutoDrive.WAYPOINT_TILES
		if dist <= limit then
			path_index = path_index + 1
			wp = waypoint_pos(path[path_index])
		else
			break
		end
	end
	if not wp then
		AutoDrive.stop(vehicle)
		return path_index, true, false
	end
	if AutoDrive.blocked_by_peer(vehicle) then
		AutoDrive.stop(vehicle)
		return path_index, false, false
	end
	AutoDrive.steer_toward(vehicle, wp)
	return path_index, false, false
end

function AutoDrive.progress_reset(rec, pos, tick)
	rec.stuck_x = pos.x
	rec.stuck_y = pos.y
	rec.stuck_tick = tick
end

function AutoDrive.progress_ok(rec, pos, tick)
	if not rec.stuck_tick then
		AutoDrive.progress_reset(rec, pos, tick)
		return true
	end
	local dx = pos.x - (rec.stuck_x or pos.x)
	local dy = pos.y - (rec.stuck_y or pos.y)
	if (dx * dx + dy * dy) >= (AutoDrive.STUCK_MIN_MOVE * AutoDrive.STUCK_MIN_MOVE) then
		AutoDrive.progress_reset(rec, pos, tick)
		return true
	end
	return (tick - rec.stuck_tick) < AutoDrive.STUCK_TICKS
end

function AutoDrive.ensure_pending()
	storage.autodrive_pending = storage.autodrive_pending or {}
	return storage.autodrive_pending
end

function AutoDrive.remember_request(path_id, unit_number)
	if not path_id or not unit_number then
		return
	end
	AutoDrive.ensure_pending()[path_id] = unit_number
end

function AutoDrive.take_request(path_id)
	local pending = storage.autodrive_pending
	if not pending then
		return nil
	end
	local id = pending[path_id]
	pending[path_id] = nil
	return id
end

function AutoDrive.alert(vehicle, home, deposit, message)
	if not (vehicle and vehicle.valid) then
		return
	end
	local force = vehicle.force
	if not force then
		return
	end
	local icon_home = {type = "item", name = "refinery"}
	local icon_miner = {type = "item", name = vehicle.name}
	local players = force.connected_players or force.players or {}
	for _, player in pairs(players) do
		if player.valid and player.add_custom_alert then
			if home and home.valid then
				pcall(function()
					player.add_custom_alert(home, icon_home, {"cncharvester.auto-stuck-home"}, true)
				end)
			end
			local red = (deposit and deposit.valid) and deposit or vehicle
			pcall(function()
				player.add_custom_alert(red, icon_miner, message or {"cncharvester.auto-stuck-miner"}, true)
			end)
		end
	end
	if force.print then
		force.print({"cncharvester.auto-stuck-print", vehicle.unit_number or 0})
	end
end
