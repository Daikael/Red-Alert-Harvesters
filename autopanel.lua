-- Per-harvester auto-drive toggles on the car inventory (relative GUI).
-- Factorio 2.0: player.gui.relative + defines.relative_gui_type.car_gui.
--
-- Do not destroy checkboxes on inventory close. Factorio fires
-- on_gui_checked_state_changed with state=false while destroying the
-- element; that used to SetAutoEnabled(false) and left unmanned trucks idle.

AutoPanel = AutoPanel or {}

local FRAME = "cncharvester-auto-panel"
local AUTO_CB = "cncharvester-auto-enabled"
local PAUSE_CB = "cncharvester-pause-on-enter"

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

-- Nested while creating/syncing/destroying so those .state writes are not
-- treated as a player click.
local ignore_checked = 0

local function testing_on()
	return ChunkIndex and ChunkIndex.enabled and ChunkIndex.enabled()
end

local function with_ignore(fn)
	ignore_checked = ignore_checked + 1
	local ok, err = pcall(fn)
	ignore_checked = ignore_checked - 1
	if not ok then
		error(err)
	end
end

local function opened_harvester(player)
	if not (player and player.valid) then
		return nil
	end
	local opened = player.opened
	if opened and opened.valid and opened.object_name == "LuaEntity" and HARVESTER_NAMES[opened.name] then
		return opened
	end
	return nil
end

function AutoPanel.destroy(player)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	with_ignore(function()
		local frame = player.gui.relative[FRAME]
		if frame and frame.valid then
			frame.destroy()
		end
	end)
end

function AutoPanel.sync(player, vehicle)
	if not (player and player.valid and player.gui and player.gui.relative) then
		return
	end
	local frame = player.gui.relative[FRAME]
	if not (frame and frame.valid) then
		return
	end
	local h = vehicle and storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
	local auto_cb = frame[AUTO_CB]
	local pause_cb = frame[PAUSE_CB]
	local flag = testing_on()
	with_ignore(function()
		if vehicle and vehicle.valid then
			frame.tags = {unit_number = vehicle.unit_number}
		end
		if auto_cb and auto_cb.valid then
			if vehicle and vehicle.valid then
				auto_cb.tags = {unit_number = vehicle.unit_number}
			end
			auto_cb.state = h ~= nil and h.auto_enabled ~= false
			auto_cb.enabled = flag and h ~= nil
			if not flag then
				auto_cb.tooltip = {"cncharvester-gui.needs-testing-flag"}
			else
				auto_cb.tooltip = {"cncharvester-gui.auto-operation-tooltip"}
			end
		end
		if pause_cb and pause_cb.valid then
			if vehicle and vehicle.valid then
				pause_cb.tags = {unit_number = vehicle.unit_number}
			end
			pause_cb.state = h ~= nil and h.pause_on_enter == true
			pause_cb.enabled = flag and h ~= nil
			if not flag then
				pause_cb.tooltip = {"cncharvester-gui.needs-testing-flag"}
			else
				pause_cb.tooltip = {"cncharvester-gui.pause-on-enter-tooltip"}
			end
		end
	end)
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
	if AutoPanel.track_vehicle then
		AutoPanel.track_vehicle(vehicle)
	end
	local rel = player.gui.relative
	local frame = rel[FRAME]
	if not (frame and frame.valid) then
		with_ignore(function()
			local anchor = {
				gui = defines.relative_gui_type.car_gui,
				position = defines.relative_gui_position.left,
				type = "car",
				names = {"cncharvester", "cncharvester-type2"},
			}
			frame = rel.add{
				type = "frame",
				name = FRAME,
				caption = {"cncharvester-gui.auto-caption"},
				anchor = anchor,
				direction = "vertical",
			}
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
		end)
	end
	AutoPanel.sync(player, vehicle)
end

function AutoPanel.sync_viewers(vehicle)
	if not (vehicle and vehicle.valid and game and game.connected_players) then
		return
	end
	for _, player in pairs(game.connected_players) do
		local opened = opened_harvester(player)
		if opened and opened == vehicle then
			AutoPanel.sync(player, vehicle)
		end
	end
end

function AutoPanel.on_checked(event)
	if ignore_checked > 0 then
		return
	end
	local el = event.element
	if not (el and el.valid) then
		return
	end
	if el.name ~= AUTO_CB and el.name ~= PAUSE_CB then
		return
	end
	-- Only apply while the car inventory is open. Closing/destroying the
	-- relative GUI must not write auto_enabled (Factorio sends state=false).
	local player = event.player_index and game.get_player(event.player_index)
	local vehicle = opened_harvester(player)
	if not (vehicle and vehicle.valid) then
		return
	end
	if AutoPanel.track_vehicle then
		AutoPanel.track_vehicle(vehicle)
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
