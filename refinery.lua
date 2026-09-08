require "utilities"
require "hybriddrive"

local beltAreas = {
	N = { -- North.
		{-1, -4}, {2, -3}
	},
}

local laneOff = 0.25
local dropOff = 0.35
local dropOffsets = {
	N = {{-laneOff,  dropOff}, { laneOff,  dropOff}},
	E = {{-dropOff, -laneOff}, {-dropOff,  laneOff}},
	S = {{ laneOff, -dropOff}, {-laneOff, -dropOff}},
	W = {{ dropOff,  laneOff}, { dropOff, -laneOff}},
}

local function belt_direction(dir)
	if dir == "N" then return defines.direction.north end
	if dir == "E" then return defines.direction.east end
	if dir == "S" then return defines.direction.south end
	if dir == "W" then return defines.direction.west end
	return defines.direction.north
end

local function refinery_inventory(self)
	if self.entity and self.entity.valid then
		return self.entity.get_inventory(defines.inventory.chest)
	end
	return nil
end

Refinery = {
	--------------------------------------------------++--------------------------------------------------
	--										   Static functions											--
	--------------------------------------------------++--------------------------------------------------
	GetByUnitNumber = function(unitNumber)
		return storage.refineries[unitNumber]
	end,

	NearestUnoccupied = function(entity)
		return Refinery.NearestWithCondition(
			entity,
			function(refinery) return refinery and not refinery:IsOccupied() and not refinery:IsFull() end
		)
	end,

	NearestWithFuel = function(entity)
		local refinery = Refinery.NearestWithCondition(
			entity,
			function(refinery) return refinery and not refinery:IsOccupied() and refinery:HasFuel() end
		)
		if not refinery then
			refinery = Refinery.NearestWithCondition(
				entity,
				function(refinery) return refinery and refinery:HasFuel() end
			)
		end
		return refinery
	end,

	Nearest = function(entity)
		return Refinery.NearestWithCondition(entity, function() return true end)
	end,

	NearestWithCondition = function(entity, conditionFunc)
		if not (entity and entity.valid) then
			return false
		end
		local refineryEntities = entity.surface.find_entities_filtered {
			name = "refinery"
		}
		local closestRefinery = false
		local minDistSq = math.huge
		for _, refineryEntity in pairs(refineryEntities) do
			local refinery = storage.refineries[refineryEntity.unit_number]
			if conditionFunc(refinery) then
				local dPos = Vector.subtract(entity.position, refineryEntity.position)
				local distSq = Vector.lengthsq(dPos)

				if distSq < minDistSq then
					closestRefinery = refinery
					minDistSq = distSq
				end
			end
		end
		return closestRefinery
	end,

	--------------------------------------------------++--------------------------------------------------
	--										   Class functions											--
	--------------------------------------------------++--------------------------------------------------
	New = function(entity)
		local self = {
			entity = entity,
			tickOffset = game.tick % 240,
			hasBelts = false,
			belts = {N = {}, E = {}, S = {}, W = {}},
			reserved = false,
		}
		setmetatable(self, {__index = Refinery})
		return self
	end,

	Delete = function(self)
		-- The entity is already being removed by the game; only drop bookkeeping.
		self.entity = nil
		self.reserved = false
	end,

	Onload = function(self)
		setmetatable(self, {__index = Refinery})
	end,

	Tick = function(self)
		if not (self.entity and self.entity.valid) then
			return
		end
		if ((game.tick + self.tickOffset) % 240) == 0 then
			self:CheckForBelts()
		end

		local inv = refinery_inventory(self)
		if self.hasBelts and inv and inv.get_item_count() > 0 then
			self:DropOnBelts()
		end
	end,

	ErrorDump = function(self)
		-- Nothing.
	end,

	FloatingText = function(self, text, color)
		if not (self.entity and self.entity.valid) then
			return
		end
		DrawFloatingText(self.entity.surface, self.entity, text, color or {r = 1, g = 1, b = 1}, 60)
	end,

	Reserve = function(self)
		if self.reserved then
			Error("Reserved an already reserved refinery.")
		end
		self.reserved = true
	end,

	UnReserve = function(self)
		if not self.reserved then
			Error("Unreserved a non-reserved refinery.")
		end
		self.reserved = false
	end,

	IsOccupied = function(self)
		return self.reserved
	end,

	GetAvailableSlots = function(self)
		if self:IsFull() then return 0 end
		local inv = refinery_inventory(self)
		if not inv then return 0 end
		return math.max(0, inv.count_empty_stacks())
	end,

	-- Convertible burnables HybridDrive will accept (not nuclear / hybrid-charge).
	HasFuel = function(self)
		local inv = refinery_inventory(self)
		if not inv then
			return false
		end
		local found = false
		EachInventoryItem(inv, function(itemName)
			if HybridDrive.convertible_joules(itemName) > 0 then
				found = true
			end
		end)
		return found
	end,

	IsFull = function(self)
		local inv = refinery_inventory(self)
		return not inv or inv.is_full()
	end,

	CheckForBelts = function(self)
		self.hasBelts = false
		self.belts = {N = {}, E = {}, S = {}, W = {}}
		if not (self.entity and self.entity.valid) then
			return
		end
		local surface = self.entity.surface
		for dir, area in pairs(beltAreas) do
			local results = surface.find_entities_filtered{
				type = "transport-belt",
				area = {Vector.add(self.entity.position, area[1]), Vector.add(self.entity.position, area[2])}
			}
			for _, belt in pairs(results) do
				if belt.direction == belt_direction(dir) then
					table.insert(self.belts[dir], belt)
					self.hasBelts = true
				end
			end
		end
	end,

	DropOnBelts = function(self)
		for dir, belts in pairs(self.belts) do
			for _, belt in pairs(belts) do
				if not belt.valid then
					self:CheckForBelts()
					return
				end
				self:DropOnBelt(belt, dir)
			end
		end
	end,

	DropOnBelt = function(self, belt, dir)
		local inv = refinery_inventory(self)
		if not inv then
			return
		end
		local dropped = 0
		local surface = self.entity.surface
		EachInventoryItem(inv, function(itemName, itemCount, quality)
			if dropped >= 2 then
				return
			end
			local proto = ItemPrototype(itemName)
			local count = itemCount
			if proto and proto.fuel_value and proto.fuel_value > 0 then
				count = count - proto.stack_size
			end
			local stack = InventoryItemStack(itemName, 1, quality)

			if count > 1 then
				dropped = 2
				for _, offset in pairs(dropOffsets[dir] or dropOffsets.N) do
					local possiblePos = surface.find_non_colliding_position("item-on-ground", Vector.add(belt.position, offset), 0.01, 0.01)
					if possiblePos then
						surface.create_entity{position = possiblePos, name = "item-on-ground", stack = stack}
						inv.remove(stack)
					end
				end
			elseif count == 1 then
				dropped = dropped + 1
				local offset = (dropOffsets[dir] or dropOffsets.N)[dropped]
				if offset then
					local possiblePos = surface.find_non_colliding_position("item-on-ground", Vector.add(belt.position, offset), 0.01, 0.01)
					if possiblePos then
						surface.create_entity{position = possiblePos, name = "item-on-ground", stack = stack}
						inv.remove(stack)
					end
				end
			end
		end)
	end,
}
