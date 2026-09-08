-- Per-harvester auto-drive toggles on the car inventory (relative GUI).
-- Factorio 2.0: player.gui.relative + defines.relative_gui_type.car_gui.

AutoPanel = AutoPanel or {}

local FRAME = "cncharvester-auto-panel"
local AUTO_CB = "cncharvester-auto-enabled"
local PAUSE_CB = "cncharvester-pause-on-enter"

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

local function testing_on()
	return ChunkIndex and ChunkIndex.enabled and ChunkIndex.enabled()
end

local function harvester_for(entity)
	if not (entity and entity.valid and HARVESTER_NAMES[entity.name]) then
		return nil, nil
	end
	local recs = storage.cncharvesters
	if not recs then
		return nil, entity
	end
	return recs[entity.unit_number], entity
end

function AutoPanel.destroy(player)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local frame = player.gui.relative[FRAME]
	if frame and frame.valid then
		frame.destroy()
	end
end

function AutoPanel.sync(player, vehicle)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local frame = player.gui.relative[FRAME]
	if not (frame and frame.valid) then
		return
	end
	local h = vehicle and harvester_for(vehicle)
	local auto_cb = frame[AUTO_CB]
	local pause_cb = frame[PAUSE_CB]
	local flag = testing_on()
	if auto_cb and auto_cb.valid then
		auto_cb.state = h ~= nil and h.auto_enabled ~= false
		auto_cb.enabled = flag and h ~= nil
		if not flag then
			auto_cb.tooltip = {"cncharvester-gui.needs-testing-flag"}
		else
			auto_cb.tooltip = {"cncharvester-gui.auto-operation-tooltip"}
		end
	end
	if pause_cb and pause_cb.valid then
		pause_cb.state = h ~= nil and h.pause_on_enter == true
		pause_cb.enabled = flag and h ~= nil
		if not flag then
			pause_cb.tooltip = {"cncharvester-gui.needs-testing-flag"}
		else
			pause_cb.tooltip = {"cncharvester-gui.pause-on-enter-tooltip"}
		end
	end
	if vehicle and vehicle.valid then
		frame.tags = {unit_number = vehicle.unit_number}
	end
end

function AutoPanel.ensure(player, vehicle)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	if not testing_on() then
		AutoPanel.destroy(player)
		return
	end
	if not (vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name]) then
		return
	end
	local rel = player.gui.relative
	local existing = rel[FRAME]
	if existing and existing.valid then
		existing.destroy()
	end
	local anchor = {
		gui = defines.relative_gui_type.car_gui,
		position = defines.relative_gui_position.left,
		type = "car",
		names = {"cncharvester", "cncharvester-type2"},
	}
	local frame = rel.add{
		type = "frame",
		name = FRAME,
		caption = {"cncharvester-gui.auto-caption"},
		anchor = anchor,
		direction = "vertical",
	}
	frame.tags = {unit_number = vehicle.unit_number}
	frame.add{
		type = "checkbox",
		name = AUTO_CB,
		caption = {"cncharvester-gui.auto-operation"},
		tooltip = {"cncharvester-gui.auto-operation-tooltip"},
		state = true,
	}
	frame.add{
		type = "checkbox",
		name = PAUSE_CB,
		caption = {"cncharvester-gui.pause-on-enter"},
		tooltip = {"cncharvester-gui.pause-on-enter-tooltip"},
		state = false,
	}
	AutoPanel.sync(player, vehicle)
end

function AutoPanel.sync_viewers(vehicle)
	if not (vehicle and vehicle.valid and game and game.connected_players) then
		return
	end
	for _, player in pairs(game.connected_players) do
		local opened = player.opened
		if opened and opened.valid and opened.object_name == "LuaEntity" and opened == vehicle then
			AutoPanel.sync(player, vehicle)
		end
	end
end

local function vehicle_from_event(event, element)
	local player = event.player_index and game.get_player(event.player_index)
	if player and player.valid then
		local opened = player.opened
		if opened and opened.valid and opened.object_name == "LuaEntity" and HARVESTER_NAMES[opened.name] then
			return opened
		end
		if player.vehicle and player.vehicle.valid and HARVESTER_NAMES[player.vehicle.name] then
			return player.vehicle
		end
	end
	local tags = element and element.valid and element.tags
	if (not tags or not tags.unit_number) and element and element.valid and element.parent then
		tags = element.parent.tags
	end
	local id = tags and tags.unit_number
	local recs = storage.cncharvesters
	if id and recs and recs[id] then
		return recs[id].vehicle
	end
	return nil
end

function AutoPanel.on_checked(event)
	local el = event.element
	if not (el and el.valid) then
		return
	end
	if el.name ~= AUTO_CB and el.name ~= PAUSE_CB then
		return
	end
	local vehicle = vehicle_from_event(event, el)
	if not (vehicle and vehicle.valid) then
		return
	end
	local h = storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
	if not h then
		return
	end
	if el.name == AUTO_CB then
		h:SetAutoEnabled(el.state)
	else
		h:SetPauseOnEnter(el.state)
	end
	AutoPanel.sync_viewers(vehicle)
end
