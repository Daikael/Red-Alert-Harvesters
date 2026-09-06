require "utilities"
require "chunksearcher"
require "modulebay"
require "scoop"
require "hybriddrive"
require "harvester"
require "specialOres"

local auto_harvester_enabled = settings.startup["Auto-cncharvester-testing"].value

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

local HARVESTER_MINE_RADIUS = {
	["cncharvester"] = 1,
	["cncharvester-type2"] = 2,
}

-- Player-in-vehicle scoop cadence (frequency only — not ore per scoop).
-- First 2.0 drop: on_nth_tick(60) × 10 = 600 ticks = 10s.
-- 320 ticks ≈ 5.33s at 60 UPS → 600/320 = 1.875× (tester-approved).
-- 2.1: countdown is equivalent to on_nth_tick(320); speed/quality may shorten from this base.
-- Volume stays Scoop.DRIVE_ITEMS_PER_SCOOP (4). Unload stays on a 60-tick poll.
local DRIVE_MINE_PERIOD_TICKS = 320

local function ensure_storage()
	storage.tibchunk = storage.tibchunk or {}
	storage.orechunk = storage.orechunk or {}
	storage.cncharvesters = storage.cncharvesters or {}
	storage.refineries = storage.refineries or {}
	storage.drive_scoop_wait = storage.drive_scoop_wait or {}
	ModuleBay.ensure_storage()
	HybridDrive.ensure_storage()
end

local function track_harvester(ent)
	if not (ent and ent.valid and HARVESTER_NAMES[ent.name]) then
		return
	end
	ModuleBay.ensure(ent)
	HybridDrive.prepare_vehicle(ent)
	if auto_harvester_enabled and not storage.cncharvesters[ent.unit_number] then
		storage.cncharvesters[ent.unit_number] = cncharvester.New(ent)
	end
end

script.on_init(function()
	ensure_storage()
	ModuleBay.attach_existing()
end)

script.on_configuration_changed(function()
	ensure_storage()
	ModuleBay.attach_existing()
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
	local ent = event.entity or event.created_entity or event.destination
	if not (ent and ent.valid) then return end
	if HARVESTER_NAMES[ent.name] then
		track_harvester(ent)
		-- Player-built: consume 1 coal/wood from the placer if they have it.
		-- Otherwise no free items — only a tiny joule spark so Hybrid can start.
		local player = event.player_index and game.get_player(event.player_index)
		if player and player.valid then
			HybridDrive.try_take_player_kickoff(ent, player)
		end
		HybridDrive.apply_spark_if_empty(ent)
	elseif ent.name == "refinery" and auto_harvester_enabled then
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

script.on_event(defines.events.on_player_driving_changed_state, function(event)
	local ent = event.entity
	if ent and ent.valid and HARVESTER_NAMES[ent.name] then
		track_harvester(ent)
		HybridDrive.prepare_vehicle(ent)
		HybridDrive.auto_equip(ent)
	end
end)

script.on_event("cncharvester-open-module-bay", function(event)
	local player = game.get_player(event.player_index)
	ModuleBay.open_for_player(player)
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
	local wait = storage.drive_scoop_wait[player.index] or 0
	if wait > 0 then
		storage.drive_scoop_wait[player.index] = wait - 1
		return
	end

	local effects = Scoop.read_effects(vehicle)
	local qlevel = Scoop.quality_level(vehicle.quality)
	-- Base 320 ticks (= on_nth_tick(320)); modules/quality may shorten.
	storage.drive_scoop_wait[player.index] = Scoop.interval_ticks(
		DRIVE_MINE_PERIOD_TICKS,
		effects.speed,
		qlevel
	)

	local radius = Scoop.radius(HARVESTER_MINE_RADIUS[vehicle.name] or 1, qlevel)
	local ores = vehicle.surface.find_entities_filtered {
		type = "resource",
		area = GetBoundingBox(vehicle.position, radius)
	}
	local harvestable = {}
	for _, entity in pairs(ores) do
		if IsHarvestableResource(entity) then
			table.insert(harvestable, entity)
		end
	end
	if #harvestable == 0 then
		return
	end
	local result = Scoop.harvest_area(vehicle, harvestable, Scoop.DRIVE_ITEMS_PER_SCOOP)
	if result.full and not result.inserted then
		DrawFloatingText(vehicle.surface, vehicle, "Inventory full", FLOATING_TEXT_ERROR_RED, FLOATING_TEXT_ERROR_TTL)
	end
end

-- Hybrid-drive and module-bay sync need every tick. Drive scoop uses a 320-tick
-- countdown (same cadence as master's on_nth_tick(320) when unmodified).
script.on_nth_tick(1, function()
	ensure_storage()

	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name] then
			track_harvester(vehicle)
		end
	end

	if game.tick % 5 == 0 then
		ModuleBay.sync_all()
	end

	for _, rec in pairs(storage.module_bays or {}) do
		if rec.vehicle and rec.vehicle.valid then
			HybridDrive.tick(rec.vehicle)
		end
	end

	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name] then
			drive_harvest(player, vehicle)
			if game.tick % 60 == 0 then
				unload_near_refinery(vehicle)
			end
		end
	end

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
