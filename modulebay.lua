-- Slave mining-drill teleported with each Ore Truck.
-- Players open it (SHIFT+E or click the truck) for the vanilla module + energy GUI.
-- 2.1.12: the drill mines natively. Hybrid pool feeds a private micro-grid.

require "utilities"
require "hybriddrive"

ModuleBay = ModuleBay or {}

ModuleBay.NAMES = {
	["cncharvester-module-bay"] = true,
	["cncharvester-type2-module-bay"] = true,
}

ModuleBay.HELPER_NAMES = {
	["cncharvester-drill-pole"] = true,
	["cncharvester-drill-supply"] = true,
	["cncharvester-scoop-hopper"] = true,
}

ModuleBay.FOR_VEHICLE = {
	["cncharvester"] = "cncharvester-module-bay",
	["cncharvester-type2"] = "cncharvester-type2-module-bay",
}

-- Headroom above prototype energy_usage so speed-module consumption still
-- has buffer. Actual hybrid spend is measured from the supply interface.
ModuleBay.SUPPLY_WATTS_CAP = 2000000
ModuleBay.MIN_FEED_J = 1000

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

local function harden(ent)
	if not (ent and ent.valid) then
		return
	end
	if ent.minable_flag ~= nil then
		ent.minable_flag = false
	end
	if ent.destructible ~= nil then
		ent.destructible = false
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

local function destroy_entity(ent)
	if ent and ent.valid then
		ent.destroy()
	end
end

local function create_helper(surface, name, position, force)
	local ent = surface.create_entity{
		name = name,
		position = position,
		force = force,
		create_build_effect_smoke = false,
	}
	harden(ent)
	return ent
end

local function snapshot_progress(bay)
	if not (bay and bay.valid) then
		return nil, nil
	end
	return bay.mining_progress, bay.bonus_mining_progress
end

local function restore_progress(bay, progress, bonus)
	if not (bay and bay.valid) then
		return
	end
	if progress ~= nil then
		pcall(function()
			bay.mining_progress = progress
		end)
	end
	if bonus ~= nil then
		pcall(function()
			bay.bonus_mining_progress = bonus
		end)
	end
end

local function teleport_one(ent, surface, position, force)
	if not (ent and ent.valid) then
		return nil
	end
	if ent.surface ~= surface then
		return nil
	end
	if ent.force ~= force then
		ent.force = force
	end
	local pos = ent.position
	if pos.x ~= position.x or pos.y ~= position.y then
		ent.teleport(position)
	end
	harden(ent)
	return ent
end

local function attach_drop_target(bay, hopper)
	if not (bay and bay.valid and hopper and hopper.valid) then
		return
	end
	pcall(function()
		bay.drop_target = hopper
	end)
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
		ModuleBay.ensure_helpers(vehicle)
		return existing.bay
	end

	local position = vehicle.position
	local force = vehicle.force
	local surface = vehicle.surface
	local create = {
		name = name,
		position = position,
		force = force,
		create_build_effect_smoke = false,
	}
	-- Do not pass vehicle quality: quality_affects_module_slots is off, and
	-- creating the bay at higher quality must not add extra slots. Baseline
	-- mining_speed stays 1.5 / 3.0; native *modules* change rate.
	local bay = surface.create_entity(create)
	if not bay then
		return nil
	end
	harden(bay)

	local pole = create_helper(surface, "cncharvester-drill-pole", position, force)
	local supply = create_helper(surface, "cncharvester-drill-supply", position, force)
	local hopper = create_helper(surface, "cncharvester-scoop-hopper", position, force)
	attach_drop_target(bay, hopper)

	storage.module_bays[vehicle.unit_number] = {
		vehicle = vehicle,
		bay = bay,
		pole = pole,
		supply = supply,
		hopper = hopper,
		mining = false,
		supply_energy_was = 0,
	}
	ModuleBay.starve(vehicle)
	return bay
end

function ModuleBay.ensure_helpers(vehicle)
	if not (vehicle and vehicle.valid) then
		return
	end
	local rec = record(vehicle)
	if not rec then
		return
	end
	local surface = vehicle.surface
	local position = vehicle.position
	local force = vehicle.force
	if not (rec.pole and rec.pole.valid) then
		rec.pole = create_helper(surface, "cncharvester-drill-pole", position, force)
	end
	if not (rec.supply and rec.supply.valid) then
		rec.supply = create_helper(surface, "cncharvester-drill-supply", position, force)
	end
	if not (rec.hopper and rec.hopper.valid) then
		rec.hopper = create_helper(surface, "cncharvester-scoop-hopper", position, force)
	end
	attach_drop_target(rec.bay, rec.hopper)
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

function ModuleBay.get_record(vehicle)
	if not (vehicle and vehicle.valid) then
		return nil
	end
	return record(vehicle)
end

function ModuleBay.ensure(vehicle)
	local bay = ModuleBay.get(vehicle)
	if bay then
		ModuleBay.ensure_helpers(vehicle)
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
	local rec = record(vehicle)
	local surface = vehicle.surface
	local position = vehicle.position
	local force = vehicle.force
	local progress, bonus = snapshot_progress(bay)

	if bay.surface ~= surface then
		local inv = bay.get_module_inventory()
		ModuleBay.destroy_helpers(rec)
		bay.destroy()
		local created = ModuleBay.create(vehicle)
		if created and inv then
			transfer_modules(inv, created.get_module_inventory())
		end
		return
	end

	teleport_one(bay, surface, position, force)
	if rec then
		if not teleport_one(rec.pole, surface, position, force) then
			rec.pole = create_helper(surface, "cncharvester-drill-pole", position, force)
		end
		if not teleport_one(rec.supply, surface, position, force) then
			rec.supply = create_helper(surface, "cncharvester-drill-supply", position, force)
		end
		if not teleport_one(rec.hopper, surface, position, force) then
			rec.hopper = create_helper(surface, "cncharvester-scoop-hopper", position, force)
		end
		attach_drop_target(bay, rec.hopper)
	end
	restore_progress(bay, progress, bonus)
	harden(bay)
end

function ModuleBay.destroy_helpers(rec)
	if not rec then
		return
	end
	destroy_entity(rec.hopper)
	destroy_entity(rec.supply)
	destroy_entity(rec.pole)
	rec.hopper = nil
	rec.supply = nil
	rec.pole = nil
end

function ModuleBay.destroy_for_vehicle(vehicle, buffer)
	if not vehicle then
		return
	end
	ModuleBay.ensure_storage()
	local rec = storage.module_bays[vehicle.unit_number]
	storage.module_bays[vehicle.unit_number] = nil
	local bay = rec and rec.bay
	if bay and bay.valid then
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
	ModuleBay.destroy_helpers(rec)
end

function ModuleBay.on_bay_removed(bay)
	if not (bay and bay.valid) then
		return
	end
	ModuleBay.ensure_storage()
	for unit_number, rec in pairs(storage.module_bays) do
		if rec.bay == bay then
			storage.module_bays[unit_number] = nil
			ModuleBay.destroy_helpers(rec)
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
			ModuleBay.destroy_helpers(rec)
			storage.module_bays[unit_number] = nil
		end
	end
end

local function is_tracked_helper(ent)
	for _, rec in pairs(storage.module_bays or {}) do
		if rec.bay == ent or rec.pole == ent or rec.supply == ent or rec.hopper == ent then
			return true
		end
	end
	return false
end

function ModuleBay.attach_existing()
	for _, surface in pairs(game.surfaces) do
		for _, ent in pairs(surface.find_entities_filtered{name = {"cncharvester", "cncharvester-type2"}}) do
			ModuleBay.ensure(ent)
		end
		local orphan_names = {
			"cncharvester-module-bay",
			"cncharvester-type2-module-bay",
			"cncharvester-drill-pole",
			"cncharvester-drill-supply",
			"cncharvester-scoop-hopper",
		}
		for _, name in pairs(orphan_names) do
			for _, ent in pairs(surface.find_entities_filtered{name = name}) do
				if not is_tracked_helper(ent) then
					if ModuleBay.NAMES[ent.name] then
						spill_modules(ent)
					end
					ent.destroy()
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

function ModuleBay.prototype_energy_w(vehicle)
	local bay = ModuleBay.get(vehicle)
	if bay and bay.valid and bay.prototype then
		local proto = bay.prototype
		if proto.get_max_energy_usage then
			local ok, watts = pcall(proto.get_max_energy_usage, proto, bay.quality)
			if ok and watts and watts > 0 then
				return watts
			end
		end
		if proto.energy_usage and proto.energy_usage > 0 then
			return proto.energy_usage
		end
	end
	if vehicle and vehicle.name == "cncharvester-type2" then
		return 360000
	end
	return 180000
end

function ModuleBay.estimated_draw_w(vehicle)
	local watts = ModuleBay.prototype_energy_w(vehicle)
	local effects = ModuleBay.effects(vehicle)
	local cons = 1 + (effects.consumption or 0)
	if cons < 0.2 then
		cons = 0.2
	end
	return watts * cons
end

local function set_supply_watts(supply, watts)
	if not (supply and supply.valid) then
		return
	end
	watts = math.max(0, watts or 0)
	if supply.power_production ~= nil then
		supply.power_production = watts
	end
	if watts > 0 and supply.electric_buffer_size then
		supply.energy = supply.electric_buffer_size
	elseif watts <= 0 then
		supply.energy = 0
	end
end

-- Factorio 2.1: LuaEntity.active is read-only (nth_tick crash in 2.1.13).
-- Gate the drill with disabled_by_script when present; always cut/restore
-- the private EEI so an empty hybrid pool cannot mine.
local function set_drill_enabled(bay, enabled)
	if not (bay and bay.valid) then
		return
	end
	pcall(function()
		bay.disabled_by_script = not enabled
	end)
	if enabled then
		if bay.electric_buffer_size then
			bay.energy = bay.electric_buffer_size
		end
	else
		bay.energy = 0
	end
end

function ModuleBay.starve(vehicle)
	local rec = record(vehicle)
	if not rec then
		return
	end
	rec.mining = false
	set_drill_enabled(rec.bay, false)
	set_supply_watts(rec.supply, 0)
	rec.supply_energy_was = 0
end

-- Pay-first: spend an estimated tick of draw, then energize the micro-grid.
-- Next call refunds unused supply energy so efficiency (lower draw) is a real
-- cheaper tick and speed/other (higher draw) costs more.
function ModuleBay.feed_energy(vehicle)
	local rec = record(vehicle)
	if not (rec and rec.bay and rec.bay.valid) then
		return false
	end
	ModuleBay.ensure_helpers(vehicle)
	local supply = rec.supply
	local previous = rec.supply_energy_was or 0
	if supply and supply.valid then
		local now = supply.energy or 0
		if previous > now then
			-- Already paid; leftover stays in the interface for the next tick.
		end
	end

	local draw_w = ModuleBay.estimated_draw_w(vehicle)
	local tick_j = math.max(ModuleBay.MIN_FEED_J, draw_w / 60)
	if not HybridDrive.can_afford(vehicle, tick_j) then
		ModuleBay.starve(vehicle)
		return false
	end
	if not HybridDrive.spend(vehicle, tick_j) then
		ModuleBay.starve(vehicle)
		return false
	end

	rec.mining = true
	set_supply_watts(supply, math.min(ModuleBay.SUPPLY_WATTS_CAP, math.max(draw_w * 2, 180000)))
	set_drill_enabled(rec.bay, true)
	if supply and supply.valid then
		rec.supply_energy_was = supply.energy or 0
	end
	return true
end

function ModuleBay.collect(vehicle)
	local rec = record(vehicle)
	if not rec then
		return {inserted = false, full = false, items = 0}
	end
	if not (rec.hopper and rec.hopper.valid) then
		return {inserted = false, full = false, items = 0}
	end
	local hop_inv = rec.hopper.get_inventory(defines.inventory.chest)
	local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
	if not (hop_inv and hop_inv.valid and trunk and trunk.valid) then
		return {inserted = false, full = false, items = 0}
	end

	local items = 0
	local inserted = false
	local full = false
	local contents = hop_inv.get_contents() or {}
	for _, item in pairs(contents) do
		local name = item.name
		local count = item.count or 0
		local quality = item.quality
		if name and count > 0 then
			local stack = InventoryItemStack(name, count, quality)
			local moved = 0
			if trunk.can_insert(stack) then
				moved = trunk.insert(stack) or 0
			end
			if moved > 0 then
				hop_inv.remove(InventoryItemStack(name, moved, quality))
				items = items + moved
				inserted = true
			end
			if moved < count then
				full = true
			end
		end
	end
	return {inserted = inserted, full = full, items = items, no_fuel = false}
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
			ModuleBay.ensure_draw_gui(player, selected)
			return
		end
	end
	if not (vehicle and vehicle.valid) then
		return
	end
	local bay = ModuleBay.ensure(vehicle)
	if bay and bay.valid then
		player.opened = bay
		ModuleBay.ensure_draw_gui(player, bay)
	end
end

function ModuleBay.ensure_draw_gui(player, bay)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local rel = player.gui.relative
	local existing = rel["cncharvester-drill-draw"]
	if existing then
		existing.destroy()
	end
	if not (bay and bay.valid and ModuleBay.NAMES[bay.name]) then
		return
	end
	local anchor = {
		gui = defines.relative_gui_type.mining_drill_gui,
		position = defines.relative_gui_position.top
	}
	local frame = rel.add{
		type = "frame",
		name = "cncharvester-drill-draw",
		caption = {"cncharvester.mining-draw-title"},
		anchor = anchor,
		direction = "vertical"
	}
	frame.add{
		type = "label",
		name = "cncharvester-drill-draw-label",
		caption = {"cncharvester.mining-draw-line", "0"}
	}
	frame.add{
		type = "progressbar",
		name = "cncharvester-drill-draw-bar",
		value = 0
	}
end

function ModuleBay.refresh_draw_gui(player, vehicle)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local frame = player.gui.relative["cncharvester-drill-draw"]
	if not frame then
		return
	end
	local draw_w = 0
	if vehicle and vehicle.valid then
		draw_w = ModuleBay.estimated_draw_w(vehicle)
	end
	local kw = math.floor(draw_w / 1000 + 0.5)
	local label = frame["cncharvester-drill-draw-label"]
	if label then
		label.caption = {"cncharvester.mining-draw-line", tostring(kw)}
	end
	local bar = frame["cncharvester-drill-draw-bar"]
	if bar then
		-- 0 at the 20% efficiency floor, 1 at 3× baseline (speed-heavy).
		local baseline = ModuleBay.prototype_energy_w(vehicle)
		local span = baseline * 3
		if span <= 0 then
			span = 180000
		end
		bar.value = math.max(0, math.min(1, draw_w / span))
	end
end

function ModuleBay.close_draw_gui(player)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local frame = player.gui.relative["cncharvester-drill-draw"]
	if frame then
		frame.destroy()
	end
end
