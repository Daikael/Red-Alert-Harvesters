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
expect(drive_src:find("RANGE_TILES = 256", 1, true) ~= nil, "temporary auto range is 256 tiles")
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
expect(hv_src:find("NoteUnauthorizedAutoOff", 1, true) ~= nil, "unauthorized auto-off is logged")
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
expect(hv_src:find("self:KickAuto()", 1, true) ~= nil, "AfterLoad/occupancy/toggle call KickAuto")
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

expect(AutoDrive.RANGE_TILES == 256, "auto range is 256 tiles")
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
expect(#far == 0, "find_ore_chunks drops chunks outside range")

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
