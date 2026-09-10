-- Hybrid energy pool: one hidden charge item is the only currently_burning identity.
-- Solids in the fuel tank are converted into that pool. Grid refill is rate-capped.
-- Writing currently_burning without this lock is what latched nuclear-fuel in 2.1.4.

HybridDrive = HybridDrive or {}

-- Deprecated Hybrid-drive / Hybrid-drive-battery equipment was removed in 2.1.10.
-- Names stay on NEVER_GIFT so leftover scripts cannot re-insert them.
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
-- Baked-in solar from the recipe panel: 18 kW (~30% of a 60 kW panel). Not removable.
HybridDrive.INTRINSIC_SOLAR_W = 18000
HybridDrive.CONVERSION_EFFICIENCY = 0.90
HybridDrive.DRIVE_OVER_REFILL = 1.10
-- Moving: grid→pool stays 10% below drive. Parked: pull much harder so a
-- charged battery visibly climbs the 80 MJ hybrid bar (old 4 s / 300 kJ cap
-- was 0.4% of the bar and felt dead).
HybridDrive.BUFFER_SECONDS = 4
HybridDrive.PARKED_GRID_MULT = 6
-- Convert tank solids on demand instead of dumping the whole stack into the
-- pool (that hid battery charge and looked like several fuel per scoop).
HybridDrive.CONVERT_FLOOR_J = 4000000
-- Grid refill stays below drive while moving so sustained driving net-drains.
-- Intrinsic idle trickle scales harder with quality and efficiency modules.
HybridDrive.QUALITY_REFILL_PER_LEVEL = 0.015
HybridDrive.QUALITY_INTRINSIC_PER_LEVEL = 0.20
HybridDrive.MODULE_INTRINSIC_FROM_EFFICIENCY = 0.50
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

function HybridDrive.rates(vehicle_name, quality, effects)
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
	local q_intrinsic = 1 + HybridDrive.QUALITY_INTRINSIC_PER_LEVEL * q
	local module_scale = 1
	if effects and (effects.consumption or 0) < 0 then
		module_scale = 1 - (effects.consumption * HybridDrive.MODULE_INTRINSIC_FROM_EFFICIENCY)
	end
	local intrinsic_w = HybridDrive.INTRINSIC_SOLAR_W * q_intrinsic * module_scale
	local parked_grid_pull_w = grid_pull_w * HybridDrive.PARKED_GRID_MULT
	local parked_refill_w = parked_grid_pull_w * HybridDrive.CONVERSION_EFFICIENCY
	return {
		drive_w = drive_w,
		refill_w = refill_w,
		grid_pull_w = grid_pull_w,
		parked_grid_pull_w = parked_grid_pull_w,
		parked_refill_w = parked_refill_w,
		refill_j_per_tick = refill_w / 60,
		grid_j_per_tick = grid_pull_w / 60,
		parked_grid_j_per_tick = parked_grid_pull_w / 60,
		parked_refill_j_per_tick = parked_refill_w / 60,
		intrinsic_w = intrinsic_w,
		intrinsic_j_per_tick = intrinsic_w / 60,
		max_buffer_j = drive_w * buffer_s,
		electric_cap_j = HybridDrive.POOL_CAP,
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

-- Cars expose the tank on LuaBurner.inventory / get_fuel_inventory, not
-- reliably via defines.inventory.fuel (that index can be trunk or nil).
-- Ore Truck is 2 slots; hitting the wrong inv looks like "won't refuel".
function HybridDrive.fuel_inventory(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	local burner = vehicle.burner
	if burner then
		local inv = burner.inventory
		if inv and inv.valid then
			return inv
		end
	end
	if vehicle.get_fuel_inventory then
		local ok, inv = pcall(function()
			return vehicle.get_fuel_inventory()
		end)
		if ok and inv and inv.valid then
			return inv
		end
	end
	if vehicle.get_inventory and defines and defines.inventory then
		local ok, inv = pcall(function()
			return vehicle.get_inventory(defines.inventory.fuel)
		end)
		if ok and inv and inv.valid then
			return inv
		end
	end
	return nil
end

local function fuel_inventory(vehicle)
	return HybridDrive.fuel_inventory(vehicle)
end

local function unlock_inventory_bar(inv)
	if not (inv and inv.supports_bar and inv.get_bar and inv.set_bar) then
		return nil
	end
	local ok_sup, supported = pcall(function()
		return inv.supports_bar()
	end)
	if not ok_sup or not supported then
		return nil
	end
	local ok_bar, bar = pcall(function()
		return inv.get_bar()
	end)
	if not ok_bar then
		return nil
	end
	pcall(function()
		inv.set_bar()
	end)
	return bar
end

local function restore_inventory_bar(inv, bar)
	if bar == nil or not (inv and inv.set_bar) then
		return
	end
	pcall(function()
		inv.set_bar(bar)
	end)
end

local function insert_stack(dest, stack)
	local ok, inserted = pcall(function()
		return dest.insert(stack)
	end)
	if not ok then
		return 0
	end
	if type(inserted) ~= "number" then
		inserted = inserted and stack.count or 0
	end
	if inserted > 0 then
		return inserted
	end
	if stack.quality then
		ok, inserted = pcall(function()
			return dest.insert({name = stack.name, count = stack.count})
		end)
		if ok and type(inserted) == "number" and inserted > 0 then
			return inserted
		end
	end
	return 0
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

function HybridDrive.has_convertible_fuel(vehicle)
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return false
	end
	local found = false
	EachInventoryItem(inv, function(name, count)
		if found or count <= 0 then
			return
		end
		if HybridDrive.convertible_joules(name) > 0 then
			found = true
		end
	end)
	return found
end

-- Pool, stored grid energy, or tank solids. Empty solid slots are OK when
-- the pool or a charged grid can still run the truck.
function HybridDrive.has_usable_energy(vehicle)
	if not (vehicle and vehicle.valid) then
		return false
	end
	HybridDrive.convert_inventory_fuels(vehicle)
	if HybridDrive.available_joules(vehicle) > 0 then
		return true
	end
	if HybridDrive.grid_stored_energy(vehicle.grid) > 0 then
		return true
	end
	return HybridDrive.has_convertible_fuel(vehicle)
end

-- Move convertible burnables (coal/wood/chemical, not nuclear / hybrid-charge)
-- from a chest or trunk into the vehicle fuel inventory. Uses insert()'s
-- return count so we never delete extra from the source. Fills dest slots.
-- Returns the number of items moved.
function HybridDrive.transfer_convertible_fuel(source, dest)
	if not (source and source.valid and dest and dest.valid) then
		return 0
	end
	local saved_bar = unlock_inventory_bar(dest)
	if dest.is_full and dest.is_full() then
		restore_inventory_bar(dest, saved_bar)
		return 0
	end
	local moved = 0
	local contents = {}
	EachInventoryItem(source, function(name, count, quality)
		contents[#contents + 1] = {name = name, count = count, quality = quality}
	end)
	local prefer = {}
	EachInventoryItem(dest, function(name, count)
		if count and count > 0 and HybridDrive.convertible_joules(name) > 0 then
			prefer[name] = true
		end
	end)
	local function take(filter_prefer)
		for _, item in ipairs(contents) do
			if dest.is_full and dest.is_full() then
				return
			end
			local can = item.count and item.count > 0
				and HybridDrive.convertible_joules(item.name) > 0
				and (not filter_prefer or prefer[item.name])
			if can then
				local stack = InventoryItemStack(item.name, item.count, item.quality)
				local inserted = insert_stack(dest, stack)
				if inserted > 0 then
					pcall(function()
						source.remove(InventoryItemStack(item.name, inserted, item.quality))
					end)
					item.count = item.count - inserted
					moved = moved + inserted
				end
			end
		end
	end
	if next(prefer) then
		take(true)
	end
	take(false)
	restore_inventory_bar(dest, saved_bar)
	return moved
end

function HybridDrive.tank_convertible_joules(vehicle)
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return 0
	end
	local sum = 0
	EachInventoryItem(inv, function(name, count)
		if count and count > 0 then
			sum = sum + HybridDrive.convertible_joules(name) * count
		end
	end)
	return sum
end

function HybridDrive.potential_joules(vehicle)
	if not (vehicle and vehicle.valid) then
		return 0
	end
	local pool = HybridDrive.available_joules(vehicle)
	local grid = HybridDrive.grid_stored_energy(vehicle.grid)
	return pool + grid * HybridDrive.CONVERSION_EFFICIENCY + HybridDrive.tank_convertible_joules(vehicle)
end

-- Dry check: pool + convertible solids + stored grid (90%). Does not drain
-- the grid. A token spark or 1 kJ leftover still cannot pay a full scoop.
function HybridDrive.can_afford(vehicle, joules)
	if not joules or joules <= 0 then
		return true
	end
	if not (vehicle and vehicle.valid) then
		return false
	end
	return HybridDrive.potential_joules(vehicle) >= joules
end

-- Pull stored grid energy into the pool to cover a shortfall. Not rate-capped
-- (that cap is the per-tick idle/drive refill). Action cost is the gate.
function HybridDrive.cover_from_grid(vehicle, joules)
	if not joules or joules <= 0 or not (vehicle and vehicle.valid and vehicle.burner) then
		return 0
	end
	local pull = joules / HybridDrive.CONVERSION_EFFICIENCY
	local got = HybridDrive.take_from_grid(vehicle.grid, pull)
	local added = got * HybridDrive.CONVERSION_EFFICIENCY
	if added <= 0 then
		return 0
	end
	local current = HybridDrive.lock_charge(vehicle.burner)
	HybridDrive.lock_charge(vehicle.burner, math.min(HybridDrive.POOL_CAP, current + added))
	return added
end

function HybridDrive.spend(vehicle, joules)
	if not joules or joules <= 0 then
		return true
	end
	if not HybridDrive.can_afford(vehicle, joules) then
		return false
	end
	HybridDrive.convert_inventory_fuels(vehicle, joules)
	local current = HybridDrive.available_joules(vehicle)
	if current < joules then
		HybridDrive.cover_from_grid(vehicle, joules - current)
		current = HybridDrive.available_joules(vehicle)
	end
	if current < joules then
		return false
	end
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

-- Convert tank solids into the pool until `target_joules` (default: a 4 MJ
-- working floor). Leaves the rest in the tank so a stack does not vanish
-- on the first tick and battery charge can still climb the bar.
function HybridDrive.convert_inventory_fuels(vehicle, target_joules)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return 0
	end
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return 0
	end
	local want = target_joules or HybridDrive.CONVERT_FLOOR_J
	if want < 0 then
		want = 0
	end
	if want > HybridDrive.POOL_CAP then
		want = HybridDrive.POOL_CAP
	end
	local added = 0
	local current = HybridDrive.lock_charge(vehicle.burner)
	EachInventoryItem(inv, function(name, count, quality)
		if count <= 0 or current >= want then
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
		while left > 0 and current < want do
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
	if HybridDrive.has_usable_energy(vehicle) then
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

local function equipment_type(eq)
	if not eq then
		return nil
	end
	if eq.type then
		return eq.type
	end
	if eq.prototype and eq.prototype.type then
		return eq.prototype.type
	end
	return nil
end

local function equipment_energy(eq)
	if not eq or eq.valid == false then
		return 0
	end
	return eq.energy or 0
end

-- Pull stored electric energy from any grid equipment (solar, battery, fusion…).
-- Batteries first so a charged cell is the obvious idle refill source.
-- Empty grid → 0. Uses vanilla portable solar/battery (or any stored equipment energy).
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
		if equipment_energy(eq) > 0 then
			if equipment_type(eq) == "battery-equipment" then
				table.insert(batteries, eq)
			else
				table.insert(others, eq)
			end
		end
	end
	local left = joules
	for _, list in ipairs({batteries, others}) do
		for _, eq in ipairs(list) do
			local have = equipment_energy(eq)
			local take = math.min(have, left)
			if take > 0 then
				eq.energy = have - take
				left = left - take
			end
			if left <= 0 then
				return joules
			end
		end
	end
	return joules - left
end

-- Electric refill only. Never shrinks an existing pool. Never changes
-- identity away from hybrid-charge. Caps at the 80 MJ hybrid pool so a
-- charged battery can fill a visible fraction of the bar.
function HybridDrive.add_burner_energy(burner, joules, electric_cap)
	if not (burner and joules > 0) then
		return 0
	end
	local current = HybridDrive.lock_charge(burner)
	local cap = electric_cap or HybridDrive.POOL_CAP
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
end

function HybridDrive.tick(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	HybridDrive.maintain(vehicle)
	local effects = nil
	if ModuleBay and ModuleBay.effects then
		effects = ModuleBay.effects(vehicle)
	end
	local rates = HybridDrive.rates(vehicle.name, SafeQuality(vehicle), effects)
	local burner = vehicle.burner
	if rates and burner then
		local moving = vehicle.speed and math.abs(vehicle.speed) > 0.001
		local pull_j = rates.grid_j_per_tick
		local cap_j = rates.refill_j_per_tick
		if not moving then
			pull_j = rates.parked_grid_j_per_tick or pull_j
			cap_j = rates.parked_refill_j_per_tick or cap_j
		end
		local from_grid = 0
		local grid = vehicle.grid
		if grid and HybridDrive.grid_stored_energy(grid) > 0 then
			from_grid = HybridDrive.take_from_grid(grid, pull_j)
		end
		local grid_converted = from_grid * HybridDrive.CONVERSION_EFFICIENCY
		if cap_j and grid_converted > cap_j then
			grid_converted = cap_j
		end
		local intrinsic_converted = (rates.intrinsic_j_per_tick or 0) * HybridDrive.CONVERSION_EFFICIENCY
		local converted = grid_converted + intrinsic_converted
		-- Moving: keep conversion below drive so driving still net-drains.
		-- Parked: battery/grid is allowed the higher parked cap; intrinsic stacks.
		if moving and rates.refill_j_per_tick and converted > rates.refill_j_per_tick then
			converted = rates.refill_j_per_tick
		end
		if converted > 0 then
			HybridDrive.add_burner_energy(burner, converted, rates.electric_cap_j or HybridDrive.POOL_CAP)
		end
	end
	HybridDrive.enforce_empty(vehicle)
end
