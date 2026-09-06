-- Hybrid-drive: pull grid electricity into the car burner at a capped rate.
-- Sustained driving net-drains even with full batteries + a strong generator.

HybridDrive = HybridDrive or {}

HybridDrive.CONVERTER_NAME = "Hybrid-drive"
HybridDrive.BATTERY_NAME = "Hybrid-drive-battery"
-- Never invent coal/wood/nuclear items. Player-built kickoff may consume 1 coal/wood
-- from the placer. Otherwise a tiny joule spark (hidden charge identity) lets
-- Hybrid-drive start; remaining is clamped so placing a truck is not a full fuel bar.
HybridDrive.CHARGE_ITEM = "cncharvester-hybrid-charge"
HybridDrive.KICKOFF_ITEMS = { "coal", "wood" }
HybridDrive.BANNED_FUELS = {
	["uranium-fuel-cell"] = true,
	["nuclear-fuel"] = true,
	["fusion-power-cell"] = true,
	["cncharvester-hybrid-charge"] = true,
}
-- Coal is 4 MJ. Anything denser than solid fuel is treated as kickoff-OP.
HybridDrive.MAX_ALLOWED_FUEL_VALUE = 12000000
-- ~1.6 ticks of Ore Truck drive (75 kW / 60 = 1250 J/tick). Not a coal/wood bar.
HybridDrive.SPARK_JOULES = 2000
HybridDrive.CONVERSION_EFFICIENCY = 0.90
-- Driving draw is 10% above max refill so you cannot cruise on electric alone.
HybridDrive.DRIVE_OVER_REFILL = 1.10
HybridDrive.BUFFER_SECONDS = 4

-- Prototype consumption (kW strings) and effectivity from harv_entity.lua.
-- Actual burner draw ≈ consumption / effectivity (effectivity 2 → 75 / 87.5 kW).
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

function HybridDrive.rates(vehicle_name)
	local spec = HybridDrive.VEHICLE[vehicle_name]
	if not spec then
		return nil
	end
	local drive_w = spec.consumption_w / spec.effectivity
	local refill_w = drive_w / HybridDrive.DRIVE_OVER_REFILL
	local grid_pull_w = refill_w / HybridDrive.CONVERSION_EFFICIENCY
	return {
		drive_w = drive_w,
		refill_w = refill_w,
		grid_pull_w = grid_pull_w,
		refill_j_per_tick = refill_w / 60,
		grid_j_per_tick = grid_pull_w / 60,
		max_buffer_j = drive_w * HybridDrive.BUFFER_SECONDS,
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

local function currently_burning_name(burner)
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

-- Named nuclear-tier / leftover hidden charge. Used on first prepare only.
function HybridDrive.is_banned_fuel(name)
	return name ~= nil and HybridDrive.BANNED_FUELS[name] == true
end

function HybridDrive.is_overdense_fuel(name)
	return fuel_value_of(name) > HybridDrive.MAX_ALLOWED_FUEL_VALUE
end

local function fuel_inventory(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	return vehicle.get_inventory(defines.inventory.fuel)
end

function HybridDrive.strip_banned_fuel(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local burner = vehicle.burner
	if burner then
		local burning = currently_burning_name(burner)
		-- Charge identity is the non-lootable spark/hybrid carrier; leave it.
		if burning and HybridDrive.is_banned_fuel(burning) and burning ~= HybridDrive.CHARGE_ITEM then
			burner.currently_burning = nil
			burner.remaining_burning_fuel = 0
		end
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

function HybridDrive.ignite_charge(burner)
	if not burner then
		return
	end
	burner.currently_burning = HybridDrive.CHARGE_ITEM
	-- Writing currently_burning fills remaining to the item's full fuel_value.
	-- Always clamp; a full charge bar is the "free fuel bar" exploit.
	burner.remaining_burning_fuel = 0
end

function HybridDrive.apply_spark(burner)
	if not burner then
		return
	end
	HybridDrive.ignite_charge(burner)
	burner.remaining_burning_fuel = HybridDrive.SPARK_JOULES
end

function HybridDrive.apply_spark_if_empty(vehicle)
	if not (vehicle and vehicle.valid and vehicle.burner) then
		return false
	end
	local inv = fuel_inventory(vehicle)
	if inv and inv.valid and inv.get_item_count() > 0 then
		return false
	end
	local burning = currently_burning_name(vehicle.burner)
	if burning and burning ~= HybridDrive.CHARGE_ITEM and not HybridDrive.is_banned_fuel(burning) then
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
	if burner and currently_burning_name(burner) == HybridDrive.CHARGE_ITEM then
		burner.currently_burning = nil
		burner.remaining_burning_fuel = 0
	end
	HybridDrive.strip_banned_fuel(vehicle)
	if buffer and buffer.valid then
		local count = buffer.get_item_count(HybridDrive.CHARGE_ITEM)
		if count and count > 0 then
			buffer.remove({name = HybridDrive.CHARGE_ITEM, count = count})
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

-- Approach A: consume 1 coal (else wood) from the placing player. Never spawn items.
-- Returns the item name moved, or nil if the tank stays empty.
function HybridDrive.try_take_player_kickoff(vehicle, player)
	if not (vehicle and vehicle.valid and player and player.valid) then
		return nil
	end
	local inv = fuel_inventory(vehicle)
	if not (inv and inv.valid) then
		return nil
	end
	if inv.get_item_count() > 0 then
		return nil
	end
	local name = HybridDrive.choose_kickoff_item(function(item)
		return player.get_item_count(item)
	end)
	if not name then
		return nil
	end
	local removed = player.remove_item({name = name, count = 1})
	if not removed or removed < 1 then
		return nil
	end
	local inserted = inv.insert({name = name, count = 1})
	if inserted < 1 then
		player.insert({name = name, count = 1})
		return nil
	end
	return name
end

function HybridDrive.prepare_vehicle(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	HybridDrive.ensure_storage()
	local id = vehicle.unit_number
	-- Once per unit_number: strip injected nuclear-tier / hidden charge.
	-- Never insert free coal/wood. Player-built kickoff is try_take_player_kickoff.
	if storage.starter_fuel_given[id] then
		return
	end
	storage.starter_fuel_given[id] = true
	HybridDrive.strip_banned_fuel(vehicle)
end

function HybridDrive.auto_equip(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local grid = vehicle.grid
	if not grid then
		return
	end
	HybridDrive.ensure_storage()
	local id = vehicle.unit_number
	if storage.hybrid_greeted[id] then
		return
	end
	storage.hybrid_greeted[id] = true
	if not grid.find(HybridDrive.CONVERTER_NAME) then
		grid.put{name = HybridDrive.CONVERTER_NAME}
	end
	if not grid.find(HybridDrive.BATTERY_NAME) then
		grid.put{name = HybridDrive.BATTERY_NAME}
	end
end

function HybridDrive.forget(unit_number)
	if storage.hybrid_greeted then
		storage.hybrid_greeted[unit_number] = nil
	end
	if storage.starter_fuel_given then
		storage.starter_fuel_given[unit_number] = nil
	end
end

local function take_from_grid(grid, joules)
	if joules <= 0 or not grid then
		return 0
	end
	local batteries = {}
	local others = {}
	for _, eq in pairs(grid.equipment) do
		if eq.valid and eq.energy and eq.energy > 0 then
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

function HybridDrive.add_burner_energy(burner, joules, max_buffer)
	if not (burner and joules > 0) then
		return 0
	end
	local burning = currently_burning_name(burner)
	-- Empty burner: use hidden charge as a non-lootable identity, clamp the
	-- engine's full-bar fill, then add only the converted joules (capped).
	if (not burning) or burning == HybridDrive.CHARGE_ITEM then
		if not burning then
			HybridDrive.ignite_charge(burner)
		elseif (burner.remaining_burning_fuel or 0) > (max_buffer or HybridDrive.SPARK_JOULES) then
			burner.remaining_burning_fuel = max_buffer or HybridDrive.SPARK_JOULES
		end
	end
	if not currently_burning_name(burner) then
		return 0
	end
	local current = burner.remaining_burning_fuel or 0
	local cap = max_buffer or current + joules
	if current > cap then
		burner.remaining_burning_fuel = cap
		current = cap
	end
	local room = math.max(0, cap - current)
	local add = math.min(joules, room)
	if add <= 0 then
		return 0
	end
	burner.remaining_burning_fuel = current + add
	return add
end

function HybridDrive.tick(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local rates = HybridDrive.rates(vehicle.name)
	if not rates then
		return
	end
	local grid = vehicle.grid
	if not grid or not grid.find(HybridDrive.CONVERTER_NAME) then
		return
	end
	local burner = vehicle.burner
	if not burner then
		return
	end
	local pulled = take_from_grid(grid, rates.grid_j_per_tick)
	if pulled <= 0 then
		return
	end
	local converted = pulled * HybridDrive.CONVERSION_EFFICIENCY
	HybridDrive.add_burner_energy(burner, converted, rates.max_buffer_j)
end
