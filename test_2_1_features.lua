-- Pure-function checks for scoop / hybrid math. Run with: lua test_2_1_features.lua
-- Does not require Factorio.

package.path = "./?.lua;" .. package.path

-- Minimal stubs so scoop.lua can load without Factorio.
package.loaded.utilities = true
package.loaded.modulebay = true
package.loaded.specialOres = true
prototypes = {quality = {}, item = {coal = {fuel_value = 4000000}, wood = {fuel_value = 2000000}, ["rocket-fuel"] = {fuel_value = 100000000}, ["nuclear-fuel"] = {fuel_value = 1210000000}}}
defines = {inventory = {fuel = "fuel"}}
function EachInventoryItem(inv, cb)
	if not inv then
		return
	end
	if inv._items then
		for name, count in pairs(inv._items) do
			if count > 0 then
				cb(name, count, nil)
			end
		end
	end
end
SpecialOres = {}
function ResourceProductItemName() return "iron-ore" end
function IsHarvestableResource() return true end
function InventoryItemStack(name, count, quality)
	return {name = name, count = count, quality = quality}
end
ModuleBay = {effects = function() return {speed=0,productivity=0,consumption=0,pollution=0,quality=0} end}

dofile("scoop.lua")
dofile("hybriddrive.lua")

local fails = 0
local function expect(cond, msg)
	if not cond then
		fails = fails + 1
		print("FAIL: " .. msg)
	else
		print("ok  " .. msg)
	end
end

-- Quality drain: missing prototype field uses 1/6 per level.
expect(math.abs(Scoop.drain_multiplier({level = 0}, 0) - 1) < 1e-9, "normal drain 100%")
expect(math.abs(Scoop.drain_multiplier({level = 1}, 0) - (5/6)) < 1e-9, "uncommon drain 5/6")
expect(Scoop.drain_multiplier({mining_drill_resource_drain_multiplier = 0.5}, 0) == 0.5, "uses prototype drain field")
local with_eff = Scoop.drain_multiplier({mining_drill_resource_drain_multiplier = 1}, -0.4)
expect(with_eff < 1 and with_eff > 0.8, "efficiency slightly reduces drain")

expect(Scoop.radius(1, 0) == 1, "normal radius")
expect(Scoop.radius(1, 2) == 1.5, "rare radius +0.5")

expect(Scoop.BASE_DRIVE_INTERVAL_TICKS == 320, "drive base is 320 ticks (1.875× vs 600)")
expect(Scoop.interval_ticks(320, 0, 0) == 320, "unmodified drive interval 320")
expect(Scoop.DRIVE_ITEMS_PER_SCOOP == 4, "volume per scoop unchanged")
local interval = Scoop.interval_ticks(320, 0.5, 2)
expect(interval < 320 and interval >= Scoop.MIN_INTERVAL_TICKS, "speed+quality shortens from 320")

local q = {name = "normal", next = {name = "uncommon", next_probability = 0, next = nil}}
local always = Scoop.roll_quality_fallback(q, 1, function() return 0 end)
expect(always.name == "uncommon", "quality effect 100% promotes")
local never = Scoop.roll_quality_fallback(q, 0, function() return 0 end)
expect(never.name == "normal", "quality effect 0 stays")

local ore = HybridDrive.rates("cncharvester")
expect(ore ~= nil, "ore truck rates")
expect(math.abs(ore.drive_w - 75000) < 1, "drive draw 75 kW (150kW / effectivity 2)")
expect(ore.drive_w > ore.refill_w, "driving outstrips refill")
expect(math.abs(ore.drive_w / ore.refill_w - 1.10) < 1e-6, "drive is 10% above refill")
expect(math.abs(ore.grid_pull_w * HybridDrive.CONVERSION_EFFICIENCY - ore.refill_w) < 1e-6, "90% conversion")

local tib = HybridDrive.rates("cncharvester-type2")
expect(math.abs(tib.drive_w - 87500) < 1, "type2 drive draw 87.5 kW")
expect(tib.drive_w > tib.refill_w, "type2 driving outstrips refill")

local rare = HybridDrive.rates("cncharvester", {level = 2})
expect(rare.refill_w > ore.refill_w, "rare hybrid refill is faster")
expect(rare.max_buffer_j > ore.max_buffer_j, "rare hybrid electric cap is larger")
expect(rare.refill_w < rare.drive_w, "rare refill still below drive")
local legendary = HybridDrive.rates("cncharvester", {level = 5})
expect(legendary.refill_w > rare.refill_w, "legendary refill beats rare")
expect(legendary.max_buffer_j > rare.max_buffer_j, "legendary cap beats rare")
expect(legendary.refill_w < legendary.drive_w, "legendary driving still net-drains")
expect(math.abs(legendary.max_buffer_j / ore.max_buffer_j - 2.25) < 1e-6, "legendary electric cap is 2.25× (9 s)")

local cell = {energy = 10000, valid = true, type = "battery-equipment"}
local pulled = HybridDrive.take_from_grid({equipment = {cell}}, 4000)
expect(pulled == 4000, "hybrid pulls stored grid energy")
expect(cell.energy == 6000, "pulled energy is removed from the equipment")
expect(HybridDrive.take_from_grid({equipment = {{energy = 0, valid = true}}}, 4000) == 0, "empty grid does not refill")
expect(HybridDrive.grid_stored_energy({equipment = {{energy = 0, valid = true}}}) == 0, "empty stored energy is 0")

expect(Scoop.PARASITIC_JOULES_BASE == 1200000, "parasitic base 1.2 MJ")
expect(math.abs(Scoop.parasitic_joules(0) - 1200000) < 1, "no efficiency = 1.2 MJ tax")
expect(math.abs(Scoop.parasitic_joules(-0.4) - 720000) < 1, "1x eff-3 = 0.72 MJ")
expect(math.abs(Scoop.parasitic_joules(-0.8) - 240000) < 1, "2x eff-3 = 0.24 MJ floor")
expect(math.abs(Scoop.parasitic_joules(-1.2) - 240000) < 1, "3x eff-3 still floors at 0.24 MJ")
expect(Scoop.parasitic_joules(0.5) > Scoop.parasitic_joules(0), "speed-consumption raises tax")

expect(HybridDrive.is_banned_fuel("nuclear-fuel"), "nuclear-fuel banned")
expect(HybridDrive.is_banned_fuel("uranium-fuel-cell"), "uranium-fuel-cell banned")
expect(HybridDrive.is_banned_fuel("fusion-power-cell"), "fusion-power-cell banned")
expect(HybridDrive.is_banned_fuel("cncharvester-hybrid-charge"), "hidden charge banned")
expect(not HybridDrive.is_banned_fuel("coal"), "coal is allowed")
expect(not HybridDrive.is_banned_fuel("wood"), "wood is allowed")
expect(HybridDrive.is_overdense_fuel("rocket-fuel"), "rocket-fuel overdense vs 12 MJ")
expect(HybridDrive.STARTER_COAL == nil, "no free coal starter constant")
expect(HybridDrive.STARTER_WOOD == nil, "no free wood starter constant")
expect(HybridDrive.choose_kickoff_item(function(n) return n == "coal" and 5 or 0 end) == "coal", "kickoff prefers coal")
expect(HybridDrive.choose_kickoff_item(function(n) return n == "wood" and 2 or 0 end) == "wood", "kickoff falls back to wood")
expect(HybridDrive.choose_kickoff_item(function() return 0 end) == nil, "no kickoff if player has none")

expect(HybridDrive.SPARK_JOULES == 2000, "spark is 2 kJ, not a coal/wood bar")
expect(HybridDrive.SPARK_JOULES < 4000000 * 0.01, "spark is well under 1% of coal")
expect(HybridDrive.CHARGE_ITEM == "cncharvester-hybrid-charge", "spark uses hidden charge identity")

expect(HybridDrive.POOL_CAP == 80000000, "pool cap is 80 MJ")
expect(HybridDrive.is_nuclear_identity("nuclear-fuel"), "nuclear-fuel is a banned burn identity")
expect(not HybridDrive.is_nuclear_identity(HybridDrive.CHARGE_ITEM), "charge is not nuclear")

local spark_burner = {currently_burning = nil, remaining_burning_fuel = 0}
HybridDrive.apply_spark(spark_burner)
expect(spark_burner.currently_burning == HybridDrive.CHARGE_ITEM, "spark uses hidden charge, not coal")
expect(spark_burner.remaining_burning_fuel == 2000, "spark remaining is 2 kJ")

local empty_burner = {currently_burning = nil, remaining_burning_fuel = 0}
expect(HybridDrive.add_burner_energy(empty_burner, 1000, 300000) == 1000, "hybrid can start from empty via charge")
expect(empty_burner.currently_burning == HybridDrive.CHARGE_ITEM, "empty hybrid start is hidden charge, not coal")
expect(empty_burner.remaining_burning_fuel == 1000, "ignite clamps then adds only converted joules")

local from_coal = {currently_burning = "coal", remaining_burning_fuel = 100}
expect(HybridDrive.add_burner_energy(from_coal, 1000, 300000) == 1000, "hybrid switches coal identity to charge")
expect(from_coal.currently_burning == HybridDrive.CHARGE_ITEM, "coal burn is rewritten to hybrid-charge")
expect(from_coal.remaining_burning_fuel == 1100, "remaining is previous plus converted joules")

local nuclear = {currently_burning = "nuclear-fuel", remaining_burning_fuel = 1210000000}
HybridDrive.lock_charge(nuclear, nil)
expect(nuclear.currently_burning == HybridDrive.CHARGE_ITEM, "nuclear identity is rewritten to charge")
expect(nuclear.remaining_burning_fuel == 0, "nuclear remaining is discarded")
expect(not HybridDrive.has_energy({valid = true, burner = nuclear}), "nuclear latch is treated as empty")

local leftover = {currently_burning = "cncharvester-hybrid-charge", remaining_burning_fuel = 1000000}
expect(HybridDrive.add_burner_energy(leftover, 500, 300000) == 0, "electric refill does not add above 4s cap")
expect(leftover.currently_burning == HybridDrive.CHARGE_ITEM, "charge identity kept")
expect(leftover.remaining_burning_fuel == 1000000, "solid/pool energy above 4s is not deflated")

local empty_pool = {valid = true, burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0}}
expect(not HybridDrive.has_energy(empty_pool), "0 remaining cannot drive/scoop")

local player_inv = {coal = 3, wood = 1}
local mock_player = {
	valid = true,
	get_item_count = function(name) return player_inv[name] or 0 end,
	remove_item = function(stack)
		local n = stack.name
		if (player_inv[n] or 0) < 1 then return 0 end
		player_inv[n] = player_inv[n] - 1
		return 1
	end,
	insert = function(stack)
		player_inv[stack.name] = (player_inv[stack.name] or 0) + stack.count
		return stack.count
	end,
}
local mock_vehicle = {
	valid = true,
	burner = {currently_burning = nil, remaining_burning_fuel = 0},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
expect(HybridDrive.try_take_player_kickoff(mock_vehicle, mock_player) == "coal", "player-built consumes 1 coal")
expect(player_inv.coal == 2, "player lost exactly 1 coal")
expect(mock_vehicle.burner.currently_burning == HybridDrive.CHARGE_ITEM, "kickoff energy is hybrid-charge")
expect(mock_vehicle.burner.remaining_burning_fuel == 4000000, "1 coal is converted to 4 MJ in the pool")
expect(HybridDrive.try_take_player_kickoff(mock_vehicle, mock_player) == nil, "second kickoff skipped if pool has energy")
expect(player_inv.coal == 2, "no further coal taken")

player_inv = {coal = 0, wood = 0}
mock_vehicle.burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0}
expect(HybridDrive.try_take_player_kickoff(mock_vehicle, mock_player) == nil, "no items if player has no coal/wood")
expect(mock_vehicle.burner.remaining_burning_fuel == 0, "pool stays empty without player fuel")

local spark_vehicle = {
	valid = true,
	burner = {currently_burning = "nuclear-fuel", remaining_burning_fuel = 1210000000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
expect(HybridDrive.apply_spark_if_empty(spark_vehicle) == true, "empty tank gets a spark")
expect(spark_vehicle.burner.remaining_burning_fuel == 2000, "nuclear leftover is replaced by 2 kJ spark")
expect(spark_vehicle.burner.currently_burning == HybridDrive.CHARGE_ITEM, "spark is not nuclear/coal")

local tank_items = {coal = 2}
local convert_vehicle = {
	valid = true,
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0},
	get_inventory = function()
		return {
			valid = true,
			_items = tank_items,
			get_item_count = function() return tank_items.coal or 0 end,
			remove = function(stack)
				local n = math.min(stack.count, tank_items[stack.name] or 0)
				tank_items[stack.name] = (tank_items[stack.name] or 0) - n
				return n
			end,
		}
	end,
}
expect(HybridDrive.convert_inventory_fuels(convert_vehicle) == 8000000, "2 coal convert to 8 MJ")
expect((tank_items.coal or 0) == 0, "converted coal is removed from the tank")
expect(convert_vehicle.burner.currently_burning == HybridDrive.CHARGE_ITEM, "convert keeps hybrid-charge")
expect(convert_vehicle.burner.remaining_burning_fuel == 8000000, "pool received both coal")
expect(HybridDrive.has_energy(convert_vehicle), "converted coal can drive")
expect(HybridDrive.apply_spark_if_empty(convert_vehicle) == false, "spark skipped when the pool has energy")

local rec_src = assert(io.open("prototypes/recipes/harv_recipe.lua", "r")):read("*a")
expect(rec_src:find('name = "solar-panel"', 1, true) ~= nil, "truck recipes include solar-panel")
expect(rec_src:find('name = "battery"', 1, true) ~= nil, "truck recipes include battery")
expect(select(2, rec_src:gsub('name = "solar%-panel"', "")) >= 2, "both harvester recipes list solar-panel")

local gifted = {put = {}}
HybridDrive.auto_equip({valid = true, grid = {
	find = function() return nil end,
	put = function(spec) table.insert(gifted.put, spec.name) end,
}})
expect(#gifted.put == 0, "auto_equip does not insert free grid equipment")

local tick_cell = {energy = 50000, valid = true, type = "solar-panel-equipment"}
local tick_burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0}
local tick_vehicle = {
	valid = true,
	name = "cncharvester",
	quality = {level = 0},
	burner = tick_burner,
	grid = {equipment = {tick_cell}, available_in_batteries = 50000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
HybridDrive.tick(tick_vehicle)
expect(tick_burner.currently_burning == HybridDrive.CHARGE_ITEM, "tick refill stays hybrid-charge")
expect(tick_burner.remaining_burning_fuel > 0, "charged grid refills the hybrid pool")
expect(tick_cell.energy < 50000, "tick consumes grid energy")

local empty_tick = {
	valid = true,
	name = "cncharvester",
	quality = {level = 0},
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0},
	grid = {equipment = {{energy = 0, valid = true}}, available_in_batteries = 0},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
HybridDrive.tick(empty_tick)
expect(empty_tick.burner.remaining_burning_fuel == 0, "empty grid does not add hybrid energy")

local bay_src = assert(io.open("prototypes/entities/module_bay.lua", "r")):read("*a")
expect(bay_src:find("quality_affects_module_slots = false", 1, true) ~= nil, "bay slots do not scale with quality")
expect(bay_src:find('module_bay("cncharvester-module-bay", 2', 1, true) ~= nil, "ore truck bay is 2 slots")
expect(bay_src:find('module_bay("cncharvester-type2-module-bay", 3', 1, true) ~= nil, "type-2 bay is 3 slots")
expect(not bay_src:find("quality_affects_module_slots = true", 1, true), "no quality-scaled slot flag")

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all scoop/hybrid rate checks passed")
