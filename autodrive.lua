-- Physical drive for type=car harvesters on Factorio 2.0.
-- Cars are not LuaCommandable (units / spider-vehicles only). Spidertron
-- autopilot_destination does not exist on these prototypes. Movement is
-- LuaSurface.request_path + riding_state (real car physics, collisions).
-- Never vehicle.teleport / heading-step fakes.
-- Auto ON overwrites riding_state even if a player occupies (pause-on-enter
-- is the only yield).

AutoDrive = AutoDrive or {}

-- Temporary assignment range until the M2 depot exists. 256 tiles = 8 chunks.
AutoDrive.RANGE_TILES = 256
-- After a scoop, prefer a nearby patch so the truck does not re-cross the map.
AutoDrive.RANGE_NEAR_TILES = 96
-- Hybrid pool + grid + tank below this → drive home for fuel (10% of 80 MJ).
AutoDrive.FUEL_LOW_J = 8000000
-- Pathfinder goal radius (tiles). Home pad is tight; chunk-center ore can be
-- looser. A known resource entity uses a tight radius so we do not stop 4
-- tiles off the patch.
AutoDrive.PATH_RADIUS_ORE = 4
AutoDrive.PATH_RADIUS_ORE_ENTITY = 1.5
AutoDrive.PATH_RADIUS_HOME = 6
-- Advance to the next waypoint / declare arrival.
AutoDrive.WAYPOINT_TILES = 4.5
AutoDrive.ARRIVE_TILES = 3.0
AutoDrive.ARRIVE_ORE_ENTITY = 1.25
-- MiningOre: walk onto a resource if we landed off-patch.
AutoDrive.MINE_SENSE_TILES = 4
AutoDrive.ORE_RETARGET_MAX = 3
AutoDrive.ORE_NEAR_TILES = 16
-- Stuck: no 0.75-tile progress for 3 seconds @ 60 UPS.
AutoDrive.STUCK_TICKS = 180
AutoDrive.STUCK_MIN_MOVE = 0.75
-- Escalation (implementer-tunable; documented in FACTORIO_2.2.md).
AutoDrive.REPATH_MAX = 3
AutoDrive.ALT_PATCH_MAX = 3
AutoDrive.HOME_REPATH_MAX = 3
AutoDrive.FAILED_CHUNK_TTL = 18000
AutoDrive.ALERT_COOLDOWN = 3600
AutoDrive.BUSY_RETRY_TICKS = 30
-- Facing: orientation is 0..1. ~0.04 ≈ 14°.
AutoDrive.TURN_DEADZONE = 0.04
AutoDrive.TURN_HARD = 0.12

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

-- True only if a player is actually in this vehicle. Empty trucks must be
-- false so Tick / StartDrive / riding_state can run.
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

function AutoDrive.player_driving(vehicle)
	return AutoDrive.player_occupying(vehicle)
end

-- Auto ON owns the wheel unless pause-on-enter is yielding. Occupying must
-- not no-op riding_state or WASD "wins" and auto looks bricked.
function AutoDrive.ai_may_steer(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local h = storage and storage.cncharvesters and vehicle.unit_number and storage.cncharvesters[vehicle.unit_number]
	local auto_on = h and h.auto_enabled ~= false
	if auto_on then
		if AutoDrive.player_occupying(vehicle) and h.pause_on_enter == true then
			return false
		end
		return true
	end
	return not AutoDrive.player_occupying(vehicle)
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

function AutoDrive.stop(vehicle)
	write_riding(vehicle, riding_acc and (riding_acc.braking or riding_acc.nothing), riding_dir and riding_dir.straight)
end

function AutoDrive.release(vehicle)
	write_riding(vehicle, riding_acc and riding_acc.nothing, riding_dir and riding_dir.straight)
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

function AutoDrive.request(surface, entity, goal, radius)
	if not (surface and surface.valid and entity and entity.valid and goal) then
		return nil
	end
	local mask = AutoDrive.collision_mask(entity)
	if not mask then
		return nil
	end
	local ok, id = pcall(function()
		return surface.request_path{
			bounding_box = AutoDrive.collision_box(entity),
			collision_mask = mask,
			start = entity.position,
			goal = goal,
			force = entity.force,
			radius = radius or AutoDrive.PATH_RADIUS_ORE,
			can_open_gates = true,
			path_resolution_modifier = 0,
			max_gap_size = 0,
			entity_to_ignore = entity,
			pathfind_flags = {
				cache = false,
				prefer_straight_paths = true,
			},
		}
	end)
	if ok then
		return id
	end
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
	if not (vehicle and vehicle.valid and dest and riding_acc and riding_dir) then
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
	local ad = math.abs(delta)
	local dir = riding_dir.straight
	if delta > AutoDrive.TURN_DEADZONE then
		dir = riding_dir.right
	elseif delta < -AutoDrive.TURN_DEADZONE then
		dir = riding_dir.left
	end
	local acc = riding_acc.accelerating
	if ad > AutoDrive.TURN_HARD then
		local speed = vehicle.speed or 0
		if math.abs(speed) > 0.08 then
			acc = riding_acc.braking
		else
			acc = riding_acc.accelerating
		end
	end
	write_riding(vehicle, acc, dir)
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
