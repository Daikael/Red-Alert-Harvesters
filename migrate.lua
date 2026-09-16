-- Versioned one-shot recovery for tester maps that still carry AI/pad
-- ghosts from earlier 2.2.0 zips (wrong fuel index, 8 MJ pad exit,
-- orphan reserves, stuck FindingRefuel / path requests).
--
-- Must not run in on_load (Factorio CRC-checks storage). Call from
-- on_configuration_changed and the first tick after on_load.
-- Overwriting the same 2.2.0 zip does not bump info.json version, so
-- storage.rah_migration.rev is the real trigger. Bump REV when this
-- recipe changes. New games stamp the rev in on_init and skip the print.

RahMigrate = RahMigrate or {}

RahMigrate.PACK = "2.2.0"
RahMigrate.REV = 1

-- Keep in sync with harvester.lua `States`.
RahMigrate.STATE = {
	FindingOre = 1,
	FindingRefinery = 3,
	ApproachedRefinery = 4,
	DroppingOre = 5,
	MovingToLocation = 6,
	FindingRefuelRefinery = 7,
	ApproachedForRefuel = 8,
	Refueling = 9,
}

function RahMigrate.needs_run(st)
	if not st then
		return false
	end
	local rec = st.rah_migration
	if not rec then
		return true
	end
	return (rec.rev or 0) < RahMigrate.REV
end

local function entity_ok(ent)
	if not ent then
		return false
	end
	if ent.valid == false then
		return false
	end
	return true
end

local function auto_on(h)
	return h and h.auto_enabled ~= false
end

-- Transient drive / pad / refuel fields only. Never writes auto_enabled,
-- pause_on_enter, cargo, or vehicle position.
function RahMigrate.clean_harvester(h, opts)
	if not h then
		return h
	end
	opts = opts or {}
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
	local st = h.state
	local S = RahMigrate.STATE
	local padish = st == S.FindingRefinery
		or st == S.ApproachedRefinery
		or st == S.DroppingOre
		or st == S.MovingToLocation
		or st == S.FindingRefuelRefinery
		or st == S.ApproachedForRefuel
		or st == S.Refueling
	if opts.tank_empty and auto_on(h) then
		-- Old 8 MJ / is_full() exit left trucks in FindingOre with an empty
		-- tank while solar/grid still sat above the trip threshold, so they
		-- never went back for chest coal. Force one pad visit.
		if h.filled then
			h.state = S.FindingRefinery
		else
			h.state = S.FindingRefuelRefinery
		end
	elseif padish then
		if not auto_on(h) then
			h.state = S.FindingOre
		elseif h.filled then
			h.state = S.FindingRefinery
		elseif st == S.FindingRefuelRefinery
		or st == S.ApproachedForRefuel
		or st == S.Refueling then
			h.state = S.FindingRefuelRefinery
		else
			h.state = S.FindingOre
		end
	end
	return h
end

function RahMigrate.clean_refinery(r)
	if not r then
		return r
	end
	r.reserved = false
	r.reserved_by = nil
	return r
end

function RahMigrate.drop_dead_harvesters(st)
	local src = st and st.cncharvesters
	if not src then
		return 0
	end
	local keep = {}
	local dropped = 0
	for id, h in pairs(src) do
		if h and entity_ok(h.vehicle) then
			local nid = h.vehicle.unit_number or id
			keep[nid] = h
		else
			dropped = dropped + 1
		end
	end
	st.cncharvesters = keep
	return dropped
end

function RahMigrate.drop_dead_refineries(st)
	local src = st and st.refineries
	if not src then
		return 0
	end
	local keep = {}
	local dropped = 0
	for id, r in pairs(src) do
		if r and entity_ok(r.entity) then
			local nid = r.entity.unit_number or id
			keep[nid] = r
		else
			dropped = dropped + 1
		end
	end
	st.refineries = keep
	return dropped
end

function RahMigrate.stamp(st, pack)
	st.rah_migration = {
		rev = RahMigrate.REV,
		pack = pack or RahMigrate.PACK,
	}
end

-- Pure table pass. `opts.tank_empty` is an optional id→bool map.
function RahMigrate.clean_storage(st, opts)
	if not RahMigrate.needs_run(st) then
		return false
	end
	opts = opts or {}
	RahMigrate.drop_dead_harvesters(st)
	RahMigrate.drop_dead_refineries(st)
	local tank_empty = opts.tank_empty or {}
	for id, h in pairs(st.cncharvesters or {}) do
		RahMigrate.clean_harvester(h, {tank_empty = tank_empty[id] and true or false})
	end
	for _, r in pairs(st.refineries or {}) do
		RahMigrate.clean_refinery(r)
	end
	RahMigrate.stamp(st, opts.pack)
	return true
end

local function pack_version()
	if script and script.active_mods then
		return script.active_mods["Red-Alert-Harvester"] or RahMigrate.PACK
	end
	return RahMigrate.PACK
end

-- Live runtime. Cancels in-flight path ids, re-validates burner tanks,
-- then clean_storage. Prints once when an old save is recovered.
function RahMigrate.apply()
	if not storage or not RahMigrate.needs_run(storage) then
		return false
	end
	if AutoDrive and AutoDrive.take_request then
		for _, h in pairs(storage.cncharvesters or {}) do
			if h.path_id then
				AutoDrive.take_request(h.path_id)
			end
		end
	end
	if AutoDrive and AutoDrive.forget_blocker_lists then
		AutoDrive.forget_blocker_lists()
	end
	local tank_empty = {}
	for id, h in pairs(storage.cncharvesters or {}) do
		local v = h.vehicle
		if entity_ok(v) then
			if HybridDrive then
				if HybridDrive.fuel_inventory then
					HybridDrive.fuel_inventory(v)
				end
				if HybridDrive.prepare_vehicle then
					HybridDrive.prepare_vehicle(v)
				end
				if HybridDrive.strip_banned_fuel then
					HybridDrive.strip_banned_fuel(v)
				end
				if HybridDrive.tank_convertible_joules then
					tank_empty[id] = HybridDrive.tank_convertible_joules(v) < 1
				end
			end
		end
	end
	local ran = RahMigrate.clean_storage(storage, {
		tank_empty = tank_empty,
		pack = pack_version(),
	})
	if ran and game and game.print then
		game.print({"cncharvester.save-migrated"})
	end
	return ran
end
