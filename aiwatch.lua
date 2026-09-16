-- Stuck-state watchdog for tracked auto harvesters.
-- If a truck expects progress (mine / dump / refuel / drive) and nothing
-- changes for too long, RebootAI clears transients and re-picks a goal
-- from inventory + fuel. Tick-throttled (not every truck every tick).
--
-- Must not StartDrive / request_path from AfterLoad (pad-storm CTD).
-- Must not rewrite auto_enabled or pause_on_enter.
-- Pathfinder try_again_later / busy_until / load grace freeze the timer.
-- A huge leftover busy_until is treated as stuck, not immunity.

AiWatch = AiWatch or {}

-- Once per this many ticks, staggered by unit_number.
AiWatch.CHECK_INTERVAL = 30
-- After a reboot, do not reboot again until this elapses (~60 s).
AiWatch.COOLDOWN_TICKS = 3600
-- One game.print across all trucks in this window (~5 s).
AiWatch.TOAST_COOLDOWN = 300
AiWatch.MOVE_TILES = 0.5
-- STUCK_RETRY is 300. Anything farther out is a ghost forever-busy.
AiWatch.BUSY_MAX_TICKS = 720
AiWatch.DEFAULT_TIMEOUT = 3600

-- Keep in sync with harvester.lua `States`.
AiWatch.STATE = {
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

-- Timeouts @ 60 UPS. Long paths / empty index / busy pathfinder get more
-- slack. Pad approach / mine / dump / refuel should move sooner.
AiWatch.TIMEOUT = {
	[0] = 1800, -- Animating ~30 s
	[1] = 5400, -- FindingOre ~90 s (empty index is legitimate)
	[2] = 2700, -- MiningOre ~45 s
	[3] = 3600, -- FindingRefinery ~60 s
	[4] = 2700, -- ApproachedRefinery ~45 s
	[5] = 1800, -- DroppingOre ~30 s
	[6] = 5400, -- MovingToLocation ~90 s
	[7] = 3600, -- FindingRefuelRefinery ~60 s
	[8] = 2700, -- ApproachedForRefuel ~45 s
	[9] = 2700, -- Refueling ~45 s
}

function AiWatch.timeout_for(state)
	return AiWatch.TIMEOUT[state] or AiWatch.DEFAULT_TIMEOUT
end

function AiWatch.due(h, tick)
	if not (h and tick) then
		return false
	end
	local id = 0
	if h.vehicle and h.vehicle.unit_number then
		id = h.vehicle.unit_number
	elseif h.unit_number then
		id = h.unit_number
	end
	local interval = AiWatch.CHECK_INTERVAL
	return (tick % interval) == (id % interval)
end

function AiWatch.auto_on(h)
	return h and h.auto_enabled ~= false
end

-- Full trunk / filled flag beats an empty tank (dump, then refuel).
-- Auto off → nil (caller must not change state).
function AiWatch.pick_goal(opts)
	opts = opts or {}
	if opts.auto_on == false then
		return nil
	end
	if opts.filled or opts.trunk_full then
		return AiWatch.STATE.FindingRefinery
	end
	if opts.tank_empty then
		return AiWatch.STATE.FindingRefuelRefinery
	end
	return AiWatch.STATE.FindingOre
end

function AiWatch.counts(h)
	local trunk, tank = 0, 0
	local v = h and h.vehicle
	if not (v and v.valid ~= false) then
		return trunk, tank
	end
	if v.get_inventory and defines and defines.inventory then
		local inv = v.get_inventory(defines.inventory.car_trunk)
		if inv and inv.get_item_count then
			trunk = inv.get_item_count() or 0
		end
	end
	if HybridDrive and HybridDrive.fuel_inventory then
		local fuel = HybridDrive.fuel_inventory(v)
		if fuel and fuel.get_item_count then
			tank = fuel.get_item_count() or 0
		end
	end
	return trunk, tank
end

function AiWatch.snapshot(h, opts)
	opts = opts or {}
	local pos = opts.pos
	if not pos and h then
		if h.vehicle and h.vehicle.position then
			pos = h.vehicle.position
		else
			pos = h.position
		end
	end
	local trunk = opts.trunk
	local tank = opts.tank
	if h and (trunk == nil or tank == nil) then
		local tr, ta = AiWatch.counts(h)
		if trunk == nil then
			trunk = tr
		end
		if tank == nil then
			tank = ta
		end
	end
	return {
		state = h and h.state,
		x = pos and pos.x or 0,
		y = pos and pos.y or 0,
		trunk = trunk or 0,
		tank = tank or 0,
		path_id = h and h.path_id,
		reserved = h and h.reservedRefinery and true or false,
		scoops = h and (h.scoopsMined or 0) or 0,
	}
end

function AiWatch.progressed(prev, snap)
	if not prev then
		return true
	end
	if not snap then
		return false
	end
	if prev.state ~= snap.state then
		return true
	end
	if prev.path_id ~= snap.path_id then
		return true
	end
	if prev.reserved ~= snap.reserved then
		return true
	end
	if (snap.scoops or 0) ~= (prev.scoops or 0) then
		return true
	end
	if (snap.trunk or 0) ~= (prev.trunk or 0) then
		return true
	end
	if (snap.tank or 0) ~= (prev.tank or 0) then
		return true
	end
	local dx = (snap.x or 0) - (prev.x or 0)
	local dy = (snap.y or 0) - (prev.y or 0)
	local need = AiWatch.MOVE_TILES
	return (dx * dx + dy * dy) >= (need * need)
end

function AiWatch.forever_busy(h, now)
	local until_t = h and h.busy_until or 0
	if until_t <= (now or 0) then
		return false
	end
	return (until_t - now) > AiWatch.BUSY_MAX_TICKS
end

function AiWatch.note_progress(h, now, snap)
	if not h then
		return
	end
	h.last_progress_tick = now
	if snap then
		h.watch_snap = snap
	end
end

-- Transient drive / pad / pathfinder leftovers. Never writes auto_enabled,
-- pause_on_enter, cargo, or vehicle position.
function AiWatch.clear_transients(h)
	if not h then
		return h
	end
	h.path_id = nil
	h.path = nil
	h.path_index = 1
	h.path_blockers = nil
	h.going_home = false
	h.home_early = false
	h.arrival_state = false
	h.busy_until = 0
	h.repath_n = 0
	h.alt_n = 0
	h.home_repath_n = 0
	h.dock_try = 0
	h.refueling = false
	h.refuel_fail_n = 0
	h.reservedRefinery = false
	h.targetRefinery = false
	return h
end

function AiWatch.should_reboot(h, now, ctx)
	if not h then
		return false
	end
	ctx = ctx or {}
	if ctx.auto_on == false or h.auto_enabled == false then
		return false
	end
	if ctx.pause_yield then
		return false
	end
	if (h.reboot_until or 0) > now then
		return false
	end
	local forever = AiWatch.forever_busy(h, now)
	if ctx.in_load_grace and not forever then
		return false
	end
	if (h.busy_until or 0) > now and not forever then
		return false
	end
	local last = h.last_progress_tick
	if last == nil then
		return false
	end
	return (now - last) >= AiWatch.timeout_for(h.state)
end

-- Staggered heartbeat. Returns "skip" | "wait" | "ok" | "reboot".
function AiWatch.tick(h, now, ctx)
	if not h then
		return "skip"
	end
	if h.auto_enabled == false then
		return "skip"
	end
	if not AiWatch.due(h, now) then
		return "skip"
	end
	ctx = ctx or {}
	if ctx.pause_yield then
		return "skip"
	end
	local snap = AiWatch.snapshot(h, ctx)
	if AiWatch.progressed(h.watch_snap, snap) then
		AiWatch.note_progress(h, now, snap)
	else
		h.watch_snap = snap
	end
	local forever = AiWatch.forever_busy(h, now)
	if (ctx.in_load_grace or ((h.busy_until or 0) > now)) and not forever then
		h.last_progress_tick = now
		return "wait"
	end
	if AiWatch.should_reboot(h, now, ctx) then
		return "reboot"
	end
	return "ok"
end

function AiWatch.apply_reboot(h, now, opts)
	if not h then
		return false
	end
	opts = opts or {}
	if opts.auto_on == false or h.auto_enabled == false then
		return false
	end
	if (h.reboot_until or 0) > now then
		return false
	end
	AiWatch.clear_transients(h)
	local goal = AiWatch.pick_goal({
		auto_on = true,
		filled = opts.filled or h.filled,
		trunk_full = opts.trunk_full,
		tank_empty = opts.tank_empty,
	})
	if goal then
		h.state = goal
	end
	h.reboot_until = now + AiWatch.COOLDOWN_TICKS
	h.last_progress_tick = now
	h.watch_snap = nil
	return true
end

-- Load-tick sanity: re-pick state only. Caller must still set busy_until
-- grace and must not StartDrive / KickAuto / destroy blockers.
function AiWatch.prepare_after_load(h, now, opts)
	if not h then
		return false
	end
	opts = opts or {}
	h.last_progress_tick = now
	h.watch_snap = nil
	if h.auto_enabled == false then
		return false
	end
	local goal = AiWatch.pick_goal({
		auto_on = true,
		filled = opts.filled or h.filled,
		trunk_full = opts.trunk_full,
		tank_empty = opts.tank_empty,
	})
	if goal then
		h.state = goal
	end
	return true
end

function AiWatch.toast(h, reason)
	if not (game and game.print) then
		return
	end
	local now = game.tick or 0
	storage = storage or {}
	if (storage.rah_watch_toast_tick or 0) + AiWatch.TOAST_COOLDOWN > now then
		return
	end
	storage.rah_watch_toast_tick = now
	local id = "?"
	if h and h.vehicle and h.vehicle.unit_number then
		id = tostring(h.vehicle.unit_number)
	end
	game.print({"cncharvester.ai-rebooted", id})
	if log then
		log("Red-Alert-Harvester: RebootAI " .. id .. " " .. tostring(reason or "watchdog"))
	end
end
