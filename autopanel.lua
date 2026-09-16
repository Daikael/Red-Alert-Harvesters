-- Per-harvester auto-drive toggles on the car inventory (relative GUI).
-- Factorio 2.0: player.gui.relative + defines.relative_gui_type.car_gui.
--
-- Never write auto_enabled from on_gui_checked_state_changed. Closing,
-- destroying, or entering a car fires state=false on those checkboxes
-- while the inventory is still "open", which used to SetAutoEnabled(false).
-- Real toggles apply only from on_gui_click while the car GUI is open.
--
-- Factorio 2.0.77: a single relative frame with type="car" plus
-- names={cncharvester, cncharvester-type2} does not show on the Ore Truck
-- (cncharvester). type2 can still look fine. Each prototype gets its own
-- frame with a singular `name` and no `type` filter. One panel only:
-- relative `car_gui` at `left` on every display (including Steam Deck).
-- Do not also pin a top bar or a free-floating `gui.screen` copy.
--
-- When Automatic harvester testing is off, do not destroy the panel.
-- Show a one-line notice (zip overwrite often resets that startup flag
-- to default off, which used to look like an Ore Truck-only bug).

AutoPanel = AutoPanel or {}

local FRAME = "cncharvester-auto-panel"
local FRAME_SCREEN = "cncharvester-auto-panel-screen"
local AUTO_CB = "cncharvester-auto-enabled"
local PAUSE_CB = "cncharvester-pause-on-enter"
local NOTICE = "cncharvester-auto-needs-testing"

local HARVESTER_NAMES = {
	["cncharvester"] = true,
	["cncharvester-type2"] = true,
}

local HARVESTER_NAME_LIST = {
	"cncharvester",
	"cncharvester-type2",
}

-- Nested while creating/syncing/destroying so those .state writes are not
-- treated as a player click.
local ignore_checked = 0
local last_sync_tick = {}
local pending_click = {}
local last_notice_tick = {}
local SYNC_GRACE_TICKS = 2
local NOTICE_TOAST_TICKS = 300
-- Below this effective width, left-of-car-gui is often off-screen.
local NARROW_WIDTH = 1366

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

local function relative_frame_id(proto_name)
	return FRAME .. "-" .. proto_name
end

function AutoPanel.harvester_names()
	return HARVESTER_NAMES
end

function AutoPanel.narrow_display(player)
	if not (player and player.valid and player.display_resolution) then
		return false
	end
	local w = player.display_resolution.width or 0
	local scale = player.display_scale or 1
	if scale < 0.1 then
		scale = 1
	end
	return (w / scale) <= NARROW_WIDTH
end

function AutoPanel.panel_position(_player)
	return defines.relative_gui_position.left
end

-- Singular prototype name, no type="car", no names-array. 2.0.77 failed to
-- show the Ore Truck panel with type+names={ore,type2} on one frame.
function AutoPanel.anchor_for(vehicle_name, position)
	return {
		gui = defines.relative_gui_type.car_gui,
		position = position,
		name = vehicle_name,
	}
end

local function add_checkboxes(frame)
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
end

local function add_notice(frame)
	local lab = frame.add{
		type = "label",
		name = NOTICE,
		caption = {"cncharvester-gui.needs-testing-flag-notice"},
		tooltip = {"cncharvester-gui.needs-testing-flag"},
	}
	pcall(function()
		lab.style.single_line = true
	end)
end

function AutoPanel.frame_is_notice(frame)
	return frame ~= nil and frame.valid == true and frame[NOTICE] ~= nil and frame[NOTICE].valid == true
end

function AutoPanel.frame_is_full(frame)
	return frame ~= nil and frame.valid == true and frame[AUTO_CB] ~= nil and frame[AUTO_CB].valid == true
end

local function frame_mode_ok(frame, want_notice)
	if want_notice then
		return AutoPanel.frame_is_notice(frame)
	end
	return AutoPanel.frame_is_full(frame)
end

local function toast_testing_off(player, vehicle)
	if not (player and player.valid) then
		return
	end
	local now = game and game.tick or 0
	local prev = last_notice_tick[player.index]
	if prev and now < prev + NOTICE_TOAST_TICKS then
		return
	end
	last_notice_tick[player.index] = now
	pcall(function()
		player.print({"cncharvester-gui.needs-testing-flag-notice"})
	end)
	if not (vehicle and vehicle.valid and vehicle.surface and vehicle.position) then
		return
	end
	pcall(function()
		vehicle.surface.create_entity{
			name = "flying-text",
			position = vehicle.position,
			text = {"cncharvester-gui.needs-testing-flag-notice"},
			color = {r = 1, g = 0.85, b = 0.3},
		}
	end)
end

local function destroy_named(parent, name)
	if not (parent and name) then
		return
	end
	local el = parent[name]
	if el and el.valid then
		el.destroy()
	end
end

function AutoPanel.destroy(player)
	if not (player and player.valid and player.gui) then
		return
	end
	with_ignore(function()
		local rel = player.gui.relative
		if rel then
			destroy_named(rel, FRAME)
			for _, proto in ipairs(HARVESTER_NAME_LIST) do
				destroy_named(rel, relative_frame_id(proto))
			end
		end
		if player.gui.screen then
			destroy_named(player.gui.screen, FRAME_SCREEN)
		end
	end)
end

function AutoPanel.hide_transient(player)
	if not (player and player.valid and player.gui and player.gui.screen) then
		return
	end
	with_ignore(function()
		destroy_named(player.gui.screen, FRAME_SCREEN)
	end)
end

local function each_panel_frame(player, vehicle, fn)
	if not (player and player.valid and player.gui) then
		return
	end
	local screen = player.gui.screen
	if screen then
		local sf = screen[FRAME_SCREEN]
		if sf and sf.valid then
			fn(sf)
		end
	end
	local rel = player.gui.relative
	if not rel then
		return
	end
	if vehicle and vehicle.valid then
		local named = rel[relative_frame_id(vehicle.name)]
		if named and named.valid then
			fn(named)
		end
	end
	local legacy = rel[FRAME]
	if legacy and legacy.valid then
		fn(legacy)
	end
end

local function relative_anchor_ok(frame, vehicle_name, position)
	if not (frame and frame.valid) then
		return false
	end
	local anchor = frame.anchor
	if not anchor then
		return false
	end
	if anchor.position ~= position then
		return false
	end
	-- Reading always populates `names`. Require a single exact prototype.
	local names = anchor.names
	local n = anchor.name
	if n == vehicle_name and (not names or #names <= 1) then
		return true
	end
	if names and #names == 1 and names[1] == vehicle_name then
		return true
	end
	return false
end

function AutoPanel.sync(player, vehicle)
	if not (player and player.valid and player.gui) then
		return
	end
	local h = vehicle and storage.cncharvesters and storage.cncharvesters[vehicle.unit_number]
	local flag = testing_on()
	mark_sync(player)
	each_panel_frame(player, vehicle, function(frame)
		if not (frame and frame.valid) then
			return
		end
		local auto_cb = frame[AUTO_CB]
		local pause_cb = frame[PAUSE_CB]
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
	end)
end

local function ensure_relative(player, vehicle, position, want_notice)
	local rel = player.gui.relative
	if not rel then
		return
	end
	-- Drop the 2.0.77 type+names-array frame that hid the Ore Truck panel.
	destroy_named(rel, FRAME)
	-- One frame per prototype (singular `name`). Factorio shows only the
	-- frame whose name matches the opened car — type2 must not steal ore.
	for _, proto in ipairs(HARVESTER_NAME_LIST) do
		local fid = relative_frame_id(proto)
		local frame = rel[fid]
		if frame and frame.valid then
			local ok = relative_anchor_ok(frame, proto, position) and frame_mode_ok(frame, want_notice)
			if not ok then
				with_ignore(function()
					frame.destroy()
				end)
				frame = nil
			end
		end
		if not (frame and frame.valid) then
			with_ignore(function()
				frame = rel.add{
					type = "frame",
					name = fid,
					caption = {"cncharvester-gui.auto-caption"},
					anchor = AutoPanel.anchor_for(proto, position),
					direction = "vertical",
				}
				if want_notice then
					add_notice(frame)
				else
					add_checkboxes(frame)
				end
			end)
		end
	end
end

function AutoPanel.ensure(player, vehicle)
	if not (player and player.valid and player.gui) then
		return
	end
	if not (vehicle and vehicle.valid and HARVESTER_NAMES[vehicle.name]) then
		return
	end
	local flag = testing_on()
	-- Flag off: do not destroy the panel. A missing GUI looks like an
	-- Ore Truck-only regression when a zip overwrite reset the startup
	-- setting to default off.
	if flag and AutoPanel.track_vehicle then
		AutoPanel.track_vehicle(vehicle)
	end
	mark_sync(player)
	local want_notice = not flag
	local position = AutoPanel.panel_position(player)
	-- One relative left strip on the car GUI. Kill leftover top/screen
	-- copies from earlier 2.2.0 zips (Deck used to spawn both).
	AutoPanel.hide_transient(player)
	if player.gui.relative then
		ensure_relative(player, vehicle, position, want_notice)
	end
	if flag then
		AutoPanel.sync(player, vehicle)
	else
		toast_testing_off(player, vehicle)
	end
end

-- Cheap: track + create if missing. Must not sync every tick or the
-- click-ignore grace never expires and checkboxes cannot write auto_enabled.
function AutoPanel.on_player_tick(player)
	if not (player and player.valid) then
		return
	end
	local vehicle = opened_harvester(player)
	AutoPanel.hide_transient(player)
	if not vehicle then
		return
	end
	local flag = testing_on()
	if flag and AutoPanel.track_vehicle then
		AutoPanel.track_vehicle(vehicle)
	end
	local want_notice = not flag
	local position = AutoPanel.panel_position(player)
	local rel = player.gui and player.gui.relative
	local frame = rel and rel[relative_frame_id(vehicle.name)]
	local ok = frame
		and frame.valid
		and relative_anchor_ok(frame, vehicle.name, position)
		and frame_mode_ok(frame, want_notice)
	if not ok then
		AutoPanel.ensure(player, vehicle)
	end
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
