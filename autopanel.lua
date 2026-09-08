-- Per-harvester auto-drive toggles on the car inventory (relative GUI).
-- Factorio 2.0: player.gui.relative + defines.relative_gui_type.car_gui.
--
-- Never write auto_enabled from on_gui_checked_state_changed. Closing,
-- destroying, or entering a car fires state=false on those checkboxes
-- while the inventory is still "open", which used to SetAutoEnabled(false).
-- Real toggles apply only from on_gui_click while the car GUI is open.

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
local last_sync_tick = {}
local pending_click = {}
local SYNC_GRACE_TICKS = 2

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

local function mark_sync(player)
	if player and player.valid and game then
		last_sync_tick[player.index] = game.tick
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

local function in_sync_grace(player_index)
	if not (game and player_index) then
		return false
	end
	local synced = last_sync_tick[player_index]
	return synced ~= nil and game.tick <= synced + SYNC_GRACE_TICKS
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
	mark_sync(player)
	with_ignore(function()
		if vehicle and vehicle.valid then
			frame.tags = {unit_number = vehicle.unit_number}
		end
		if auto_cb and auto_cb.valid then
			if vehicle and vehicle.valid then
				auto_cb.tags = {unit_number = vehicle.unit_number}
			end
			local want_auto = h ~= nil and h.auto_enabled ~= false
			if auto_cb.state ~= want_auto then
				auto_cb.state = want_auto
			end
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
			local want_pause = h ~= nil and h.pause_on_enter == true
			if pause_cb.state ~= want_pause then
				pause_cb.state = want_pause
			end
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
	mark_sync(player)
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

local function apply_toggle(el, player)
	if ignore_checked > 0 then
		return false
	end
	if player and player.valid and in_sync_grace(player.index) then
		return false
	end
	if not (el and el.valid) then
		return false
	end
	if el.name ~= AUTO_CB and el.name ~= PAUSE_CB then
		return false
	end
	-- Only apply while the car inventory is genuinely open.
	local vehicle = opened_harvester(player)
	if not (vehicle and vehicle.valid) then
		return false
	end
	local tags = el.tags
	if tags and tags.unit_number and tags.unit_number ~= vehicle.unit_number then
		return false
	end
	if AutoPanel.track_vehicle then
		AutoPanel.track_vehicle(vehicle)
	end
	local h = storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
	if not h then
		return false
	end
	if el.name == AUTO_CB then
		local want = el.state and true or false
		if want == (h.auto_enabled ~= false) then
			return true
		end
		h:SetAutoEnabled(want, "player_checkbox")
	else
		local want = el.state and true or false
		if want == (h.pause_on_enter == true) then
			return true
		end
		h:SetPauseOnEnter(want)
	end
	AutoPanel.sync_viewers(vehicle)
	return true
end

-- User click is the only path that may write auto_enabled.
function AutoPanel.on_click(event)
	local el = event.element
	if not (el and el.valid) then
		return
	end
	if el.name ~= AUTO_CB and el.name ~= PAUSE_CB then
		return
	end
	local player = event.player_index and game.get_player(event.player_index)
	if event.player_index then
		pending_click[event.player_index] = {
			name = el.name,
			tick = game and game.tick or 0,
		}
	end
	apply_toggle(el, player)
end

-- Destroy/close/enter fire this with state=false. Never write storage from
-- a checked event unless it is the same tick as a real click.
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
	local pending = event.player_index and pending_click[event.player_index]
	local same_click = pending
		and pending.name == el.name
		and game
		and pending.tick == game.tick
	if same_click then
		pending_click[event.player_index] = nil
		local player = game.get_player(event.player_index)
		apply_toggle(el, player)
		return
	end
	if in_sync_grace(event.player_index) then
		return
	end
	if el.name == AUTO_CB and el.state ~= true then
		local player = event.player_index and game.get_player(event.player_index)
		local vehicle = opened_harvester(player)
		local h = vehicle and storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
		if h and h.NoteUnauthorizedAutoOff then
			h:NoteUnauthorizedAutoOff("gui-checked")
		else
			log("Red-Alert-Harvester: ignored checkbox uncheck without a click")
		end
	end
end
