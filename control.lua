require "utilities"
require "chunksearcher"
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

local function ensure_storage()
	storage.tibchunk = storage.tibchunk or {}
	storage.orechunk = storage.orechunk or {}
	storage.cncharvesters = storage.cncharvesters or {}
	storage.refineries = storage.refineries or {}
end

local function grid_has_equipment(grid, name)
	if not grid then
		return false
	end
	return grid.find(name) ~= nil
end

script.on_init(function()
	ensure_storage()
end)

script.on_configuration_changed(function()
	ensure_storage()
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
		storage.cncharvesters[ent.unit_number] = cncharvester.New(ent)
	elseif ent.name == "refinery" then
		storage.refineries[ent.unit_number] = Refinery.New(ent)
	end
end

local function On_Removed(event)
	local ent = event.entity
	if not (ent and ent.valid) then return end
	if HARVESTER_NAMES[ent.name] then
		local harvester = storage.cncharvesters[ent.unit_number]
		if harvester then
			harvester:Delete()
			storage.cncharvesters[ent.unit_number] = nil
			return
		end
		for id, tracked in pairs(storage.cncharvesters) do
			if tracked.vehicle == ent then
				tracked:Delete()
				storage.cncharvesters[id] = nil
				return
			end
		end
	elseif ent.name == "refinery" then
		local refinery = storage.refineries[ent.unit_number]
		if refinery then
			refinery:Delete()
			storage.refineries[ent.unit_number] = nil
			return
		end
		for id, tracked in pairs(storage.refineries) do
			if tracked.entity == ent then
				tracked:Delete()
				storage.refineries[id] = nil
				return
			end
		end
	end
end

if auto_harvester_enabled then
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
end

script.on_event(defines.events.on_player_driving_changed_state, function(event)
	local ent = event.entity
	if ent and ent.valid and HARVESTER_NAMES[ent.name] then
		local vehgrid = ent.grid
		if vehgrid and not grid_has_equipment(vehgrid, "Hybrid-drive") then
			vehgrid.put{name = "Hybrid-drive"}
			vehgrid.put{name = "Hybrid-drive-battery"}
		end
	end
end)

-- Player-in-vehicle scoop cadence at 60 UPS:
-- on_nth_tick(60) * DRIVE_MINE_INTERVAL seconds between scoops.
-- First 2.0 drop used 10 (one scoop / 10s). 6 is just under doubled (10/6 ≈ 1.67×).
-- An exact 2× would be 5; keep 6 so it stays "just under 2×".
local DRIVE_MINE_INTERVAL = 6
local mine_timer = 0
local function On_Tick_Driving_Players()
	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name] then
			local surface = vehicle.surface
			local bounding_box_size = HARVESTER_MINE_RADIUS[vehicle.name] or 1
			local ore = surface.find_entities_filtered {
				type = "resource",
				area = GetBoundingBox(vehicle.position, bounding_box_size)
			}

			mine_timer = mine_timer + 1
			if mine_timer >= DRIVE_MINE_INTERVAL then
				mine_timer = 0
				local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
				if trunk then
					local showed_full = false
					for _, entity in pairs(ore) do
						if IsHarvestableResource(entity) then
							local can_insert = false
							for _, product in pairs(entity.prototype.mineable_properties.products) do
								if (not product.type or product.type == "item") and product.name then
									if vehicle.can_insert({name = product.name, count = 4}) then
										can_insert = true
										break
									end
								end
							end
							if can_insert then
								entity.mine({inventory = trunk})
							elseif not showed_full then
								DrawFloatingText(surface, vehicle, "Inventory full", {r = 1, g = 1, b = 1, a = 1}, 20)
								showed_full = true
							end
						end
					end
				end
			end

			local refineries = surface.find_entities_filtered {
				name = "refinery",
				area = GetBoundingBox(vehicle.position, 5)
			}
			if #refineries > 0 then
				local inventory = vehicle.get_inventory(defines.inventory.car_trunk)
				if inventory then
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
			end
		end
	end
end

script.on_nth_tick(60, On_Tick_Driving_Players)

if auto_harvester_enabled then
	script.on_nth_tick(1, function()
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
	end)
end
