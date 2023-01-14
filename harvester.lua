require "utilities"
require "harvesterstats"
require "refinery"
require "specialOres"

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

cncharvester = {
	New = function(entity)
		local self = {
			vehicle = entity,
			animEntity = false,
			-- Movement variables.
			targetPosition = entity.position,
			targetHeading = false,
			targetDistance = 0,
			targetOrientation = 0,
			currentOrientation = entity.orientation,
			
			targetRefinery = false,
			reservedRefinery = false,
			
			state = States.FindingOre,
			oldState = false,
			onArrivalCallback = false,
			
			searchRadius = Stats.DefaultSearchRadius,
			oresInRadius = {},
			lastOreRadius = 0,
			
			
			ticksMined = 0,
			filled = false,
			refueling = false,
			
			driver = false,
			
			currentEnergy = 0,
			usingEnergy = false,
			
			animationState = false,
		}
		setmetatable(self, {__index=cncharvester})
		
		-- Add a driver.
		--[[ entity name "player" unknown
		self.driver = game.surfaces.nauvis.create_entity{name="player", force=self.vehicle.force, position=self.vehicle.position}
		self.vehicle.passenger = self.driver
		]]--
		self:SetIsFilled(false)
		
		--[[ unknown animation "cncharvester-anim"
		self.animEntity = game.surfaces.nauvis.create_entity{name = "cncharvester-anim", force=self.vehicle.force, position=self.vehicle.position}
		-- Get rid of the flashing "no fuel" icon.
		self.animEntity.get_inventory(defines.inventory.fuel).insert({name = "coal", count = 1})
		]]--
		
		--[[ table cncharvesterAnimator is missing in repository
		self.animationState = cncharvesterAnimator.New(self)
		self.animationState:SetOrientation(self.vehicle.orientation)
		]]--
	
		return self
	end,

	Delete = function(self)
		-- Remove the driver
		--[[
		if self.driver and self.driver.valid then
			self.vehicle.passenger = nil
			self.driver.destroy()
			self.driver = nil
		end
		]]--
		--[[
		if self.animEntity and self.animEntity.valid then
			self.animEntity.destroy()
			self.animEntity = nil
		end
		]]--
		if self.vehicle and self.vehicle.valid then
			self.vehicle.destroy()
			self.vehicle = nil
		end
		if self.targetRefinery and self.reservedRefinery then
			self.targetRefinery:UnReserve()
		end
	end,
	
	Onload = function(self)
		setmetatable(self, {__index=cncharvester})
		--[[ unknown table cncharvesterAnimator 
		cncharvesterAnimator.Onload(self.animationState)
		]]--
	end,
	
	Tick = function(self)
		-- Kick any players that entered.
		--[[
		self.animEntity.passenger = nil
		]]--
		
		if StateUsesEnergy[self.state] then
			if not self:CheckFuel() then
				return
			end
			self.currentEnergy = self.currentEnergy - Stats.EnergyUsedPerTick
			--game.player.print("self.currentEnergy = " .. self.currentEnergy)
		end
		st = self.state
		cncharvester.StateFunctions[st](self)
	end,
	
	ErrorDump = function(self)
		game.player.print("self.currentOrientation = " .. self.currentOrientation)
		game.player.print("self.state = " .. self.state)
		if self.animationState then
			self.animationState:ErrorDump()
		end
	end,
	
	FloatingText = function(self, text, color)
		local color = color or {r = 1, g = 1, b = 1}
		game.surfaces.nauvis.create_entity({name="flying-text", position=self.vehicle.position, text=text, color=color})
	end,
	
	CheckFuel = function(self)
		if self.currentEnergy <= 0 then
			self:UseFuel()
		end
		
		-- If we're running out of fuel, head for a refuel.
		if 
			not self.refueling
			and not (self.state == States.Animating)
			and self.vehicle.valid
			and self.vehicle.get_inventory(defines.inventory.fuel).get_item_count() < 5 
		then
			self:FloatingText("Heading for refuel", {g = 0.8})
			self.state = States.FindingRefuelRefinery
			self.refueling = true
		end
		
		return self.currentEnergy > 0
	end,
	
	UseFuel = function(self)
		local fuelInv = self.vehicle.get_inventory(defines.inventory.fuel)
		-- We are currently low of fuel.
		if fuelInv.get_item_count() < 10 then
			-- Attempt to refuel from the hold.
			self:RefuelFromHold()
			-- There's no fuel there either.
			if fuelInv.get_item_count() < 1 then
				-- Show a notification every 2 seconds.
				if (game.tick % 120) == 0 then
					--self:FloatingText("Out of fuel", {r = 0.8})
				end
				return
			end
		end
		-- Use up some fuel.
		for fuelName, count in pairs(fuelInv.get_contents()) do
			local fuelValue = game.item_prototypes[fuelName].fuel_value
			local fuelNeeded = math.ceil(math.max(1, -self.currentEnergy) / fuelValue)
			local fuelUsed = math.min(count, fuelNeeded)
			
			fuelInv.remove({name = fuelName, count = fuelUsed})
			self.currentEnergy = self.currentEnergy + fuelValue * fuelUsed
			break
		end
	end,
	
	RefuelFromInventory = function(self, inventory)
		local fuelName = false
		local fuelCount = 0
		local vehicleFuelInventory = self.vehicle.get_inventory(defines.inventory.fuel)

		if vehicleFuelInventory.is_full() then
			-- We're already full, so refueling was successful.
			return true
		end

		-- Find out which fuel we're currently using.
		for itemName, count in pairs(vehicleFuelInventory.get_contents()) do
			if count == game.item_prototypes[itemName].stack_size then
				return true
			end
			fuelName = itemName
			fuelCount = count
			break
		end
		-- If the fuel slot is currently empty or that fuel is not available.
		if not fuelName or inventory.get_item_count(fuelName) == 0 then
			-- Check if we have fuel in the back
			for itemName, count in pairs(inventory.get_contents()) do
				-- Is this item a fuel?
				if game.item_prototypes[itemName].fuel_value > 0 then
					fuelName = itemName
					fuelCount = vehicleFuelInventory.get_item_count(fuelName)
					break
				end
			end
		end
		-- Have we found a fuel either currently used or in the back?
		if fuelName then
			-- How much is there of it in the back?
			local fuelCountInBack = inventory.get_item_count(fuelName)
			-- We need at least one, obviously.
			if fuelCountInBack > 0 then
				local fuelStackSize = game.item_prototypes[fuelName].stack_size
				local amountToCompleteStack = fuelStackSize - fuelCount % fuelStackSize
				local amountForRemainingStacks = vehicleFuelInventory.count_empty_stacks() * fuelStackSize

				-- Transfer it.
				local stack = {
					name = fuelName,
					count = math.min(fuelCountInBack, amountToCompleteStack + amountForRemainingStacks)
				}
				self.vehicle.get_inventory(defines.inventory.fuel).insert(stack)
				inventory.remove(stack)
				
				return true
			end
		end
		return false
	end,
	
	RefuelFromHold = function(self)
		self:RefuelFromInventory(self.vehicle.get_inventory(2))
	end,
	
	SetIsFilled = function(self, isFilled)
		self.filled = isFilled
-- 		if self.filled then
-- 			self.driver.color = {r = 1, g = 1, b = 0, a = 0.8}
-- 		else
-- 			self.driver.color = {r = 1, g = 1, b = 1, a = 1}
-- 		end
	end,
	
	SetTargetPosition = function(self, position, onArrivalCallback)
		self.targetPosition = position
		local dPos = Vector.subtract(position, self.vehicle.position)
		self.targetDistance = Vector.length(dPos)
		self.targetHeading = Vector.div(dPos, self.targetDistance) -- Normalized(dPos)
		if self.targetDistance > Stats.MovementSpeed then
			self.targetOrientation = DeltaposToOrientation(dPos)
		end
		self.onArrivalCallback = onArrivalCallback
		
		--game.player.print("Moving to location {" .. position.x .. ", " .. position.y .. "}")
	end,
	
	SetTargetOrientation = function(self, orientation)
		self.targetOrientation = orientation
	end,
	
	FindRandomOreInRadius = function(self, radius)
		if radius ~= lastOreRadius then
			self.lastOreRadius = lastOreRadius
			self.oresInRadius = self.vehicle.surface.find_entities_filtered{type = "resource", area = GetBoundingBox(self.vehicle.position, radius)}
		end
		
		if #self.oresInRadius < 1 then
			return false
		end
		
		local i = math.random(#self.oresInRadius)
		local ore = self.oresInRadius[i]
		
		-- No fluids.
		if game.entity_prototypes[ore.name].resource_category == "basic-fluid"
		-- No lava.
		or game.entity_prototypes[ore.name].resource_category == "lava-magma"
		-- No depleted resources that aren't infinite.
		or (ore.amount <= 0 and not game.entity_prototypes[ore.name].infiniteresource)
		-- No trees.
		or string.find(ore.name, "tree") then
			-- Not a valid ore.
			ore = false
		end
		-- Remove from the results list.
		table.remove(self.oresInRadius, i)
		
		return ore
	end,
	

	FindOresInRadius = function(self, radius)
		local results = self.vehicle.surface.find_entities_filtered{type = "resource", area = GetBoundingBox(self.vehicle.position, radius)}
		local ores = {}
		--for i = #results, 1, -1 do
			--local ore = results[i]
		for _, ore in pairs(results) do
			-- No fluids.
			if game.entity_prototypes[ore.name].resource_category == "basic-fluid"
			-- No lava.
			or game.entity_prototypes[ore.name].resource_category == "lava-magma"
			-- No depleted resources that aren't infinite.
			or (ore.amount <= 0 and not game.entity_prototypes[ore.name].infinite_resource)
			-- No trees.
			or string.find(ore.name, "tree") then
				--ore.destroy()
				--table.remove(results, i)
			else
				table.insert(ores, ore)
			end
		end
		return ores
	end,

	PlayAnimation = function(self, animation)
		if States.MiningOre == false then
		  return
		end
	  
		-- determine the orientation of the animation based on the RealOrientation value
		local orientation = math.floor(self.RealOrientation * 8)
	  
		-- save the current state and set the state to States.Animating
		self.oldState = self.state
		self.state = States.Animating
	  
		-- play the animation using the animationState operator
		game.player.print("Requesting animation (" .. animation .. ")")
		self.animationState:PlayAnimation(animation, function(self)
		  -- when the animation is finished, set the state back to the old state
		  self.state = self.oldState
		end)
	end,
	  
	StateFunctions = {
		--------------------------------------------------++--------------------------------------------------
		--											   Animating											--
		--------------------------------------------------++--------------------------------------------------
		[States.Animating] = function(self)
			if self.animationState then
				self.animationState:Tick()
			end
		end,
		--------------------------------------------------++--------------------------------------------------
		--											  FindingOre											--
		--------------------------------------------------++--------------------------------------------------
		[States.FindingOre] = function(self)
			--self:FloatingText("FindingOre")
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
			
			-- We've found ore, so reset search radius and ores for next time.
			self.searchRadius = Stats.DefaultSearchRadius
			self.oresInRadius = {}
			
			-- Go there.
			self:SetTargetPosition(ore.position, function(self) self.state = States.MiningOre end)
			--self.nextState = States.MiningOre
			self.state = States.MovingToLocation
			
			-- We haven't mined the new location yet.
			self.scoopsMined = 0
		end,
		--------------------------------------------------++--------------------------------------------------
		--											   MiningOre											--
		--------------------------------------------------++--------------------------------------------------
		[States.MiningOre] = function(self)
			--self:FloatingText("MiningOre")
			-- If we've mined this location enough.
			if self.scoopsMined >= Stats.ScoopsPerLocation then
				-- Find a new location.
				self.state = States.FindingOre
				self.searchRadius = Stats.CloseMineSearchRadius
				return
			end
			
			-- Mine what we can.
			local ores = self:FindOresInRadius(Stats.MiningRadius)
			local amountPerOre = math.ceil(Stats.OreMinedPerScoop / #ores)
			for _, ore in pairs(ores) do
				local oreName = ore.name
				-- Check if the ore is "special", such as silica where the resource is called "silica" and the item is called "raw-silica".
				if SpecialOres[ore.name] then
					oreName = SpecialOres[ore.name]()
				end
				local oreAmount = ore.amount - math.max(0, game.entity_prototypes[ore.name].minimum_resource_amount)
				local maxAmount = math.min(amountPerOre, oreAmount)
				if not self.vehicle.can_insert{name = oreName, count = 1} then
					self:SetIsFilled(true)
				elseif maxAmount >= 0 then
					-- Remove up to what we can.
					if game.entity_prototypes[ore.name].infinite_resource then
						-- If it's infinite we can just extract the ore we want.
						self.vehicle.insert{name = oreName, count = amountPerOre}
					elseif maxAmount > 0 then
						-- Otherwise at most that which the ore has available.
						self.vehicle.insert{name = oreName, count = maxAmount}
					end
					
					local newAmount = ore.amount - maxAmount
					
					-- If we've just depleted it and it's not infinite, destroy it.
					-- Oddly, this is not automatically done by the game.
					if newAmount == 0 then
						if not game.entity_prototypes[ore.name].infinite_resource then
							ore.destroy()
						end
					else
						ore.amount = newAmount
					end
				else -- It was already negative, not for me to decide what happens...
					self.vehicle.insert{name = oreName, count = amountPerOre}
					self:FloatingText("Negative", {r = 0.8})
				end
			end
			-- If we're full, go home.
			if self.filled then
				self.scoopsMined = 0
				self.state = States.FindingRefinery
				return
			end
			self.scoopsMined = self.scoopsMined + 1
			
			--[[ Animations does not exist 
			self:PlayAnimation(Animations.ScoopOre)
			]]--
		end,
		--------------------------------------------------++--------------------------------------------------
		--											FindingRefinery											--
		--------------------------------------------------++--------------------------------------------------
		[States.FindingRefinery] = function(self)
			--self:FloatingText("FindingRefinery")
			local refinery = Refinery.NearestUnoccupied(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText("Cannot find unoccupied empty refinery", {r = 0.8})
				end
				return
			end
			
			self.targetRefinery = refinery.entity.unit_number
		
			-- Move towards an approach position.
			self:SetTargetPosition(Vector.add(refinery.entity.position, Stats.RefineryApproachOffset), function(self) self.state = States.ApproachedRefinery end)
			
			--self.nextState = States.ApproachedRefinery
			self.state = States.MovingToLocation
		end,
		--------------------------------------------------++--------------------------------------------------
		--										 ApproachedRefinery											--
		--------------------------------------------------++--------------------------------------------------
		[States.ApproachedRefinery] = function(self)
			--self:FloatingText("ApproachedRefinery")
			-- Check if it's still there.
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery.entity.valid and not targetRefinery:IsFull()then
				-- Wait until the refinery is free if it isn't currently.
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					-- Move onto the pad.
					self:SetTargetPosition(Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset), function(self) self.state = States.DroppingOre end)
					--self.nextState = States.DroppingOre
					self.state = States.MovingToLocation
				end
			else
				-- Find another refinery.
				self.state = States.FindingRefinery
			end
		end,
		--------------------------------------------------++--------------------------------------------------
		--											  DroppingOre											--
		--------------------------------------------------++--------------------------------------------------
		[States.DroppingOre] = function(self)
			--self:FloatingText("DroppingOre")
			local inv = self.vehicle.get_inventory(2)
			-- If the refinery is still there and we can dump the complete contents of our cargo hold.
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery.entity.valid then
				if targetRefinery:GetAvailableSlots() > Stats.cncharvesterCargoSlots then
					for itemname, count in pairs(inv.get_contents()) do
						local stack = {name = itemname, count = count}
						-- Dump our inventory into the refinery.
						targetRefinery.entity.insert(stack)
						inv.remove(stack)
					end
				else
					--game.player.print("Cannot dump ore.")
					return
				end
			else
				self.state = States.FindingRefinery
				return
			end
			
			-- Wait until it's empty.
			self:SetIsFilled(false)
			self.searchRadius = Stats.DefaultSearchRadius
			
			if targetRefinery:HasFuel() then
				self.state = States.Refueling
			else
				self.state = States.FindingOre
				targetRefinery:UnReserve()
				self.reservedRefinery = false
			end
			
			
			--[[ Animations does not exist 
			self:PlayAnimation(Animations.DumpOre)
			--]]
		end,
		--------------------------------------------------++--------------------------------------------------
		--										  MovingToLocation											--
		--------------------------------------------------++--------------------------------------------------
		[States.MovingToLocation] = function(self)
			--if game.tick % 17 == 0 then self:FloatingText("MovingToLocation") end
			-- First rotate to face the target.
			if math.abs(self.vehicle.orientation - self.targetOrientation) > 0.001 then
				-- Check if it's faster to rotate the other way.
				if self.targetOrientation - self.vehicle.orientation > 0.5 then
					self.targetOrientation = self.targetOrientation - 1
				elseif self.targetOrientation - self.vehicle.orientation < -0.5 then
					self.targetOrientation = self.targetOrientation + 1
				end
				-- Rotate up to RotationSpeed.
				self.vehicle.orientation = self.vehicle.orientation + math.max(math.min((self.targetOrientation - self.vehicle.orientation), Stats.RotationSpeed), -Stats.RotationSpeed)
				if self.animationState then
					self.animationState:SetOrientation(self.vehicle.orientation)
				end
				return
			end
			-- We're rotated correctly, so move towards the target.
			
			dPos = Vector.subtract(self.targetPosition, self.vehicle.position)
			self.targetDistance = Vector.length(dPos)
			self.targetHeading = Vector.div(dPos, self.targetDistance) -- Vector.normalized(dPos)
			
			if self.targetDistance < Stats.MovementSpeed then
				self.vehicle.teleport(self.targetPosition)
				-- This should set the new state.
				self.onArrivalCallback(self)
				return
			end
			self.vehicle.teleport(Vector.add(self.vehicle.position, Vector.mul(self.targetHeading, Stats.MovementSpeed)))
			--[[
			self.animEntity.teleport(self.vehicle.position)
			]]--
			self.targetDistance = self.targetDistance - Stats.MovementSpeed
		end,
		--------------------------------------------------++--------------------------------------------------
		--										FindingRefuelRefinery										--
		--------------------------------------------------++--------------------------------------------------
		[States.FindingRefuelRefinery] = function(self)
			--if game.tick % 17 == 0 then self:FloatingText("FindingRefuelRefinery") end
			local refinery = Refinery.NearestWithFuel(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText("Cannot find refinery with fuel", {r = 0.8})
				end
				return
			end
			
			self.targetRefinery = refinery.entity.unit_number
		
			-- Move towards an approach position.
			self:SetTargetPosition(
				Vector.add(refinery.entity.position, Stats.RefineryApproachOffset), 
				function(self) self.state = States.ApproachedForRefuel end
			)
			
			--self.nextState = States.ApproachedForRefuel
			self.state = States.MovingToLocation
		end,
		--------------------------------------------------++--------------------------------------------------
		--										  ApproachedForRefuel										--
		--------------------------------------------------++--------------------------------------------------
		[States.ApproachedForRefuel] = function(self)
			--if game.tick % 17 == 0 then self:FloatingText("ApproachedForRefuel") end
			-- Check if it's still there and if it still has fuel.
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery.entity.valid and targetRefinery:HasFuel() then
				-- Wait until the refinery is free if it isn't currently.
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					-- Move onto the pad.
					self:SetTargetPosition(Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset), function(self) self.state = States.Refueling end)
					--self.nextState = States.Refueling
					self.state = States.MovingToLocation
				end
			else
				-- If it's invalid or has no fuel left, find another refinery.
				self.state = States.FindingRefuelRefinery
			end
		end,
		--------------------------------------------------++--------------------------------------------------
		--											  Refueling												--
		--------------------------------------------------++--------------------------------------------------
		[States.Refueling] = function(self)
			--self:FloatingText("Refueling")
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if self:RefuelFromInventory(targetRefinery.entity.get_inventory(defines.inventory.chest)) then
				self.refueling = false
				if self.vehicle.get_inventory(2).get_item_count() > 0 then
					self.state = States.DroppingOre
				else
					self.state = States.FindingOre
					targetRefinery:UnReserve()
					self.reservedRefinery = false
				end
				
				return
			end
			-- We didn't find any fuel, so find another refinery.
			self.state = States.FindingRefuelRefinery
		end,
	}
}