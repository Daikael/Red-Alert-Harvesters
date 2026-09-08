require "utilities"
require "chunkindex"
require "autodrive"
require "modulebay"
require "scoop"
require "hybriddrive"
require "harvester"
require "specialOres"

-- Console cannot see ChunkIndex (mod sandbox). Use remote.call from /c:
-- /c game.print(serpent.line(remote.call("Red-Alert-Harvester", "chunkindex_stats")))
-- /c game.print(tostring(remote.call("Red-Alert-Harvester", "chunkindex_enabled")))
-- /c remote.call("Red-Alert-Harvester", "chunkindex_overlay", true)
-- /c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed')))
-- /c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed', true)))
-- /c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed_full')))
remote.add_interface("Red-Alert-Harvester", {
	chunkindex_stats = function()
		return ChunkIndex.debug_stats()
	end,
	chunkindex_enabled = function()
		return ChunkIndex.enabled()
	end,
	chunkindex_overlay = function(on)
		if on ~= nil then
			return ChunkIndex.overlay_set(on and true or false)
		end
		return ChunkIndex.overlay_get()
	end,
	-- Default: missing-only. Pass true / "full" to re-scan already-indexed chunks.
	chunkindex_reseed = function(full)
		return ChunkIndex.reseed(full)
	end,
	chunkindex_reseed_full = function()
		return ChunkIndex.reseed(true)
	end,
	harvester_ai = function()
		local out = {}
		for id, h in pairs(storage.cncharvesters or {}) do
			out[#out + 1] = {
				id = id,
				state = h.state,
				repath_n = h.repath_n,
				alt_n = h.alt_n,
				home_repath_n = h.home_repath_n,
				going_home = h.going_home == true,
				home_early = h.home_early == true,
				range = h.search_range,
				assign = h.assign_cx and {si = h.assign_si, x = h.assign_cx, y = h.assign_cy} or nil,
			}
		end
		return out
	end,
})

-- Same startup flag ChunkIndex.enabled() reads. Teleport autonomy stays disabled;
-- Tick runs physical AutoDrive + ChunkIndex FindingOre when this flag is on.
local auto_harvester_enabled = settings.startup["Auto-cncharvester-testing"].value

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

-- Player-in-vehicle mining runs through the slave miner after a first-sit
-- wait (40 / 20 ticks) so place-on-ore is not free. Unload stays on a 60-tick poll.

local function ensure_storage()
	storage.cncharvesters = storage.cncharvesters or {}
	storage.refineries = storage.refineries or {}
	storage.drive_scoop_wait = storage.drive_scoop_wait or {}
	storage.drive_scoop_vehicle = storage.drive_scoop_vehicle or {}
	ChunkIndex.ensure_storage()
	ModuleBay.ensure_storage()
	HybridDrive.ensure_storage()
end

local function track_harvester(ent)
	if not (ent and ent.valid and HARVESTER_NAMES[ent.name]) then
		return
	end
	ModuleBay.ensure(ent)
	HybridDrive.prepare_vehicle(ent)
	ChunkIndex.watch_harvester(ent)
	if auto_harvester_enabled and not storage.cncharvesters[ent.unit_number] then
		storage.cncharvesters[ent.unit_number] = cncharvester.New(ent)
	end
end

script.on_init(function()
	ensure_storage()
	ModuleBay.attach_existing()
	ChunkIndex.seed_existing()
	ChunkIndex.overlay_sync_shortcuts()
end)

script.on_configuration_changed(function()
	ensure_storage()
	ModuleBay.attach_existing()
	ChunkIndex.seed_existing()
	-- legacy teleport AI disabled; physical AutoDrive runs below when the flag is on.
	if not auto_harvester_enabled then
		return
	end
	for _, surface in pairs(game.surfaces) do
		for _, ent in pairs(surface.find_entities_filtered{name = {"cncharvester", "cncharvester-type2"}}) do
			if not storage.cncharvesters[ent.unit_number] then
				storage.cncharvesters[ent.unit_number] = cncharvester.New(ent)
			end
		end
		for _, ent in pairs(surface.find_entities_filtered{name = "refinery"}) do
			if not storage.refineries[ent.unit_number] then
				storage.refineries[ent.unit_number] = Refinery.New(ent)
			end
		end
	end
end)

local function On_Load()
	if storage.refineries then
		for _, refinery in pairs(storage.refineries) do
			Refinery.Onload(refinery)
		end
	end
	if storage.cncharvesters then
		for _, harvester in pairs(storage.cncharvesters) do
			cncharvester.Onload(harvester)
		end
	end
end
script.on_load(On_Load)

local function On_Built(event)
	ensure_storage()
	local ent = event.entity or event.created_entity or event.destination
	if not (ent and ent.valid) then return end
	if HARVESTER_NAMES[ent.name] then
		track_harvester(ent)
		-- Recipe solar/battery are consumed at craft. Do not insert them (or any
		-- modules/equipment) here — that is a place→strip→recycle exploit.
		local player = event.player_index and game.get_player(event.player_index)
		HybridDrive.on_built(ent, player and player.valid and player or nil)
	end
	if ent.name == "refinery" and auto_harvester_enabled then
		storage.refineries[ent.unit_number] = Refinery.New(ent)
	end
end

local function On_Removed(event)
	local ent = event.entity
	if not (ent and ent.valid) then return end
	if HARVESTER_NAMES[ent.name] then
		ModuleBay.destroy_for_vehicle(ent, event.buffer)
		HybridDrive.scrub_charge_before_remove(ent, event.buffer)
		HybridDrive.forget(ent.unit_number)
		ChunkIndex.unwatch_harvester(ent.unit_number)
		local harvester = storage.cncharvesters and storage.cncharvesters[ent.unit_number]
		if harvester then
			harvester:Delete()
			storage.cncharvesters[ent.unit_number] = nil
			return
		end
		if storage.cncharvesters then
			for id, tracked in pairs(storage.cncharvesters) do
				if tracked.vehicle == ent then
					tracked:Delete()
					storage.cncharvesters[id] = nil
					return
				end
			end
		end
	elseif ModuleBay.NAMES[ent.name] then
		if event.buffer and event.buffer.valid then
			local inv = ent.get_module_inventory()
			if inv then
				for i = 1, #inv do
					local stack = inv[i]
					if stack.valid_for_read then
						event.buffer.insert(stack)
						stack.clear()
					end
				end
			end
		end
		ModuleBay.on_bay_removed(ent)
	elseif ent.name == "refinery" then
		local refinery = storage.refineries and storage.refineries[ent.unit_number]
		if refinery then
			refinery:Delete()
			storage.refineries[ent.unit_number] = nil
			return
		end
		if storage.refineries then
			for id, tracked in pairs(storage.refineries) do
				if tracked.entity == ent then
					tracked:Delete()
					storage.refineries[id] = nil
					return
				end
			end
		end
	end
end

local built_events = {
	defines.events.on_built_entity,
	defines.events.on_robot_built_entity,
	defines.events.script_raised_built,
	defines.events.script_raised_revive,
}
if defines.events.on_space_platform_built_entity then
	table.insert(built_events, defines.events.on_space_platform_built_entity)
end
script.on_event(built_events, On_Built)
script.on_event(defines.events.on_entity_cloned, On_Built)

local removed_events = {
	defines.events.on_player_mined_entity,
	defines.events.on_robot_mined_entity,
	defines.events.on_entity_died,
	defines.events.script_raised_destroy,
}
if defines.events.on_space_platform_mined_entity then
	table.insert(removed_events, defines.events.on_space_platform_mined_entity)
end
script.on_event(removed_events, On_Removed)

script.on_event(defines.events.on_chunk_generated, ChunkIndex.on_chunk_generated)
script.on_event(defines.events.on_pre_chunk_deleted, ChunkIndex.on_chunks_deleted)
script.on_event(defines.events.on_chunk_deleted, ChunkIndex.on_chunks_deleted)
script.on_event(defines.events.on_surface_created, ChunkIndex.on_surface_created)
script.on_event(defines.events.on_player_changed_surface, ChunkIndex.on_player_changed_surface)
script.on_event(defines.events.on_player_created, ChunkIndex.on_player_entered)
script.on_event(defines.events.on_player_joined_game, ChunkIndex.on_player_entered)

script.on_event(defines.events.on_player_driving_changed_state, function(event)
	local ent = event.entity
	if ent and ent.valid and HARVESTER_NAMES[ent.name] then
		track_harvester(ent)
		HybridDrive.prepare_vehicle(ent)
	end
end)

script.on_event("cncharvester-open-module-bay", function(event)
	local player = game.get_player(event.player_index)
	ModuleBay.open_for_player(player)
end)

script.on_event("cncharvester-chunkindex-overlay", function(event)
	local player = game.get_player(event.player_index)
	ChunkIndex.overlay_toggle(player)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
	if event.prototype_name ~= "cncharvester-chunkindex-overlay" then
		return
	end
	local player = game.get_player(event.player_index)
	ChunkIndex.overlay_toggle(player)
end)

script.on_event(defines.events.on_gui_opened, function(event)
	local player = game.get_player(event.player_index)
	local ent = event.entity
	if player and ent and ent.valid and ModuleBay.NAMES[ent.name] then
		ModuleBay.ensure_draw_gui(player, ent)
	end
end)

script.on_event(defines.events.on_gui_closed, function(event)
	local player = game.get_player(event.player_index)
	local ent = event.entity
	if player and ent and ent.valid and ModuleBay.NAMES[ent.name] then
		ModuleBay.close_draw_gui(player)
	end
end)

local function unload_near_refinery(vehicle)
	local surface = vehicle.surface
	local refineries = surface.find_entities_filtered {
		name = "refinery",
		area = GetBoundingBox(vehicle.position, 5)
	}
	if #refineries == 0 then
		return
	end
	local inventory = vehicle.get_inventory(defines.inventory.car_trunk)
	if not inventory then
		return
	end
	EachInventoryItem(inventory, function(name, count, quality)
		local itemstack = InventoryItemStack(name, count, quality)
		for _, refinery in pairs(refineries) do
			if refinery.valid and refinery.can_insert(itemstack) then
				local inserted = refinery.insert(itemstack)
				if inserted > 0 then
					inventory.remove(InventoryItemStack(name, inserted, quality))
				end
				break
			end
		end
	end)
end

local function drive_harvest(player, vehicle)
	storage.drive_scoop_wait = storage.drive_scoop_wait or {}
	storage.drive_scoop_vehicle = storage.drive_scoop_vehicle or {}
	local vehicle_id = vehicle.unit_number
	if storage.drive_scoop_wait[player.index] == nil or storage.drive_scoop_vehicle[player.index] ~= vehicle_id then
		-- First tick in this seat must not mine (place-on-ore free yield).
		storage.drive_scoop_wait[player.index] = Scoop.interval_base(vehicle)
		storage.drive_scoop_vehicle[player.index] = vehicle_id
		ModuleBay.starve(vehicle)
		return
	end
	local wait = storage.drive_scoop_wait[player.index] or 0
	if wait > 0 then
		storage.drive_scoop_wait[player.index] = wait - 1
		ModuleBay.starve(vehicle)
		return
	end

	-- After the first-sit gate, the slave miner runs every tick. Native
	-- mining_speed (1.5 / 3.0) plus modules set the cadence — do not also
	-- apply the old scripted interval_ticks or prod would be bypassed again.
	local result = Scoop.tick_slave(vehicle)
	if result.no_fuel then
		Scoop.toast(vehicle, "cncharvester.out-of-fuel")
		return
	end
	if result.full and not result.inserted then
		Scoop.toast(vehicle, "cncharvester.inventory-full")
	end
end

-- Hybrid pool, slave-miner feed, and hitch teleport run every tick.
script.on_nth_tick(1, function()
	ensure_storage()

	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name] then
			track_harvester(vehicle)
		end
	end

	ModuleBay.sync_all()

	local ticked = {}
	local function tick_hybrid(vehicle)
		if not (vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name]) then
			return
		end
		local id = vehicle.unit_number
		if ticked[id] then
			return
		end
		ticked[id] = true
		HybridDrive.tick(vehicle)
	end
	for _, rec in pairs(storage.module_bays or {}) do
		tick_hybrid(rec.vehicle)
	end
	for _, player in pairs(game.connected_players) do
		tick_hybrid(player.vehicle)
	end
	if storage.cncharvesters then
		for _, harvester in pairs(storage.cncharvesters) do
			tick_hybrid(harvester.vehicle)
		end
	end

	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name] then
			drive_harvest(player, vehicle)
			ModuleBay.refresh_draw_gui(player, vehicle)
			if game.tick % 60 == 0 then
				unload_near_refinery(vehicle)
			end
		end
	end

	ChunkIndex.tick()

	if auto_harvester_enabled then
		if storage.cncharvesters then
			for id, harvester in pairs(storage.cncharvesters) do
				if harvester.vehicle and harvester.vehicle.valid then
					harvester:Tick()
				else
					storage.cncharvesters[id] = nil
				end
			end
		end
		if storage.refineries then
			for id, refinery in pairs(storage.refineries) do
				if refinery.entity and refinery.entity.valid then
					refinery:Tick()
				else
					storage.refineries[id] = nil
				end
			end
		end
	end
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
	local unit_number = AutoDrive.take_request(event.id)
	if not unit_number then
		return
	end
	local harvester = storage.cncharvesters and storage.cncharvesters[unit_number]
	if harvester then
		harvester:OnPathFinished(event)
	end
end)

script.on_event(defines.events.on_entity_damaged, function(event)
	local ent = event.entity
	if not (ent and ent.valid and HARVESTER_NAMES[ent.name]) then
		return
	end
	local harvester = storage.cncharvesters and storage.cncharvesters[ent.unit_number]
	if not harvester then
		return
	end
	local dtype = event.damage_type and event.damage_type.name
	harvester:OnDamaged(dtype)
end)
