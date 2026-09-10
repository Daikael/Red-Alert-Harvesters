-- Pure-function checks for scoop / hybrid math. Run with: lua test_2_1_features.lua
-- Does not require Factorio.

package.path = "./?.lua;" .. package.path

-- Minimal stubs so scoop.lua can load without Factorio.
package.loaded.utilities = true
package.loaded.modulebay = true
package.loaded.specialOres = true
prototypes = {quality = {}, item = {coal = {fuel_value = 4000000}, wood = {fuel_value = 2000000}, ["rocket-fuel"] = {fuel_value = 100000000}, ["nuclear-fuel"] = {fuel_value = 1210000000}}}
defines = {inventory = {fuel = "fuel", car_trunk = "car_trunk"}}
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
function SafeQuality(obj)
	if not obj then
		return nil
	end
	return obj.quality
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

expect(Scoop.ORE_INTERVAL_TICKS == 40, "ore mines one item every 40 ticks")
expect(Scoop.TYPE2_INTERVAL_TICKS == 20, "tiberium mines one item every 20 ticks")
expect(Scoop.EQUIV_WINDOW_TICKS == 320, "legacy equivalent window is still 320 ticks")
expect(Scoop.ORE_INTERVAL_TICKS * Scoop.LEGACY_ORE_ITEMS == 320, "ore 8×40 matches old 320-tick window")
expect(Scoop.TYPE2_INTERVAL_TICKS * Scoop.LEGACY_TYPE2_ITEMS == 320, "tib 16×20 matches old 320-tick window")
expect(Scoop.interval_base({name = "cncharvester"}) == 40, "ore interval_base is 40")
expect(Scoop.interval_base({name = "cncharvester-type2"}) == 20, "type-2 interval_base is 20")
expect(Scoop.interval_ticks(40, 0, 0) == 40, "unmodified ore interval 40")
expect(Scoop.interval_ticks(20, 0, 0) == 20, "unmodified tiberium interval 20")
expect(Scoop.ITEMS_PER_SCOOP == 1, "each mine inserts 1 item")
expect(Scoop.scoop_items({name = "cncharvester"}) == 1, "scoop_items ore truck is 1")
expect(Scoop.scoop_items({name = "cncharvester-type2"}) == 1, "scoop_items type-2 is 1")
expect(Scoop.items_per_location({name = "cncharvester"}) == 24, "auto ore stays 3×8 items per location")
expect(Scoop.items_per_location({name = "cncharvester-type2"}) == 48, "auto tib stays 3×16 items per location")
local interval = Scoop.interval_ticks(40, 0.5, 2)
expect(interval < 40 and interval >= Scoop.MIN_INTERVAL_TICKS, "speed+quality shortens from 40")
expect(Scoop.interval_ticks(20, 4, 0) == 4, "high-speed tiberium is not clamped above 4")

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
expect(HybridDrive.PARKED_GRID_MULT == 6, "parked grid pull is 6× the moving refill")
expect(ore.parked_refill_w > ore.refill_w, "parked battery pull is faster than moving refill")
expect(ore.parked_refill_w > ore.intrinsic_w, "battery idle rate beats intrinsic trickle")
expect(ore.electric_cap_j == HybridDrive.POOL_CAP, "electric refill cap is the 80 MJ pool")

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

expect(Scoop.JOULES_PER_ITEM == 120000, "120 kJ per item (4× 2.1.10)")
expect(math.abs(Scoop.action_joules(1, 0, 0) - 120000) < 1, "1 item no modules = 120 kJ")
expect(math.abs(Scoop.action_joules(8, 0, 0) - 960000) < 1, "8 items (legacy window) = 960 kJ")
expect(Scoop.action_joules(1, 0, 0) * 100 == 12000000, "100 items per 12 MJ solid fuel")
expect(Scoop.action_joules(1, 0, 0) < 12000000 / 50, "one item is far below 1 solid fuel")
expect(Scoop.action_joules(1, 0, 1) > Scoop.action_joules(1, 0, 0), "speed modules raise scoop cost")
expect(Scoop.action_joules(1, 0, 0, 5) > Scoop.action_joules(1, 0, 0, 0), "quality level raises scoop cost")
expect(math.abs(Scoop.parasitic_joules(0) - 120000) < 1, "no efficiency = 120 kJ tax for 1 item")
expect(math.abs(Scoop.parasitic_joules(-0.4) - 72000) < 1, "1x eff-3 = 72 kJ for 1 item")
expect(math.abs(Scoop.parasitic_joules(-0.8) - 24000) < 1, "2x eff-3 = 24 kJ floor for 1 item")
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
expect(HybridDrive.add_burner_energy(leftover, 500) == 500, "grid refill continues above the old 4s / 300 kJ cap")
expect(leftover.currently_burning == HybridDrive.CHARGE_ITEM, "charge identity kept")
expect(leftover.remaining_burning_fuel == 1000500, "pool above 4s of drive still accepts battery charge")
local full_pool = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = HybridDrive.POOL_CAP}
expect(HybridDrive.add_burner_energy(full_pool, 500) == 0, "electric refill does not add above the 80 MJ pool cap")
expect(full_pool.remaining_burning_fuel == HybridDrive.POOL_CAP, "full pool is not deflated")

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
expect(HybridDrive.convert_inventory_fuels(convert_vehicle) == 4000000, "1 coal converts to reach the 4 MJ floor")
expect((tank_items.coal or 0) == 1, "second coal stays in the tank")
expect(convert_vehicle.burner.currently_burning == HybridDrive.CHARGE_ITEM, "convert keeps hybrid-charge")
expect(convert_vehicle.burner.remaining_burning_fuel == 4000000, "pool received one coal")
expect(HybridDrive.convert_inventory_fuels(convert_vehicle, 8000000) == 4000000, "higher target converts the second coal")
expect((tank_items.coal or 0) == 0, "both coal convert when the target needs them")
expect(convert_vehicle.burner.remaining_burning_fuel == 8000000, "pool received both coal")
expect(HybridDrive.has_energy(convert_vehicle), "converted coal can drive")
expect(HybridDrive.apply_spark_if_empty(convert_vehicle) == false, "spark skipped when the pool has energy")

local chest_items = {coal = 10, ["nuclear-fuel"] = 5, ["cncharvester-hybrid-charge"] = 1, ["iron-ore"] = 20}
local tank_fill = {}
local function mock_fuel_inv(items, cap)
	local inv = {valid = true, _items = items}
	inv.is_full = function()
		local n = 0
		for _, c in pairs(items) do
			n = n + c
		end
		return n >= cap
	end
	inv.insert = function(stack)
		local n = 0
		for _, c in pairs(items) do
			n = n + c
		end
		local got = math.min(stack.count, math.max(0, cap - n))
		if got <= 0 then
			return 0
		end
		items[stack.name] = (items[stack.name] or 0) + got
		return got
	end
	inv.remove = function(stack)
		local have = items[stack.name] or 0
		local n = math.min(stack.count, have)
		items[stack.name] = have - n
		return n
	end
	return inv
end
local chest_inv = mock_fuel_inv(chest_items, 1000)
local tank_inv = mock_fuel_inv(tank_fill, 100)
expect(HybridDrive.transfer_convertible_fuel(chest_inv, tank_inv) == 10, "refuel moves coal from chest to tank")
expect((tank_fill.coal or 0) == 10, "tank received chest coal")
expect((chest_items.coal or 0) == 0, "chest coal was removed by insert count")
expect((chest_items["nuclear-fuel"] or 0) == 5, "nuclear stays in the chest")
expect((chest_items["cncharvester-hybrid-charge"] or 0) == 1, "hidden charge is not transferred")
expect((chest_items["iron-ore"] or 0) == 20, "ore is not transferred as fuel")
local small_src = {coal = 10}
local small_dst = {}
expect(HybridDrive.transfer_convertible_fuel(mock_fuel_inv(small_src, 1000), mock_fuel_inv(small_dst, 2)) == 2, "tank fill stops at dest capacity")
expect((small_src.coal or 0) == 8, "chest keeps fuel the tank could not take")
expect((small_dst.coal or 0) == 2, "tank took only what fit")
local match_src = {wood = 8, coal = 4}
local match_dst = {coal = 1}
expect(HybridDrive.transfer_convertible_fuel(mock_fuel_inv(match_src, 1000), mock_fuel_inv(match_dst, 5)) == 4, "prefers topping up tank coal before wood")
expect((match_dst.coal or 0) == 5, "coal stack filled first")
expect((match_src.coal or 0) == 0, "matching coal was taken first")
expect((match_src.wood or 0) == 8, "wood left when tank is already full of coal")
expect(HybridDrive.fuel_inventory ~= nil, "fuel_inventory helper exists")
local trunk_items = {["iron-ore"] = 10}
local tank_2slot = {}
local tank_inv_2 = mock_fuel_inv(tank_2slot, 2)
local ore_truck = {
	valid = true,
	burner = {
		currently_burning = HybridDrive.CHARGE_ITEM,
		remaining_burning_fuel = 0,
		inventory = tank_inv_2,
	},
	get_inventory = function()
		return mock_fuel_inv(trunk_items, 50)
	end,
}
expect(HybridDrive.fuel_inventory(ore_truck) == tank_inv_2, "ore truck fuel tank is burner.inventory, not get_inventory(fuel)")
local depot_chest = mock_fuel_inv({coal = 80}, 1000)
expect(HybridDrive.transfer_convertible_fuel(depot_chest, HybridDrive.fuel_inventory(ore_truck)) == 2, "ore truck 2-slot tank fills from the refinery chest")
expect((tank_2slot.coal or 0) == 2, "chest coal landed in the ore truck fuel tank")
expect((trunk_items["iron-ore"] or 0) == 10, "refuel does not insert coal into the cargo trunk")
expect((depot_chest._items.coal or 0) == 78, "chest keeps coal the 2-slot tank could not take")
local fallback_tank = mock_fuel_inv({coal = 1}, 2)
local fallback_veh = {
	valid = true,
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0},
	get_inventory = function()
		return fallback_tank
	end,
}
expect(HybridDrive.fuel_inventory(fallback_veh) == fallback_tank, "fuel_inventory falls back to get_inventory when burner.inventory is missing")

local rec_src = assert(io.open("prototypes/recipes/harv_recipe.lua", "r")):read("*a")
expect(rec_src:find('category = "crafting"', 1, true) ~= nil, "2.0 recipes use category")
expect(rec_src:find("categories =", 1, true) == nil, "2.0 recipes do not use 2.1 categories")
local refin_src = assert(io.open("prototypes/recipes/refin_recipe.lua", "r")):read("*a")
expect(refin_src:find('category = "crafting"', 1, true) ~= nil, "refinery recipe uses 2.0 category")
expect(refin_src:find("categories =", 1, true) == nil, "refinery recipe does not use 2.1 categories")
local harv_src = assert(io.open("prototypes/entities/harv_entity.lua", "r")):read("*a")
expect(harv_src:find("braking_power =", 1, true) ~= nil, "2.0 cars use braking_power")
expect(harv_src:find("braking_force =", 1, true) == nil, "2.0 cars do not assign 2.1 braking_force")
expect(harv_src:find("friction_force =", 1, true) == nil, "2.0 cars do not assign 2.1 friction_force")
expect(harv_src:find("friction = vehicle_friction", 1, true) ~= nil, "2.0 cars use friction")
expect(rec_src:find('name = "solar-panel"', 1, true) ~= nil, "truck recipes include solar-panel")
expect(rec_src:find('name = "battery"', 1, true) ~= nil, "truck recipes include vanilla battery")
expect(select(2, rec_src:gsub('name = "solar%-panel"', "")) >= 2, "both harvester recipes list solar-panel")
expect(rec_src:find("Hybrid-drive", 1, true) == nil, "recipes do not include deprecated Hybrid-drive")
expect(rec_src:find("Hybrid-drive-battery", 1, true) == nil, "recipes do not include deprecated Hybrid-drive-battery")
expect(rec_src:find('name = "electric-engine-unit"', 1, true) ~= nil, "Tiberium recipe uses electric-engine-unit")
local type2_block = rec_src:match('name = "cncharvester%-type2".-results')
expect(type2_block ~= nil, "type-2 recipe block exists")
expect(type2_block:find('name = "engine-unit"', 1, true) == nil, "type-2 recipe does not use regular engines")
expect(type2_block:find('name = "electric-engine-unit"', 1, true) ~= nil, "type-2 recipe requires electric engines")

expect(HybridDrive.NEVER_GIFT["solar-panel"] and HybridDrive.NEVER_GIFT["battery"], "craft-cost solar/battery are never gifted")
expect(HybridDrive.NEVER_GIFT["Hybrid-drive"] and HybridDrive.NEVER_GIFT["Hybrid-drive-battery"], "Hybrid-drive is never gifted")
expect(HybridDrive.NEVER_GIFT["efficiency-module"] and HybridDrive.NEVER_GIFT["speed-module"], "modules are never gifted")

local gift_scan = {
	"hybriddrive.lua",
	"control.lua",
	"modulebay.lua",
	"prototypes/entities/harv_entity.lua",
}
for _, path in ipairs(gift_scan) do
	local src = assert(io.open(path, "r")):read("*a")
	expect(src:find("grid.put", 1, true) == nil, path .. " does not grid.put free equipment")
	expect(src:find('insert{name = "efficiency-module', 1, true) == nil, path .. " does not insert efficiency modules")
	expect(src:find('insert{name = "solar-panel', 1, true) == nil, path .. " does not insert solar items")
	expect(src:find('put{name = "Hybrid-drive', 1, true) == nil, path .. " does not put Hybrid-drive")
end
expect(io.open("hybriddrive.lua"):read("*a"):find("function HybridDrive.auto_equip", 1, true) == nil, "auto_equip gift path is gone")

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

local parked_cell = {energy = 20000000, valid = true, type = "battery-equipment"}
local parked_burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 1000000}
local parked_vehicle = {
	valid = true,
	name = "cncharvester",
	quality = {level = 0},
	speed = 0,
	burner = parked_burner,
	grid = {equipment = {parked_cell}, available_in_batteries = 20000000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
local before_parked = parked_burner.remaining_burning_fuel
HybridDrive.tick(parked_vehicle)
expect(parked_burner.remaining_burning_fuel > before_parked, "parked battery raises the hybrid pool")
expect(parked_burner.remaining_burning_fuel - before_parked > ore.refill_j_per_tick, "parked battery refill beats the moving cap")
expect(parked_cell.energy < 20000000, "parked tick drains the battery")
expect(parked_burner.remaining_burning_fuel > 300000, "battery charge is not stuck at the old 300 kJ cap")

local moving_cell = {energy = 20000000, valid = true, type = "battery-equipment"}
local moving_burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 1000000}
local moving_vehicle = {
	valid = true,
	name = "cncharvester",
	quality = {level = 0},
	speed = 0.2,
	burner = moving_burner,
	grid = {equipment = {moving_cell}, available_in_batteries = 20000000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
HybridDrive.tick(moving_vehicle)
expect(moving_burner.remaining_burning_fuel - 1000000 <= ore.refill_j_per_tick + 1, "moving grid refill stays rate-capped")

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
local intrinsic_tick = HybridDrive.INTRINSIC_SOLAR_W / 60 * HybridDrive.CONVERSION_EFFICIENCY
expect(empty_tick.burner.remaining_burning_fuel > 0, "intrinsic solar ticks with an empty grid")
expect(math.abs(empty_tick.burner.remaining_burning_fuel - intrinsic_tick) < 1, "empty-grid refill is the baked-in solar trickle")

expect(HybridDrive.INTRINSIC_SOLAR_W == 18000, "baked-in solar is 18 kW")
expect(math.abs(ore.intrinsic_w - 18000) < 1, "normal intrinsic solar is 18 kW")
expect(math.abs(legendary.intrinsic_w - 18000 * 2) < 1, "legendary intrinsic is 2× (20%/level × 5)")
expect(legendary.intrinsic_w > ore.intrinsic_w, "legendary intrinsic solar is faster")
local legendary_eff = HybridDrive.rates("cncharvester", {level = 5}, {consumption = -0.8})
expect(legendary_eff.intrinsic_w > legendary.intrinsic_w, "efficiency modules raise idle trickle")
expect(ore.intrinsic_w < ore.drive_w, "intrinsic solar is below drive draw")
expect(legendary.intrinsic_w < legendary.drive_w, "legendary intrinsic still below drive without extra gear")
expect(legendary.refill_w * HybridDrive.DRIVE_OVER_REFILL > legendary.refill_w, "legendary refill still rate-capped vs drive")

local spark_pool = {
	valid = true,
	name = "cncharvester",
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = HybridDrive.SPARK_JOULES},
	grid = {equipment = {{energy = 50000, valid = true, type = "solar-panel-equipment"}}, available_in_batteries = 50000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
expect(not HybridDrive.can_afford(spark_pool, 120000), "2 kJ spark + 50 kJ solar cannot afford a 120 kJ item")
expect(HybridDrive.can_afford(spark_pool, 2000), "spark can afford its own 2 kJ")
expect(not HybridDrive.spend(spark_pool, 120000), "failed spend does not take a token drain")
expect(spark_pool.burner.remaining_burning_fuel == 2000, "unaffected remaining after rejected spend")
expect(spark_pool.grid.equipment[1].energy == 50000, "rejected spend does not drain the grid")

local charged_grid = {
	valid = true,
	name = "cncharvester",
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0},
	grid = {equipment = {{energy = 5000000, valid = true, type = "battery-equipment"}}, available_in_batteries = 5000000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
expect(HybridDrive.has_usable_energy(charged_grid), "empty solids + charged grid is usable energy")
expect(HybridDrive.can_afford(charged_grid, 120000), "5 MJ grid can pay a 120 kJ item")
expect(charged_grid.grid.equipment[1].energy == 5000000, "can_afford does not drain the grid")
expect(HybridDrive.spend(charged_grid, 120000), "spend pulls stored grid energy into the pool")
expect(charged_grid.grid.equipment[1].energy < 5000000, "scoop spend drains the grid")
expect(math.abs(charged_grid.burner.remaining_burning_fuel) < 1, "spend leaves the pool empty after paying from grid")
expect(not HybridDrive.has_usable_energy({
	valid = true,
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 0},
	grid = {equipment = {{energy = 0, valid = true}}, available_in_batteries = 0},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}), "empty pool + empty grid + empty tank is not usable")

local paid_pool = {
	valid = true,
	burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = 2000000},
	get_inventory = function()
		return {valid = true, get_item_count = function() return 0 end, _items = {}}
	end,
}
expect(HybridDrive.spend(paid_pool, 1200000), "2 MJ pool can pay a 1.2 MJ scoop")
expect(math.abs(paid_pool.burner.remaining_burning_fuel - 800000) < 1, "spend deducts the full action cost")

local inserted = 0
local function harvest_vehicle(remaining)
	return {
		valid = true,
		quality = {level = 0},
		burner = {currently_burning = HybridDrive.CHARGE_ITEM, remaining_burning_fuel = remaining},
		get_inventory = function(kind)
			if kind == defines.inventory.fuel then
				return {valid = true, get_item_count = function() return 0 end, _items = {}}
			end
			return {
				valid = true,
				can_insert = function() return true end,
				insert = function(stack)
					inserted = inserted + (stack.count or 1)
					return stack.count or 1
				end,
			}
		end,
		surface = {valid = true, pollute = function() end},
	}
end
local patch = {valid = true, amount = 50, name = "iron-ore", prototype = {}, destroy = function() end}
inserted = 0
local denied = Scoop.harvest_area(harvest_vehicle(2000), {patch}, 1)
expect(denied.no_fuel == true, "harvest_area refuses a scoop the pool cannot pay")
expect(inserted == 0, "refused scoop inserts no ore")

inserted = 0
local rich = harvest_vehicle(40000000)
local allowed = Scoop.harvest_area(rich, {patch, {valid = true, amount = 50, name = "iron-ore", prototype = {}, destroy = function() end}}, 1)
expect(allowed.no_fuel ~= true, "funded scoop is allowed")
expect(inserted == 1, "funded scoop inserts 1 item")
expect(rich.burner.remaining_burning_fuel < 40000000, "funded scoop spends pool energy")

inserted = 0
local tib = harvest_vehicle(40000000)
tib.name = "cncharvester-type2"
local tib_ok = Scoop.harvest_area(tib, {patch}, Scoop.scoop_items(tib))
expect(tib_ok.no_fuel ~= true, "type-2 scoop is allowed when the pool can pay")
expect(inserted == 1, "type-2 scoop inserts 1 item")

local loc = assert(io.open("locale/en/all.cfg", "r")):read("*a")
expect(loc:find("cncharvester%-hybrid%-charge=Hybrid charge", 1) ~= nil, "hybrid-charge item-name is localized")
expect(loc:find("%[fuel%-category%-name%]", 1) ~= nil, "fuel-category-name section exists")
expect(loc:find("cncharvester%-hybrid=Hybrid charge", 1) ~= nil, "hybrid fuel category is localized")
expect(loc:find("out%-of%-fuel=Out of fuel", 1) ~= nil, "out-of-fuel is localized")
expect(loc:find("inventory%-full=Inventory full", 1) ~= nil, "inventory-full is localized")
expect(loc:find("heading%-for%-refuel=Heading for refuel", 1) ~= nil, "heading-for-refuel is localized")
expect(loc:find("no%-empty%-refinery=Cannot find unoccupied empty refinery", 1) ~= nil, "no-empty-refinery is localized")
expect(loc:find("Hybrid-drive=", 1, true) == nil, "locale has no Hybrid-drive item name")
expect(loc:find("Tiberium-Harvesting=Tiberium Harvesting", 1, true) ~= nil, "Tiberium Harvesting tech is localized")
expect(loc:find("no%-fuel%-refinery=Cannot find refinery with fuel", 1) ~= nil, "no-fuel-refinery is localized")
expect(loc:find("Fuel inserted in the tank charges this electrical capacity", 1, true) ~= nil, "fuel→electrical capacity string is localized")

local toast_files = { "control.lua", "harvester.lua" }
local toast_banned = {
	'"Inventory full"',
	'"Heading for refuel"',
	'"Cannot find unoccupied empty refinery"',
	'"Cannot find refinery with fuel"',
}
for _, path in ipairs(toast_files) do
	local src = assert(io.open(path, "r")):read("*a")
	for _, needle in ipairs(toast_banned) do
		expect(src:find(needle, 1, true) == nil, path .. " does not hard-code " .. needle)
	end
end
expect(io.open("control.lua"):read("*a"):find("cncharvester.inventory-full", 1, true) ~= nil, "control.lua uses inventory-full locale key")
expect(io.open("harvester.lua"):read("*a"):find('{"cncharvester.no-empty-refinery"}', 1, true) ~= nil, "harvester.lua uses no-empty-refinery locale key")

local info_src = assert(io.open("info.json", "r")):read("*a")
expect(info_src:find('"name": "Red-Alert-Harvester"', 1, true) ~= nil, "mod name is singular Red-Alert-Harvester")
expect(info_src:find('"name": "Red-Alert-Harvesters"', 1, true) == nil, "mod name is not the plural portal mismatch")
expect(info_src:find('"version": "2.2.0"', 1, true) ~= nil, "pack version is 2.2.0")
expect(info_src:find('"factorio_version": "2.0"', 1, true) ~= nil, "factorio_version is 2.0")
expect(info_src:find('"factorio_version": "2.1"', 1, true) == nil, "factorio_version is not 2.1")
expect(info_src:find("base >= 2.0.0", 1, true) ~= nil, "base dependency is 2.0")
expect(info_src:find("base >= 2.1", 1, true) == nil, "base dependency is not pinned to 2.1")
expect(info_src:find("Factorio%-Tiberium >= 2%.0%.0") ~= nil, "optional Tiberium dep is 2.0")
local proto_scan = {
	"prototypes/items/hybrid_charge.lua",
	"prototypes/entities/harv_entity.lua",
	"prototypes/entities/module_bay.lua",
}
for _, path in ipairs(proto_scan) do
	local src = assert(io.open(path, "r")):read("*a")
	expect(src:find("__Red-Alert-Harvesters__/", 1, true) == nil, path .. " does not use plural asset prefix")
	expect(src:find("__Red-Alert-Harvester__/", 1, true) ~= nil, path .. " uses singular asset prefix")
end

local charge_src = assert(io.open("prototypes/items/hybrid_charge.lua", "r")):read("*a")
expect(charge_src:find('localised_name = {"item-name.cncharvester-hybrid-charge"}', 1, true) ~= nil, "charge item sets localised_name")
expect(charge_src:find('localised_name = {"fuel-category-name.cncharvester-hybrid"}', 1, true) ~= nil, "fuel category sets localised_name")

local bay_src = assert(io.open("prototypes/entities/module_bay.lua", "r")):read("*a")
expect(bay_src:find("HAS_QUALITY", 1, true) ~= nil, "quality prototype keys are gated for base 2.0")
expect(bay_src:find("quality_affects_module_slots = false", 1, true) ~= nil, "bay slots do not scale with quality when quality exists")
expect(bay_src:match('module_bay%s*%(%s*"cncharvester%-module%-bay"%s*,%s*(%d+)') == "2", "ore truck bay is 2 slots")
expect(bay_src:match('module_bay%s*%(%s*"cncharvester%-type2%-module%-bay"%s*,%s*(%d+)') == "3", "type-2 bay is 3 slots")
expect(bay_src:find("module_slots = slots", 1, true) ~= nil, "bay uses slot argument")
expect(not bay_src:find("quality_affects_module_slots = true", 1, true), "no quality-scaled slot flag")
expect(bay_src:find('type = "electric"', 1, true) ~= nil, "slave miner is electric so the energy bar exists")
expect(bay_src:find('type = "void"', 1, true) == nil, "slave miner is not void-energy")
expect(bay_src:find('resource_categories = {"basic-solid"}', 1, true) ~= nil, "slave miner lists only vanilla basic-solid")
expect(not bay_src:match('resource_categories%s*=%s*{[^}\n]*basic%-solid%-tiberium'), "resource_categories assignment does not list basic-solid-tiberium")
expect(bay_src:find('type = "resource-category"', 1, true) == nil, "this pack does not invent a resource-category prototype")
expect(bay_src:find("cncharvester-module-bay\"", 1, true) ~= nil, "ore truck bay name present")
local fixes_src = assert(io.open("data-final-fixes.lua", "r")):read("*a")
expect(fixes_src:find("category_exists", 1, true) ~= nil, "final-fixes only add categories that exist")
expect(fixes_src:find("strip_tiberium_categories", 1, true) ~= nil, "ore bay strips injected Tiberium categories")
expect(io.open("chunksearcher.lua") == nil, "dead chunksearcher.lua stub is deleted")
local index_src = assert(io.open("chunkindex.lua"):read("*a"))
expect(index_src:find('"basic-solid-tiberium"', 1, true) == nil, "chunkindex does not hard-code basic-solid-tiberium")
expect(index_src:find("string.find(category, \"tiberium\"", 1, true) ~= nil, "chunkindex detects Tib by category substring")
expect(index_src:find("BUDGET_PER_TICK = 1", 1, true) ~= nil, "scanner drains one chunk per budget tick")
expect(index_src:find("SCAN_INTERVAL_TICKS = 10", 1, true) ~= nil, "scanner waits 10 ticks between classify calls")
expect(index_src:find("BORDER_REQUEUE_TICKS = 36000", 1, true) ~= nil, "border requeue is 10 minutes")
expect(index_src:find("HARVESTER_REQUEUE_TICKS = 10800", 1, true) ~= nil, "harvester requeue is 3 minutes")
expect(index_src:find("function overlay_rebuild_dirty", 1, true) ~= nil, "overlay steady state is dirty-only")
expect(io.open("control.lua"):read("*a"):find('require "chunkindex"', 1, true) ~= nil, "control requires chunkindex")
expect(io.open("control.lua"):read("*a"):find("ChunkIndex.tick", 1, true) ~= nil, "nth-tick drains the chunk index")
expect(io.open("control.lua"):read("*a"):find("legacy teleport AI disabled", 1, true) ~= nil, "legacy teleport AI is commented out")
expect(io.open("control.lua"):read("*a"):find("\n\t\t\t\t\tharvester:Tick()", 1, true) ~= nil, "harvester:Tick is live")
expect(io.open("control.lua"):read("*a"):find("on_script_path_request_finished", 1, true) ~= nil, "control hooks pathfinder results")
expect(io.open("control.lua"):read("*a"):find("harvester_ai", 1, true) ~= nil, "remote exposes harvester_ai")
expect(io.open("autodrive.lua") ~= nil, "autodrive.lua exists")
local drive_src = assert(io.open("autodrive.lua"):read("*a"))
expect(drive_src:find("vehicle.teleport(", 1, true) == nil, "autodrive never teleports")
expect(drive_src:find("request_path", 1, true) ~= nil, "autodrive uses surface.request_path")
expect(drive_src:find("riding_state", 1, true) ~= nil, "autodrive steers with riding_state")
expect(drive_src:find("RANGE_TILES = 10000000", 1, true) ~= nil, "auto assignment is not capped at 256 tiles")
expect(drive_src:find("REPATH_MAX = 3", 1, true) ~= nil, "repath budget is 3")
expect(drive_src:find("ALT_PATCH_MAX = 3", 1, true) ~= nil, "alternate-patch budget is 3")
expect(drive_src:find("STUCK_TICKS = 180", 1, true) ~= nil, "no-progress window is 180 ticks")
expect(index_src:find("function ChunkIndex.find_ore_chunks", 1, true) ~= nil, "FindingOre reads the chunk index")
expect(io.open("harvester.lua"):read("*a"):find("PickIndexTarget", 1, true) ~= nil, "FindingOre uses PickIndexTarget")
expect(io.open("harvester.lua"):read("*a"):find("StartDrive", 1, true) ~= nil, "harvester starts physical drives")
expect(drive_src:find("player_occupying", 1, true) ~= nil, "autodrive detects player occupancy")
expect(drive_src:find("ai_may_steer", 1, true) ~= nil, "riding writes allow seat-lock AI")
expect(drive_src:find("PATH_RADIUS_ORE_ENTITY = 1.5", 1, true) ~= nil, "ore entity path radius is tight")
expect(drive_src:find("ORE_RETARGET_MAX = 3", 1, true) ~= nil, "off-patch retarget budget is 3")
expect(drive_src:find("PEER_EXCLUDE_TILES = 16", 1, true) ~= nil, "assignment exclusion is 16 tiles")
expect(drive_src:find("PEER_SIT_TILES = 8", 1, true) ~= nil, "sitting exclusion is 8 tiles")
expect(drive_src:find("function AutoDrive.has_peer_priority", 1, true) ~= nil, "lowest unit_number peels out of a cluster")
expect(drive_src:find("PEER_CLEARANCE_TILES = 4", 1, true) ~= nil, "runtime peer clearance is 4 tiles")
expect(drive_src:find("PEER_RAM_TILES = 3.2", 1, true) ~= nil, "ram bubble is 3.2 tiles")
expect(drive_src:find("PEER_BLOCKER_NEAR = 32", 1, true) ~= nil, "path blockers are local (32 tiles), not map-wide")
expect(drive_src:find("function AutoDrive.peer_needs_blocker", 1, true) ~= nil, "peer_needs_blocker decides local traffic only")
expect(drive_src:find("REVERSE_TICKS = 90", 1, true) ~= nil, "peer reverse wiggle is 90 ticks")
expect(drive_src:find("REVERSE_CHECK_TILES = 6", 1, true) ~= nil, "rear-clear check is 6 tiles")
expect(drive_src:find("ALIGN_SPEED = 0.08", 1, true) ~= nil, "in-place align speed threshold is 0.08")
expect(drive_src:find("function AutoDrive.steer_plan", 1, true) ~= nil, "steer_plan is the testable in-place turn helper")
expect(drive_src:find("function AutoDrive.tick_peer_block", 1, true) ~= nil, "tick_peer_block handles reverse-then-repath")
expect(drive_src:find("function AutoDrive.path_request_plan", 1, true) ~= nil, "path_request_plan stays car-precise")
expect(drive_src:find("function AutoDrive.clear_nearby_trees", 1, true) ~= nil, "auto-drive harvests nearby trees")
expect(drive_src:find("function AutoDrive.remove_tree", 1, true) ~= nil, "trees destroy when the trunk cannot take wood")
expect(drive_src:find("DOCK_ACCEPT_TILES = 8", 1, true) ~= nil, "dock accept radius is 8 tiles")
expect(drive_src:find("DOCK_DUMP_TILES = 12", 1, true) ~= nil, "holder may dump from 12 tiles")
expect(drive_src:find("function AutoDrive.can_dump", 1, true) ~= nil, "can_dump finishes the last approach")
expect(drive_src:find("function AutoDrive.same_goal", 1, true) ~= nil, "same_goal stops StartDrive from re-pathing every tick")
expect(drive_src:find("PAD_RECHECK_TICKS = 30", 1, true) ~= nil, "pad waiters recheck every 30 ticks")
expect(io.open("harvester.lua"):read("*a"):find("already_driving", 1, true) ~= nil, "StartDrive no-ops when the same dest is in flight")
expect(io.open("refinery.lua"):read("*a"):find("for _, refinery in pairs(storage.refineries", 1, true) ~= nil, "Nearest* walks storage.refineries, not a surface scan")
expect(drive_src:find("function AutoDrive.is_pad_holder", 1, true) ~= nil, "pad holder wins peel at the dock")
expect(drive_src:find("PATH_RADIUS_HOME = 10", 1, true) ~= nil, "home path radius is 10 tiles")
expect(drive_src:find("PATH_RES_LONG = 0", 1, true) ~= nil, "pathfinder stays at 1-tile resolution")
expect(drive_src:find("STUCK_RETRY_TICKS = 300", 1, true) ~= nil, "stuck alerts back off before retry")
expect(io.open("harvester.lua"):read("*a"):find("aligning_in_place", 1, true) ~= nil, "in-place turn does not consume the stuck window")
expect(io.open("harvesterstats.lua"):read("*a"):find("RefineryDumpOffset = {0.75, -5.5}", 1, true) ~= nil, "dump offset is the north dump face")
expect(drive_src:find("cncharvester-path-blocker", 1, true) ~= nil, "pathfinder uses sibling path blockers")
expect(drive_src:find("allow_destroy_friendly_entities = false", 1, true) ~= nil, "pathfinder may not destroy friendlies")
expect(drive_src:find("entity_to_ignore = entity", 1, true) ~= nil, "pathfinder ignores only self")
expect(io.open("prototypes/entities/harv_entity.lua"):read("*a"):find('type = "collision-layer"', 1, true) ~= nil, "private peer collision layer exists")
expect(io.open("prototypes/entities/harv_entity.lua"):read("*a"):find('name = "cncharvester-path-blocker"', 1, true) ~= nil, "path-blocker prototype exists")
expect(io.open("prototypes/entities/harv_entity.lua"):read("*a"):find("extra-low", 1, true) == nil, "path-blocker does not use invalid extra-low sprite priority")
expect(io.open("prototypes/entities/harv_entity.lua"):read("*a"):find('priority = "very-low"', 1, true) ~= nil, "path-blocker sprite priority is very-low")
expect(io.open("harvester.lua"):read("*a"):find("peer_blocks_assignment", 1, true) ~= nil, "PickIndexTarget skips peer-occupied chunks")
expect(io.open("harvester.lua"):read("*a"):find("path_hits_peer", 1, true) ~= nil, "OnPathFinished still checks path_hits_peer")
expect(io.open("harvester.lua"):read("*a"):find("tick_peer_block", 1, true) ~= nil, "Tick reverse-wiggles then repaths instead of freezing on a sibling")
expect(io.open("harvester.lua"):read("*a"):find("clear_nearby_trees", 1, true) ~= nil, "Tick mines trees that threaten collision")
expect(io.open("harvester.lua"):read("*a"):find("near_dock", 1, true) ~= nil, "home trip accepts a close-enough dock")
expect(io.open("harvester.lua"):read("*a"):find("dock_goal", 1, true) ~= nil, "stuck home trips try alternate dock faces")
expect(io.open("harvester.lua"):read("*a"):find("self:claim_pad", 1, true) ~= nil, "FindingRefinery reserves before the drive")
expect(io.open("harvester.lua"):read("*a"):find("self:release_pad", 1, true) ~= nil, "pad lock is released on dump/fail/leave")
expect(io.open("harvester.lua"):read("*a"):find("GetAvailableSlots() > Stats.cncharvesterCargoSlots", 1, true) == nil, "dump no longer requires 21 empty chest stacks")
expect(io.open("refinery.lua"):read("*a"):find("reserved_by", 1, true) ~= nil, "reserve records the holding truck")
expect(io.open("refinery.lua"):read("*a"):find("leaked `reserved`", 1, true) ~= nil, "IsOccupied reclaims a leaked pad lock")
expect(drive_src:find("blocked_by_peer(vehicle, true)", 1, true) ~= nil, "follow_path brakes only for the ram bubble")
expect(io.open("harvester.lua"):read("*a"):find('action == "repath"', 1, true) ~= nil, "peer repath is a soft StartDrive, not OnPathFail")
expect(drive_src:find("function AutoDrive.eject_players", 1, true) == nil, "eject_players is removed")
expect(drive_src:find("function AutoDrive.demote_driver_to_passenger", 1, true) ~= nil, "demote helper exists")
expect(drive_src:find("vehicle.set_driver(nil)", 1, true) ~= nil, "demote clears the driver seat")
expect(drive_src:find("vehicle.set_passenger", 1, true) ~= nil, "demote uses set_passenger")
expect(drive_src:find("player.driving = false", 1, true) == nil, "no player.driving ground dump")
local hv_src = assert(io.open("harvester.lua"):read("*a"))
expect(hv_src:find("auto_enabled = true", 1, true) ~= nil, "new trucks default auto ON")
expect(hv_src:find("pause_on_enter = false", 1, true) ~= nil, "pause-on-enter defaults OFF")
expect(hv_src:find("return self.auto_enabled ~= false", 1, true) ~= nil, "nil auto_enabled reads as ON")
expect(hv_src:find("pause_on_enter == true", 1, true) ~= nil, "nil pause_on_enter reads as OFF")
expect(hv_src:find("seat_locked = function", 1, true) ~= nil, "seat_locked helper exists")
expect(hv_src:find("pause_yields = function", 1, true) ~= nil, "pause_yields helper exists")
expect(hv_src:find("MaybeDemoteDriver", 1, true) ~= nil, "MaybeDemoteDriver exists")
expect(hv_src:find("MaybeEjectLockedSeat", 1, true) == nil, "locked-seat eject helper is gone")
expect(hv_src:find("player.driving = false", 1, true) == nil, "harvester does not ground-eject")
expect(hv_src:find("NotifyToggle", 1, true) ~= nil, "toggle feedback helper exists")
expect(hv_src:find("nearest_harvestable_in_area", 1, true) ~= nil, "ore retarget finds a resource entity")
expect(hv_src:find("PATH_RADIUS_ORE_ENTITY", 1, true) ~= nil, "FindingOre drives to ore entity tightly")
expect(hv_src:find("pause_yields()", 1, true) ~= nil, "StartDrive is not blocked by occupying when auto owns the wheel")
expect(hv_src:find("player_is_driver(self.vehicle) and self:pause_yields()", 1, true) ~= nil, "StartDrive yields only for driver + pause")
expect(hv_src:find("A passenger must not block the path", 1, true) ~= nil, "StartDrive comment forbids passenger abort")
expect(hv_src:find("driving and self:pause_yields()", 1, true) ~= nil, "Tick yields only for driver + pause-on-enter")
expect(hv_src:find('source ~= "player_checkbox"', 1, true) ~= nil, "SetAutoEnabled(false) requires a real checkbox click")
expect(hv_src:find("transfer_convertible_fuel", 1, true) ~= nil, "refuel uses HybridDrive chest-to-tank transfer")
expect(hv_src:find("convert_inventory_fuels(self.vehicle)", 1, true) ~= nil, "Refueling converts tank solids into the hybrid pool")
expect(hv_src:find("Must run even when the tank is empty", 1, true) ~= nil, "Tick calls MaybeReturnHome before aborting on empty fuel")
expect(hv_src:find("HybridDrive.fuel_inventory(vehicle)", 1, true) ~= nil, "harvester reads the burner fuel tank helper")
expect(hv_src:find("tank_convertible_joules(self.vehicle) > 0", 1, true) ~= nil, "Refueling does not treat an empty is_full tank as refueled")
expect(io.open("hybriddrive.lua"):read("*a"):find("function HybridDrive.fuel_inventory", 1, true) ~= nil, "fuel_inventory prefers burner.inventory")
expect(io.open("scoop.lua"):read("*a"):find("HybridDrive.fuel_inventory(vehicle)", 1, true) ~= nil, "scoop parasitic drain uses the burner fuel tank")
expect(hv_src:find("potential >= AutoDrive.FUEL_LOW_J", 1, true) ~= nil, "refuel leaves when potential is at least the 8 MJ trip")
expect(hv_src:find("Empty burner must not skip dock/refuel", 1, true) ~= nil, "Tick still docks when the burner is empty")
local refin_ent = assert(io.open("prototypes/entities/refin_entity.lua"):read("*a"))
expect(refin_ent:find("circuit_wire_max_distance = default_circuit_wire_max_distance", 1, true) ~= nil, "refinery sets 2.0 circuit wire reach")
expect(refin_ent:find("circuit_connector_definitions.create_vector", 1, true) ~= nil, "refinery has a 2.0 circuit_connector")
expect(refin_ent:find("universal_connector_template", 1, true) ~= nil, "refinery uses the vanilla connector template")
expect(io.open("refinery.lua"):read("*a"):find("HybridDrive.convertible_joules", 1, true) ~= nil, "HasFuel counts convertible burnables")
expect(io.open("refinery.lua"):read("*a"):find("count = count - proto.stack_size", 1, true) ~= nil, "DropOnBelt still withholds one fuel stack")
expect(io.open("hybriddrive.lua"):read("*a"):find("function HybridDrive.transfer_convertible_fuel", 1, true) ~= nil, "transfer_convertible_fuel exists")
local hv_onload = hv_src:match("\n\tOnload = function%(self%)\n(.-)\n\tend,")
expect(hv_onload ~= nil, "harvester Onload exists")
expect(hv_onload:find("setmetatable", 1, true) ~= nil, "Onload rebinds metatable")
expect(hv_onload:find("self%.[%w_]+%s*=", 1) == nil, "Onload does not assign harvester fields")
expect(hv_onload:find("storage%.[%w_]+%s*=", 1) == nil, "Onload does not assign storage fields")
expect(hv_onload:find("auto_enabled", 1, true) == nil, "Onload does not default auto_enabled")
expect(hv_onload:find("pause_on_enter", 1, true) == nil, "Onload does not default pause_on_enter")
expect(hv_src:find("AfterLoad = function", 1, true) ~= nil, "AfterLoad migrates fields outside on_load")
local ctl_src = assert(io.open("control.lua"):read("*a"))
local on_load_fn = ctl_src:match("local function On_Load%(%)\n(.-)\nend\nscript%.on_load")
expect(on_load_fn ~= nil, "On_Load exists")
expect(on_load_fn:find("ensure_storage", 1, true) == nil, "On_Load does not call ensure_storage")
expect(on_load_fn:find("AfterLoad", 1, true) == nil, "On_Load does not call AfterLoad")
expect(on_load_fn:find("storage%.[%w_]+%s*=", 1) == nil, "On_Load does not assign storage fields")
expect(on_load_fn:find("auto_enabled", 1, true) == nil, "On_Load does not write auto_enabled")
expect(ctl_src:find("script.on_load(On_Load)", 1, true) ~= nil, "on_load hooks On_Load")
expect(ctl_src:find("migrate_after_load()", 1, true) ~= nil, "first tick migrates stale path ids")
expect(hv_src:find("Pause-on-enter: player has the seat", 1, true) ~= nil, "Tick yields riding only for pause-on-enter")
expect(hv_src:find("FindingOre / path / riding_state every tick, even occupied", 1, true) ~= nil, "auto_on keeps AI while occupied")
expect(hv_src:find("KickAuto = function", 1, true) ~= nil, "KickAuto resumes empty auto trucks")
expect(hv_src:find("self:KickAuto()", 1, true) ~= nil, "occupancy/toggle call KickAuto")
local after_load_fn = hv_src:match("AfterLoad = function%(self%)\n(.-)\n\tauto_on = function")
expect(after_load_fn ~= nil, "AfterLoad body is extractable")
expect(after_load_fn:find("self:KickAuto", 1, true) == nil, "AfterLoad does not KickAuto/StartDrive on the load tick")
expect(after_load_fn:find("LOAD_GRACE_TICKS", 1, true) ~= nil, "AfterLoad staggers resume after load grace")
expect(after_load_fn:find("rec:Reserve", 1, true) == nil, "AfterLoad does not re-claim pads from the save")
expect(ctl_src:find("destroy_orphan_blockers", 1, true) == nil, "load migrate does not mass-destroy path blockers")
expect(ctl_src:find("begin_load_recovery", 1, true) ~= nil, "load migrate starts batched blocker recovery")
expect(ctl_src:find("tick_purge_blockers", 1, true) ~= nil, "nth-tick runs the batched blocker purge")
expect(ctl_src:find("path_blockers", 1, true) ~= nil, "remote exposes path_blockers purge status")
expect(drive_src:find("LOAD_GRACE_TICKS = 60", 1, true) ~= nil, "load grace is 60 ticks")
expect(drive_src:find("PURGE_PER_TICK = 8", 1, true) ~= nil, "orphan purge destroys 8 dummies per tick")
expect(drive_src:find("function AutoDrive.in_load_grace", 1, true) ~= nil, "in_load_grace gates blocker spawn")
expect(drive_src:find("function AutoDrive.forget_blocker_lists", 1, true) ~= nil, "forget_blocker_lists exists")
expect(drive_src:find("function AutoDrive.tick_purge_blockers", 1, true) ~= nil, "tick_purge_blockers exists")
expect(drive_src:find("function AutoDrive.peer_layer_enabled", 1, true) ~= nil, "peer_layer_enabled exists")
expect(drive_src:find("function AutoDrive.begin_load_recovery", 1, true) ~= nil, "begin_load_recovery exists")
expect(hv_src:find("self:holds_pad(held)", 1, true) ~= nil, "FindingRefinery held-pad drive requires holds_pad")
expect(hv_src:find("Stale save flag", 1, true) ~= nil, "FindingRefinery clears a stale reserve without UnReserve")
expect(hv_src:find("return refinery and self.targetRefinery ==", 1, true) == nil, "holds_pad does not treat every home-bound truck as the holder")
expect(hv_src:find("refinery.reserved_by == id", 1, true) ~= nil, "holds_pad requires reserved_by")
expect(hv_src:find("(self.busy_until or 0) > game.tick", 1, true) ~= nil, "Tick honors busy_until before the state machine")
expect(hv_src:find("SetAutoEnabled", 1, true) ~= nil, "per-truck auto setter exists")
expect(hv_src:find("SetPauseOnEnter", 1, true) ~= nil, "per-truck pause-on-enter setter exists")
expect(io.open("autopanel.lua") ~= nil, "autopanel.lua exists")
local panel_src = assert(io.open("autopanel.lua"):read("*a"))
expect(panel_src:find("relative_gui_type.car_gui", 1, true) ~= nil, "auto panel anchors to car GUI")
expect(panel_src:find("relative_gui_position.left", 1, true) ~= nil, "auto panel sits on the inventory side")
expect(panel_src:find("cncharvester-auto-enabled", 1, true) ~= nil, "automatic operation checkbox")
expect(panel_src:find("cncharvester-pause-on-enter", 1, true) ~= nil, "pause-on-enter checkbox")
expect(io.open("control.lua"):read("*a"):find('require "autopanel"', 1, true) ~= nil, "control requires autopanel")
expect(io.open("control.lua"):read("*a"):find("on_gui_checked_state_changed", 1, true) ~= nil, "control hooks checkbox toggles")
expect(io.open("control.lua"):read("*a"):find("on_gui_click", 1, true) ~= nil, "control hooks checkbox clicks")
expect(io.open("control.lua"):read("*a"):find("Do not destroy the auto panel here", 1, true) ~= nil, "closing inventory does not destroy auto checkboxes")
expect(io.open("control.lua"):read("*a"):find("AutoPanel.track_vehicle", 1, true) ~= nil, "auto panel can track the opened truck")
expect(panel_src:find("opened_harvester", 1, true) ~= nil, "checkbox writes require the car GUI to be open")
expect(panel_src:find("ignore_checked", 1, true) ~= nil, "programmatic checkbox state is ignored")
expect(panel_src:find("function AutoPanel.on_click", 1, true) ~= nil, "checkbox writes go through on_click")
expect(panel_src:find('SetAutoEnabled(want, "player_checkbox")', 1, true) ~= nil, "auto off is tagged as player_checkbox")
expect(panel_src:find("Never write storage from", 1, true) ~= nil, "checked-state events do not write auto by default")
expect(panel_src:find("last_sync_tick", 1, true) ~= nil, "checkbox writes ignore the sync tick")
expect(panel_src:find("SYNC_GRACE_TICKS", 1, true) ~= nil, "checkbox writes ignore a few ticks after sync")
expect(io.open("control.lua"):read("*a"):find("auto_on = auto_on", 1, true) ~= nil, "harvester_ai reports auto_on")
expect(io.open("control.lua"):read("*a"):find("seat_locked = auto_on and h.pause_on_enter ~= true", 1, true) ~= nil, "harvester_ai reports seat_locked")
expect(io.open("control.lua"):read("*a"):find("path_id = h.path_id", 1, true) ~= nil, "harvester_ai reports path_id")
expect(io.open("control.lua"):read("*a"):find("has_path = h.path ~= nil", 1, true) ~= nil, "harvester_ai reports has_path")
expect(io.open("control.lua"):read("*a"):find("fuel_ok =", 1, true) ~= nil, "harvester_ai reports fuel_ok")
expect(io.open("control.lua"):read("*a"):find("occupied = occupying", 1, true) ~= nil, "harvester_ai occupied is live player_occupying")
expect(io.open("control.lua"):read("*a"):find("is_driver = veh_ok and AutoDrive.player_is_driver(veh)", 1, true) ~= nil, "harvester_ai reports is_driver")
expect(io.open("control.lua"):read("*a"):find("is_passenger = occupying and not", 1, true) ~= nil, "harvester_ai reports is_passenger")
expect(io.open("control.lua"):read("*a"):find("MaybeDemoteDriver", 1, true) ~= nil, "driving-changed demotes driver to passenger")
expect(io.open("control.lua"):read("*a"):find("AutoDrive.eject_player", 1, true) == nil, "driving-changed does not eject")
expect(io.open("prototypes/entities/harv_entity.lua"):read("*a"):find("allow_passengers = true", 1, true) ~= nil, "car prototype has a passenger seat")
expect(io.open("utilities.lua"):read("*a"):find("FLOATING_TEXT_TOGGLE_TTL = 300", 1, true) ~= nil, "toggle floating text lasts 5 seconds")
expect(hv_src:find("player.print(text)", 1, true) ~= nil, "toggle feedback also player.prints")
expect(loc:find("auto%-operation=Automatic operation", 1) ~= nil, "automatic operation locale exists")
expect(loc:find("pause%-on%-enter=Pause when somebody jumps in", 1) ~= nil, "pause-on-enter locale exists")
expect(loc:find("auto%-toggled%-on=", 1) ~= nil, "auto-on toggle locale exists")
expect(loc:find("pause%-toggled%-on=", 1) ~= nil, "pause-on toggle locale exists")
expect(loc:find("auto%-locked=", 1) == nil, "eject toast locale is gone")
expect(loc:find("auto%-passenger=", 1) ~= nil, "passenger demote locale exists")
expect(loc:find("auto%-no%-passenger=", 1) ~= nil, "no-passenger-seat locale exists")
expect(loc:find("auto%-off%-blocked=", 1) ~= nil, "auto-off-blocked locale exists")
expect(loc:find("needs%-testing%-flag=", 1) ~= nil, "testing-flag tooltip locale exists")
dofile("autodrive.lua")
expect(AutoDrive.player_occupying(nil) == false, "nil vehicle is not occupied")
expect(AutoDrive.player_occupying({
	valid = true,
	unit_number = 1,
	get_driver = function() return nil end,
	get_passenger = function() return nil end,
}) == false, "empty mock vehicle is not occupied")
expect(AutoDrive.player_occupying({
	valid = true,
	unit_number = 2,
	get_driver = function()
		return {object_name = "LuaPlayer", valid = true}
	end,
	get_passenger = function() return nil end,
}) == true, "LuaPlayer driver counts as occupying")
expect(AutoDrive.player_occupying({
	valid = true,
	unit_number = 3,
	get_driver = function()
		return {object_name = "LuaEntity", valid = true, type = "character", player = {valid = true}}
	end,
	get_passenger = function() return nil end,
}) == true, "player character driver counts as occupying")
expect(AutoDrive.player_occupying({
	valid = true,
	unit_number = 4,
	get_driver = function()
		return {object_name = "LuaEntity", valid = true, type = "character"}
	end,
	get_passenger = function() return nil end,
}) == false, "uncontrolled character is not occupying")
expect(drive_src:find("return obj:is_player()", 1, true) == nil, "occupying does not call is_player on seat objects")
local occupied_mock = {
	valid = true,
	unit_number = 5,
	get_driver = function()
		return {object_name = "LuaPlayer", valid = true}
	end,
	get_passenger = function() return nil end,
}
expect(AutoDrive.ai_may_steer(occupied_mock) == false, "occupied without lock does not steer")
storage = { cncharvesters = { [6] = { auto_enabled = true, pause_on_enter = false } } }
expect(AutoDrive.ai_may_steer({
	valid = true,
	unit_number = 6,
	get_driver = function()
		return {object_name = "LuaPlayer", valid = true}
	end,
	get_passenger = function() return nil end,
}) == true, "auto on + pause off still steers while occupied")
storage = { cncharvesters = { [7] = { auto_enabled = true, pause_on_enter = true } } }
expect(AutoDrive.ai_may_steer({
	valid = true,
	unit_number = 7,
	get_driver = function()
		return {object_name = "LuaPlayer", valid = true}
	end,
	get_passenger = function() return nil end,
}) == false, "pause-on-enter occupied does not steer")
storage = { cncharvesters = { [8] = { auto_enabled = true, pause_on_enter = false } } }
expect(AutoDrive.ai_may_steer({
	valid = true,
	unit_number = 8,
	get_driver = function() return nil end,
	get_passenger = function()
		return {object_name = "LuaPlayer", valid = true}
	end,
}) == true, "passenger does not block auto steering")
storage = nil
local demote_player = {object_name = "LuaPlayer", valid = true}
demote_player.character = {object_name = "LuaEntity", valid = true, type = "character", player = demote_player}
local demote_driver, demote_passenger = demote_player, nil
local demote_veh = {
	valid = true,
	prototype = {allow_passengers = true},
	get_driver = function() return demote_driver end,
	get_passenger = function() return demote_passenger end,
	set_driver = function(v) demote_driver = v end,
	set_passenger = function(v) demote_passenger = v end,
}
expect(AutoDrive.demote_driver_to_passenger(demote_veh) == "passenger", "demote returns passenger")
expect(demote_driver == nil, "driver seat empty after demote")
expect(demote_passenger ~= nil, "passenger seat filled after demote")
local ground_driver = {object_name = "LuaPlayer", valid = true}
local ground_veh = {
	valid = true,
	prototype = {allow_passengers = false},
	get_driver = function() return ground_driver end,
	get_passenger = function() return nil end,
	set_driver = function(v) ground_driver = v end,
	set_passenger = function() error("no passenger seat") end,
}
expect(AutoDrive.demote_driver_to_passenger(ground_veh) == "ground", "no passenger seat returns ground")
expect(ground_driver == nil, "driver still cleared when passenger is impossible")
local peer_surf = {}
local truck_a = {valid = true, unit_number = 11, surface = peer_surf, position = {x = 0, y = 0}, orientation = 0.25}
local truck_b = {valid = true, unit_number = 12, surface = peer_surf, position = {x = 8, y = 0}, orientation = 0}
storage = {
	cncharvesters = {
		[11] = {vehicle = truck_a, assign_si = 1, assign_cx = 0, assign_cy = 0, going_home = false},
		[12] = {vehicle = truck_b, assign_si = nil, assign_cx = nil, assign_cy = nil, going_home = false},
	},
}
expect(AutoDrive.PEER_EXCLUDE_TILES == 16, "same-chunk claim is 16 tiles")
expect(AutoDrive.PEER_SIT_TILES == 8, "sitting exclusion is 8 tiles")
expect(AutoDrive.peer_blocks_assignment(truck_b, 1, 0, 0, {x = 16, y = 16}) == true, "same assigned chunk is blocked for the other truck")
expect(AutoDrive.peer_blocks_assignment(truck_b, 1, 5, 5, {x = 176, y = 176}) == false, "far chunk is not blocked")
expect(AutoDrive.peer_blocks_assignment(truck_b, 1, 0, 1, {x = 6, y = 0}) == true, "chunk center within 8 tiles of a sitting truck is blocked")
expect(AutoDrive.peer_blocks_assignment(truck_b, 1, 0, 1, {x = 20, y = 0}) == false, "chunk center 20 tiles from a sitting truck is open")
storage.cncharvesters[11].going_home = true
storage.cncharvesters[11].assign_cx = 0
expect(AutoDrive.peer_blocks_assignment(truck_b, 1, 0, 0, {x = 176, y = 176}) == false, "going-home assignment does not keep the chunk claimed")
expect(AutoDrive.path_hits_peer({{position = {x = 8, y = 0}}}, truck_a) == false, "waypoint near a sibling is not a path fail")
expect(AutoDrive.path_hits_peer({{position = {x = 3, y = 0}}}, truck_a) == false, "waypoints next to the start are not a peer-path fail")
expect(AutoDrive.path_hits_peer({{position = {x = 80, y = 80}}}, truck_a) == false, "path far from siblings is accepted")
expect(AutoDrive.path_hits_peer({{position = {x = 4, y = 0}}}, truck_a) == false, "home path that grazes a distant sibling is accepted")
expect(AutoDrive.path_hits_peer({{position = {x = 80, y = 80}, needs_destroy_to_reach = true}}, truck_a) == true, "destroy-to-reach paths are rejected")
expect(AutoDrive.peer_needs_blocker(truck_a, truck_b, {x = 200, y = 0}) == true, "sibling 8 tiles from start is local traffic")
local far = {valid = true, unit_number = 99, surface = peer_surf, position = {x = 200, y = 40}}
expect(AutoDrive.peer_needs_blocker(truck_a, far, {x = 180, y = 0}) == false, "sibling far from start and goal is not a blocker")
expect(AutoDrive.peer_needs_blocker(truck_a, far, {x = 200, y = 36}) == true, "sibling sitting on the dock/goal is a blocker")
local beside = {valid = true, unit_number = 98, surface = peer_surf, position = {x = 3, y = 0}}
expect(AutoDrive.peer_needs_blocker(truck_a, beside, {x = 80, y = 0}) == false, "sibling already next to start is not a blocker")
truck_b.position = {x = 3, y = 0}
expect(AutoDrive.blocked_by_peer(truck_a) == true, "eastbound truck brakes for a sibling ahead")
expect(AutoDrive.rear_clear(truck_a) == true, "rear is clear when the sibling is ahead")
truck_b.position = {x = 3, y = 1}
expect(AutoDrive.peer_peel_direction(truck_a) == "left", "peer on the right peels reverse-left")
truck_b.position = {x = -3, y = 0}
expect(AutoDrive.blocked_by_peer(truck_a) == false, "sibling behind does not count as ahead")
expect(AutoDrive.rear_clear(truck_a) == false, "sibling behind blocks reverse")
truck_b.position = {x = 0, y = 20}
expect(AutoDrive.blocked_by_peer(truck_a) == false, "sibling behind/beside does not brake")
expect(AutoDrive.rear_clear(truck_a) == true, "far sibling does not block reverse")
local accel, dir
accel, dir = AutoDrive.steer_plan(0, 0)
expect(accel == "accelerating" and dir == "straight", "aligned and stopped accelerates forward")
accel, dir = AutoDrive.steer_plan(0, 0.2)
expect(accel == "nothing" and dir == "right", "stopped with yaw error tank-rotates right")
accel, dir = AutoDrive.steer_plan(0, -0.2)
expect(accel == "nothing" and dir == "left", "stopped with yaw error tank-rotates left")
accel, dir = AutoDrive.steer_plan(0.01, 0.05)
expect(accel == "nothing" and dir == "right", "nearly stopped does not creep forward to turn")
accel, dir = AutoDrive.steer_plan(0.5, 0.2)
expect(accel == "braking" and dir == "right", "moving with hard yaw brakes to align")
accel, dir = AutoDrive.steer_plan(0.5, 0.06)
expect(accel == "nothing" and dir == "right", "moving with medium yaw coasts instead of powering an arc")
accel, dir = AutoDrive.steer_plan(0.5, 0)
expect(accel == "accelerating" and dir == "straight", "aligned at speed accelerates")
local wiggle_rec = {}
truck_b.position = {x = 3, y = 1}
expect(AutoDrive.tick_peer_block(wiggle_rec, truck_a, 100) == "reverse", "pinned truck reverse-wiggles when rear is clear")
expect(wiggle_rec.reverse_until == 190, "reverse wiggle lasts REVERSE_TICKS")
expect(wiggle_rec.reverse_steer == "left", "wiggle peels away from the peer")
expect(AutoDrive.tick_peer_block(wiggle_rec, truck_a, 150) == "reverse", "wiggle keeps reversing until the timer elapses")
expect(AutoDrive.tick_peer_block(wiggle_rec, truck_a, 190) == "repath", "wiggle then repaths")
expect(wiggle_rec.reverse_until == nil, "repath clears the wiggle timer")
local wait_rec = {}
truck_b.position = {x = -3, y = 0}
local truck_c = {valid = true, unit_number = 13, surface = peer_surf, position = {x = 3, y = 0}, orientation = 0.75}
storage.cncharvesters[13] = {vehicle = truck_c, going_home = false}
expect(AutoDrive.blocked_by_peer(truck_a) == true, "ahead sibling still blocks")
expect(AutoDrive.rear_clear(truck_a) == false, "behind sibling blocks reverse")
expect(AutoDrive.tick_peer_block(wait_rec, truck_a, 200) == "wait", "boxed-in truck waits instead of reversing into a peer")
expect(wait_rec.reverse_until == nil, "wait does not start a wiggle")
expect(AutoDrive.has_peer_priority(truck_a) == true, "lowest unit_number in the cluster has peel priority")
expect(AutoDrive.has_peer_priority(truck_c) == false, "higher unit_number yields")
local yield_rec = {}
expect(AutoDrive.tick_peer_block(yield_rec, truck_c, 300) == "wait", "yielding truck does not reverse-fight the leader")
expect(yield_rec.reverse_until == nil, "yielder does not start a wiggle")
storage.cncharvesters[13].reservedRefinery = true
expect(AutoDrive.is_pad_holder(truck_c) == true, "reserved truck is the pad holder")
expect(AutoDrive.has_peer_priority(truck_c) == true, "pad holder peels even with a higher unit_number")
expect(AutoDrive.has_peer_priority(truck_a) == false, "non-holder yields to the pad holder")
storage.cncharvesters[13].reservedRefinery = nil
storage.cncharvesters[13] = nil
truck_b.position = {x = 3.5, y = 0}
expect(AutoDrive.blocked_by_peer(truck_a) == true, "3.5-tile gap is still a yield hint")
expect(AutoDrive.blocked_by_peer(truck_a, true) == false, "3.5-tile gap is not a ram")
expect(AutoDrive.tick_peer_block({}, truck_a, 400) == "clear", "priority truck drives forward when the gap is open")
truck_b.position = {x = 0, y = 20}
expect(AutoDrive.tick_peer_block({}, truck_a, 0) == "clear", "no peer ahead is clear")
local merged = AutoDrive.path_collision_mask({
	valid = true,
	prototype = {collision_mask = {layers = {player = true}}},
})
expect(merged.layers.player == true, "path mask keeps the car layers")
expect(merged.layers["cncharvester-peer"] == true, "path mask unions the peer blocker layer")
storage.autodrive_purge = true
local purged_mask = AutoDrive.path_collision_mask({
	valid = true,
	prototype = {collision_mask = {layers = {player = true}}},
})
expect(purged_mask.layers.player == true, "purge path mask keeps the car layers")
expect(purged_mask.layers["cncharvester-peer"] == nil, "purge path mask omits leftover peer blockers")
expect(AutoDrive.peer_layer_enabled() == false, "peer layer is off while purging leftovers")
expect(AutoDrive.PURGE_PER_TICK == 8, "purge budget is 8 per tick")
game = { tick = 1000 }
storage.autodrive_load_tick = 1000
storage.autodrive_purge_destroyed = 0
storage.autodrive_purge_cursor = 0
storage.autodrive_purge_quiet = 0
storage.refineries = {}
local leftovers = {}
for i = 1, 10 do
	local dummy = { valid = true }
	dummy.destroy = function()
		dummy.valid = false
	end
	leftovers[i] = dummy
end
local last_purge_filter
local purge_veh = {
	valid = true,
	unit_number = 1,
	position = {x = 0, y = 0},
	surface = {
		valid = true,
		find_entities_filtered = function(filter)
			last_purge_filter = filter
			local out = {}
			for i = 1, #leftovers do
				if leftovers[i].valid then
					out[#out + 1] = leftovers[i]
					if #out >= (filter.limit or 99) then
						break
					end
				end
			end
			return out
		end,
	},
}
storage.cncharvesters = { [1] = { vehicle = purge_veh, reservedRefinery = true } }
expect(AutoDrive.tick_purge_blockers() == 0, "purge waits out load grace")
expect(leftovers[1].valid == true, "grace does not destroy leftovers")
storage.autodrive_load_tick = 0
expect(AutoDrive.tick_purge_blockers() == 8, "first purge tick destroys the budget")
expect(last_purge_filter.limit == AutoDrive.PURGE_PER_TICK, "purge find is limited per tick")
expect(last_purge_filter.radius == AutoDrive.PURGE_RADIUS, "purge find is local to the truck/pad")
expect(leftovers[8].valid == false, "budget leftovers are gone")
expect(leftovers[9].valid == true, "overflow leftovers wait for the next tick")
expect(storage.autodrive_purge_cursor == 0, "dense pad keeps the purge cursor")
expect(AutoDrive.tick_purge_blockers() == 2, "second purge tick finishes the pile")
expect(leftovers[10].valid == false, "remaining leftovers are destroyed")
expect(storage.autodrive_purge == true, "purge stays on until a quiet round")
expect(AutoDrive.tick_purge_blockers() == 0, "empty radius is a quiet visit")
expect(storage.autodrive_purge == false, "quiet round over all anchors ends the purge")
expect(storage.autodrive_purge_destroyed == 10, "purge reports how many leftovers died")
local dbg = AutoDrive.debug_purge()
expect(dbg.purge == false and dbg.destroyed == 10, "debug_purge reports finished cleanup")
expect(dbg.peer_layer == true, "peer layer returns after cleanup")
storage.refineries = { [9] = { reserved = true, reserved_by = 1, entity = { valid = true } } }
AutoDrive.begin_load_recovery()
expect(storage.autodrive_purge == true, "begin_load_recovery starts a purge")
expect(storage.cncharvesters[1].reservedRefinery == false, "load recovery drops stale pad claims")
expect(storage.refineries[9].reserved == false, "load recovery clears pad reserved")
expect(storage.refineries[9].reserved_by == nil, "load recovery clears reserved_by")
game = nil
storage = nil
expect(io.open("locale/en/all.cfg"):read("*a"):find("auto-stuck-miner=", 1, true) ~= nil, "stuck miner locale exists")
expect(io.open("control.lua"):read("*a"):find("on_chunk_generated", 1, true) ~= nil, "control hooks on_chunk_generated")
expect(io.open("control.lua"):read("*a"):find("on_pre_chunk_deleted", 1, true) ~= nil, "control hooks on_pre_chunk_deleted")
expect(io.open("control.lua"):read("*a"):find("on_chunk_deleted", 1, true) ~= nil, "control hooks on_chunk_deleted")
expect(io.open("control.lua"):read("*a"):find('remote.add_interface("Red-Alert-Harvester"', 1, true) ~= nil, "control registers the Red-Alert-Harvester remote")
expect(io.open("control.lua"):read("*a"):find("chunkindex_stats", 1, true) ~= nil, "remote exposes chunkindex_stats")
expect(io.open("control.lua"):read("*a"):find("chunkindex_enabled", 1, true) ~= nil, "remote exposes chunkindex_enabled")
expect(io.open("control.lua"):read("*a"):find("ChunkIndex.debug_stats", 1, true) ~= nil, "stats remote calls ChunkIndex.debug_stats")
expect(io.open("control.lua"):read("*a"):find("chunkindex_overlay", 1, true) ~= nil, "remote exposes chunkindex_overlay")
expect(io.open("control.lua"):read("*a"):find("chunkindex_reseed", 1, true) ~= nil, "remote exposes chunkindex_reseed")
expect(io.open("control.lua"):read("*a"):find("chunkindex_reseed_full", 1, true) ~= nil, "remote exposes chunkindex_reseed_full")
expect(io.open("control.lua"):read("*a"):find("ChunkIndex.reseed(full)", 1, true) ~= nil, "reseed remote forwards the full/missing arg")
expect(io.open("control.lua"):read("*a"):find("cncharvester-chunkindex-overlay", 1, true) ~= nil, "control hooks the overlay toggle")
local input_src = assert(io.open("prototypes/custom-input.lua"):read("*a"))
expect(input_src:find('name = "cncharvester-chunkindex-overlay"', 1, true) ~= nil, "overlay custom-input exists")
expect(input_src:find("ALT + I", 1, true) ~= nil, "overlay default key is Alt+I")
expect(input_src:find('type = "shortcut"', 1, true) ~= nil, "overlay shortcut exists")
expect(input_src:find("toggleable = true", 1, true) ~= nil, "overlay shortcut is toggleable")
expect(io.open("harvester.lua"):read("*a"):find("vehicle.teleport", 1, true) ~= nil, "M1 does not remove legacy teleport AI")
expect(io.open("utilities.lua"):read("*a"):find('category ~= "basic-solid-tiberium"', 1, true) == nil, "harvest filter does not require basic-solid-tiberium")
expect(bay_src:find("1.5", 1, true) ~= nil, "ore truck mining_speed 1.5")
expect(bay_src:find("3.0", 1, true) ~= nil, "tiberium mining_speed 3.0")
expect(bay_src:find('"180kW"', 1, true) ~= nil, "ore truck drill is 180 kW")
expect(bay_src:find('"360kW"', 1, true) ~= nil, "tiberium drill is 360 kW")
expect(bay_src:find("cncharvester-drill-pole", 1, true) ~= nil, "private micro-grid pole exists")
expect(bay_src:find("cncharvester-drill-supply", 1, true) ~= nil, "hybrid-fed electric-energy-interface exists")
expect(bay_src:find("cncharvester-scoop-hopper", 1, true) ~= nil, "output hopper exists")
expect(bay_src:find("maximum_wire_distance = 0", 1, true) ~= nil, "private pole does not copper-join the factory")
expect(bay_src:find("function strip_world_graphics", 1, true) ~= nil, "helpers strip vanilla world graphics")
expect(bay_src:find("util.empty_sprite", 1, true) ~= nil, "helpers use util.empty_sprite")
expect(bay_src:find("__core__/graphics/empty.png", 1, true) ~= nil, "helpers use core 1x1 empty.png")
expect(bay_src:find('filename = "__Red-Alert-Harvester__/graphics/entity/transparent.png"', 1, true) == nil, "helpers do not assign the 256 transparent sheet")
expect(io.open("graphics/entity/transparent.png", "r") == nil, "orphaned transparent.png is deleted")
expect(bay_src:find("function bay_animation", 1, true) == nil, "slave drill has no hitch icon animation")
expect(bay_src:find("shift = {0.85, 0.85}", 1, true) == nil, "slave drill does not paint a bottom-right icon")
expect(bay_src:find("empty_4way_animation", 1, true) ~= nil, "slave drill graphics_set uses empty 4-way animation")
expect(bay_src:find("direction_count = 4", 1, true) == nil, "helpers do not slice a 4-wide sheet")
expect(bay_src:find("x = 0", 1, true) ~= nil, "helper sprites pin x=0")
expect(bay_src:find("y = 0", 1, true) ~= nil, "helper sprites pin y=0")

expect(Scoop.USES_SLAVE_MINER == true, "runtime mining is flagged as slave-miner")
expect(Scoop.ORE_MINING_SPEED == 1.5, "ore slave mining_speed is 1.5")
expect(Scoop.TYPE2_MINING_SPEED == 3.0, "tib slave mining_speed is 3.0")
expect(Scoop.ORE_ENERGY_W == 180000, "ore drill 180 kW = 1.5/s × 120 kJ")
expect(Scoop.TYPE2_ENERGY_W == 360000, "tib drill 360 kW = 3.0/s × 120 kJ")
expect(math.abs(Scoop.ORE_ENERGY_W / Scoop.ORE_MINING_SPEED - Scoop.JOULES_PER_ITEM) < 1, "ore watts match 120 kJ/item")
expect(math.abs(Scoop.TYPE2_ENERGY_W / Scoop.TYPE2_MINING_SPEED - Scoop.JOULES_PER_ITEM) < 1, "tib watts match 120 kJ/item")
expect(Scoop.drill_energy_w({name = "cncharvester"}) == 180000, "drill_energy_w ore")
expect(Scoop.drill_energy_w({name = "cncharvester-type2"}) == 360000, "drill_energy_w type-2")

local scoop_src = assert(io.open("scoop.lua", "r")):read("*a")
expect(scoop_src:find("math.random() < effects.productivity", 1, true) == nil, "no fake productivity roll on the scoop path")
expect(scoop_src:find("function Scoop.tick_slave", 1, true) ~= nil, "tick_slave is the runtime mine path")
expect(io.open("control.lua"):read("*a"):find("Scoop.tick_slave", 1, true) ~= nil, "drive harvest uses tick_slave")
expect(io.open("harvester.lua"):read("*a"):find("Scoop.tick_slave", 1, true) ~= nil, "auto harvest uses tick_slave")
expect(io.open("control.lua"):read("*a"):find("Scoop.harvest_area", 1, true) == nil, "drive harvest does not script-insert via harvest_area")
local mb_src = assert(io.open("modulebay.lua", "r")):read("*a")
expect(mb_src:find("function ModuleBay.feed_energy", 1, true) ~= nil, "hybrid feeds the slave-miner micro-grid")
expect(mb_src:find("disabled_by_script", 1, true) ~= nil, "prefers disabled_by_script when present")
expect(mb_src:find("bay.active = enabled", 1, true) ~= nil, "2.0 fallback writes LuaEntity.active")
expect(mb_src:find("set_supply_watts", 1, true) ~= nil, "starve/feed still cut or restore EEI watts")
local active_scan = {
	"control.lua",
	"scoop.lua",
	"hybriddrive.lua",
	"harvester.lua",
	"migrations/Red-Alert-Harvester_2.1.12.lua",
}
for _, path in ipairs(active_scan) do
	local src = assert(io.open(path, "r")):read("*a")
	expect(src:find(".active =", 1, true) == nil, path .. " does not write .active")
end
expect(io.open("data-final-fixes.lua", "r") ~= nil, "data-final-fixes exists for optional Tiberium categories")

expect(loc:find("mining%-draw%-title=Hybrid mining draw", 1) ~= nil, "hybrid mining draw title is localized")
expect(loc:find("mining%-draw%-line=Draw", 1) ~= nil, "hybrid mining draw line is localized")

local grid_src = assert(io.open("prototypes/equipment-grid.lua", "r")):read("*a")
expect(grid_src:find("width = 2", 1, true) ~= nil, "ore truck grid is 2 wide")
expect(grid_src:find("height = 2", 1, true) ~= nil, "ore truck grid is 2 tall")
expect(grid_src:find("width = 3", 1, true) ~= nil, "tiberium grid is 3 wide")
expect(grid_src:find("height = 3", 1, true) ~= nil, "tiberium grid is 3 tall")
expect(grid_src:find("width = 4", 1, true) == nil, "no leftover 4-wide grid")
expect(grid_src:find("width = 5", 1, true) == nil, "no leftover 5-wide grid")

local tech_src = assert(io.open("prototypes/technology/technology.lua", "r")):read("*a")
expect(tech_src:find('"solar-energy"', 1, true) ~= nil, "Old World Harvesting requires solar-energy")
expect(tech_src:find('"electric-engine"', 1, true) ~= nil, "Tiberium Harvesting requires electric-engine")
expect(tech_src:find('name = "Tiberium-Harvesting"', 1, true) ~= nil, "Tiberium-Harvesting tech exists")
expect(tech_src:find("Hybrid-drive", 1, true) == nil, "tech does not unlock Hybrid-drive")
local old_world = tech_src:match('name = "Old%-World%-Harvesting".-unit =')
expect(old_world ~= nil, "Old-World-Harvesting block exists")
expect(old_world:find('recipe = "cncharvester-type2"', 1, true) == nil, "Old World Harvesting does not unlock Tiberium harvester")
expect(old_world:find('"solar-energy"', 1, true) ~= nil, "Old World prereqs include solar-energy")

local data_src = assert(io.open("data.lua", "r")):read("*a")
expect(data_src:find("prototypes.items.equipment", 1, true) == nil, "data.lua does not load Hybrid-drive items")
expect(data_src:find("prototypes.equipment.equipment", 1, true) == nil, "data.lua does not load Hybrid-drive equipment")
expect(io.open("prototypes/items/equipment.lua") == nil, "Hybrid-drive item file is removed")
expect(io.open("prototypes/equipment/equipment.lua") == nil, "Hybrid-drive equipment file is removed")

dofile("chunkindex.lua")
dofile("autodrive.lua")

expect(AutoDrive.RANGE_TILES >= 1000000, "auto range is effectively unlimited")
expect(math.abs(AutoDrive.orientation_delta(0, 0.25) - 0.25) < 1e-9, "turn right is positive delta")
expect(math.abs(AutoDrive.orientation_delta(0, 0.75) + 0.25) < 1e-9, "turn left is negative delta")
expect(math.abs(AutoDrive.wrap01(-0.25) - 0.75) < 1e-9, "wrap01 handles negative")
local rec = {}
AutoDrive.progress_reset(rec, {x = 0, y = 0}, 0)
expect(AutoDrive.progress_ok(rec, {x = 0.1, y = 0}, 100) == true, "small move inside stuck window is ok")
expect(AutoDrive.progress_ok(rec, {x = 0.1, y = 0}, 200) == false, "no progress after STUCK_TICKS is stuck")
expect(AutoDrive.progress_ok(rec, {x = 2, y = 0}, 50) == true, "enough movement resets stuck")

expect(ChunkIndex.row_allows_vehicle({empty = false, items = {["iron-ore"] = true}}, false, false) == true, "ore truck can take iron")
expect(ChunkIndex.row_allows_vehicle({empty = false, items = {["tiberium-ore"] = true}}, true, false) == false, "ore truck skips Tib-only")
expect(ChunkIndex.row_allows_vehicle({empty = false, items = {["iron-ore"] = true, ["tiberium-ore"] = true}}, true, false) == true, "ore truck can take mixed via iron")
expect(ChunkIndex.row_allows_vehicle({empty = false, items = {["tiberium-ore"] = true}}, true, true) == true, "type-2 with tech can take Tib")
expect(ChunkIndex.row_allows_vehicle({empty = true, items = {}}, false, true) == false, "empty row is not assignable")
local orechunk = {[1] = {[0] = {[0] = {empty = false, items = {["iron-ore"] = true}}}}}
local found = ChunkIndex.find_ore_chunks(orechunk, {}, 1, {x = 16, y = 16}, 256, false, nil)
expect(#found == 1 and found[1].x == 0 and found[1].y == 0, "find_ore_chunks returns the nearby iron chunk")
local excluded = ChunkIndex.find_ore_chunks(orechunk, {}, 1, {x = 16, y = 16}, 256, false, {[ChunkIndex.chunk_key(1, 0, 0)] = true})
expect(#excluded == 0, "find_ore_chunks honors exclude keys")
local far = ChunkIndex.find_ore_chunks(orechunk, {}, 1, {x = 10000, y = 10000}, 256, false, nil)
expect(#far == 0, "find_ore_chunks still honors a small range cap")
local far_open = ChunkIndex.find_ore_chunks(orechunk, {}, 1, {x = 10000, y = 10000}, AutoDrive.RANGE_TILES, false, nil)
expect(#far_open == 1, "unlimited range includes a far indexed chunk")
local kind, res
kind, res = AutoDrive.path_request_plan({x = 0, y = 0}, {x = 10, y = 0}, false)
expect(kind == "car" and res == 0, "short trips keep the car collision box")
kind, res = AutoDrive.path_request_plan({x = 0, y = 0}, {x = 200, y = 0}, false)
expect(kind == "car" and res == 0, "long trips also use the car box (unit box was un-followable)")
kind, res = AutoDrive.path_request_plan({x = 0, y = 0}, {x = 200, y = 0}, true)
expect(kind == "car" and res == 0, "dock trips stay precise")
expect(AutoDrive.aligning_in_place(0, 0.2) == true, "stopped with yaw error is aligning in place")
expect(AutoDrive.aligning_in_place(0.5, 0.2) == false, "rolling is not an in-place align")
expect(AutoDrive.aligning_in_place(0, 0) == false, "aligned is not holding stuck")
expect(AutoDrive.near_dock({x = 7, y = 0}, {x = 0, y = 0}) == true, "7 tiles from the refinery is close enough to dump")
expect(AutoDrive.near_dock({x = 20, y = 0}, {x = 0, y = 0}) == false, "far from the refinery is not docked")
expect(AutoDrive.can_dump({x = 11, y = 0}, {x = 0, y = 0}) == true, "11 tiles is still in dump finish range")
expect(AutoDrive.can_dump({x = 20, y = 0}, {x = 0, y = 0}) == false, "20 tiles is not dump range")
expect(AutoDrive.same_goal({x = 1, y = 2}, {x = 1.1, y = 2}) == true, "goals within 0.5 tiles are the same dest")
expect(AutoDrive.same_goal({x = 0, y = 0}, {x = 10, y = 0}) == false, "distant goals are not the same dest")
expect(AutoDrive.PAD_RECHECK_TICKS == 30, "pad recheck is 30 ticks")
local dock0 = AutoDrive.dock_goal({x = 0, y = 0}, 0)
expect(dock0.y < -3, "first dock goal is north of the building")
expect(AutoDrive.tree_is_threat(3, 0, 1, 0) == true, "tree ahead is a collision threat")
expect(AutoDrive.tree_is_threat(-3, 0, 1, 0) == false, "tree behind is not cleared")
expect(AutoDrive.tree_is_threat(1.5, 0, 1, 0) == true, "touching tree is a collision threat")
expect(AutoDrive.tree_is_threat(20, 0, 1, 0) == false, "distant trees are left standing")
local tree_rec = {}
local mined_tree = {valid = true, position = {x = 3, y = 0}, mine = function() return true end}
local tree_veh = {
	valid = true,
	position = {x = 0, y = 0},
	orientation = 0.25,
	surface = {
		find_entities_filtered = function()
			return {mined_tree}
		end,
	},
	get_inventory = function()
		return {valid = true, is_full = function() return false end}
	end,
}
expect(AutoDrive.clear_nearby_trees(tree_veh, tree_rec, 1) == 1, "ahead tree is mined into the trunk")
expect(AutoDrive.clear_nearby_trees(tree_veh, tree_rec, 2) == 0, "tree clear is interval-throttled")
local full_tree = {
	valid = true,
	position = {x = 3, y = 0},
	mine = function() return false end,
}
full_tree.destroy = function()
	full_tree.valid = false
end
tree_rec.tree_tick = nil
tree_veh.surface.find_entities_filtered = function()
	return {full_tree}
end
tree_veh.get_inventory = function()
	return {valid = true, is_full = function() return true end}
end
expect(AutoDrive.clear_nearby_trees(tree_veh, tree_rec, 100) == 1, "full trunk destroys the blocking tree")
expect(full_tree.valid == false, "destroyed tree is gone")
local fail_tree = {
	valid = true,
	position = {x = 2, y = 0},
	mine = function() error("mine failed") end,
}
fail_tree.destroy = function()
	fail_tree.valid = false
end
expect(AutoDrive.remove_tree(fail_tree, {valid = true, is_full = function() return false end}) == true, "mine failure falls back to destroy")

local offs = ChunkIndex.neighbor_offsets()
expect(#offs == 8, "Tib border uses 8 neighbors")

local border, holds = {}, {}
ChunkIndex.apply_tib_transition(border, holds, 1, 0, 0, false, true)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 1, "Tib source increments neighbor refcount")
expect(ChunkIndex.border_count(border, 1, 0, 0) == 0, "Tib chunk does not increment itself")
ChunkIndex.apply_tib_transition(border, holds, 1, 2, 0, false, true)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 2, "two Tib sources share a neighbor (refcount 2)")
ChunkIndex.apply_tib_transition(border, holds, 1, 0, 0, true, false)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 1, "one Tib deplete leaves the other source's flag")
ChunkIndex.apply_tib_transition(border, holds, 1, 2, 0, true, false)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 0, "last Tib deplete clears neighbor flag")
ChunkIndex.apply_tib_transition(border, holds, 1, 2, 0, true, false)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 0, "double deplete is a no-op")

local orechunk, tibchunk = {}, {}
orechunk[1] = {[0] = {[0] = {items = {["tiberium-ore"] = true}, empty = false}}}
tibchunk[1] = {[0] = {[0] = true}}
local qstate = {queue = {{1, 0, 0}, {1, 1, 0}}, head = 1, queued = {["1:0:0"] = true, ["1:1:0"] = true}}
border, holds = {}, {}
ChunkIndex.apply_tib_transition(border, holds, 1, 0, 0, false, true)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 1, "pre-delete neighbor is flagged")
ChunkIndex.forget_chunk_state(orechunk, tibchunk, border, holds, qstate, 1, 0, 0)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 0, "delete Tib source unwinds neighbor refcount")
expect(holds[1] == nil or holds[1][0] == nil or holds[1][0][0] == nil, "delete Tib source drops tib_holds")
expect(orechunk[1] == nil, "delete clears orechunk row")
expect(tibchunk[1] == nil, "delete clears tibchunk row")
expect(qstate.queued["1:0:0"] == nil, "delete drops queued key")
expect(qstate.queue[1] == false, "delete tombstones the queue slot")
expect(qstate.queued["1:1:0"] == true, "other queued chunks stay")

-- Two Tib sources; delete one source; shared neighbor stays at 1.
border, holds = {}, {}
ChunkIndex.apply_tib_transition(border, holds, 1, 0, 0, false, true)
ChunkIndex.apply_tib_transition(border, holds, 1, 2, 0, false, true)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 2, "shared neighbor before delete")
ChunkIndex.forget_chunk_state({}, {[1]={[0]={[0]=true}}}, border, holds, nil, 1, 0, 0)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 1, "delete one of two Tib sources leaves neighbor at 1")

-- Border-only neighbor deleted: drop its border slot, do not unwind the source.
border, holds = {}, {}
ChunkIndex.apply_tib_transition(border, holds, 1, 0, 0, false, true)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 1, "border neighbor flagged")
ChunkIndex.forget_chunk_state({}, {}, border, holds, nil, 1, 1, 0)
expect(ChunkIndex.border_count(border, 1, 1, 0) == 0, "delete border neighbor drops its border entry")
expect(holds[1][0][0] == true, "Tib source holds stay when only a neighbor is deleted")
expect(ChunkIndex.border_count(border, 1, 0, 1) == 1, "other neighbors of the source stay counted")

ChunkIndex.forget_chunk_state({}, {}, border, holds, nil, 1, 0, 0)
expect(ChunkIndex.border_count(border, 1, 0, 1) == 0, "later delete of the source still unwinds remaining neighbors")
expect(ChunkIndex.forget_chunk_state({}, {}, {}, {}, nil, 1, 9, 9) == nil, "forget of unknown chunk is a no-op")

local flags_off = {present = false, mode = "tiber", extra = {nauvis = true}}
expect(ChunkIndex.tib_can_spawn_on("nauvis", flags_off) == false, "no Tib mod means no Tib spawn")
local flags_sa = {present = true, mode = "tiber", extra = {nauvis = false, all_other = false}}
expect(ChunkIndex.tib_can_spawn_on("tiber", flags_sa) == true, "tiberium-on=tiber allows planet tiber")
expect(ChunkIndex.tib_can_spawn_on("nauvis", flags_sa) == false, "tiber mode does not imply nauvis")
expect(ChunkIndex.tib_can_spawn_on("nauvis", {present = true, mode = "nauvis", extra = {}}) == true, "tiberium-on=nauvis allows nauvis")
expect(ChunkIndex.tib_can_spawn_on("vulcanus", {present = true, mode = "tiber", extra = {vulcanus = true}}) == true, "extra planet bool enables vulcanus")
expect(ChunkIndex.tib_can_spawn_on("gleba", {present = true, mode = "tiber", extra = {all_other = true}}) == true, "all-other-planets enables gleba")
expect(ChunkIndex.surface_in_scope(false, false) == false, "skip unvisited ineligible surfaces")
expect(ChunkIndex.surface_in_scope(true, false) == true, "visited surfaces are in scope for ore")
expect(ChunkIndex.surface_in_scope(false, true) == true, "Tib-eligible unvisited surfaces are in scope")

expect(ChunkIndex.resource_is_tiberium("basic-solid-tiberium", "ore") == true, "category substring detects Tib")
expect(ChunkIndex.resource_is_tiberium("basic-solid", "iron-ore") == false, "iron is not Tib")
expect(ChunkIndex.resource_is_skip("basic-fluid", "crude-oil", 100, true) == true, "fluids are skipped")
expect(ChunkIndex.resource_is_skip("basic-solid", "iron-ore", 100, false) == false, "solids are kept")

local classified = ChunkIndex.classify_entities({
	{
		valid = true,
		name = "iron-ore",
		amount = 200,
		prototype = {
			resource_category = "basic-solid",
			infinite_resource = false,
			mineable_properties = {products = {{type = "item", name = "iron-ore"}}},
		},
	},
	{
		valid = true,
		name = "tiberium-ore",
		amount = 50,
		prototype = {
			resource_category = "advanced-liquid-tiberium",
			infinite_resource = false,
			mineable_properties = {products = {{type = "item", name = "tiberium-ore"}}},
		},
	},
})
expect(classified.items["iron-ore"] == true, "index stores iron-ore item name")
expect(classified.has_tib == true, "Tib category substring flags the chunk")
expect(classified.empty == false, "mixed chunk is not empty")

local empty_c = ChunkIndex.classify_entities({})
expect(empty_c.empty == true, "no resources means empty")
expect(empty_c.has_tib == false, "empty chunk is not Tib")

local settings_src = assert(io.open("settings.lua"):read("*a"))
expect(settings_src:find('name = "cncharvester-chunk-index"', 1, true) == nil, "runtime chunk-index setting is removed")
expect(settings_src:find('name = "Auto-cncharvester-testing"', 1, true) ~= nil, "startup testing flag remains the scanner gate")
expect(index_src:find("cncharvester-chunk-index", 1, true) == nil, "chunkindex does not read a runtime setting")
expect(index_src:find('Auto-cncharvester-testing', 1, true) ~= nil, "chunkindex.enabled reads the startup testing flag")
storage = storage or {}
local stats = ChunkIndex.debug_stats()
expect(type(stats) == "table", "debug_stats returns a table when storage.chunkindex is missing")
expect(stats.queued == 0, "debug_stats queued is 0 before the index exists")
expect(stats.enabled == false, "debug_stats.enabled is false without the startup flag")

expect(ChunkIndex.overlay_class(nil, true, 0, false) == "green", "Tib is green")
expect(ChunkIndex.overlay_class({empty = false, items = {["iron-ore"] = true}}, true, 5, true) == "green", "green beats orange yellow and red")
expect(ChunkIndex.overlay_class({empty = false}, false, 1, false) == "orange", "Tib-border with ore is orange")
expect(ChunkIndex.overlay_class({empty = false, items = {["iron-ore"] = true}}, false, 3, false) == "orange", "ore on border-rescan set is orange")
expect(ChunkIndex.overlay_class({empty = true}, false, 2, false) == "yellow", "empty border stays yellow")
expect(ChunkIndex.overlay_class(nil, false, 1, false) == "yellow", "unindexed border watch is yellow")
expect(ChunkIndex.overlay_class({empty = false}, false, 0, true) == "yellow", "harvester on ore stays yellow")
expect(ChunkIndex.overlay_class({empty = false, items = {["iron-ore"] = true}}, false, 0, false) == "red", "ore is red")
expect(ChunkIndex.overlay_class({empty = true}, false, 0, false) == "purple", "empty scanned is purple")
expect(ChunkIndex.overlay_class(nil, false, 0, false) == nil, "unscanned is blank")
expect(ChunkIndex.OVERLAY_COLORS.orange ~= nil, "orange overlay color exists")
expect(ChunkIndex.OVERLAY_COLORS.orange.r >= 0.9, "orange is red-heavy")
expect(ChunkIndex.OVERLAY_COLORS.orange.g > 0.35 and ChunkIndex.OVERLAY_COLORS.orange.g < 0.75, "orange sits between red and yellow")
expect(ChunkIndex.overlay_blink_on(0) == true, "blink on at tick 0")
expect(ChunkIndex.overlay_blink_on(7) == true, "blink on in first half-period")
expect(ChunkIndex.overlay_blink_on(8) == false, "blink off in second half-period")
expect(ChunkIndex.overlay_blink_on(16) == true, "blink period wraps")
expect(ChunkIndex.OVERLAY_MAX_CHUNKS == 0, "chart overlay is not camera-capped at 600")
expect(ChunkIndex.OVERLAY_COLORS.purple.a < 0.20, "empty-scanned purple is dim")
expect(index_src:find("OVERLAY_CHART_RADIUS", 1, true) == nil, "overlay does not cull by chart camera radius")
expect(index_src:find("each_nested_chunk(storage.orechunk", 1, true) ~= nil, "overlay rebuild walks orechunk")
expect(index_src:find("each_nested_chunk(storage.tibchunk", 1, true) ~= nil, "overlay rebuild walks tibchunk")
expect(index_src:find("function ChunkIndex.reseed", 1, true) ~= nil, "reseed is a public ChunkIndex API")
local nested_n = ChunkIndex.each_nested_chunk({[1] = {[0] = {[0] = true, [1] = true}}}, nil)
expect(nested_n == 2, "each_nested_chunk counts index rows")
local reseed = ChunkIndex.reseed()
expect(type(reseed) == "table", "reseed returns a table")
expect(reseed.enabled == false, "reseed is disabled without the startup flag")
expect(reseed.mode == "missing", "default reseed is missing-only")
expect(reseed.enqueued == 0, "reseed enqueues nothing when disabled")
expect(reseed.missing == 0, "disabled reseed missing is 0")
expect(reseed.enqueued_missing == 0, "disabled reseed enqueued_missing is 0")
expect(ChunkIndex.reseed_wants_full(nil) == false, "nil reseed arg is missing-only")
expect(ChunkIndex.reseed_wants_full(false) == false, "false reseed arg is missing-only")
expect(ChunkIndex.reseed_wants_full("missing") == false, "missing string is missing-only")
expect(ChunkIndex.reseed_wants_full(true) == true, "true reseed arg is full refresh")
expect(ChunkIndex.reseed_wants_full("full") == true, "full string is full refresh")
expect(ChunkIndex.reseed(true).mode == "full", "reseed(true) reports full mode")
expect(ChunkIndex.SCAN_INTERVAL_TICKS == 10, "scan interval is 10 ticks")
expect(ChunkIndex.BUDGET_PER_TICK == 1, "budget stays one chunk per scan tick")
expect(ChunkIndex.BORDER_REQUEUE_TICKS == 36000, "border requeue is 36000 ticks")
expect(ChunkIndex.HARVESTER_REQUEUE_TICKS == 10800, "harvester requeue is 10800 ticks")
expect(ChunkIndex.coords_ok(1, 0, 0) == true, "coords_ok accepts chunk (0,0)")
expect(ChunkIndex.coords_ok(1, 0, 5) == true, "coords_ok accepts x=0")
expect(ChunkIndex.coords_ok(1, 5, 0) == true, "coords_ok accepts y=0")
expect(ChunkIndex.coords_ok(1, nil, 0) == false, "coords_ok rejects nil x")
expect(ChunkIndex.has_index_row({[1] = {[0] = {[0] = {empty = true}}}}, 1, 0, 0) == true, "origin chunk can be indexed")
expect(ChunkIndex.has_index_row({[1] = {[0] = {[0] = {empty = true}}}}, 1, 0, 1) == false, "missing neighbor is unindexed")
storage = storage or {}
local st = ChunkIndex.ensure_storage()
st.queue = {{1, 2, 3}}
st.head = 1
st.queued = {[ChunkIndex.chunk_key(1, 0, 0)] = true}
expect(ChunkIndex.rebuild_queued_set(st) == 1, "rebuild_queued_set counts live slots")
expect(st.queued[ChunkIndex.chunk_key(1, 0, 0)] == nil, "rebuild drops stale queued keys")
expect(st.queued[ChunkIndex.chunk_key(1, 2, 3)] == true, "rebuild keeps live queue keys")
expect(ChunkIndex.enqueue(1, 0, 0) == true, "enqueue accepts chunk (0,0)")
expect(index_src:find("surface_index and x and y", 1, true) == nil, "enqueue no longer uses truthy x and y")
expect(index_src:find("pos.x and pos.y", 1, true) == nil, "chunk-delete no longer uses truthy pos.x and pos.y")
expect(index_src:find("missing_list", 1, true) ~= nil, "reseed collects unindexed generated chunks first")
expect(index_src:find("surface.get_chunks()", 1, true) ~= nil, "reseed walks generated chunks")
expect(index_src:find("has_index_row(storage.orechunk, si, chunk.x, chunk.y)", 1, true) ~= nil, "enqueue_generated skips already-indexed chunks")
expect(index_src:find("mode == \"full\"", 1, true) ~= nil, "reseed only queues refresh rows in full mode")
expect(index_src:find("Keep already-drawn keys first", 1, true) == nil, "overlay cap does not drop newly classified chunks")
expect(ChunkIndex.overlay_is_world_mode("game") == true, "game render_mode is world")
expect(ChunkIndex.overlay_is_world_mode(nil) == true, "omitted render_mode defaults to world")
expect(ChunkIndex.overlay_is_world_mode("chart") == false, "chart is not world")
expect(ChunkIndex.overlay_is_world_mode("chart-zoomed-in") == false, "chart-zoomed-in is not world")
local modes = ChunkIndex.overlay_render_modes()
expect(modes[1] == "chart", "overlay draws chart (map)")
expect(modes[2] == nil, "overlay does not draw a second chart-zoomed-in rect")
expect(index_src:find('render_mode = "game"', 1, true) == nil, "overlay source does not request game/world draws")
expect(index_src:find("type(obj) == \"number\"", 1, true) ~= nil, "get_object_by_id is only used for numeric ids")
expect(index_src:find("overlay_chart_only", 1, true) ~= nil, "overlay migrates away from leftover world rectangles")
expect(index_src:find("overlay_orange", 1, true) ~= nil, "overlay one-shot rebuilds for orange border+ore")
expect(index_src:find("st.scan = nil", 1, true) ~= nil, "idle tick clears the scan blink")
expect(index_src:find("function ChunkIndex.overlay_clear", 1, true) ~= nil, "overlay off destroys render objects")
expect(io.open("locale/en/all.cfg"):read("*a"):find("chunkindex-overlay-on=", 1, true) ~= nil, "overlay on locale exists")

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all scoop/hybrid rate checks passed")
