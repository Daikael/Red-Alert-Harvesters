-- remote.addinterface("cncharvester", {
--	Error = function()
--		Error()
--	end,
-- })
require "utilities"
require "chunksearcher"
require "harvester"

local autocncharvestertesting = settings.startup["Auto-cncharvester-testing"].value

script.on_init(function()
	global.tibchunk = {}
	global.orechunk = {}
	global.cncharvesters = {}
	global.refineries = {}
end
)

--script.on_load(function() On_Load() end)


--[[ function Consume_fuel_or_battery(cncharvesters)
local vehicle = player.vehicle
if vehicle.grid and vehicle.grid.available_in_batteries > 10000 and vehicle.grid.available_in_batteries > vehicle.grid.battery_capacity * 0.5 then
	if fuel_items <1 then
		
	end
end
end ]]

function On_Load()
	for _, refinery in pairs(global.refineries) do
		-- Allow it to re-set its metatable.
		Refinery.Onload(refinery)
	end
	for _, harvester in pairs(global.cncharvesters) do
		-- Allow it to re-set its metatable.
		cncharvester.Onload(harvester)
	end
end
script.on_load(On_Load)

function On_Built(event)
	local ent = event.created_entity or event.entity
	if not (ent and ent.valid) then return end
	if ent.name == "cncharvester" or ent.name == "cncharvester-type2" then
		global.cncharvesters[ent.unit_number] = cncharvester.New(ent)
	elseif ent.name == "refinery" then
		global.refineries[ent.unit_number] = Refinery.New(ent)
	end
end
if autocncharvestertesting then
	script.on_event(defines.events.on_built_entity, On_Built)
end

function On_Removed(event)
	local ent = event.entity
	if ent.name == "cncharvester" or ent.name == "cncharvester-type2" then
		for i, harvester in pairs(global.cncharvesters) do
			if harvester.vehicle == ent then
				harvester:Delete()
				table.remove(global.cncharvesters, i)
				return
			end
		end
	elseif ent.name == "refinery" then
		for i, refinery in pairs(global.refineries) do
			if refinery.refinery == ent then
				refinery:Delete()
				table.remove(global.refineries, i)
				return
			end
		end
	elseif not ent.name == ("cncharvester" and "refinery") then
		return
	end
end

script.on_event(defines.events.on_player_driving_changed_state, function(event)
	local ent = event.entity
	if ent and ent.valid and ent.name =="cncharvester" then
		local vehgrid = ent.grid
		if not vehgrid.get_contents()["Hybrid-drive"] then
			vehgrid.put{name="Hybrid-drive"}
			vehgrid.put{name="Hybrid-drive-battery"}
		end
	end
end
)

local timer = 0
function On_Tick_Driving_Players()
	-- Create a table to store the names of the cncharvester vehicles
	local cncharvester_names = {'cncharvester', 'cncharvester-ai', 'cncharvester-type2', 'cncharvester-type2-ai'}
	
	-- Iterate over the list of connected players and the list of ore entities
	for _, player in pairs(game.connected_players) do
		local vehicle = player.vehicle
		if vehicle then
			for _, name in ipairs(cncharvester_names) do
				local surface = vehicle.surface
				local bounding_box_size = 1
				if name == "cncharvester-type2" or name == "cncharvester-type2-ai" then
					bounding_box_size = 2
				end
				local ore = surface.find_entities_filtered {
					type = "resource",
					area = GetBoundingBox(vehicle.position, bounding_box_size)
				}
				
				-- Increment the timer and reset it if it reaches 10
				timer = timer + 1
				if timer >= 10 then
					timer = 0  -- Reset the timer
					for _, entity in pairs(ore) do
						-- Check if the entity is a basic solid or tiberium resource
						if (entity.prototype.resource_category == "basic-solid") or (entity.prototype.resource_category == "basic-solid-tiberium") then
							if entity.prototype.mineable_properties and entity.prototype.mineable_properties.minable and entity.prototype.mineable_properties.products then
								for _, product in pairs(entity.prototype.mineable_properties.products) do
									local itemStack = {name = product.name, count = 4}
									if entity.valid and vehicle.can_insert(itemStack) then
										entity.mine({inventory = vehicle.get_inventory(defines.inventory.car_trunk)})
									else
										rendering.draw_text{text="Inventory full", target=player.vehicle, surface=surface, scale=1.4, scale_with_zoom=true, color={r = 1, g = 1, b = 1, a = 1}, time_to_live=20}
									end
								end
								
							end
						end
					end
				end
				
				
				-- find refinery's within a 4x4 square centered around the vehicle
				local refineries = surface.find_entities_filtered {
					name = "refinery",
					area = GetBoundingBox(vehicle.position, 5)
				}
				if #refineries > 0 then -- if the returned table has at least one entry
					-- I think this is the correct inventory...I might be wrong
					local inventory = vehicle.get_inventory(2)
					local contents = inventory.get_contents()
					local itemstack = {} -- temp var
					for name, count in pairs(contents) do
						itemstack.name = name
						itemstack.count = count
						-- loop through found refineries (err on side of caution, a radius of 5 might find more than one refinery)
						for _, refinery in pairs(refineries) do
							if refinery.can_insert(itemstack) then -- if this refinery can hold the items
								refinery.insert(itemstack)
								inventory.remove(itemstack) -- remove from inventory (the cncharvester)
								break
							end
						end
					end
				end
			end
		end
	end
end

script.on_nth_tick(60, On_Tick_Driving_Players)

if autocncharvestertesting then
	script.on_nth_tick(1, function() 
		if global.cncharvesters then
			for _, harvester in pairs(global.cncharvesters) do
				harvester:Tick()
			end
		end
	end)
end