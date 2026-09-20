-- Stuck-state watchdog for tracked auto harvesters.
-- If a truck expects progress (mine / dump / refuel / drive) and nothing
-- changes for too long, RebootAI clears transients and re-picks a goal
-- from inventory + fuel. Tick-throttled (not every truck every tick).
--
-- Must not StartDrive / request_path from AfterLoad (pad-storm CTD).
-- Must not rewrite auto_enabled or pause_on_enter.
-- Pathfinder try_again_later / in-flight path_id / active path / peer yield /
-- busy_until / load grace / pad queue / idle FindingOre|FindingRefuel freeze
-- the timer. A huge leftover busy_until is treated as stuck, not immunity.
-- queued_for_pad is a refinery unit_number (id) on the harvester record.
-- Movement progress is measured from the last-progress snap (not per sample),
-- so a crawl below MOVE_TILES per heartbeat still counts.
--
-- UPS: cheap skip classes (queued / path / search / busy) run before any
-- inventory or find. Position-only snaps first; trunk/tank counts only when
-- a truck is at timeout. Full evals are staggered and capped per tick.
-- Hop search is attempt 2+ only, tile precision, range capped at 16.

AiWatch = AiWatch or {}

-- Compile-gate for long reboot reason strings + log(). Off in tester zips.
AiWatch.DEBUG_REASON = false

-- Once per this many ticks, staggered by unit_number. 90 ≈ 1.5 s @ 60 UPS.
AiWatch.CHECK_INTERVAL = 90
-- Hard cap: full (position / timeout) evals per game tick across all trucks.
AiWatch.MAX_EVALS_PER_TICK = 3
-- After a reboot, do not reboot again until this elapses (~60 s).
AiWatch.COOLDOWN_TICKS = 3600
-- One game.print across all trucks in this window (~5 s).
AiWatch.TOAST_COOLDOWN = 300
AiWatch.MOVE_TILES = 0.5
-- STUCK_RETRY is 300. Anything farther out is a ghost forever-busy.
AiWatch.BUSY_MAX_TICKS = 720
AiWatch.DEFAULT_TIMEOUT = 3600
-- Match AutoDrive.PAD_RECHECK_TICKS. Waiters idle this long between scans.
AiWatch.PAD_RECHECK_TICKS = 30
-- Emergency hop on true reboot streaks (attempt 2+). Physical path stays default.
-- Cap 16 / precision 1: a 64-tile 0.5-precision search is a frame spike.
AiWatch.HOP_RANGE_BASE = 8
AiWatch.HOP_RANGE_CAP = 16
AiWatch.HOP_PRECISION = 1
AiWatch.HOP_COOLDOWN = 3600

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

-- Per-tick budget for full snapshots. Cheap waits do not consume it.
-- WatchAI passes ctx.budget; Lua tests call tick() without it.
function AiWatch.begin_tick(now)
	now = now or 0
	if AiWatch._budget_tick ~= now then
		AiWatch._budget_tick = now
		AiWatch._budget_left = AiWatch.MAX_EVALS_PER_TICK
	end
end

function AiWatch.claim_eval(now)
	AiWatch.begin_tick(now)
	if (AiWatch._budget_left or 0) <= 0 then
		return false
	end
	AiWatch._budget_left = AiWatch._budget_left - 1
	return true
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
	-- Inventory get_item_count is a Factorio API hit. Default is position-only
	-- plus cheap lua fields; counts() only when opts.counts (timeout confirm).
	if opts.counts and h and (trunk == nil or tank == nil) then
		local tr, ta = AiWatch.counts(h)
		if trunk == nil then
			trunk = tr
		end
		if tank == nil then
			tank = ta
		end
	end
	if trunk == nil then
		trunk = (h and h.watch_snap and h.watch_snap.trunk) or 0
	end
	if tank == nil then
		tank = (h and h.watch_snap and h.watch_snap.tank) or 0
	end
	return {
		state = h and h.state,
		x = pos and pos.x or 0,
		y = pos and pos.y or 0,
		trunk = trunk or 0,
		tank = tank or 0,
		path_id = h and h.path_id,
		has_path = h and h.path ~= nil,
		path_index = h and (h.path_index or 0) or 0,
		reserved = h and h.reservedRefinery and true or false,
		scoops = h and (h.scoopsMined or 0) or 0,
		queued = h and h.queued_for_pad or nil,
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
	if (prev.has_path and true or false) ~= (snap.has_path and true or false) then
		return true
	end
	if (prev.path_index or 0) ~= (snap.path_index or 0) then
		return true
	end
	if prev.reserved ~= snap.reserved then
		return true
	end
	if prev.queued ~= snap.queued then
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

function AiWatch.note_progress(h, now, snap, reset_streak)
	if not h then
		return
	end
	h.last_progress_tick = now
	if snap then
		h.watch_snap = snap
	end
	-- Only a real delta (not the first snap / post-reboot seed) clears the streak.
	if reset_streak then
		h.reboot_streak = 0
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
	local truck_id = h.vehicle and h.vehicle.unit_number
	if storage and truck_id then
		AiWatch.clear_waiter(storage, truck_id)
	end
	h.queued_for_pad = nil
	return h
end

-- Numbers only. Never a LuaEntity / record (those are not storage-safe keys).
function AiWatch.as_id(v)
	if type(v) == "number" then
		return v
	end
	return nil
end

function AiWatch.ensure_pad_index(st)
	if not st then
		return nil
	end
	st.rah_pads = st.rah_pads or {}
	return st.rah_pads
end

function AiWatch.pad_rec(st, pad_id)
	pad_id = AiWatch.as_id(pad_id)
	local pads = AiWatch.ensure_pad_index(st)
	if not (pads and pad_id) then
		return nil
	end
	local rec = pads[pad_id]
	if not rec then
		rec = {waiters = {}, reserved_by = nil, free_tick = 0}
		pads[pad_id] = rec
	end
	rec.waiters = rec.waiters or {}
	return rec
end

function AiWatch.enqueue_waiter(st, pad_id, truck_id)
	pad_id = AiWatch.as_id(pad_id)
	truck_id = AiWatch.as_id(truck_id)
	local rec = AiWatch.pad_rec(st, pad_id)
	if not (rec and truck_id) then
		return nil
	end
	rec.waiters[truck_id] = true
	return rec
end

function AiWatch.dequeue_waiter(st, pad_id, truck_id)
	pad_id = AiWatch.as_id(pad_id)
	truck_id = AiWatch.as_id(truck_id)
	local rec = st and st.rah_pads and pad_id and st.rah_pads[pad_id]
	if rec and rec.waiters and truck_id then
		rec.waiters[truck_id] = nil
	end
	return rec
end

function AiWatch.clear_waiter(st, truck_id)
	truck_id = AiWatch.as_id(truck_id)
	if not (st and st.rah_pads and truck_id) then
		return
	end
	for _, rec in pairs(st.rah_pads) do
		if rec.waiters then
			rec.waiters[truck_id] = nil
		end
		if rec.reserved_by == truck_id then
			rec.reserved_by = nil
		end
	end
end

function AiWatch.note_reserved(st, pad_id, truck_id)
	local rec = AiWatch.pad_rec(st, pad_id)
	if not rec then
		return nil
	end
	rec.reserved_by = AiWatch.as_id(truck_id)
	if rec.reserved_by and rec.waiters then
		rec.waiters[rec.reserved_by] = nil
	end
	return rec
end

function AiWatch.note_free(st, pad_id, now)
	local rec = AiWatch.pad_rec(st, pad_id)
	if not rec then
		return nil
	end
	rec.reserved_by = nil
	rec.free_tick = now or 0
	return rec
end

-- Lowest truck unit_number still queued on this pad. IDs only.
function AiWatch.next_claimant(st, pad_id)
	pad_id = AiWatch.as_id(pad_id)
	local rec = st and st.rah_pads and pad_id and st.rah_pads[pad_id]
	if not (rec and rec.waiters) then
		return nil
	end
	local best
	for id, on in pairs(rec.waiters) do
		if on and type(id) == "number" and (not best or id < best) then
			best = id
		end
	end
	return best
end

-- Only the elected waiter may StartDrive when the pad frees.
function AiWatch.may_start_drive_for_pad(st, pad_id, truck_id, pad_is_free)
	if not pad_is_free then
		return false
	end
	truck_id = AiWatch.as_id(truck_id)
	pad_id = AiWatch.as_id(pad_id)
	if not truck_id then
		return false
	end
	local next_id = AiWatch.next_claimant(st, pad_id)
	if next_id == nil then
		return true
	end
	return next_id == truck_id
end

-- Holder cleared the pad. Mark free_tick and wake only the next claimant
-- (busy_until = now). Other waiters keep their recheck tick.
function AiWatch.wake_next_claimant(st, pad_id, now)
	AiWatch.note_free(st, pad_id, now)
	local id = AiWatch.next_claimant(st, pad_id)
	if not id then
		return nil
	end
	local h = st and st.cncharvesters and st.cncharvesters[id]
	if h then
		h.busy_until = now or 0
	end
	return id
end

function AiWatch.queued_resume(st, h, pad_is_free, pad_ok)
	if not pad_ok then
		return "gone"
	end
	if not pad_is_free then
		return "wait"
	end
	local me = h and h.vehicle and h.vehicle.unit_number
	if AiWatch.may_start_drive_for_pad(st, h and h.queued_for_pad, me, true) then
		return "claim"
	end
	return "wait"
end

function AiWatch.rebuild_pad_index(st)
	if not st then
		return nil
	end
	st.rah_pads = {}
	for id, h in pairs(st.cncharvesters or {}) do
		local truck_id = AiWatch.as_id(h.vehicle and h.vehicle.unit_number) or AiWatch.as_id(id)
		if truck_id then
			local q = AiWatch.as_id(h.queued_for_pad)
			if q then
				AiWatch.enqueue_waiter(st, q, truck_id)
			end
			local pad = AiWatch.as_id(h.targetRefinery)
			if h.reservedRefinery and pad then
				AiWatch.note_reserved(st, pad, truck_id)
			end
		end
	end
	return st.rah_pads
end

-- Pad id is a unit_number. busy_until is a tick. No callbacks.
function AiWatch.begin_pad_queue(h, now, pad_id)
	if not h then
		return h
	end
	h.queued_for_pad = AiWatch.as_id(pad_id)
	local wait = AiWatch.PAD_RECHECK_TICKS
	if AutoDrive and AutoDrive.PAD_RECHECK_TICKS then
		wait = AutoDrive.PAD_RECHECK_TICKS
	end
	h.busy_until = (now or 0) + wait
	h.going_home = false
	return h
end

function AiWatch.end_pad_queue(h)
	if h then
		h.queued_for_pad = nil
	end
	return h
end

-- In-flight request_path or a waypoint list AutoDrive is still following.
function AiWatch.path_busy(h)
	if not h then
		return false
	end
	if h.path_id then
		return true
	end
	if h.path then
		return true
	end
	return false
end

-- Reverse peel / in-progress wiggle. Same class as pathfinder-busy.
function AiWatch.peer_wait(h, now)
	if not h then
		return false
	end
	return (h.reverse_until or 0) > (now or 0)
end

-- Idle search: no drive yet. FindingOre waits on the chunk index;
-- FindingRefuelRefinery waits for a fueled pad. Reboot cannot create ore/fuel.
function AiWatch.search_wait(h)
	if not h then
		return false
	end
	if AiWatch.path_busy(h) then
		return false
	end
	local st = h.state
	return st == AiWatch.STATE.FindingOre or st == AiWatch.STATE.FindingRefuelRefinery
end

-- Quiet wait: reserved-but-not-full pad, or short pad-recheck busy.
-- Same class as pathfinder try_again_later — not a RebootAI reason.
function AiWatch.pad_wait(h, now)
	if not h then
		return false
	end
	if h.queued_for_pad then
		return true
	end
	if (h.busy_until or 0) > (now or 0) and not AiWatch.forever_busy(h, now) then
		return true
	end
	return false
end

-- Legitimate wait/progress that must not trip RebootAI. forever_busy still wins.
function AiWatch.legit_wait(h, now, ctx)
	if not h then
		return false
	end
	ctx = ctx or {}
	if ctx.pause_yield then
		return true
	end
	if h.queued_for_pad then
		return true
	end
	if AiWatch.peer_wait(h, now) then
		return true
	end
	if AiWatch.path_busy(h) then
		return true
	end
	if (h.wait_ticks or 0) > 0 then
		return true
	end
	if AiWatch.search_wait(h) then
		return true
	end
	if AiWatch.pad_wait(h, now) then
		return true
	end
	if (h.busy_until or 0) > (now or 0) then
		return true
	end
	if ctx.in_load_grace then
		return true
	end
	return false
end

-- No free pad, but a not-full (often reserved) pad exists → idle, no StartDrive.
function AiWatch.waiter_should_idle(opts)
	opts = opts or {}
	if opts.holds_pad or opts.free_pad then
		return false
	end
	return opts.waitable_pad and true or false
end

-- After the home repath budget. Quiet queue is not yellow/red stuck.
function AiWatch.should_alert_stuck_home(opts)
	opts = opts or {}
	if opts.queued_for_pad then
		return false
	end
	if opts.holds_pad then
		return true
	end
	if opts.no_pads or opts.all_full then
		return true
	end
	if opts.waitable_pad then
		return false
	end
	return true
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
	if AiWatch.legit_wait(h, now, ctx) and not forever then
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
	-- Cheap skip classes: lua fields only. No inventory, no find, no path walk.
	local forever = AiWatch.forever_busy(h, now)
	if AiWatch.legit_wait(h, now, ctx) and not forever then
		h.last_progress_tick = now
		return "wait"
	end
	-- Full eval (position snap, maybe inventory at timeout). WatchAI budgets this.
	if ctx.budget and not AiWatch.claim_eval(now) then
		return "skip"
	end
	local snap = AiWatch.snapshot(h, {
		pos = ctx.pos,
		trunk = ctx.trunk,
		tank = ctx.tank,
		counts = false,
	})
	if not h.watch_snap then
		AiWatch.note_progress(h, now, snap)
	elseif AiWatch.progressed(h.watch_snap, snap) then
		AiWatch.note_progress(h, now, snap, true)
	end
	-- Trunk/tank only when this sample would otherwise trip the timeout.
	-- Dumping / refueling sit still; scoops/path/position already counted above.
	if h.watch_snap and not AiWatch.progressed(h.watch_snap, snap) then
		local last = h.last_progress_tick
		if last ~= nil and (now - last) >= AiWatch.timeout_for(h.state) then
			local need_counts = (ctx.trunk == nil and ctx.tank == nil)
			snap = AiWatch.snapshot(h, {
				pos = ctx.pos,
				trunk = ctx.trunk,
				tank = ctx.tank,
				counts = need_counts,
			})
			if AiWatch.progressed(h.watch_snap, snap) then
				AiWatch.note_progress(h, now, snap, true)
			end
		end
	end
	if AiWatch.should_reboot(h, now, ctx) then
		return "reboot"
	end
	return "ok"
end

function AiWatch.reason_fields(h, now, extra)
	extra = extra or {}
	local last = h and h.last_progress_tick
	local age
	if last ~= nil then
		age = (now or 0) - last
	end
	return {
		state = h and h.state,
		goal = extra.goal,
		last_progress = last,
		age = age,
		queued_for_pad = h and h.queued_for_pad,
		busy_until = h and (h.busy_until or 0) or 0,
		path_id = h and h.path_id,
		has_path = h and h.path ~= nil,
		path_busy = AiWatch.path_busy(h),
		forever_busy = AiWatch.forever_busy(h, now),
		streak = h and (h.reboot_streak or 0) or 0,
		hop_until = h and (h.reboot_hop_until or 0) or 0,
	}
end

function AiWatch.format_reason(fields)
	fields = fields or {}
	return "state=" .. tostring(fields.state)
		.. " goal=" .. tostring(fields.goal)
		.. " last=" .. tostring(fields.last_progress)
		.. " age=" .. tostring(fields.age)
		.. " queued=" .. tostring(fields.queued_for_pad)
		.. " busy=" .. tostring(fields.busy_until)
		.. " path_id=" .. tostring(fields.path_id)
		.. " path_busy=" .. tostring(fields.path_busy)
		.. " streak=" .. tostring(fields.streak)
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
	h.reboot_streak = (h.reboot_streak or 0) + 1
	return true
end

function AiWatch.hop_range(streak)
	streak = streak or 0
	if streak < 2 then
		return 0
	end
	local range = AiWatch.HOP_RANGE_BASE
	local grow = streak - 2
	while grow > 0 and range < AiWatch.HOP_RANGE_CAP do
		range = range * 2
		grow = grow - 1
	end
	if range > AiWatch.HOP_RANGE_CAP then
		range = AiWatch.HOP_RANGE_CAP
	end
	return range
end

function AiWatch.hop_center(h)
	if h and h.targetPosition and h.targetPosition.x ~= nil then
		return h.targetPosition
	end
	local v = h and h.vehicle
	if v and v.position then
		return v.position
	end
	return h and h.position
end

-- Attempt 2+ only. Never while queued / player driver / pause-on-enter yield.
function AiWatch.may_teleport(h, now, opts)
	if not h then
		return false
	end
	opts = opts or {}
	if opts.queued_for_pad or h.queued_for_pad then
		return false
	end
	if opts.pause_yield then
		return false
	end
	if opts.player_driver then
		return false
	end
	if (h.reboot_hop_until or 0) > (now or 0) then
		return false
	end
	return AiWatch.hop_range(h.reboot_streak) > 0
end

-- Safe hop: find_non_colliding_position then teleport. Never blind into cliffs/water.
-- Clears pathfinder leftovers after a hop. Physical driving stays the default path.
function AiWatch.try_hop(h, now, opts)
	if not AiWatch.may_teleport(h, now, opts) then
		return false
	end
	local v = h.vehicle
	if not (v and v.valid ~= false and v.name and v.teleport) then
		return false
	end
	local surface = v.surface
	if not (surface and surface.find_non_colliding_position) then
		return false
	end
	local center = AiWatch.hop_center(h)
	if not center then
		return false
	end
	local range = AiWatch.hop_range(h.reboot_streak)
	-- Stamp cooldown before the search returns so a miss cannot re-scan
	-- on the next reboot (find_non_colliding_position is the spike).
	h.reboot_hop_until = (now or 0) + AiWatch.HOP_COOLDOWN
	local pos = surface.find_non_colliding_position(
		v.name,
		center,
		range,
		AiWatch.HOP_PRECISION,
		true
	)
	if not pos then
		return false
	end
	local ok = v.teleport(pos)
	if ok == false then
		return false
	end
	h.path_id = nil
	h.path = nil
	h.path_index = 1
	h.path_blockers = nil
	h.targetPosition = nil
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

function AiWatch.toast(h, reason, fields)
	local now = (game and game.tick) or 0
	local id = "?"
	if h and h.vehicle and h.vehicle.unit_number then
		id = tostring(h.vehicle.unit_number)
	end
	local detail
	if AiWatch.DEBUG_REASON or fields then
		fields = fields or AiWatch.reason_fields(h, now, {goal = h and h.state})
		detail = AiWatch.format_reason(fields)
	else
		detail = "s=" .. tostring(h and (h.reboot_streak or 0) or 0)
	end
	local line = "Red-Alert-Harvester: RebootAI " .. id .. " " .. tostring(reason or "watchdog")
	if detail ~= "" then
		line = line .. " " .. detail
	end
	-- log() is always present in Factorio and writes the script log. Gate it.
	if AiWatch.DEBUG_REASON and log then
		log(line)
	end
	if not (game and game.print) then
		return line
	end
	storage = storage or {}
	if (storage.rah_watch_toast_tick or 0) + AiWatch.TOAST_COOLDOWN > now then
		return line
	end
	storage.rah_watch_toast_tick = now
	game.print({"cncharvester.ai-rebooted", id, detail})
	return line
end
