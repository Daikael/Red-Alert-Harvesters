-- Scripted scoop: entity quality (Layer A) + companion module effects (Layer B).
-- Cars cannot host modules; effects are read from the companion mining-drill bay.

require "utilities"
require "modulebay"
require "hybriddrive"

Scoop = Scoop or {}

-- Modest quality bonuses (not vanilla drill +1 tile/level).
Scoop.QUALITY_RADIUS_PER_LEVEL = 0.25
Scoop.QUALITY_SPEED_PER_LEVEL = 0.05
-- Per-item mining at the same average throughput as the old 8/16 per 320 ticks.
-- Ore: 40 ticks (0.667 s) → 8×40 = 320 ticks for 8 items (~1.50 items/s).
-- Tiberium: 20 ticks (0.333 s) → 16×20 = 320 ticks for 16 items (~3.00 items/s).
Scoop.EQUIV_WINDOW_TICKS = 320
Scoop.ORE_INTERVAL_TICKS = 40
Scoop.TYPE2_INTERVAL_TICKS = 20
Scoop.BASE_DRIVE_INTERVAL_TICKS = Scoop.ORE_INTERVAL_TICKS
-- Floor is low enough that speed-module scaling matches the old 320-tick curve
-- (40/5 = 8, 20/5 = 4). The old min of 12 never bound that curve.
Scoop.MIN_INTERVAL_TICKS = 4
Scoop.ITEMS_PER_SCOOP = 1
Scoop.DRIVE_ITEMS_PER_SCOOP = 1
Scoop.TYPE2_ITEMS_PER_SCOOP = 1
Scoop.LEGACY_ORE_ITEMS = 8
Scoop.LEGACY_TYPE2_ITEMS = 16
Scoop.AUTO_LEGACY_SCOOPS_PER_LOCATION = 3
Scoop.EFFICIENCY_DRAIN_WEIGHT = 0.25
-- 120 kJ/item = 4× the 2.1.10 tax. One solid fuel (12 MJ) ≈ 100 items.
-- Sustained ore mining (~1.50/s) lasts ~67 s per solid fuel; Tiberium ~33 s.
-- Still far below the old 300 kJ/item / "5 solid fuel per dig" class.
Scoop.PARASITIC_JOULES_BASE = 120000
Scoop.PARASITIC_MIN_FACTOR = 0.2
Scoop.JOULES_PER_ITEM = 120000

function Scoop.interval_base(vehicle)
	if vehicle and vehicle.name == "cncharvester-type2" then
		return Scoop.TYPE2_INTERVAL_TICKS
	end
	return Scoop.ORE_INTERVAL_TICKS
end

function Scoop.scoop_items(vehicle)
	return Scoop.ITEMS_PER_SCOOP
end

function Scoop.items_per_location(vehicle)
	local legacy = Scoop.LEGACY_ORE_ITEMS
	if vehicle and vehicle.name == "cncharvester-type2" then
		legacy = Scoop.LEGACY_TYPE2_ITEMS
	end
	return Scoop.AUTO_LEGACY_SCOOPS_PER_LOCATION * legacy
end

local EMPTY_EFFECTS = {
	speed = 0,
	productivity = 0,
	consumption = 0,
	pollution = 0,
	quality = 0,
}

function Scoop.quality_level(quality)
	if not quality then
		return 0
	end
	return quality.level or 0
end

function Scoop.drain_multiplier(quality, consumption_effect)
	local drain = 1
	if quality and quality.mining_drill_resource_drain_multiplier then
		drain = quality.mining_drill_resource_drain_multiplier
	elseif quality and quality.level then
		-- Vanilla-like 1/6 less drain per level when the prototype field is missing.
		drain = math.max(0, 1 - (quality.level / 6))
	end
	local consumption = consumption_effect or 0
	if consumption < 0 then
		drain = drain * (1 + consumption * Scoop.EFFICIENCY_DRAIN_WEIGHT)
	end
	return math.max(0.05, math.min(1, drain))
end

function Scoop.interval_ticks(base_ticks, speed_effect, quality_level)
	local denom = 1 + (speed_effect or 0) + Scoop.QUALITY_SPEED_PER_LEVEL * (quality_level or 0)
	if denom < 0.2 then
		denom = 0.2
	end
	return math.max(Scoop.MIN_INTERVAL_TICKS, math.floor((base_ticks or Scoop.BASE_DRIVE_INTERVAL_TICKS) / denom))
end

function Scoop.radius(base_radius, quality_level)
	return (base_radius or 1) + Scoop.QUALITY_RADIUS_PER_LEVEL * (quality_level or 0)
end

function Scoop.parasitic_joules(consumption_effect)
	return Scoop.action_joules(Scoop.ITEMS_PER_SCOOP, consumption_effect, 0)
end

function Scoop.action_joules(item_count, consumption_effect, speed_effect, quality_level)
	local n = math.max(0, math.floor(item_count or 0))
	if n <= 0 then
		return 0
	end
	local eff = 1 + (consumption_effect or 0)
	if eff < Scoop.PARASITIC_MIN_FACTOR then
		eff = Scoop.PARASITIC_MIN_FACTOR
	end
	local speed = 1 + math.max(0, speed_effect or 0) + Scoop.QUALITY_SPEED_PER_LEVEL * (quality_level or 0)
	return n * Scoop.JOULES_PER_ITEM * eff * speed
end

function Scoop.apply_parasitic_fuel(vehicle, joules)
	if not (vehicle and vehicle.valid and joules and joules > 0) then
		return 0
	end
	local left = joules
	local burner = vehicle.burner
	if burner and (burner.remaining_burning_fuel or 0) > 0 then
		local take = math.min(burner.remaining_burning_fuel, left)
		burner.remaining_burning_fuel = burner.remaining_burning_fuel - take
		left = left - take
	end
	if left <= 0 then
		return joules
	end
	local fuel = vehicle.get_inventory(defines.inventory.fuel)
	if not (fuel and fuel.valid) then
		return joules - left
	end
	EachInventoryItem(fuel, function(name, count, quality)
		if left <= 0 then
			return
		end
		local proto = ItemPrototype(name)
		if not (proto and proto.fuel_value and proto.fuel_value > 0) then
			return
		end
		local used = math.min(count, math.ceil(left / proto.fuel_value))
		if used > 0 then
			fuel.remove(InventoryItemStack(name, used, quality))
			left = left - used * proto.fuel_value
		end
	end)
	return joules - math.max(0, left)
end

function Scoop.roll_quality_fallback(start_quality, quality_effect, rng)
	rng = rng or math.random
	local q = start_quality
	if not q then
		return nil
	end
	if (quality_effect or 0) > 0 and rng() < quality_effect then
		if q.next then
			q = q.next
		end
		while q and q.next and (q.next_probability or 0) > 0 and rng() < q.next_probability do
			q = q.next
		end
	end
	return q
end

function Scoop.roll_product_quality(start_quality, quality_effect, force)
	local seed = start_quality
	if not seed and prototypes and prototypes.quality then
		seed = prototypes.quality["normal"]
	end
	if not seed then
		return "normal"
	end
	if seed.roll_quality then
		local rolled = seed.roll_quality(quality_effect or 0, math.random(), force)
		return rolled or seed
	end
	return Scoop.roll_quality_fallback(seed, quality_effect, math.random)
end

function Scoop.read_effects(vehicle)
	local effects = ModuleBay.effects(vehicle)
	if not effects then
		return EMPTY_EFFECTS
	end
	return {
		speed = effects.speed or 0,
		productivity = effects.productivity or 0,
		consumption = effects.consumption or 0,
		pollution = effects.pollution or 0,
		quality = effects.quality or 0,
	}
end

local function is_infinite_resource(ore)
	local proto = ore.prototype
	return proto and proto.infinite_resource
end

local function product_name(ore)
	return ResourceProductItemName(ore)
end

local function decrement_resource(ore)
	if not (ore and ore.valid) then
		return
	end
	if is_infinite_resource(ore) then
		local min_amount = ore.prototype.minimum_resource_amount or 0
		if ore.amount > min_amount then
			ore.amount = ore.amount - 1
		end
		return
	end
	if ore.amount > 1 then
		ore.amount = ore.amount - 1
	else
		ore.destroy()
	end
end

local function insert_one(trunk, name, quality)
	local stack = InventoryItemStack(name, 1, quality)
	if not trunk.can_insert(stack) then
		return false
	end
	return trunk.insert(stack) > 0
end

-- Harvest one resource entity. Returns {inserted=bool, full=bool}.
function Scoop.harvest_resource(vehicle, ore, trunk, units)
	if not (vehicle and vehicle.valid and ore and ore.valid and trunk and trunk.valid) then
		return {inserted = false, full = false}
	end
	if not IsHarvestableResource(ore) then
		return {inserted = false, full = false}
	end

	local effects = Scoop.read_effects(vehicle)
	local vq = vehicle.quality
	local drain_mult = Scoop.drain_multiplier(vq, effects.consumption)
	local name = product_name(ore)
	local force = vehicle.force
	local seed_quality = prototypes.quality and prototypes.quality["normal"]
	local inserted = false
	local full = false
	units = math.max(1, math.floor(units or 1))

	for _ = 1, units do
		local quality = Scoop.roll_product_quality(seed_quality, effects.quality, force)
		if not insert_one(trunk, name, quality) then
			full = true
			break
		end
		inserted = true

		if math.random() < drain_mult then
			decrement_resource(ore)
			if not ore.valid then
				break
			end
		end

		-- Productivity: extra product, no extra drain.
		if (effects.productivity or 0) > 0 and math.random() < effects.productivity then
			local bonus_q = Scoop.roll_product_quality(seed_quality, effects.quality, force)
			if not insert_one(trunk, name, bonus_q) then
				full = true
				break
			end
		end
	end

	if inserted and (effects.pollution or 0) ~= 0 and vehicle.surface and vehicle.surface.valid then
		local pollution = 0.5 * (1 + effects.pollution)
		if pollution > 0 then
			vehicle.surface.pollute(vehicle.position, pollution)
		end
	end

	return {inserted = inserted, full = full}
end

function Scoop.harvest_area(vehicle, ores, total_items)
	local valid = {}
	for _, ore in pairs(ores or {}) do
		if ore.valid then
			table.insert(valid, ore)
		end
	end
	if #valid <= 0 then
		return {inserted = false, full = false}
	end
	total_items = math.max(1, math.floor(total_items or Scoop.scoop_items(vehicle)))
	local effects = Scoop.read_effects(vehicle)
	local qlevel = Scoop.quality_level(vehicle and vehicle.quality)
	local cost = Scoop.action_joules(total_items, effects.consumption, effects.speed, qlevel)
	-- Pay the full planned insert before any ore is added. Default is 1 item.
	if not HybridDrive.can_afford(vehicle, cost) then
		return {inserted = false, full = false, no_fuel = true}
	end
	local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
	if not trunk then
		return {inserted = false, full = true, no_fuel = false}
	end
	if not HybridDrive.spend(vehicle, cost) then
		return {inserted = false, full = false, no_fuel = true}
	end
	local left = total_items
	local any = false
	local full = false
	for _, ore in ipairs(valid) do
		while left > 0 and ore.valid do
			local result = Scoop.harvest_resource(vehicle, ore, trunk, 1)
			if result.inserted then
				any = true
				left = left - 1
			else
				if result.full then
					full = true
				end
				break
			end
			if result.full then
				full = true
				break
			end
		end
		if full or left <= 0 then
			break
		end
	end
	-- Inventory-full / missed insert: do not keep the tax.
	if not any and cost > 0 and vehicle.burner then
		local current = HybridDrive.available_joules(vehicle)
		HybridDrive.lock_charge(vehicle.burner, current + cost)
	end
	return {inserted = any, full = full, no_fuel = false}
end
