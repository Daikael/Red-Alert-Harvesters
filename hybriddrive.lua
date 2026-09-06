-- Hybrid-drive: pull grid electricity into the car burner at a capped rate.
-- Sustained driving net-drains even with full batteries + a strong generator.

HybridDrive = HybridDrive or {}

HybridDrive.CONVERTER_NAME = "Hybrid-drive"
HybridDrive.BATTERY_NAME = "Hybrid-drive-battery"
HybridDrive.CHARGE_ITEM = "cncharvester-hybrid-charge"
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

local function currently_burning_name(burner)
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

function HybridDrive.add_burner_energy(burner, joules, max_buffer)
	if not (burner and joules > 0) then
		return 0
	end
	if not currently_burning_name(burner) then
		burner.currently_burning = HybridDrive.CHARGE_ITEM
	end
	if not currently_burning_name(burner) then
		return 0
	end
	local current = burner.remaining_burning_fuel or 0
	local room = math.max(0, (max_buffer or current + joules) - current)
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
