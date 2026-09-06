require "utilities"
require "harvesterstats"
require "refinery"
require "specialOres"
require "modulebay"
require "scoop"

local States = {
	Animating = 0,
	FindingOre = 1,
	MiningOre = 2,
	FindingRefinery = 3,
	ApproachedRefinery = 4,
	DroppingOre = 5,
	MovingToLocation = 6,
	FindingRefuelRefinery = 7,
	ApproachedForRefuel = 8,
	Refueling = 9,
}

local StateUsesEnergy = {
	[States.Animating] = true,
	[States.FindingOre] = false,
	[States.MiningOre] = true,
	[States.FindingRefinery] = false,
	[States.ApproachedRefinery] = false,
	[States.DroppingOre] = false,
	[States.MovingToLocation] = true,
	[States.FindingRefuelRefinery] = false,
	[States.ApproachedForRefuel] = false,
	[States.Refueling] = false,
}

local function vehicle_fuel_inventory(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	return vehicle.get_inventory(defines.inventory.fuel)
end

local function vehicle_trunk(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	return vehicle.get_inventory(defines.inventory.car_trunk)
end

cncharvester = {
	New = function(entity)
		local self = {
			vehicle = entity,
			targetPosition = entity.position,
			targetHeading = false,
			targetDistance = 0,
			targetOrientation = 0,
			currentOrientation = entity.orientation,

			targetRefinery = false,
			reservedRefinery = false,

			state = States.FindingOre,
			oldState = false,
			arrival_state = false,

			searchRadius = Stats.DefaultSearchRadius,
			oresInRadius = {},
			lastOreRadius = 0,

			ticksMined = 0,
			scoopsMined = 0,
			wait_ticks = 0,
			filled = false,
			refueling = false,

			currentEnergy = 0,
			usingEnergy = false,
		}
		setmetatable(self, {__index = cncharvester})
		self:SetIsFilled(false)
		ModuleBay.ensure(entity)
		return self
	end,

	Delete = function(self)
		if self.targetRefinery and self.reservedRefinery then
			local refinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if refinery then
				refinery:UnReserve()
			end
		end
		if self.vehicle and self.vehicle.valid then
			ModuleBay.destroy_for_vehicle(self.vehicle)
		end
		self.vehicle = nil
	end,

	Onload = function(self)
		setmetatable(self, {__index = cncharvester})
		-- 2.0 cannot persist functions in storage; drop any leftover 1.1 callback.
		self.onArrivalCallback = nil
	end,

	Tick = function(self)
		if not (self.vehicle and self.vehicle.valid) then
			return
		end

		if StateUsesEnergy[self.state] then
			if not self:CheckFuel() then
				return
			end
			local consume = Stats.EnergyUsedPerTick
			if self.state == States.MiningOre or self.state == States.Animating then
				local effects = Scoop.read_effects(self.vehicle)
				consume = consume * math.max(0.2, 1 + (effects.consumption or 0))
			end
			self.currentEnergy = self.currentEnergy - consume
		end
		local st = self.state
		local fn = cncharvester.StateFunctions[st]
		if fn then
			fn(self)
		end
	end,

	ErrorDump = function(self)
		log("Red-Alert-Harvester harvester state=" .. tostring(self.state) .. " orientation=" .. tostring(self.currentOrientation))
	end,

	FloatingText = function(self, text, color)
		if not (self.vehicle and self.vehicle.valid) then
			return
		end
		DrawFloatingText(self.vehicle.surface, self.vehicle, text, color or {r = 1, g = 1, b = 1}, 60)
	end,

	CheckFuel = function(self)
		if self.currentEnergy <= 0 then
			self:UseFuel()
		end

		local fuelInv = vehicle_fuel_inventory(self.vehicle)
		if
			not self.refueling
			and self.state ~= States.Animating
			and self.vehicle.valid
			and fuelInv
			and fuelInv.get_item_count() < 5
		then
			self:FloatingText("Heading for refuel", {r = 0.2, g = 0.8, b = 0.2})
			self.state = States.FindingRefuelRefinery
			self.refueling = true
		end

		return self.currentEnergy > 0
	end,

	UseFuel = function(self)
		local fuelInv = vehicle_fuel_inventory(self.vehicle)
		if not fuelInv then
			return
		end
		if fuelInv.get_item_count() < 10 then
			self:RefuelFromHold()
			if fuelInv.get_item_count() < 1 then
				return
			end
		end
		local consumed = false
		EachInventoryItem(fuelInv, function(fuelName, count)
			if consumed then
				return
			end
			local proto = ItemPrototype(fuelName)
			if not (proto and proto.fuel_value and proto.fuel_value > 0) then
				return
			end
			local fuelValue = proto.fuel_value
			local fuelNeeded = math.ceil(math.max(1, -self.currentEnergy) / fuelValue)
			local fuelUsed = math.min(count, fuelNeeded)
			fuelInv.remove({name = fuelName, count = fuelUsed})
			self.currentEnergy = self.currentEnergy + fuelValue * fuelUsed
			consumed = true
		end)
	end,

	RefuelFromInventory = function(self, inventory)
		local fuelName = false
		local fuelCount = 0
		local vehicleFuelInventory = vehicle_fuel_inventory(self.vehicle)
		if not (vehicleFuelInventory and inventory and inventory.valid) then
			return false
		end

		if vehicleFuelInventory.is_full() then
			return true
		end

		EachInventoryItem(vehicleFuelInventory, function(itemName, count)
			if not fuelName then
				fuelName = itemName
				fuelCount = count
			end
		end)

		if not fuelName or inventory.get_item_count(fuelName) == 0 then
			EachInventoryItem(inventory, function(itemName)
				if fuelName then
					return
				end
				local proto = ItemPrototype(itemName)
				if proto and proto.fuel_value and proto.fuel_value > 0 then
					fuelName = itemName
					fuelCount = vehicleFuelInventory.get_item_count(fuelName)
				end
			end)
		end

		if fuelName then
			local proto = ItemPrototype(fuelName)
			local fuelCountInBack = inventory.get_item_count(fuelName)
			if proto and fuelCountInBack > 0 then
				local fuelStackSize = proto.stack_size
				local amountToCompleteStack = fuelStackSize - (fuelCount % fuelStackSize)
				local amountForRemainingStacks = vehicleFuelInventory.count_empty_stacks() * fuelStackSize
				local stack = {
					name = fuelName,
					count = math.min(fuelCountInBack, amountToCompleteStack + amountForRemainingStacks)
				}
				vehicleFuelInventory.insert(stack)
				inventory.remove(stack)
				return true
			end
		end
		return false
	end,

	RefuelFromHold = function(self)
		local trunk = vehicle_trunk(self.vehicle)
		if trunk then
			self:RefuelFromInventory(trunk)
		end
	end,

	SetIsFilled = function(self, isFilled)
		self.filled = isFilled
	end,

	SetTargetPosition = function(self, position, arrival_state)
		self.targetPosition = position
		local dPos = Vector.subtract(position, self.vehicle.position)
		self.targetDistance = Vector.length(dPos)
		if self.targetDistance > 0 then
			self.targetHeading = Vector.div(dPos, self.targetDistance)
		end
		if self.targetDistance > Stats.MovementSpeed then
			self.targetOrientation = DeltaposToOrientation(dPos)
		end
		-- Store a state id, never a function: 2.0 errors if storage contains functions.
		self.arrival_state = arrival_state
	end,

	BeginWait = function(self, ticks, nextState)
		self.oldState = nextState or self.state
		self.wait_ticks = ticks
		self.state = States.Animating
	end,

	FindRandomOreInRadius = function(self, radius)
		if radius ~= self.lastOreRadius then
			self.lastOreRadius = radius
			self.oresInRadius = self.vehicle.surface.find_entities_filtered{
				type = "resource",
				area = GetBoundingBox(self.vehicle.position, radius)
			}
		end

		if #self.oresInRadius < 1 then
			return false
		end

		local i = math.random(#self.oresInRadius)
		local ore = self.oresInRadius[i]
		table.remove(self.oresInRadius, i)

		if not (ore and ore.valid) then
			return false
		end

		local proto = ore.prototype
		if proto.resource_category == "basic-fluid"
		or proto.resource_category == "lava-magma"
		or (ore.amount <= 0 and not proto.infinite_resource)
		or string.find(ore.name, "tree") then
			return false
		end

		return ore
	end,

	FindOresInRadius = function(self, radius)
		local results = self.vehicle.surface.find_entities_filtered{
			type = "resource",
			area = GetBoundingBox(self.vehicle.position, radius)
		}
		local ores = {}
		for _, ore in pairs(results) do
			if ore.valid then
				local proto = ore.prototype
				if proto.resource_category == "basic-fluid"
				or proto.resource_category == "lava-magma"
				or (ore.amount <= 0 and not proto.infinite_resource)
				or string.find(ore.name, "tree") then
					-- skip non-solid / depleted / trees
				else
					table.insert(ores, ore)
				end
			end
		end
		return ores
	end,

	PlayAnimation = function(self)
		-- Scoop / dump animations are not in this repository. Wait a short time instead.
		local effects = Scoop.read_effects(self.vehicle)
		local qlevel = Scoop.quality_level(self.vehicle.quality)
		local wait = Scoop.interval_ticks(Stats.TicksPerAnimationFrame * 8, effects.speed, qlevel)
		self:BeginWait(wait, self.oldState or self.state)
	end,

	StateFunctions = {
		[States.Animating] = function(self)
			self.wait_ticks = (self.wait_ticks or 0) - 1
			if self.wait_ticks <= 0 then
				self.state = self.oldState or States.FindingOre
			end
		end,

		[States.FindingOre] = function(self)
			local tries = 0
			local ore = false
			while not ore and tries < 10 do
				ore = self:FindRandomOreInRadius(self.searchRadius)
				tries = tries + 1
			end
			if not ore then
				self.searchRadius = self.searchRadius + 5
				return
			end

			self.searchRadius = Stats.DefaultSearchRadius
			self.oresInRadius = {}

			self:SetTargetPosition(ore.position, States.MiningOre)
			self.state = States.MovingToLocation
			self.scoopsMined = 0
		end,

		[States.MiningOre] = function(self)
			if self.scoopsMined >= Stats.ScoopsPerLocation then
				self.state = States.FindingOre
				self.searchRadius = Stats.CloseMineSearchRadius
				return
			end

			local qlevel = Scoop.quality_level(self.vehicle.quality)
			local ores = self:FindOresInRadius(Scoop.radius(Stats.MiningRadius, qlevel))
			if #ores < 1 then
				self.state = States.FindingOre
				self.searchRadius = Stats.CloseMineSearchRadius
				return
			end

			local amountPerOre = math.ceil(Stats.OreMinedPerScoop / #ores)
			local result = Scoop.harvest_area(self.vehicle, ores, amountPerOre)
			if result.full then
				self:SetIsFilled(true)
			end

			if self.filled then
				self.scoopsMined = 0
				self.state = States.FindingRefinery
				return
			end
			self.scoopsMined = self.scoopsMined + 1
			self.oldState = States.MiningOre
			self:PlayAnimation()
		end,

		[States.FindingRefinery] = function(self)
			local refinery = Refinery.NearestUnoccupied(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText("Cannot find unoccupied empty refinery", {r = 0.8, g = 0.2, b = 0.2})
				end
				return
			end

			self.targetRefinery = refinery.entity.unit_number
			self:SetTargetPosition(Vector.add(refinery.entity.position, Stats.RefineryApproachOffset), States.ApproachedRefinery)
			self.state = States.MovingToLocation
		end,

		[States.ApproachedRefinery] = function(self)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery and targetRefinery.entity and targetRefinery.entity.valid and not targetRefinery:IsFull() then
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					self:SetTargetPosition(Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset), States.DroppingOre)
					self.state = States.MovingToLocation
				end
			else
				self.state = States.FindingRefinery
			end
		end,

		[States.DroppingOre] = function(self)
			local inv = vehicle_trunk(self.vehicle)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if not (inv and targetRefinery and targetRefinery.entity and targetRefinery.entity.valid) then
				self.state = States.FindingRefinery
				return
			end

			if targetRefinery:GetAvailableSlots() > Stats.cncharvesterCargoSlots then
				EachInventoryItem(inv, function(itemname, count, quality)
					local stack = InventoryItemStack(itemname, count, quality)
					local inserted = targetRefinery.entity.insert(stack)
					if inserted > 0 then
						inv.remove(InventoryItemStack(itemname, inserted, quality))
					end
				end)
			else
				return
			end

			self:SetIsFilled(false)
			self.searchRadius = Stats.DefaultSearchRadius

			if targetRefinery:HasFuel() then
				self.state = States.Refueling
			else
				self.state = States.FindingOre
				targetRefinery:UnReserve()
				self.reservedRefinery = false
			end
		end,

		[States.MovingToLocation] = function(self)
			if math.abs(self.vehicle.orientation - self.targetOrientation) > 0.001 then
				if self.targetOrientation - self.vehicle.orientation > 0.5 then
					self.targetOrientation = self.targetOrientation - 1
				elseif self.targetOrientation - self.vehicle.orientation < -0.5 then
					self.targetOrientation = self.targetOrientation + 1
				end
				self.vehicle.orientation = self.vehicle.orientation + math.max(math.min((self.targetOrientation - self.vehicle.orientation), Stats.RotationSpeed), -Stats.RotationSpeed)
				return
			end

			local dPos = Vector.subtract(self.targetPosition, self.vehicle.position)
			self.targetDistance = Vector.length(dPos)
			if self.targetDistance > 0 then
				self.targetHeading = Vector.div(dPos, self.targetDistance)
			end

			if self.targetDistance < Stats.MovementSpeed then
				self.vehicle.teleport(self.targetPosition)
				if self.arrival_state then
					self.state = self.arrival_state
					self.arrival_state = false
				end
				return
			end
			self.vehicle.teleport(Vector.add(self.vehicle.position, Vector.mul(self.targetHeading, Stats.MovementSpeed)))
			self.targetDistance = self.targetDistance - Stats.MovementSpeed
		end,

		[States.FindingRefuelRefinery] = function(self)
			local refinery = Refinery.NearestWithFuel(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText("Cannot find refinery with fuel", {r = 0.8, g = 0.2, b = 0.2})
				end
				return
			end

			self.targetRefinery = refinery.entity.unit_number
			self:SetTargetPosition(
				Vector.add(refinery.entity.position, Stats.RefineryApproachOffset),
				States.ApproachedForRefuel
			)
			self.state = States.MovingToLocation
		end,

		[States.ApproachedForRefuel] = function(self)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery and targetRefinery.entity and targetRefinery.entity.valid and targetRefinery:HasFuel() then
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					self:SetTargetPosition(Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset), States.Refueling)
					self.state = States.MovingToLocation
				end
			else
				self.state = States.FindingRefuelRefinery
			end
		end,

		[States.Refueling] = function(self)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if not (targetRefinery and targetRefinery.entity and targetRefinery.entity.valid) then
				self.state = States.FindingRefuelRefinery
				return
			end
			local chest = targetRefinery.entity.get_inventory(defines.inventory.chest)
			if self:RefuelFromInventory(chest) then
				self.refueling = false
				local trunk = vehicle_trunk(self.vehicle)
				if trunk and trunk.get_item_count() > 0 then
					self.state = States.DroppingOre
				else
					self.state = States.FindingOre
					targetRefinery:UnReserve()
					self.reservedRefinery = false
				end
				return
			end
			self.state = States.FindingRefuelRefinery
		end,
	}
}
