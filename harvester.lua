require "utilities"
require "harvesterstats"
require "refinery"
require "specialOres"
require "modulebay"
require "scoop"
require "hybriddrive"
require "autodrive"
require "chunkindex"

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

			path = nil,
			path_index = 1,
			path_id = nil,
			repath_n = 0,
			alt_n = 0,
			home_repath_n = 0,
			failed_chunks = {},
			assign_si = nil,
			assign_cx = nil,
			assign_cy = nil,
			going_home = false,
			home_early = false,
			alert_tick = 0,
			busy_until = 0,
			search_range = AutoDrive.RANGE_TILES,

			-- Per-truck (not a global startup setting). Default auto ON so
			-- testers with Automatic harvester testing already on keep AI.
			-- Pause-on-enter default OFF: yield controls while seated, resume
			-- the same assignment on exit.
			auto_enabled = true,
			pause_on_enter = false,
			occupied = false,
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
		-- Path request ids do not survive save/load.
		self.path_id = nil
		self.path = self.path or nil
		self.failed_chunks = self.failed_chunks or {}
		self.repath_n = self.repath_n or 0
		self.alt_n = self.alt_n or 0
		self.home_repath_n = self.home_repath_n or 0
		self.search_range = self.search_range or AutoDrive.RANGE_TILES
		-- nil → ON so existing tester saves keep auto. false must persist.
		if self.auto_enabled == nil then
			self.auto_enabled = true
		end
		if self.pause_on_enter == nil then
			self.pause_on_enter = false
		end
	end,

	auto_on = function(self)
		return self.auto_enabled ~= false
	end,

	CancelPendingPath = function(self)
		if self.path_id then
			AutoDrive.take_request(self.path_id)
			self.path_id = nil
		end
		self.path = nil
		self.path_index = 1
	end,

	RepathCurrentAssignment = function(self)
		if not self:auto_on() then
			return
		end
		if AutoDrive.player_occupying(self.vehicle) then
			return
		end
		if self.state == States.MovingToLocation and self.targetPosition then
			local radius = self.going_home and AutoDrive.PATH_RADIUS_HOME or AutoDrive.PATH_RADIUS_ORE
			self:StartDrive(self.targetPosition, self.arrival_state, radius)
		end
	end,

	OnOccupancyChanged = function(self, occupied)
		if self.vehicle and self.vehicle.valid then
			AutoDrive.progress_reset(self, self.vehicle.position, game and game.tick or 0)
		end
		if occupied then
			if self.pause_on_enter then
				-- Freeze assignment: do not keep pathing in the background.
				self:CancelPendingPath()
			end
		elseif self:auto_on() then
			self:RepathCurrentAssignment()
		end
	end,

	SetAutoEnabled = function(self, enabled)
		local on = enabled and true or false
		local was = self:auto_on()
		self.auto_enabled = on
		if was and not on then
			self:CancelPendingPath()
			if not AutoDrive.player_occupying(self.vehicle) then
				AutoDrive.release(self.vehicle)
			end
		elseif on and not was then
			self:RepathCurrentAssignment()
		end
	end,

	SetPauseOnEnter = function(self, enabled)
		self.pause_on_enter = enabled and true or false
		if self.pause_on_enter and AutoDrive.player_occupying(self.vehicle) then
			self:CancelPendingPath()
			if self.vehicle and self.vehicle.valid then
				AutoDrive.progress_reset(self, self.vehicle.position, game and game.tick or 0)
			end
		end
	end,

	Tick = function(self)
		if not (self.vehicle and self.vehicle.valid) then
			return
		end

		local occupied = AutoDrive.player_occupying(self.vehicle)
		if occupied ~= self.occupied then
			self.occupied = occupied
			self:OnOccupancyChanged(occupied)
		end

		if occupied then
			-- Never write riding_state while a player is in the seat.
			if self.state ~= States.MiningOre then
				ModuleBay.starve(self.vehicle)
			end
			return
		end

		if not self:auto_on() then
			ModuleBay.starve(self.vehicle)
			return
		end

		if self.state ~= States.MiningOre then
			ModuleBay.starve(self.vehicle)
		end

		if not self:CheckFuel() then
			AutoDrive.stop(self.vehicle)
			return
		end
		self:MaybeReturnHome()

		if StateUsesEnergy[self.state] then
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
		log("Red-Alert-Harvesters harvester state=" .. tostring(self.state) .. " orientation=" .. tostring(self.currentOrientation))
	end,

	FloatingText = function(self, text, color, ttl)
		if not (self.vehicle and self.vehicle.valid) then
			return
		end
		DrawFloatingText(self.vehicle.surface, self.vehicle, text, color or {r = 1, g = 1, b = 1}, ttl or 60)
	end,

	CheckFuel = function(self)
		if not (self.vehicle and self.vehicle.valid) then
			return false
		end
		-- Same gate as the Ore Truck: hybrid pool, charged grid, or burnables.
		-- Empty solid slots are fine while the pool/grid can still run.
		if HybridDrive.has_usable_energy(self.vehicle) then
			self.currentEnergy = math.max(self.currentEnergy or 0, 1)
			return true
		end
		self:UseFuel()
		if HybridDrive.has_usable_energy(self.vehicle) then
			self.currentEnergy = math.max(self.currentEnergy or 0, 1)
			return true
		end
		if game and game.tick and (game.tick % FLOATING_TEXT_ERROR_TTL) == 0 then
			self:FloatingText({"cncharvester.out-of-fuel"}, FLOATING_TEXT_ERROR_RED, FLOATING_TEXT_ERROR_TTL)
		end
		return false
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

	is_home_state = function(self)
		local st = self.state
		return st == States.FindingRefinery
			or st == States.ApproachedRefinery
			or st == States.DroppingOre
			or st == States.FindingRefuelRefinery
			or st == States.ApproachedForRefuel
			or st == States.Refueling
	end,

	MaybeReturnHome = function(self)
		if self:is_home_state() or self.going_home then
			return
		end
		if self.filled then
			AutoDrive.stop(self.vehicle)
			self.state = States.FindingRefinery
			return
		end
		if HybridDrive.potential_joules(self.vehicle) < AutoDrive.FUEL_LOW_J then
			AutoDrive.stop(self.vehicle)
			self:FloatingText({"cncharvester.heading-for-refuel"}, {r = 0.3, g = 0.9, b = 0.3}, 90)
			self.state = States.FindingRefuelRefinery
		end
	end,

	OnDamaged = function(self, damage_type_name)
		if damage_type_name == "impact" then
			return
		end
		if not self:auto_on() then
			return
		end
		if AutoDrive.player_occupying(self.vehicle) then
			return
		end
		if self:is_home_state() or self.going_home then
			return
		end
		AutoDrive.stop(self.vehicle)
		self.state = States.FindingRefinery
	end,

	expire_failed = function(self)
		local failed = self.failed_chunks or {}
		local now = game and game.tick or 0
		for key, tick in pairs(failed) do
			if now - tick > AutoDrive.FAILED_CHUNK_TTL then
				failed[key] = nil
			end
		end
		self.failed_chunks = failed
	end,

	mark_failed_chunk = function(self)
		if self.assign_si ~= nil and self.assign_cx ~= nil then
			self.failed_chunks = self.failed_chunks or {}
			self.failed_chunks[AutoDrive.chunk_key(self.assign_si, self.assign_cx, self.assign_cy)] = game and game.tick or 0
		end
	end,

	resource_in_chunk = function(self, si, cx, cy)
		local surface = self.vehicle.surface
		if not (surface and surface.valid) then
			return nil
		end
		local left, top = cx * 32, cy * 32
		local ents = surface.find_entities_filtered{
			type = "resource",
			area = {{left, top}, {left + 32, top + 32}},
		}
		local allow_tib = AutoDrive.allow_tib(self.vehicle)
		for _, ent in pairs(ents) do
			if IsHarvestableResource(ent, self.vehicle) then
				local cat = ent.prototype and ent.prototype.resource_category
				if ChunkIndex.resource_is_tiberium(cat, ent.name) then
					if allow_tib then
						return ent
					end
				else
					return ent
				end
			end
		end
		return nil
	end,

	PickIndexTarget = function(self)
		self:expire_failed()
		local vehicle = self.vehicle
		local si = vehicle.surface.index
		local allow_tib = AutoDrive.allow_tib(vehicle)
		local range = self.search_range or AutoDrive.RANGE_TILES
		local chunks = ChunkIndex.find_ore_chunks(
			storage.orechunk,
			storage.tibchunk,
			si,
			vehicle.position,
			range,
			allow_tib,
			self.failed_chunks
		)
		if #chunks == 0 then
			return nil, nil
		end
		local chunk = chunks[1]
		local ore = self:resource_in_chunk(chunk.si, chunk.x, chunk.y)
		return ore, chunk
	end,

	StartDrive = function(self, position, arrival_state, radius)
		if not (self.vehicle and self.vehicle.valid and position) then
			return
		end
		if not self:auto_on() then
			return
		end
		if AutoDrive.player_occupying(self.vehicle) then
			return
		end
		self.targetPosition = position
		self.arrival_state = arrival_state
		self.going_home = arrival_state == States.ApproachedRefinery
			or arrival_state == States.DroppingOre
			or arrival_state == States.ApproachedForRefuel
			or arrival_state == States.Refueling
		self.path = nil
		self.path_index = 1
		if self.path_id then
			AutoDrive.take_request(self.path_id)
			self.path_id = nil
		end
		local id = AutoDrive.request(self.vehicle.surface, self.vehicle, position, radius)
		self.state = States.MovingToLocation
		AutoDrive.progress_reset(self, self.vehicle.position, game.tick)
		if not id then
			self:OnPathFail()
			return
		end
		self.path_id = id
		AutoDrive.remember_request(id, self.vehicle.unit_number)
	end,

	raise_stuck_alert = function(self)
		local now = game.tick
		if (self.alert_tick or 0) + AutoDrive.ALERT_COOLDOWN > now then
			return
		end
		self.alert_tick = now
		local home
		if self.targetRefinery then
			local rec = Refinery.GetByUnitNumber(self.targetRefinery)
			home = rec and rec.entity
		end
		if not (home and home.valid) then
			local nearest = Refinery.Nearest(self.vehicle)
			home = nearest and nearest.entity
		end
		local deposit
		if self.assign_si and self.vehicle.surface and self.vehicle.surface.valid then
			deposit = self:resource_in_chunk(self.assign_si, self.assign_cx, self.assign_cy)
		end
		local msg = self.going_home and {"cncharvester.auto-stuck-home-trip"} or {"cncharvester.auto-stuck-miner"}
		AutoDrive.alert(self.vehicle, home, deposit, msg)
		self:FloatingText({"cncharvester.auto-stuck-miner"}, FLOATING_TEXT_ERROR_RED, FLOATING_TEXT_ERROR_TTL)
	end,

	OnPathFail = function(self)
		AutoDrive.stop(self.vehicle)
		if self.going_home or self.home_early or self:is_home_state() then
			self.home_repath_n = (self.home_repath_n or 0) + 1
			if self.home_repath_n <= AutoDrive.HOME_REPATH_MAX and self.targetPosition then
				self:StartDrive(self.targetPosition, self.arrival_state, AutoDrive.PATH_RADIUS_HOME)
				return
			end
			self:raise_stuck_alert()
			return
		end
		self.repath_n = (self.repath_n or 0) + 1
		if self.repath_n <= AutoDrive.REPATH_MAX and self.targetPosition then
			self:StartDrive(self.targetPosition, self.arrival_state, AutoDrive.PATH_RADIUS_ORE)
			return
		end
		self:mark_failed_chunk()
		self.alt_n = (self.alt_n or 0) + 1
		self.repath_n = 0
		if self.alt_n <= AutoDrive.ALT_PATCH_MAX then
			self.state = States.FindingOre
			return
		end
		self.home_early = true
		self.alt_n = 0
		self.home_repath_n = 0
		self.state = States.FindingRefinery
	end,

	OnPathFinished = function(self, event)
		if not event or event.id ~= self.path_id then
			return
		end
		self.path_id = nil
		if not self:auto_on() then
			self.path = nil
			return
		end
		if AutoDrive.player_occupying(self.vehicle) and self.pause_on_enter then
			self.path = nil
			return
		end
		if event.try_again_later then
			self.path_id = nil
			self.busy_until = game.tick + AutoDrive.BUSY_RETRY_TICKS
			return
		end
		if not event.path then
			self:OnPathFail()
			return
		end
		self.path = event.path
		self.path_index = 1
		self.repath_n = 0
		if self.going_home then
			self.home_repath_n = 0
		end
		AutoDrive.progress_reset(self, self.vehicle.position, game.tick)
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
		-- Same per-item cadence as player drive-harvest (40 / 20 ticks).
		local effects = Scoop.read_effects(self.vehicle)
		local qlevel = Scoop.quality_level(SafeQuality(self.vehicle))
		local wait = Scoop.interval_ticks(Scoop.interval_base(self.vehicle), effects.speed, qlevel)
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
			local ore, chunk = self:PickIndexTarget()
			if not chunk then
				if (game.tick % 300) == 0 then
					self:FloatingText({"cncharvester.auto-waiting-index"}, {r = 0.8, g = 0.8, b = 0.4}, 120)
				end
				return
			end
			self.assign_si = chunk.si
			self.assign_cx = chunk.x
			self.assign_cy = chunk.y
			self.searchRadius = Stats.DefaultSearchRadius
			self.oresInRadius = {}
			self.scoopsMined = 0
			local dest = (ore and ore.position) or chunk.center
			self:StartDrive(dest, States.MiningOre, AutoDrive.PATH_RADIUS_ORE)
		end,

		[States.MiningOre] = function(self)
			if self.scoopsMined == 0 then
				local here = self.vehicle.surface.find_entities_filtered{
					type = "resource",
					area = GetBoundingBox(self.vehicle.position, 4),
				}
				local on_patch = false
				for _, ent in pairs(here) do
					if IsHarvestableResource(ent, self.vehicle) then
						on_patch = true
						break
					end
				end
				if not on_patch and self.assign_cx ~= nil then
					local ore = self:resource_in_chunk(self.assign_si, self.assign_cx, self.assign_cy)
					if ore then
						self:StartDrive(ore.position, States.MiningOre, AutoDrive.PATH_RADIUS_ORE)
						return
					end
					self:mark_failed_chunk()
					self.state = States.FindingOre
					return
				end
			end
			if self.scoopsMined >= Scoop.items_per_location(self.vehicle) then
				ModuleBay.starve(self.vehicle)
				self.state = States.FindingOre
				self.searchRadius = Stats.CloseMineSearchRadius
				self.search_range = AutoDrive.RANGE_NEAR_TILES
				self.alt_n = 0
				self.repath_n = 0
				return
			end

			local result = Scoop.tick_slave(self.vehicle)
			if result.no_fuel then
				Scoop.toast(self.vehicle, "cncharvester.out-of-fuel")
				return
			end
			if result.full and not result.inserted then
				self:SetIsFilled(true)
			end
			if (result.items or 0) > 0 then
				self.scoopsMined = self.scoopsMined + result.items
			end
			if result.full then
				self:SetIsFilled(true)
			end

			if self.filled then
				ModuleBay.starve(self.vehicle)
				self.scoopsMined = 0
				self.state = States.FindingRefinery
				return
			end
			-- Stay in MiningOre. Native drill cadence replaces PlayAnimation waits.
		end,

		[States.FindingRefinery] = function(self)
			local refinery = Refinery.NearestUnoccupied(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText({"cncharvester.no-empty-refinery"}, FLOATING_TEXT_ERROR_RED, FLOATING_TEXT_ERROR_TTL)
				end
				return
			end

			self.targetRefinery = refinery.entity.unit_number
			self:StartDrive(
				Vector.add(refinery.entity.position, Stats.RefineryApproachOffset),
				States.ApproachedRefinery,
				AutoDrive.PATH_RADIUS_HOME
			)
		end,

		[States.ApproachedRefinery] = function(self)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery and targetRefinery.entity and targetRefinery.entity.valid and not targetRefinery:IsFull() then
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					self:StartDrive(
						Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset),
						States.DroppingOre,
						AutoDrive.PATH_RADIUS_HOME
					)
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
			self.search_range = AutoDrive.RANGE_TILES
			self.home_early = false
			self.alt_n = 0
			self.repath_n = 0
			self.home_repath_n = 0

			if targetRefinery:HasFuel() then
				self.state = States.Refueling
			else
				self.state = States.FindingOre
				targetRefinery:UnReserve()
				self.reservedRefinery = false
			end
		end,

		-- Physical drive: request_path + riding_state.
		-- Legacy teleport (do not restore):
		-- self.vehicle.teleport(self.targetPosition)
		[States.MovingToLocation] = function(self)
			if (self.busy_until or 0) > game.tick then
				return
			end
			if self.path_id and not self.path then
				return
			end
			if not self.path then
				if self.targetPosition then
					self:StartDrive(self.targetPosition, self.arrival_state, self.going_home and AutoDrive.PATH_RADIUS_HOME or AutoDrive.PATH_RADIUS_ORE)
				else
					self:OnPathFail()
				end
				return
			end
			if not AutoDrive.progress_ok(self, self.vehicle.position, game.tick) then
				self:OnPathFail()
				return
			end
			local idx, arrived = AutoDrive.follow_path(self.vehicle, self.path, self.path_index)
			self.path_index = idx
			if arrived then
				AutoDrive.stop(self.vehicle)
				self.path = nil
				self.going_home = false
				if self.arrival_state then
					self.state = self.arrival_state
					self.arrival_state = false
				end
			end
		end,

		[States.FindingRefuelRefinery] = function(self)
			local refinery = Refinery.NearestWithFuel(self.vehicle)
			if not refinery then
				if (game.tick % 120) == 0 then
					self:FloatingText({"cncharvester.no-fuel-refinery"}, FLOATING_TEXT_ERROR_RED, FLOATING_TEXT_ERROR_TTL)
				end
				return
			end

			self.targetRefinery = refinery.entity.unit_number
			self:StartDrive(
				Vector.add(refinery.entity.position, Stats.RefineryApproachOffset),
				States.ApproachedForRefuel,
				AutoDrive.PATH_RADIUS_HOME
			)
		end,

		[States.ApproachedForRefuel] = function(self)
			local targetRefinery = Refinery.GetByUnitNumber(self.targetRefinery)
			if targetRefinery and targetRefinery.entity and targetRefinery.entity.valid and targetRefinery:HasFuel() then
				if not targetRefinery:IsOccupied() then
					targetRefinery:Reserve()
					self.reservedRefinery = true
					self:StartDrive(
						Vector.add(targetRefinery.entity.position, Stats.RefineryDumpOffset),
						States.Refueling,
						AutoDrive.PATH_RADIUS_HOME
					)
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
