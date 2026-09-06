-- Companion module bay: a hidden mining-drill teleported with each Ore Truck.
-- Players open it (click or SHIFT+E) for the vanilla module GUI.

require "utilities"

ModuleBay = ModuleBay or {}

ModuleBay.NAMES = {
	["cncharvester-module-bay"] = true,
	["cncharvester-type2-module-bay"] = true,
}

ModuleBay.FOR_VEHICLE = {
	["cncharvester"] = "cncharvester-module-bay",
	["cncharvester-type2"] = "cncharvester-type2-module-bay",
}

local EMPTY_EFFECTS = {
	speed = 0,
	productivity = 0,
	consumption = 0,
	pollution = 0,
	quality = 0,
}

function ModuleBay.ensure_storage()
	storage.module_bays = storage.module_bays or {}
end

local function record(vehicle)
	ModuleBay.ensure_storage()
	return storage.module_bays[vehicle.unit_number]
end

local function bay_name_for(vehicle)
	return ModuleBay.FOR_VEHICLE[vehicle.name]
end

local function harden(bay)
	if not (bay and bay.valid) then
		return
	end
	if bay.minable_flag ~= nil then
		bay.minable_flag = false
	end
	if bay.destructible ~= nil then
		bay.destructible = false
	end
end

local function transfer_modules(from_inv, to_inv)
	if not (from_inv and from_inv.valid and to_inv and to_inv.valid) then
		return
	end
	for i = 1, #from_inv do
		local stack = from_inv[i]
		if stack.valid_for_read then
			to_inv.insert(stack)
			stack.clear()
		end
	end
end

local function spill_modules(bay)
	if not (bay and bay.valid) then
		return
	end
	local inv = bay.get_module_inventory()
	if not inv then
		return
	end
	local surface = bay.surface
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			local ok = pcall(function()
				surface.spill_item_stack{
					position = bay.position,
					stack = stack,
					allow_belts = false
				}
			end)
			if not ok then
				pcall(surface.spill_item_stack, surface, stack, bay.position)
			end
			stack.clear()
		end
	end
end

function ModuleBay.create(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	local name = bay_name_for(vehicle)
	if not name then
		return nil
	end
	ModuleBay.ensure_storage()
	local existing = storage.module_bays[vehicle.unit_number]
	if existing and existing.bay and existing.bay.valid then
		return existing.bay
	end

	local create = {
		name = name,
		position = vehicle.position,
		force = vehicle.force,
		create_build_effect_smoke = false,
	}
	if vehicle.quality then
		create.quality = vehicle.quality.name or vehicle.quality
	end
	local bay = vehicle.surface.create_entity(create)
	if not bay then
		return nil
	end
	harden(bay)
	storage.module_bays[vehicle.unit_number] = {
		vehicle = vehicle,
		bay = bay,
	}
	return bay
end

function ModuleBay.get(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	local rec = record(vehicle)
	if rec and rec.bay and rec.bay.valid then
		return rec.bay
	end
	return nil
end

function ModuleBay.ensure(vehicle)
	local bay = ModuleBay.get(vehicle)
	if bay then
		return bay
	end
	return ModuleBay.create(vehicle)
end

function ModuleBay.sync(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local bay = ModuleBay.ensure(vehicle)
	if not (bay and bay.valid) then
		return
	end
	if bay.surface ~= vehicle.surface then
		local inv = bay.get_module_inventory()
		bay.destroy()
		local created = ModuleBay.create(vehicle)
		if created and inv then
			transfer_modules(inv, created.get_module_inventory())
		end
		return
	end
	if bay.force ~= vehicle.force then
		bay.force = vehicle.force
	end
	local pos = vehicle.position
	if bay.position.x ~= pos.x or bay.position.y ~= pos.y then
		bay.teleport(pos)
	end
	harden(bay)
end

function ModuleBay.destroy_for_vehicle(vehicle, buffer)
	if not vehicle then
		return
	end
	ModuleBay.ensure_storage()
	local rec = storage.module_bays[vehicle.unit_number]
	storage.module_bays[vehicle.unit_number] = nil
	local bay = rec and rec.bay
	if not (bay and bay.valid) then
		return
	end
	local inv = bay.get_module_inventory()
	if buffer and buffer.valid and inv then
		transfer_modules(inv, buffer)
	elseif vehicle.valid then
		local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
		if trunk and inv then
			transfer_modules(inv, trunk)
		else
			spill_modules(bay)
		end
	else
		spill_modules(bay)
	end
	bay.destroy()
end

function ModuleBay.on_bay_removed(bay)
	if not (bay and bay.valid) then
		return
	end
	ModuleBay.ensure_storage()
	for unit_number, rec in pairs(storage.module_bays) do
		if rec.bay == bay then
			storage.module_bays[unit_number] = nil
			local vehicle = rec.vehicle
			if vehicle and vehicle.valid then
				ModuleBay.create(vehicle)
			end
			return
		end
	end
end

function ModuleBay.sync_all()
	ModuleBay.ensure_storage()
	for unit_number, rec in pairs(storage.module_bays) do
		local vehicle = rec.vehicle
		if vehicle and vehicle.valid then
			ModuleBay.sync(vehicle)
		else
			if rec.bay and rec.bay.valid then
				spill_modules(rec.bay)
				rec.bay.destroy()
			end
			storage.module_bays[unit_number] = nil
		end
	end
end

function ModuleBay.attach_existing()
	for _, surface in pairs(game.surfaces) do
		for _, ent in pairs(surface.find_entities_filtered{name = {"cncharvester", "cncharvester-type2"}}) do
			ModuleBay.ensure(ent)
		end
		-- Destroy orphan bays that are not tracked.
		for bay_name in pairs(ModuleBay.NAMES) do
			for _, bay in pairs(surface.find_entities_filtered{name = bay_name}) do
				local tracked = false
				for _, rec in pairs(storage.module_bays or {}) do
					if rec.bay == bay then
						tracked = true
						break
					end
				end
				if not tracked then
					spill_modules(bay)
					bay.destroy()
				end
			end
		end
	end
end

local function add_effect(dst, src, quality)
	if not src then
		return
	end
	local function scaled(key, qmult)
		local v = src[key] or 0
		if quality and quality[qmult] then
			v = v * quality[qmult]
		end
		dst[key] = (dst[key] or 0) + v
	end
	scaled("speed", "module_speed_multiplier")
	scaled("productivity", "module_productivity_multiplier")
	scaled("consumption", "module_consumption_multiplier")
	scaled("pollution", "module_pollution_multiplier")
	scaled("quality", "module_quality_multiplier")
end

function ModuleBay.effects(vehicle)
	local bay = ModuleBay.ensure(vehicle)
	if not (bay and bay.valid) then
		return EMPTY_EFFECTS
	end
	if bay.effects then
		return bay.effects
	end
	local inv = bay.get_module_inventory()
	if not inv then
		return EMPTY_EFFECTS
	end
	local out = {
		speed = 0,
		productivity = 0,
		consumption = 0,
		pollution = 0,
		quality = 0,
	}
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			local proto = stack.prototype
			local me = proto.module_effects
			if me then
				add_effect(out, me, stack.quality)
			end
		end
	end
	return out
end

function ModuleBay.open_for_player(player)
	if not (player and player.valid) then
		return
	end
	local vehicle = player.vehicle
	if not (vehicle and vehicle.valid and bay_name_for(vehicle)) then
		local selected = player.selected
		if selected and selected.valid and bay_name_for(selected) then
			vehicle = selected
		elseif selected and selected.valid and ModuleBay.NAMES[selected.name] then
			player.opened = selected
			return
		end
	end
	if not (vehicle and vehicle.valid) then
		return
	end
	local bay = ModuleBay.ensure(vehicle)
	if bay and bay.valid then
		player.opened = bay
	end
end
