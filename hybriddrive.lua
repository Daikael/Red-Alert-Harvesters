-- Hybrid energy pool: one hidden charge item is the only currently_burning identity.
-- Solids in the fuel tank are converted into that pool. Grid refill is rate-capped.
-- Writing currently_burning without this lock is what latched nuclear-fuel in 2.1.4.

HybridDrive = HybridDrive or {}

HybridDrive.CONVERTER_NAME = "Hybrid-drive"
HybridDrive.BATTERY_NAME = "Hybrid-drive-battery"
HybridDrive.CHARGE_ITEM = "cncharvester-hybrid-charge"
HybridDrive.CHARGE_CATEGORY = "cncharvester-hybrid"
HybridDrive.KICKOFF_ITEMS = { "coal", "wood" }
HybridDrive.NUCLEAR_FUELS = {
	["uranium-fuel-cell"] = true,
	["nuclear-fuel"] = true,
	["fusion-power-cell"] = true,
}
HybridDrive.BANNED_FUELS = {
	["uranium-fuel-cell"] = true,
	["nuclear-fuel"] = true,
	["fusion-power-cell"] = true,
	["cncharvester-hybrid-charge"] = true,
}
-- Matches prototypes/items/hybrid_charge.lua (20× coal). Bar is meaningful; spark is a sliver.
HybridDrive.POOL_CAP = 80000000
HybridDrive.MAX_ALLOWED_FUEL_VALUE = 12000000
-- ~1.6 ticks of Ore Truck drive (75 kW / 60 = 1250 J/tick).
HybridDrive.SPARK_JOULES = 2000
-- Baked-in solar from the recipe panel: ~1/15 of a 60 kW solar. Not removable.
HybridDrive.INTRINSIC_SOLAR_W = 4000
HybridDrive.CONVERSION_EFFICIENCY = 0.90
HybridDrive.DRIVE_OVER_REFILL = 1.10
HybridDrive.BUFFER_SECONDS = 4
-- Quality: faster refill + larger electric cap. Refill stays below drive so
-- sustained driving still net-drains at every quality.
HybridDrive.QUALITY_REFILL_PER_LEVEL = 0.015
HybridDrive.QUALITY_BUFFER_PER_LEVEL = 0.25

HybridDrive.VEHICLE = {
	["cncharvester"] = {
		consumption_w = 150000,
		effectivity = 2,
	},
	["cncharvester-type2"] = {
		consumption_w = 175000,
		effectivity = 2,
	},
}

function HybridDrive.quality_level(quality)
	if not quality then
		return 0
	end
	return quality.level or 0
end

function HybridDrive.rates(vehicle_name, quality)
	local spec = HybridDrive.VEHICLE[vehicle_name]
	if not spec then
		return nil
	end
	local q = HybridDrive.quality_level(quality)
	local drive_w = spec.consumption_w / spec.effectivity
	local refill_w = (drive_w / HybridDrive.DRIVE_OVER_REFILL) * (1 + HybridDrive.QUALITY_REFILL_PER_LEVEL * q)
	if refill_w >= drive_w then
		refill_w = drive_w / HybridDrive.DRIVE_OVER_REFILL
	end
	local grid_pull_w = refill_w / HybridDrive.CONVERSION_EFFICIENCY
	local buffer_s = HybridDrive.BUFFER_SECONDS * (1 + HybridDrive.QUALITY_BUFFER_PER_LEVEL * q)
	local intrinsic_w = HybridDrive.INTRINSIC_SOLAR_W * (1 + HybridDrive.QUALITY_REFILL_PER_LEVEL * q)
	return {
		drive_w = drive_w,
		refill_w = refill_w,
		grid_pull_w = grid_pull_w,
		refill_j_per_tick = refill_w / 60,
		grid_j_per_tick = grid_pull_w / 60,
		intrinsic_w = intrinsic_w,
		intrinsic_j_per_tick = intrinsic_w / 60,
		max_buffer_j = drive_w * buffer_s,
		buffer_s = buffer_s,
		quality_level = q,
		consumption_w = spec.consumption_w,
		effectivity = spec.effectivity,
	}
end

function HybridDrive.ensure_storage()
	storage.hybrid_greeted = storage.hybrid_greeted or {}
	storage.starter_fuel_given = storage.starter_fuel_given or {}
end

local function fuel_value_of(name)
	if not name then
		return 0
	end
	local proto = prototypes and prototypes.item and prototypes.item[name]
	return (proto and proto.fuel_value) or 0
end

function HybridDrive.currently_burning_name(burner)
	if not burner then
		return nil
	end
	local burning = burner.currently_burning
	if not burning then
		return nil
	end
	if type(burning) == "string" then
		return burning
	end
	if burning.name then
		if type(burning.name) == "string" then
			return burning.name
		end
		if burning.name.name then
			return burning.name.name
		end
	end
	return nil
end

function HybridDrive.is_banned_fuel(name)
	return name ~= nil and HybridDrive.BANNED_FUELS[name] == true
end

function HybridDrive.is_nuclear_identity(name)
	return name ~= nil and HybridDrive.NUCLEAR_FUELS[name] == true
end

function HybridDrive.is_overdense_fuel(name)
	return fuel_value_of(name) > HybridDrive.MAX_ALLOWED_FUEL_VALUE
end

function HybridDrive.convertible_joules(name)
	if not name or HybridDrive.is_banned_fuel(name) then
		return 0
	end
	return fuel_value_of(name)
end

local function fuel_inventory(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	return vehicle.get_inventory(defines.inventory.fuel)
end

-- The only legal currently_burning. Always write remaining after assigning
-- currently_burning — the engine fills remaining to POOL_CAP / nuclear-scale.
function HybridDrive.lock_charge(burner, remaining)
	if not burner then
		return 0
	end
	local burning = HybridDrive.currently_burning_name(burner)
	local current = burner.remaining_burning_fuel or 0
	if HybridDrive.is_nuclear_identity(burning) then
		current = 0
	end
	if remaining ~= nil then
		current = remaining
	end
	if current < 0 then
		current = 0
	end
	if current > HybridDrive.POOL_CAP then
		current = HybridDrive.POOL_CAP
	end
	if burning ~= HybridDrive.CHARGE_ITEM then
		burner.currently_burning = HybridDrive.CHARGE_ITEM
	end
	burner.remaining_burning_fuel = current
	return current
end

function HybridDrive.has_energy(vehicle)
	return HybridDrive.available_joules(vehicle) > 0
end

function HybridDrive.available_joules(vehicle)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return 0
	end
	if HybridDrive.currently_burning_name(vehicle.burner) ~= HybridDrive.CHARGE_ITEM then
		return 0
	end
	return vehicle.burner.remaining_burning_fuel or 0
end

function HybridDrive.can_afford(vehicle, joules)
	if not joules or joules <= 0 then
		return true
	end
	if not (vehicle and vehicle.valid) then
		return false
	end
	HybridDrive.convert_inventory_fuels(vehicle)
	return HybridDrive.available_joules(vehicle) >= joules
end

function HybridDrive.spend(vehicle, joules)
	if not joules or joules <= 0 then
		return true
	end
	if not HybridDrive.can_afford(vehicle, joules) then
		return false
	end
	local current = HybridDrive.available_joules(vehicle)
	HybridDrive.lock_charge(vehicle.burner, current - joules)
	return true
end

function HybridDrive.strip_banned_fuel(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local burner = vehicle.burner
	if burner and HybridDrive.is_nuclear_identity(HybridDrive.currently_burning_name(burner)) then
		HybridDrive.lock_charge(burner, 0)
	end
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return
	end
	EachInventoryItem(inv, function(name, count, quality)
		if HybridDrive.is_banned_fuel(name) and count > 0 then
			inv.remove(InventoryItemStack(name, count, quality))
		end
	end)
end

function HybridDrive.convert_inventory_fuels(vehicle)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return 0
	end
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return 0
	end
	local added = 0
	local current = HybridDrive.lock_charge(vehicle.burner)
	EachInventoryItem(inv, function(name, count, quality)
		if count <= 0 then
			return
		end
		if HybridDrive.is_banned_fuel(name) then
			inv.remove(InventoryItemStack(name, count, quality))
			return
		end
		local fv = HybridDrive.convertible_joules(name)
		if fv <= 0 then
			return
		end
		local left = count
		while left > 0 do
			if current + fv > HybridDrive.POOL_CAP then
				break
			end
			local removed = inv.remove(InventoryItemStack(name, 1, quality))
			if removed < 1 then
				break
			end
			current = current + fv
			added = added + fv
			left = left - 1
		end
	end)
	HybridDrive.lock_charge(vehicle.burner, current)
	return added
end

function HybridDrive.apply_spark(burner)
	if not burner then
		return
	end
	HybridDrive.lock_charge(burner, HybridDrive.SPARK_JOULES)
end

function HybridDrive.apply_spark_if_empty(vehicle)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return false
	end
	HybridDrive.strip_banned_fuel(vehicle)
	HybridDrive.convert_inventory_fuels(vehicle)
	if HybridDrive.has_energy(vehicle) then
		return false
	end
	HybridDrive.apply_spark(vehicle.burner)
	return true
end

function HybridDrive.scrub_charge_before_remove(vehicle, buffer)
	if not (vehicle and vehicle.valid) then
		return
	end
	local burner = vehicle.burner
	if burner then
		burner.currently_burning = nil
		burner.remaining_burning_fuel = 0
	end
	HybridDrive.strip_banned_fuel(vehicle)
	if buffer and buffer.valid then
		local count = buffer.get_item_count(HybridDrive.CHARGE_ITEM)
		if count and count > 0 then
			buffer.remove({name = HybridDrive.CHARGE_ITEM, count = count})
		end
		for name, _ in pairs(HybridDrive.NUCLEAR_FUELS) do
			local n = buffer.get_item_count(name)
			if n and n > 0 then
				buffer.remove({name = name, count = n})
			end
		end
	end
end

function HybridDrive.choose_kickoff_item(get_count)
	if not get_count then
		return nil
	end
	for _, name in ipairs(HybridDrive.KICKOFF_ITEMS) do
		if (get_count(name) or 0) >= 1 then
			return name
		end
	end
	return nil
end

-- Consume 1 coal/wood from the placer and add its joules to the hybrid pool.
-- Never inserts the item into the truck (that would become currently_burning).
function HybridDrive.try_take_player_kickoff(vehicle, player)
	if not (vehicle and vehicle.valid and vehicle.burner and player and player.valid) then
		return nil
	end
	if HybridDrive.has_energy(vehicle) then
		return nil
	end
	local name = HybridDrive.choose_kickoff_item(function(item)
		return player.get_item_count(item)
	end)
	if not name then
		return nil
	end
	local joules = HybridDrive.convertible_joules(name)
	if joules <= 0 then
		return nil
	end
	local removed = player.remove_item({name = name, count = 1})
	if not removed or removed < 1 then
		return nil
	end
	local current = HybridDrive.lock_charge(vehicle.burner)
	HybridDrive.lock_charge(vehicle.burner, math.min(HybridDrive.POOL_CAP, current + joules))
	return name
end

function HybridDrive.prepare_vehicle(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	HybridDrive.ensure_storage()
	local id = vehicle.unit_number
	if storage.starter_fuel_given[id] then
		return
	end
	storage.starter_fuel_given[id] = true
	HybridDrive.strip_banned_fuel(vehicle)
	if vehicle.burner and HybridDrive.is_nuclear_identity(HybridDrive.currently_burning_name(vehicle.burner)) then
		HybridDrive.lock_charge(vehicle.burner, 0)
	end
end

-- Recycler exploit: never script-insert these as removable stacks on place.
-- Craft-cost solar-panel + battery are consumed by the recipe only.
HybridDrive.NEVER_GIFT = {
	["solar-panel"] = true,
	["solar-panel-equipment"] = true,
	["battery"] = true,
	["battery-equipment"] = true,
	["Hybrid-drive"] = true,
	["Hybrid-drive-battery"] = true,
	["efficiency-module"] = true,
	["efficiency-module-2"] = true,
	["efficiency-module-3"] = true,
	["speed-module"] = true,
	["speed-module-2"] = true,
	["speed-module-3"] = true,
	["productivity-module"] = true,
	["productivity-module-2"] = true,
	["productivity-module-3"] = true,
	["quality-module"] = true,
	["quality-module-2"] = true,
	["quality-module-3"] = true,
	["coal"] = true,
	["wood"] = true,
}

-- Place/build: no removable freebies. Only joule spark / paid coal conversion.
function HybridDrive.on_built(vehicle, player)
	if not (vehicle and vehicle.valid) then
		return
	end
	HybridDrive.prepare_vehicle(vehicle)
	if player and player.valid then
		HybridDrive.try_take_player_kickoff(vehicle, player)
	end
	HybridDrive.apply_spark_if_empty(vehicle)
end

function HybridDrive.forget(unit_number)
	if storage.hybrid_greeted then
		storage.hybrid_greeted[unit_number] = nil
	end
	if storage.starter_fuel_given then
		storage.starter_fuel_given[unit_number] = nil
	end
end

function HybridDrive.enforce_empty(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	if HybridDrive.has_energy(vehicle) then
		return
	end
	if vehicle.burner then
		HybridDrive.lock_charge(vehicle.burner, 0)
	end
	if vehicle.speed and vehicle.speed ~= 0 then
		vehicle.speed = 0
	end
end

function HybridDrive.grid_stored_energy(grid)
	if not grid then
		return 0
	end
	local sum = 0
	if grid.available_in_batteries then
		sum = grid.available_in_batteries
	end
	if grid.equipment then
		local from_eq = 0
		for _, eq in pairs(grid.equipment) do
			if eq.valid ~= false and eq.energy and eq.energy > 0 then
				from_eq = from_eq + eq.energy
			end
		end
		if from_eq > sum then
			sum = from_eq
		end
	end
	return sum
end

-- Pull stored electric energy from any grid equipment (solar, battery, fusion…).
-- Empty grid → 0. Does not require Hybrid-drive to be installed.
function HybridDrive.take_from_grid(grid, joules)
	if joules <= 0 or not grid then
		return 0
	end
	local batteries = {}
	local others = {}
	if not grid.equipment then
		return 0
	end
	for _, eq in pairs(grid.equipment) do
		if eq.valid ~= false and eq.energy and eq.energy > 0 then
			local eq_type = eq.type or (eq.prototype and eq.prototype.type)
			if eq_type == "battery-equipment" then
				table.insert(batteries, eq)
			else
				table.insert(others, eq)
			end
		end
	end
	local left = joules
	for _, list in ipairs({batteries, others}) do
		for _, eq in ipairs(list) do
			local take = math.min(eq.energy, left)
			eq.energy = eq.energy - take
			left = left - take
			if left <= 0 then
				return joules
			end
		end
	end
	return joules - left
end

-- Electric refill only. Never shrinks a solid-converted pool. Never changes
-- identity away from hybrid-charge. Never fills a full charge/nuclear bar.
function HybridDrive.add_burner_energy(burner, joules, electric_cap)
	if not (burner and joules > 0) then
		return 0
	end
	local current = HybridDrive.lock_charge(burner)
	local cap = electric_cap
	if not cap then
		return 0
	end
	if current >= cap then
		return 0
	end
	local add = math.min(joules, cap - current)
	if add <= 0 then
		return 0
	end
	HybridDrive.lock_charge(burner, current + add)
	return add
end

function HybridDrive.maintain(vehicle)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return
	end
	HybridDrive.strip_banned_fuel(vehicle)
	HybridDrive.convert_inventory_fuels(vehicle)
	local burning = HybridDrive.currently_burning_name(vehicle.burner)
	if burning ~= HybridDrive.CHARGE_ITEM then
		local keep = 0
		if burning and not HybridDrive.is_nuclear_identity(burning) then
			keep = vehicle.burner.remaining_burning_fuel or 0
		end
		HybridDrive.lock_charge(vehicle.burner, keep)
	end
	HybridDrive.enforce_empty(vehicle)
end

function HybridDrive.tick(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	HybridDrive.maintain(vehicle)
	local rates = HybridDrive.rates(vehicle.name, vehicle.quality)
	if not rates then
		return
	end
	local burner = vehicle.burner
	if not burner then
		return
	end
	local from_grid = 0
	local grid = vehicle.grid
	if grid and HybridDrive.grid_stored_energy(grid) > 0 then
		from_grid = HybridDrive.take_from_grid(grid, rates.grid_j_per_tick)
	end
	local incoming = from_grid + (rates.intrinsic_j_per_tick or 0)
	if incoming <= 0 then
		return
	end
	local converted = incoming * HybridDrive.CONVERSION_EFFICIENCY
	if rates.refill_j_per_tick and converted > rates.refill_j_per_tick then
		converted = rates.refill_j_per_tick
	end
	HybridDrive.add_burner_energy(burner, converted, rates.max_buffer_j)
end
