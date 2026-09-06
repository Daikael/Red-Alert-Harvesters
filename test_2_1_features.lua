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
expect(io.open("control.lua"):read("*a"):find('{"cncharvester.inventory-full"}', 1, true) ~= nil, "control.lua uses inventory-full locale key")
expect(io.open("harvester.lua"):read("*a"):find('{"cncharvester.no-empty-refinery"}', 1, true) ~= nil, "harvester.lua uses no-empty-refinery locale key")

local info_src = assert(io.open("info.json", "r")):read("*a")
expect(info_src:find('"name": "Red-Alert-Harvesters"', 1, true) ~= nil, "mod name is plural Red-Alert-Harvesters")
expect(info_src:find('"version": "2.1.11"', 1, true) ~= nil, "pack version is 2.1.11")
expect(info_src:find('"factorio_version": "2.1"', 1, true) ~= nil, "factorio_version is 2.1")
expect(info_src:find('"factorio_version": "2.0"', 1, true) == nil, "factorio_version is not 2.0")
expect(info_src:find("base >= 2.1.0", 1, true) ~= nil, "base dependency is 2.1")
expect(info_src:find("base >= 2.0", 1, true) == nil, "base dependency is not pinned to 2.0")
expect(info_src:find("Factorio%-Tiberium >= 2%.1%.0") ~= nil, "optional Tiberium dep is 2.1")
local proto_scan = {
	"prototypes/items/hybrid_charge.lua",
	"prototypes/entities/harv_entity.lua",
	"prototypes/entities/module_bay.lua",
}
for _, path in ipairs(proto_scan) do
	local src = assert(io.open(path, "r")):read("*a")
	expect(src:find("__Red-Alert-Harvester__/", 1, true) == nil, path .. " does not use singular asset prefix")
	expect(src:find("__Red-Alert-Harvesters__/", 1, true) ~= nil, path .. " uses plural asset prefix")
end

local charge_src = assert(io.open("prototypes/items/hybrid_charge.lua", "r")):read("*a")
expect(charge_src:find('localised_name = {"item-name.cncharvester-hybrid-charge"}', 1, true) ~= nil, "charge item sets localised_name")
expect(charge_src:find('localised_name = {"fuel-category-name.cncharvester-hybrid"}', 1, true) ~= nil, "fuel category sets localised_name")

local bay_src = assert(io.open("prototypes/entities/module_bay.lua", "r")):read("*a")
expect(bay_src:find("quality_affects_module_slots = false", 1, true) ~= nil, "bay slots do not scale with quality")
expect(bay_src:find('module_bay("cncharvester-module-bay", 2', 1, true) ~= nil, "ore truck bay is 2 slots")
expect(bay_src:find('module_bay("cncharvester-type2-module-bay", 3', 1, true) ~= nil, "type-2 bay is 3 slots")
expect(not bay_src:find("quality_affects_module_slots = true", 1, true), "no quality-scaled slot flag")

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

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all scoop/hybrid rate checks passed")
