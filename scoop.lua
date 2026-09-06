-- Scripted scoop: entity quality (Layer A) + companion module effects (Layer B).
-- Cars cannot host modules; effects are read from the companion mining-drill bay.

require "utilities"
require "modulebay"

Scoop = Scoop or {}

-- Modest quality bonuses (not vanilla drill +1 tile/level).
Scoop.QUALITY_RADIUS_PER_LEVEL = 0.25
Scoop.QUALITY_SPEED_PER_LEVEL = 0.05
-- 320 ticks = tester-approved 1.875× vs the original 600-tick cadence (~5.33s).
-- Frequency only; DRIVE_ITEMS_PER_SCOOP stays 4.
Scoop.BASE_DRIVE_INTERVAL_TICKS = 320
Scoop.MIN_INTERVAL_TICKS = 12
Scoop.DRIVE_ITEMS_PER_SCOOP = 4
Scoop.EFFICIENCY_DRAIN_WEIGHT = 0.25

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

function Scoop.harvest_area(vehicle, ores, units_each)
	local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
	if not trunk then
		return {inserted = false, full = true}
	end
	local any = false
	local full = false
	for _, ore in pairs(ores) do
		if ore.valid then
			local result = Scoop.harvest_resource(vehicle, ore, trunk, units_each)
			any = any or result.inserted
			if result.full then
				full = true
				break
			end
		end
	end
	return {inserted = any, full = full}
end
