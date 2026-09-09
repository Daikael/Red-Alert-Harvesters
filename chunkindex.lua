-- Milestone 1: global slow chunk index.
-- Event handlers only enqueue. Scan ticks classify one generated chunk.
-- Prefer low script cost over fast coverage (hours-long first pass is OK).
-- Do not generate chunks. Do not teleport or drive trucks.

ChunkIndex = ChunkIndex or {}

-- One find_entities_filtered (32x32) per scan tick. Never raise this for
-- normal play — throughput comes from SCAN_INTERVAL_TICKS, not a bigger bite.
ChunkIndex.BUDGET_PER_TICK = 1
-- 1 chunk / 10 ticks @ 60 UPS. 40k generated chunks ≈ 40000*10/60 ≈ 1.85 h.
ChunkIndex.SCAN_INTERVAL_TICKS = 10
-- Tib-neighbor border refresh. Minutes-scale; skipped while the queue is draining.
-- 36000 ticks = 10 min @ 60 UPS (idle uses the same interval).
ChunkIndex.BORDER_REQUEUE_TICKS = 36000
ChunkIndex.BORDER_REQUEUE_IDLE_TICKS = 36000
-- Harvester-chunk depletion refresh. 10800 ticks = 3 min @ 60 UPS.
ChunkIndex.HARVESTER_REQUEUE_TICKS = 10800
ChunkIndex.HARVESTER_REQUEUE_IDLE_TICKS = 10800

local NEIGHBOR_OFFSETS = {
	{-1, -1}, {-1, 0}, {-1, 1},
	{ 0, -1},          { 0, 1},
	{ 1, -1}, { 1, 0}, { 1, 1},
}

local PLANET_BOOL = {
	nauvis = "tiberium-on-nauvis",
	vulcanus = "tiberium-on-vulcanus",
	gleba = "tiberium-on-gleba",
	fulgora = "tiberium-on-fulgora",
	aquilo = "tiberium-on-aquilo",
}

--------------------------------------------------
-- Pure helpers (unit-tested without Factorio)
--------------------------------------------------

function ChunkIndex.chunk_key(surface_index, x, y)
	return tostring(surface_index) .. ":" .. tostring(x) .. ":" .. tostring(y)
end

-- Explicit nil checks. Do not use `x and y` for "present" — keep the
-- intent obvious. (Lua treats 0 as truthy; JS/Python do not.)
function ChunkIndex.coords_ok(surface_index, x, y)
	return surface_index ~= nil and x ~= nil and y ~= nil
end

function ChunkIndex.has_index_row(orechunk, si, x, y)
	if not ChunkIndex.coords_ok(si, x, y) then
		return false
	end
	local s = orechunk and orechunk[si]
	local row = s and s[x]
	return row ~= nil and row[y] ~= nil
end

function ChunkIndex.neighbor_offsets()
	return NEIGHBOR_OFFSETS
end

-- Refcount: each Tib source increments its 8 neighbors once. Deplete
-- decrements those same neighbors. A neighbor stays on the border-rescan
-- set until every bordering Tib source is gone (count hits 0).
function ChunkIndex.apply_tib_transition(border, holds, si, cx, cy, had_tib, has_tib)
	border[si] = border[si] or {}
	holds[si] = holds[si] or {}
	if has_tib and not had_tib then
		holds[si][cx] = holds[si][cx] or {}
		if holds[si][cx][cy] then
			return
		end
		holds[si][cx][cy] = true
		for _, off in ipairs(NEIGHBOR_OFFSETS) do
			local nx, ny = cx + off[1], cy + off[2]
			border[si][nx] = border[si][nx] or {}
			border[si][nx][ny] = (border[si][nx][ny] or 0) + 1
		end
	elseif had_tib and not has_tib then
		if not (holds[si][cx] and holds[si][cx][cy]) then
			return
		end
		holds[si][cx][cy] = nil
		for _, off in ipairs(NEIGHBOR_OFFSETS) do
			local nx, ny = cx + off[1], cy + off[2]
			local row = border[si][nx]
			if row then
				local n = (row[ny] or 0) - 1
				if n <= 0 then
					row[ny] = nil
				else
					row[ny] = n
				end
			end
		end
	end
end

function ChunkIndex.border_count(border, si, x, y)
	local s = border and border[si]
	local row = s and s[x]
	return (row and row[y]) or 0
end

-- Drop one nested [si][x][y] slot and prune empty parents (no ghost keys).
function ChunkIndex.nest_clear(root, si, x, y)
	if not root then
		return
	end
	local s = root[si]
	if not s then
		return
	end
	local row = s[x]
	if not row then
		return
	end
	row[y] = nil
	if next(row) == nil then
		s[x] = nil
	end
	if next(s) == nil then
		root[si] = nil
	end
end

-- Remove a deleted chunk from the FIFO + queued set. Tombstones are
-- skipped on pop so we do not scan or re-enqueue ghosts.
function ChunkIndex.drop_from_queue(queue_state, si, x, y)
	if not queue_state then
		return
	end
	local key = ChunkIndex.chunk_key(si, x, y)
	if queue_state.queued then
		queue_state.queued[key] = nil
	end
	local q = queue_state.queue
	if not q then
		return
	end
	local head = queue_state.head or 1
	for i = head, #q do
		local item = q[i]
		if item and item[1] == si and item[2] == x and item[3] == y then
			q[i] = false
		end
	end
end

-- Forget a chunk that was deleted / is about to be deleted.
-- If it was a Tib source, unwind neighbor refcounts (same as deplete).
-- If it was only a border neighbor, drop its border slot so it is not
-- requeued. Index rows and the scan queue are cleared either way.
function ChunkIndex.forget_chunk_state(orechunk, tibchunk, border, holds, queue_state, si, x, y)
	if not ChunkIndex.coords_ok(si, x, y) then
		return
	end
	border = border or {}
	holds = holds or {}
	local held = holds[si] and holds[si][x] and holds[si][x][y]
	local marked_tib = tibchunk and tibchunk[si] and tibchunk[si][x] and tibchunk[si][x][y] == true
	if held or marked_tib then
		ChunkIndex.apply_tib_transition(border, holds, si, x, y, true, false)
	end
	ChunkIndex.nest_clear(border, si, x, y)
	ChunkIndex.nest_clear(holds, si, x, y)
	if orechunk then
		ChunkIndex.nest_clear(orechunk, si, x, y)
	end
	if tibchunk then
		ChunkIndex.nest_clear(tibchunk, si, x, y)
	end
	ChunkIndex.drop_from_queue(queue_state, si, x, y)
end

-- James-Fire Factorio-Tiberium startup flags. Slurry tech is not a gate.
-- flags = { present, mode, extra = {nauvis=bool,...}, all_other = bool }
function ChunkIndex.tib_can_spawn_on(planet_name, flags)
	if not flags or not flags.present then
		return false
	end
	if not planet_name then
		return false
	end
	local mode = flags.mode
	local extra = flags.extra or {}
	if planet_name == "nauvis" then
		if mode == "nauvis" or mode == "pure-nauvis" then
			return true
		end
		return extra.nauvis == true
	end
	if planet_name == "tiber" then
		return mode == "tiber" or mode == "tiber-start" or extra.all_other == true
	end
	if planet_name == "vulcanus" then
		return extra.vulcanus == true or extra.all_other == true
	end
	if planet_name == "gleba" then
		return extra.gleba == true or extra.all_other == true
	end
	if planet_name == "fulgora" then
		return extra.fulgora == true or extra.all_other == true
	end
	if planet_name == "aquilo" then
		return extra.aquilo == true or extra.all_other == true
	end
	return extra.all_other == true
end

-- Skip = Tib cannot spawn AND player has not visited.
function ChunkIndex.surface_in_scope(visited, tib_eligible)
	return visited == true or tib_eligible == true
end

function ChunkIndex.resource_is_tiberium(category, name)
	if category and string.find(category, "tiberium", 1, true) then
		return true
	end
	if name and string.find(name, "tiberium", 1, true) then
		return true
	end
	return false
end

function ChunkIndex.resource_is_skip(category, name, amount, infinite)
	if category == "basic-fluid" or category == "lava-magma" then
		return true
	end
	if name and string.find(name, "tree") then
		return true
	end
	if (not infinite) and amount and amount <= 0 then
		return true
	end
	return false
end

--------------------------------------------------
-- Runtime (Factorio control stage)
--------------------------------------------------

local function startup_value(name)
	if not (settings and settings.startup and settings.startup[name]) then
		return nil
	end
	return settings.startup[name].value
end

function ChunkIndex.read_tib_flags()
	local present = script and script.active_mods and script.active_mods["Factorio-Tiberium"]
	if not present then
		return {present = false, mode = nil, extra = {}, all_other = false}
	end
	local extra = {}
	for planet, setting_name in pairs(PLANET_BOOL) do
		extra[planet] = startup_value(setting_name) == true
	end
	extra.all_other = startup_value("tiberium-on-all-other-planets") == true
	return {
		present = true,
		mode = startup_value("tiberium-on"),
		extra = extra,
		all_other = extra.all_other,
	}
end

function ChunkIndex.enabled()
	-- One gate: startup Automatic harvester testing. Needs a restart.
	-- Enables the index and the physical auto-drive AI (not teleport).
	return startup_value("Auto-cncharvester-testing") == true
end

function ChunkIndex.ensure_storage()
	storage.orechunk = storage.orechunk or {}
	storage.tibchunk = storage.tibchunk or {}
	storage.chunkindex = storage.chunkindex or {}
	local st = storage.chunkindex
	st.queue = st.queue or {}
	st.head = st.head or 1
	st.queued = st.queued or {}
	st.visited = st.visited or {}
	st.border = st.border or {}
	st.tib_holds = st.tib_holds or {}
	st.watch = st.watch or {}
	st.border_due = st.border_due or 0
	st.harvest_due = st.harvest_due or 0
	st.scan_due = st.scan_due or 0
	st.overlay_reconcile_due = st.overlay_reconcile_due or 0
	st.seeded = st.seeded or false
	if st.overlay == nil then
		st.overlay = false
	end
	st.overlay_ids = st.overlay_ids or {}
	st.overlay_due = st.overlay_due or 0
	st.overlay_dirty = st.overlay_dirty or {}
	st.overlay_full = st.overlay_full or false
	st.harvest_overlay_keys = st.harvest_overlay_keys or {}
	return st
end

function ChunkIndex.queue_len(st)
	if not st or not st.queue then
		return 0
	end
	local n = #st.queue - (st.head or 1) + 1
	if n < 0 then
		return 0
	end
	return n
end

function ChunkIndex.overlay_mark_dirty(si, x, y)
	if not ChunkIndex.coords_ok(si, x, y) then
		return
	end
	if not storage then
		return
	end
	local st = storage.chunkindex
	if not st then
		return
	end
	st.overlay_dirty = st.overlay_dirty or {}
	st.overlay_dirty[ChunkIndex.chunk_key(si, x, y)] = {si, x, y}
end

local function compact_queue(st)
	if st.head <= 64 then
		return
	end
	local q = st.queue
	local newq = {}
	for i = st.head, #q do
		newq[#newq + 1] = q[i]
	end
	st.queue = newq
	st.head = 1
end

function ChunkIndex.rebuild_queued_set(st)
	if not st then
		return 0
	end
	local queued = {}
	local n = 0
	local q = st.queue or {}
	local head = st.head or 1
	for i = head, #q do
		local item = q[i]
		if item and ChunkIndex.coords_ok(item[1], item[2], item[3]) then
			queued[ChunkIndex.chunk_key(item[1], item[2], item[3])] = true
			n = n + 1
		end
	end
	st.queued = queued
	return n
end

function ChunkIndex.enqueue(surface_index, x, y)
	if not ChunkIndex.coords_ok(surface_index, x, y) then
		return false
	end
	local st = ChunkIndex.ensure_storage()
	local key = ChunkIndex.chunk_key(surface_index, x, y)
	if st.queued[key] then
		return false
	end
	st.queued[key] = true
	st.queue[#st.queue + 1] = {surface_index, x, y}
	return true
end

function ChunkIndex.forget_chunk(surface_index, x, y)
	if not ChunkIndex.coords_ok(surface_index, x, y) then
		return
	end
	if not storage then
		return
	end
	ChunkIndex.ensure_storage()
	ChunkIndex.forget_chunk_state(
		storage.orechunk,
		storage.tibchunk,
		storage.chunkindex.border,
		storage.chunkindex.tib_holds,
		storage.chunkindex,
		surface_index,
		x,
		y
	)
	ChunkIndex.overlay_forget(surface_index, x, y)
end

-- on_pre_chunk_deleted / on_chunk_deleted: positions[] on one surface.
-- Run even if the scanner setting is off so leftover index rows die.
function ChunkIndex.on_chunks_deleted(event)
	if not event then
		return
	end
	local si = event.surface_index
	local positions = event.positions
	if si == nil or not positions then
		return
	end
	for _, pos in pairs(positions) do
		if pos and pos.x ~= nil and pos.y ~= nil then
			ChunkIndex.forget_chunk(si, pos.x, pos.y)
		end
	end
end

function ChunkIndex.watch_harvester(entity)
	if not (entity and entity.valid and entity.unit_number) then
		return
	end
	local st = ChunkIndex.ensure_storage()
	st.watch[entity.unit_number] = true
end

function ChunkIndex.unwatch_harvester(unit_number)
	if not unit_number then
		return
	end
	local st = storage.chunkindex
	if st and st.watch then
		st.watch[unit_number] = nil
	end
end

local function planet_name_of(surface)
	if not (surface and surface.valid) then
		return nil
	end
	local ok, planet = pcall(function()
		return surface.planet
	end)
	if ok and planet and planet.valid and planet.name then
		return planet.name
	end
	return surface.name
end

local function surface_is_platform(surface)
	if not (surface and surface.valid) then
		return false
	end
	local ok, platform = pcall(function()
		return surface.platform
	end)
	return ok and platform ~= nil
end

function ChunkIndex.surface_eligible(surface)
	if not (surface and surface.valid) then
		return false
	end
	if surface_is_platform(surface) then
		return false
	end
	local st = ChunkIndex.ensure_storage()
	local visited = st.visited[surface.index] == true
	local tib = ChunkIndex.tib_can_spawn_on(planet_name_of(surface), ChunkIndex.read_tib_flags())
	return ChunkIndex.surface_in_scope(visited, tib)
end

function ChunkIndex.mark_visited(surface)
	if not (surface and surface.valid) then
		return
	end
	ChunkIndex.ensure_storage().visited[surface.index] = true
end

-- Missing-only: already-indexed chunks are not re-queued.
-- seed_existing / player enter / surface change must not chew a finished map.
-- Never find_entities here. Returns how many chunks were newly queued.
function ChunkIndex.enqueue_generated(surface)
	if not (surface and surface.valid) then
		return 0
	end
	if not ChunkIndex.surface_eligible(surface) then
		return 0
	end
	local n = 0
	local si = surface.index
	for chunk in surface.get_chunks() do
		if not ChunkIndex.has_index_row(storage.orechunk, si, chunk.x, chunk.y) then
			if ChunkIndex.enqueue(si, chunk.x, chunk.y) then
				n = n + 1
			end
		end
	end
	return n
end

function ChunkIndex.reseed_wants_full(arg)
	return arg == true or arg == "full" or arg == "refresh"
end

local function empty_reseed_result(enabled, mode)
	return {
		enabled = enabled,
		mode = mode or "missing",
		surfaces = 0,
		generated = 0,
		indexed = 0,
		missing = 0,
		enqueued = 0,
		enqueued_missing = 0,
		enqueued_refresh = 0,
	}
end

-- Walk surface.get_chunks() (all generated), not the index tables.
-- Default (nil / false / "missing"): queue unindexed gaps only.
-- Full refresh is opt-in: reseed(true) / reseed("full") / chunkindex_reseed_full.
-- Rebuilds st.queued from the live queue so a stale key cannot hide a gap.
function ChunkIndex.reseed(full)
	local mode = ChunkIndex.reseed_wants_full(full) and "full" or "missing"
	if not ChunkIndex.enabled() then
		return empty_reseed_result(false, mode)
	end
	if not game then
		return empty_reseed_result(true, mode)
	end
	local st = ChunkIndex.ensure_storage()
	for _, player in pairs(game.players) do
		if player.valid and player.surface and player.surface.valid then
			ChunkIndex.mark_visited(player.surface)
		end
	end
	local missing_list, refresh_list = {}, {}
	local surfaces, generated, indexed, missing = 0, 0, 0, 0
	for _, surface in pairs(game.surfaces) do
		if surface.valid and ChunkIndex.surface_eligible(surface) then
			surfaces = surfaces + 1
			local si = surface.index
			for chunk in surface.get_chunks() do
				local x, y = chunk.x, chunk.y
				if ChunkIndex.coords_ok(si, x, y) then
					generated = generated + 1
					if ChunkIndex.has_index_row(storage.orechunk, si, x, y) then
						indexed = indexed + 1
						if mode == "full" then
							refresh_list[#refresh_list + 1] = {si, x, y}
						end
					else
						missing = missing + 1
						missing_list[#missing_list + 1] = {si, x, y}
					end
				end
			end
		end
	end
	st.queue = {}
	st.head = 1
	st.queued = {}
	local enqueued_missing, enqueued_refresh = 0, 0
	for _, item in ipairs(missing_list) do
		if ChunkIndex.enqueue(item[1], item[2], item[3]) then
			enqueued_missing = enqueued_missing + 1
		end
	end
	if mode == "full" then
		for _, item in ipairs(refresh_list) do
			if ChunkIndex.enqueue(item[1], item[2], item[3]) then
				enqueued_refresh = enqueued_refresh + 1
			end
		end
	end
	ChunkIndex.rebuild_queued_set(st)
	st.seeded = true
	return {
		enabled = true,
		mode = mode,
		surfaces = surfaces,
		generated = generated,
		indexed = indexed,
		missing = missing,
		enqueued = enqueued_missing + enqueued_refresh,
		enqueued_missing = enqueued_missing,
		enqueued_refresh = enqueued_refresh,
	}
end

local function nest_set(root, si, x, y, value)
	root[si] = root[si] or {}
	root[si][x] = root[si][x] or {}
	root[si][x][y] = value
end

local function nest_get(root, si, x, y)
	local s = root and root[si]
	local row = s and s[x]
	if not row then
		return nil
	end
	return row[y]
end

local function item_name_for(entity)
	if ResourceProductItemName then
		local ok, name = pcall(ResourceProductItemName, entity)
		if ok and name then
			return name
		end
	end
	local proto = entity.valid and entity.prototype
	local props = proto and proto.mineable_properties
	if props and props.products then
		for _, product in pairs(props.products) do
			if (not product.type or product.type == "item") and product.name then
				return product.name
			end
		end
	end
	return entity.name
end

function ChunkIndex.classify_entities(resources)
	local items = {}
	local has_ore = false
	local has_tib = false
	for _, entity in pairs(resources) do
		if entity and (entity.valid ~= false) then
			local proto = entity.prototype
			local cat = proto and proto.resource_category
			local name = entity.name
			local amount = entity.amount
			local infinite = proto and proto.infinite_resource
			if not ChunkIndex.resource_is_skip(cat, name, amount, infinite) then
				if ChunkIndex.resource_is_tiberium(cat, name) then
					has_tib = true
				end
				local item = item_name_for(entity)
				if item then
					items[item] = true
					has_ore = true
				end
			end
		end
	end
	return {
		items = items,
		empty = not has_ore,
		has_tib = has_tib,
	}
end

local function scan_chunk(surface, x, y)
	if not (surface and surface.valid) then
		return
	end
	if not surface.is_chunk_generated({x, y}) then
		return
	end
	local left = x * 32
	local top = y * 32
	local resources = surface.find_entities_filtered{
		type = "resource",
		area = {{left, top}, {left + 32, top + 32}},
	}
	local classified = ChunkIndex.classify_entities(resources)
	local si = surface.index
	local had_tib = nest_get(storage.tibchunk, si, x, y) == true
	nest_set(storage.orechunk, si, x, y, {
		items = classified.items,
		empty = classified.empty,
	})
	if classified.has_tib then
		nest_set(storage.tibchunk, si, x, y, true)
	elseif had_tib or nest_get(storage.tibchunk, si, x, y) ~= nil then
		nest_set(storage.tibchunk, si, x, y, false)
	else
		nest_set(storage.tibchunk, si, x, y, false)
	end
	local st = ChunkIndex.ensure_storage()
	ChunkIndex.apply_tib_transition(st.border, st.tib_holds, si, x, y, had_tib, classified.has_tib)
	-- New Tib source: enqueue already-generated neighbors for border classify.
	if classified.has_tib and not had_tib then
		for _, off in ipairs(NEIGHBOR_OFFSETS) do
			local nx, ny = x + off[1], y + off[2]
			if surface.is_chunk_generated({nx, ny}) then
				ChunkIndex.enqueue(si, nx, ny)
			end
		end
	end
	ChunkIndex.overlay_mark_dirty(si, x, y)
	if classified.has_tib ~= had_tib then
		for _, off in ipairs(NEIGHBOR_OFFSETS) do
			ChunkIndex.overlay_mark_dirty(si, x + off[1], y + off[2])
		end
	end
end

local function pop_queue(st)
	local q = st.queue
	while true do
		local head = st.head
		if head > #q then
			return nil
		end
		local item = q[head]
		q[head] = nil
		st.head = head + 1
		compact_queue(st)
		-- Tombstones (deleted chunks) and empty slots are skipped.
		if item then
			st.queued[ChunkIndex.chunk_key(item[1], item[2], item[3])] = nil
			return item
		end
	end
end

local function enqueue_border(st)
	for si, xs in pairs(st.border) do
		local surface = game.get_surface(si)
		if surface and surface.valid then
			for x, ys in pairs(xs) do
				for y, count in pairs(ys) do
					if (count or 0) > 0 and surface.is_chunk_generated({x, y}) then
						ChunkIndex.enqueue(si, x, y)
					end
				end
			end
		end
	end
end

local function enqueue_entity_chunk(entity)
	if not (entity and entity.valid) then
		return
	end
	local surface = entity.surface
	if not (surface and surface.valid) then
		return
	end
	local pos = entity.position
	local cx = math.floor(pos.x / 32)
	local cy = math.floor(pos.y / 32)
	if surface.is_chunk_generated({cx, cy}) then
		ChunkIndex.enqueue(surface.index, cx, cy)
	end
end

local function enqueue_harvester_chunks(st)
	if storage.cncharvesters then
		for _, harvester in pairs(storage.cncharvesters) do
			enqueue_entity_chunk(harvester.vehicle)
		end
	end
	if storage.module_bays then
		for _, rec in pairs(storage.module_bays) do
			enqueue_entity_chunk(rec.vehicle)
		end
	end
	if st.watch then
		for unit_number, _ in pairs(st.watch) do
			-- Placeholder watch list: unit numbers only. Real ents come from
			-- the two tables above; this set is for later depot-spawned miners.
			if storage.cncharvesters and storage.cncharvesters[unit_number] then
				enqueue_entity_chunk(storage.cncharvesters[unit_number].vehicle)
			elseif storage.module_bays and storage.module_bays[unit_number] then
				enqueue_entity_chunk(storage.module_bays[unit_number].vehicle)
			end
		end
	end
end

function ChunkIndex.on_player_entered(event)
	if not ChunkIndex.enabled() then
		return
	end
	local player = event and event.player_index and game.get_player(event.player_index)
	if not (player and player.valid and player.surface) then
		return
	end
	ChunkIndex.mark_visited(player.surface)
	ChunkIndex.enqueue_generated(player.surface)
	ChunkIndex.overlay_sync_shortcuts()
end

function ChunkIndex.tick()
	if not game then
		return
	end
	if not ChunkIndex.enabled() then
		ChunkIndex.overlay_tick()
		return
	end
	local st = ChunkIndex.ensure_storage()
	-- Map-gen chunks can fire before a player exists. First enabled tick
	-- marks current player surfaces and enqueues their generated chunks.
	if not st.seeded then
		ChunkIndex.seed_existing()
		st.seeded = true
	end
	local tick = game.tick
	-- First-pass / missing backlog owns the queue. Do not inject border or
	-- harvester refresh into a multi-hour chew.
	local idle = ChunkIndex.queue_len(st) == 0
	if idle and tick >= (st.border_due or 0) then
		st.border_due = tick + ChunkIndex.BORDER_REQUEUE_IDLE_TICKS
		if next(st.border) and next(st.tib_holds) then
			enqueue_border(st)
		end
	elseif not idle then
		st.border_due = tick + ChunkIndex.BORDER_REQUEUE_TICKS
	end
	if idle and tick >= (st.harvest_due or 0) then
		st.harvest_due = tick + ChunkIndex.HARVESTER_REQUEUE_IDLE_TICKS
		if (storage.cncharvesters and next(storage.cncharvesters)) or (storage.module_bays and next(storage.module_bays)) then
			enqueue_harvester_chunks(st)
		end
	elseif not idle then
		st.harvest_due = tick + ChunkIndex.HARVESTER_REQUEUE_TICKS
	end
	local scanned = false
	if tick >= (st.scan_due or 0) then
		st.scan_due = tick + ChunkIndex.SCAN_INTERVAL_TICKS
		local budget = ChunkIndex.BUDGET_PER_TICK
		while budget > 0 do
			local item = pop_queue(st)
			if not item then
				break
			end
			local surface = game.get_surface(item[1])
			scan_chunk(surface, item[2], item[3])
			st.scan = {si = item[1], x = item[2], y = item[3]}
			scanned = true
			budget = budget - 1
		end
	elseif st.scan then
		-- Keep the last scan blink until the next scan tick.
		scanned = true
	end
	if not scanned then
		st.scan = nil
	end
	ChunkIndex.overlay_tick()
end

-- Event handlers: enqueue only.

function ChunkIndex.on_chunk_generated(event)
	if not ChunkIndex.enabled() then
		return
	end
	local surface = event.surface
	if not (surface and surface.valid) then
		return
	end
	if game and game.players then
		for _, player in pairs(game.players) do
			if player.valid and player.surface == surface then
				ChunkIndex.mark_visited(surface)
				break
			end
		end
	end
	if not ChunkIndex.surface_eligible(surface) then
		return
	end
	local pos = event.position
	if pos then
		ChunkIndex.enqueue(surface.index, pos.x, pos.y)
	end
end

function ChunkIndex.on_surface_created(event)
	if not ChunkIndex.enabled() then
		return
	end
	local surface = event.surface_index and game.get_surface(event.surface_index)
	if not (surface and surface.valid) then
		return
	end
	-- Eligible unvisited: do not walk get_chunks() on empty void.
	-- chunk_generated / first visit will enqueue real chunks.
end

function ChunkIndex.on_player_changed_surface(event)
	if not ChunkIndex.enabled() then
		return
	end
	local player = event.player_index and game.get_player(event.player_index)
	if not (player and player.valid and player.surface) then
		return
	end
	local surface = player.surface
	ChunkIndex.mark_visited(surface)
	ChunkIndex.enqueue_generated(surface)
end

function ChunkIndex.seed_existing()
	if not ChunkIndex.enabled() then
		return
	end
	if not game then
		return
	end
	for _, player in pairs(game.players) do
		if player.valid and player.surface and player.surface.valid then
			ChunkIndex.mark_visited(player.surface)
		end
	end
	for _, surface in pairs(game.surfaces) do
		if surface.valid and ChunkIndex.ensure_storage().visited[surface.index] then
			ChunkIndex.enqueue_generated(surface)
		end
	end
	ChunkIndex.ensure_storage().seeded = true
end

function ChunkIndex.lookup(surface_index, x, y)
	return nest_get(storage.orechunk, surface_index, x, y), nest_get(storage.tibchunk, surface_index, x, y)
end

function ChunkIndex.chunk_center(x, y)
	return {x = x * 32 + 16, y = y * 32 + 16}
end

function ChunkIndex.item_is_tiberium(name)
	return name and string.find(name, "tiberium", 1, true) ~= nil
end

-- Index row is assignable if it has a non-empty item the truck may mine.
-- Ore trucks never take Tib-only chunks. Type-2 may take Tib when allow_tib.
function ChunkIndex.row_allows_vehicle(ore_row, tib_flag, allow_tib)
	if not ore_row or ore_row.empty == true then
		return false
	end
	local items = ore_row.items
	if items then
		local any = false
		for name, _ in pairs(items) do
			any = true
			if ChunkIndex.item_is_tiberium(name) then
				if allow_tib then
					return true
				end
			else
				return true
			end
		end
		if any then
			return false
		end
	end
	if tib_flag == true then
		return allow_tib == true
	end
	return true
end

-- Nearest non-empty indexed chunks. range_tiles nil / <=0 / huge = no cap
-- (whole surface index). Results are nearest-first, truncated to FIND_ORE_MAX.
ChunkIndex.FIND_ORE_MAX = 96

function ChunkIndex.find_ore_chunks(orechunk, tibchunk, si, origin, range_tiles, allow_tib, exclude)
	local out = {}
	if not (orechunk and si and origin) then
		return out
	end
	local xs = orechunk[si]
	if not xs then
		return out
	end
	local range = range_tiles
	local range_sq = nil
	if range and range > 0 and range < 1000000 then
		range_sq = range * range
	end
	local ox, oy = origin.x, origin.y
	local tibs = tibchunk and tibchunk[si]
	for x, ys in pairs(xs) do
		for y, row in pairs(ys) do
			local key = ChunkIndex.chunk_key(si, x, y)
			if not (exclude and exclude[key]) then
				local tib = tibs and tibs[x] and tibs[x][y] == true
				if ChunkIndex.row_allows_vehicle(row, tib, allow_tib) then
					local c = ChunkIndex.chunk_center(x, y)
					local dx, dy = c.x - ox, c.y - oy
					local dsq = dx * dx + dy * dy
					if not range_sq or dsq <= range_sq then
						out[#out + 1] = {si = si, x = x, y = y, dist_sq = dsq, center = c, tib = tib}
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist_sq < b.dist_sq
	end)
	local maxn = ChunkIndex.FIND_ORE_MAX
	if maxn and #out > maxn then
		for i = maxn + 1, #out do
			out[i] = nil
		end
	end
	return out
end

function ChunkIndex.debug_stats()
	local st = storage.chunkindex
	if not st then
		return {enabled = ChunkIndex.enabled(), queued = 0}
	end
	local queued = ChunkIndex.queue_len(st)
	local ore_n, tib_n, border_n = 0, 0, 0
	for _, xs in pairs(storage.orechunk or {}) do
		for _, ys in pairs(xs) do
			for _, _ in pairs(ys) do
				ore_n = ore_n + 1
			end
		end
	end
	for _, xs in pairs(storage.tibchunk or {}) do
		for _, ys in pairs(xs) do
			for _, v in pairs(ys) do
				if v then
					tib_n = tib_n + 1
				end
			end
		end
	end
	for _, xs in pairs(st.border or {}) do
		for _, ys in pairs(xs) do
			for _, count in pairs(ys) do
				if (count or 0) > 0 then
					border_n = border_n + 1
				end
			end
		end
	end
	local scan = st.scan
	local overlay_drawn, overlay_dirty = 0, 0
	if st.overlay_ids then
		for _ in pairs(st.overlay_ids) do
			overlay_drawn = overlay_drawn + 1
		end
	end
	if st.overlay_dirty then
		for _ in pairs(st.overlay_dirty) do
			overlay_dirty = overlay_dirty + 1
		end
	end
	return {
		enabled = ChunkIndex.enabled(),
		queued = queued,
		queue_len = queued,
		ore_chunks = ore_n,
		tib_chunks = tib_n,
		border_n = border_n,
		overlay = st.overlay == true,
		overlay_drawn = overlay_drawn,
		overlay_dirty = overlay_dirty,
		overlay_full = st.overlay_full == true,
		overlay_cap = ChunkIndex.OVERLAY_MAX_CHUNKS,
		overlay_last_ms = st.overlay_last_ms,
		budget_per_tick = ChunkIndex.BUDGET_PER_TICK,
		scan_interval_ticks = ChunkIndex.SCAN_INTERVAL_TICKS,
		scan = scan and {si = scan.si, x = scan.x, y = scan.y} or nil,
	}
end

--------------------------------------------------
-- Map overlay (chart rectangles + scan blink)
--------------------------------------------------

-- Full walk only on toggle-on / rare idle reconcile. Steady state is dirty-only.
ChunkIndex.OVERLAY_REBUILD_TICKS = 30
ChunkIndex.OVERLAY_DIRTY_BUDGET = 48
-- 10 min idle safety walk. Never during a first-pass chew.
ChunkIndex.OVERLAY_RECONCILE_TICKS = 36000
-- 0 = no cap. Chart overlay is pollution-like (all indexed charted chunks).
ChunkIndex.OVERLAY_MAX_CHUNKS = 0
-- 8 ticks on / 8 off ≈ 3.75 Hz at 60 UPS.
ChunkIndex.OVERLAY_BLINK_PERIOD = 16

ChunkIndex.OVERLAY_COLORS = {
	green = {r = 0.12, g = 0.80, b = 0.18, a = 0.30},
	orange = {r = 1.0, g = 0.55, b = 0.10, a = 0.45},
	yellow = {r = 0.95, g = 0.82, b = 0.08, a = 0.30},
	red = {r = 0.88, g = 0.12, b = 0.10, a = 0.30},
	purple = {r = 0.55, g = 0.18, b = 0.82, a = 0.12},
	blink = {r = 0.35, g = 0.95, b = 1.0, a = 0.50},
	outline = {r = 1, g = 1, b = 1, a = 0.85},
	outline_dim = {r = 0.45, g = 0.90, b = 1.0, a = 0.55},
}

-- Priority: green (Tib) → orange (Tib-border + ore) → yellow (harvester or empty border)
-- → red (ore) → purple (empty scanned). nil = unscanned / no draw.
function ChunkIndex.overlay_class(ore_row, tib_flag, border_count, has_harvester)
	if tib_flag == true then
		return "green"
	end
	local on_border = (border_count or 0) > 0
	local has_ore = ore_row ~= nil and ore_row.empty ~= true
	if on_border and has_ore then
		return "orange"
	end
	if has_harvester or on_border then
		return "yellow"
	end
	if ore_row then
		if ore_row.empty ~= true then
			return "red"
		end
		return "purple"
	end
	return nil
end

function ChunkIndex.overlay_blink_on(tick)
	local period = ChunkIndex.OVERLAY_BLINK_PERIOD
	return ((tick or 0) % period) < (period / 2)
end

function ChunkIndex.overlay_get()
	return storage and storage.chunkindex and storage.chunkindex.overlay == true
end

-- 2.0 draw_* returns LuaRenderObject userdata. get_object_by_id only
-- accepts a numeric id — passing userdata CTDs ("real number expected").
local function resolve_render(obj)
	if obj == nil or not rendering then
		return nil
	end
	if type(obj) == "number" then
		local got = rendering.get_object_by_id and rendering.get_object_by_id(obj)
		if got and got.valid then
			return got
		end
		return nil
	end
	local ok, valid = pcall(function()
		return obj.valid
	end)
	if ok and valid then
		return obj
	end
	return nil
end

local function destroy_render(obj)
	obj = resolve_render(obj)
	if obj then
		obj.destroy()
	end
end

local function destroy_list(list)
	if not list then
		return
	end
	for i, obj in pairs(list) do
		destroy_render(obj)
		list[i] = nil
	end
end

local function destroy_rec(rec)
	if not rec then
		return
	end
	destroy_list(rec.fills)
	destroy_list(rec.outlines)
	destroy_render(rec.outline)
	rec.outline = nil
end

local function set_render_color(obj, color)
	obj = resolve_render(obj)
	if not (obj and color) then
		return false
	end
	obj.color = color
	return true
end

local function recolor_list(list, color)
	if not list then
		return false
	end
	local n, ok = 0, true
	for _, obj in pairs(list) do
		n = n + 1
		if not set_render_color(obj, color) then
			ok = false
		end
	end
	return ok and n > 0
end

function ChunkIndex.overlay_is_world_mode(mode)
	if mode == nil or mode == "game" then
		return true
	end
	local rm = defines and defines.render_mode
	return rm ~= nil and mode == rm.game
end

-- One ScriptRenderMode. "chart" covers the map and minimap; a second
-- chart-zoomed-in rect doubled objects for no extra semantics on 2.0.77.
-- Never "game" (world surface).
function ChunkIndex.overlay_render_modes()
	return {"chart"}
end

local function draw_rect(surface, cx, cy, color, filled, width, render_mode)
	if not (rendering and surface and surface.valid) then
		return nil
	end
	if ChunkIndex.overlay_is_world_mode(render_mode) then
		return nil
	end
	local args = {
		color = color,
		filled = filled ~= false,
		width = width or 1,
		left_top = {x = cx * 32, y = cy * 32},
		right_bottom = {x = (cx + 1) * 32, y = (cy + 1) * 32},
		surface = surface,
		render_mode = render_mode,
	}
	local ok, obj = pcall(function()
		return rendering.draw_rectangle(args)
	end)
	if ok then
		return obj
	end
	return nil
end

local function draw_chunk_fills(surface, cx, cy, color)
	local fills = {}
	for _, mode in ipairs(ChunkIndex.overlay_render_modes()) do
		local obj = draw_rect(surface, cx, cy, color, true, 1, mode)
		if obj then
			fills[#fills + 1] = obj
		end
	end
	return fills
end

local function draw_chunk_outlines(surface, cx, cy, color)
	local outlines = {}
	for _, mode in ipairs(ChunkIndex.overlay_render_modes()) do
		local obj = draw_rect(surface, cx, cy, color, false, 3, mode)
		if obj then
			outlines[#outlines + 1] = obj
		end
	end
	return outlines
end

local function recolor_fills(rec, color)
	return rec and recolor_list(rec.fills, color)
end

local function recolor_outlines(rec, color)
	if not rec then
		return false
	end
	if rec.outlines then
		return recolor_list(rec.outlines, color)
	end
	return set_render_color(rec.outline, color)
end

local function ensure_outlines(rec, surface, cx, cy, color)
	if recolor_outlines(rec, color) then
		return
	end
	destroy_list(rec.outlines)
	destroy_render(rec.outline)
	rec.outline = nil
	rec.outlines = draw_chunk_outlines(surface, cx, cy, color)
end

function ChunkIndex.overlay_clear()
	local st = storage and storage.chunkindex
	if not st then
		return
	end
	for key, rec in pairs(st.overlay_ids or {}) do
		destroy_rec(rec)
		st.overlay_ids[key] = nil
	end
	st.overlay_ids = {}
	st.overlay_dirty = {}
	st.overlay_full = false
	st.overlay_due = 0
	st.overlay_reconcile_due = 0
end

function ChunkIndex.overlay_forget(si, x, y)
	local st = storage and storage.chunkindex
	if not st then
		return
	end
	local key = ChunkIndex.chunk_key(si, x, y)
	if st.overlay_ids then
		destroy_rec(st.overlay_ids[key])
		st.overlay_ids[key] = nil
	end
	if st.overlay_dirty then
		st.overlay_dirty[key] = nil
	end
end

function ChunkIndex.overlay_sync_shortcuts()
	if not game then
		return
	end
	local on = ChunkIndex.overlay_get()
	for _, player in pairs(game.players) do
		if player.valid and player.set_shortcut_toggled then
			pcall(function()
				player.set_shortcut_toggled("cncharvester-chunkindex-overlay", on)
			end)
		end
	end
end

function ChunkIndex.overlay_set(on, player)
	local st = ChunkIndex.ensure_storage()
	if on and not ChunkIndex.enabled() then
		st.overlay = false
		ChunkIndex.overlay_clear()
		ChunkIndex.overlay_sync_shortcuts()
		if player and player.valid and player.print then
			player.print({"cncharvester.chunkindex-overlay-disabled"})
		end
		return false
	end
	st.overlay = on and true or false
	if not st.overlay then
		ChunkIndex.overlay_clear()
	else
		st.overlay_full = true
		st.overlay_due = 0
	end
	ChunkIndex.overlay_sync_shortcuts()
	if player and player.valid and player.print then
		player.print({st.overlay and "cncharvester.chunkindex-overlay-on" or "cncharvester.chunkindex-overlay-off"})
	end
	return st.overlay
end

function ChunkIndex.overlay_toggle(player)
	if game and storage and storage.chunkindex and storage.chunkindex.overlay_event_tick == game.tick then
		return ChunkIndex.overlay_get()
	end
	if game and storage and storage.chunkindex then
		storage.chunkindex.overlay_event_tick = game.tick
	end
	return ChunkIndex.overlay_set(not ChunkIndex.overlay_get(), player)
end

local harvest_cache_tick, harvest_cache_set, harvest_cache_list

local function harvester_chunk_set()
	if game and harvest_cache_tick == game.tick and harvest_cache_set then
		return harvest_cache_set, harvest_cache_list
	end
	local set = {}
	local list = {}
	local function mark(ent)
		if not (ent and ent.valid and ent.surface and ent.position) then
			return
		end
		local si = ent.surface.index
		local cx = math.floor(ent.position.x / 32)
		local cy = math.floor(ent.position.y / 32)
		local key = ChunkIndex.chunk_key(si, cx, cy)
		if set[key] then
			return
		end
		set[key] = true
		list[#list + 1] = {si = si, x = cx, y = cy}
	end
	if storage.cncharvesters then
		for _, harvester in pairs(storage.cncharvesters) do
			mark(harvester.vehicle)
		end
	end
	if storage.module_bays then
		for _, rec in pairs(storage.module_bays) do
			mark(rec.vehicle)
		end
	end
	harvest_cache_tick = game and game.tick
	harvest_cache_set = set
	harvest_cache_list = list
	return set, list
end

function ChunkIndex.each_nested_chunk(root, fn)
	local n = 0
	if not root then
		return n
	end
	for si, xs in pairs(root) do
		for x, ys in pairs(xs) do
			for y, val in pairs(ys) do
				n = n + 1
				if fn then
					fn(si, x, y, val)
				end
			end
		end
	end
	return n
end

local function classify_at(si, x, y, harvest)
	local ore = nest_get(storage.orechunk, si, x, y)
	local tib = nest_get(storage.tibchunk, si, x, y)
	local border = 0
	if storage.chunkindex then
		border = ChunkIndex.border_count(storage.chunkindex.border, si, x, y)
	end
	return ChunkIndex.overlay_class(ore, tib == true, border, harvest[ChunkIndex.chunk_key(si, x, y)] == true)
end

local function viewed_surfaces()
	local surfaces, forces = {}, {}
	if not game then
		return surfaces, forces
	end
	for _, player in pairs(game.connected_players) do
		if player.valid and player.surface and player.surface.valid then
			local si = player.surface.index
			surfaces[si] = player.surface
			forces[si] = forces[si] or {}
			if player.force then
				forces[si][#forces[si] + 1] = player.force
			end
		end
	end
	return surfaces, forces
end

local function chunk_is_charted(surface, x, y, force_list)
	if not (surface and surface.valid) then
		return false
	end
	if not force_list or #force_list == 0 then
		return true
	end
	for _, force in ipairs(force_list) do
		if force.valid and force.is_chunk_charted then
			if force.is_chunk_charted(surface, {x, y}) then
				return true
			end
		elseif force.valid then
			return true
		end
	end
	return false
end

local function overlay_clock()
	if os and os.clock then
		return os.clock()
	end
	return nil
end

-- nil, false = not on a viewed surface (leave existing draw).
-- nil, true  = viewed but not wanted (drop draw).
-- info, true = draw / recolor.
local function overlay_wanted_info(si, x, y, harvest, surfaces, forces, scan)
	local surface = surfaces[si]
	if not (surface and surface.valid) then
		return nil, false
	end
	if not chunk_is_charted(surface, x, y, forces[si]) then
		return nil, true
	end
	local class = classify_at(si, x, y, harvest)
	local is_scan = scan and scan.si == si and scan.x == x and scan.y == y
	if not class and not is_scan then
		return nil, true
	end
	return {
		si = si,
		x = x,
		y = y,
		class = class,
		surface = surface,
	}, true
end

local function overlay_apply_info(st, key, info)
	local existing = st.overlay_ids[key]
	local color = info.class and ChunkIndex.OVERLAY_COLORS[info.class]
	if info.class and color then
		if existing and existing.class == info.class and recolor_fills(existing, color) then
			existing.scan = nil
		else
			destroy_rec(existing)
			st.overlay_ids[key] = {
				fills = draw_chunk_fills(info.surface, info.x, info.y, color),
				class = info.class,
			}
		end
	elseif existing then
		destroy_rec(existing)
		st.overlay_ids[key] = nil
	end
end

local function overlay_track_harvesters(st, harvest_list)
	local prev = st.harvest_overlay_keys or {}
	local next_keys = {}
	for _, item in ipairs(harvest_list) do
		local key = ChunkIndex.chunk_key(item.si, item.x, item.y)
		next_keys[key] = {item.si, item.x, item.y}
		if not prev[key] then
			ChunkIndex.overlay_mark_dirty(item.si, item.x, item.y)
		end
	end
	for key, item in pairs(prev) do
		if not next_keys[key] then
			ChunkIndex.overlay_mark_dirty(item[1], item[2], item[3])
		end
	end
	st.harvest_overlay_keys = next_keys
end

-- Pollution-like full walk. Toggle-on and rare idle reconcile only.
local function overlay_rebuild(st)
	if not (game and rendering) then
		return
	end
	local harvest, harvest_list = harvester_chunk_set()
	local scan = st.scan
	local surfaces, forces = viewed_surfaces()
	local wanted = {}
	local function consider(si, x, y)
		local info = overlay_wanted_info(si, x, y, harvest, surfaces, forces, scan)
		if info then
			wanted[ChunkIndex.chunk_key(si, x, y)] = info
		end
	end
	ChunkIndex.each_nested_chunk(storage.orechunk, consider)
	ChunkIndex.each_nested_chunk(storage.tibchunk, consider)
	ChunkIndex.each_nested_chunk(st.border, consider)
	for _, item in ipairs(harvest_list) do
		consider(item.si, item.x, item.y)
	end
	if scan then
		consider(scan.si, scan.x, scan.y)
	end
	for key, rec in pairs(st.overlay_ids) do
		if not wanted[key] then
			destroy_rec(rec)
			st.overlay_ids[key] = nil
		end
	end
	for key, info in pairs(wanted) do
		overlay_apply_info(st, key, info)
	end
end

-- Steady state: only chunks marked dirty by scan / Tib / harvester move.
local function overlay_rebuild_dirty(st)
	if not (game and rendering) then
		return
	end
	local dirty = st.overlay_dirty or {}
	if next(dirty) == nil then
		return
	end
	local harvest = harvester_chunk_set()
	local surfaces, forces = viewed_surfaces()
	local scan = st.scan
	local budget = ChunkIndex.OVERLAY_DIRTY_BUDGET
	for key, item in pairs(dirty) do
		if budget <= 0 then
			break
		end
		dirty[key] = nil
		budget = budget - 1
		local si, x, y = item[1], item[2], item[3]
		local info, viewed = overlay_wanted_info(si, x, y, harvest, surfaces, forces, scan)
		if info then
			overlay_apply_info(st, key, info)
		elseif viewed then
			local rec = st.overlay_ids[key]
			if rec then
				destroy_rec(rec)
				st.overlay_ids[key] = nil
			end
		end
	end
end

local function overlay_update_blink(st)
	if not (game and rendering) then
		return
	end
	local scan = st.scan
	local blink_key = st.overlay_blink_key
	if blink_key and (not scan or ChunkIndex.chunk_key(scan.si, scan.x, scan.y) ~= blink_key) then
		local rec = st.overlay_ids[blink_key]
		if rec then
			destroy_list(rec.outlines)
			destroy_render(rec.outline)
			rec.outlines = nil
			rec.outline = nil
			if rec.class and ChunkIndex.OVERLAY_COLORS[rec.class] then
				if not recolor_fills(rec, ChunkIndex.OVERLAY_COLORS[rec.class]) then
					destroy_rec(rec)
					st.overlay_ids[blink_key] = nil
				end
			else
				destroy_rec(rec)
				st.overlay_ids[blink_key] = nil
			end
		end
		st.overlay_blink_key = nil
	end
	if not scan then
		return
	end
	local surface = game.get_surface(scan.si)
	if not (surface and surface.valid) then
		return
	end
	local key = ChunkIndex.chunk_key(scan.si, scan.x, scan.y)
	local harvest = harvester_chunk_set()
	local class = classify_at(scan.si, scan.x, scan.y, harvest)
	local on = ChunkIndex.overlay_blink_on(game.tick)
	local rec = st.overlay_ids[key]
	if on then
		local color = ChunkIndex.OVERLAY_COLORS.blink
		if rec and recolor_fills(rec, color) then
			rec.class = class or rec.class
		else
			destroy_rec(rec)
			rec = {
				fills = draw_chunk_fills(surface, scan.x, scan.y, color),
				class = class,
			}
			st.overlay_ids[key] = rec
		end
		ensure_outlines(rec, surface, scan.x, scan.y, ChunkIndex.OVERLAY_COLORS.outline)
	else
		if class and rec then
			if not recolor_fills(rec, ChunkIndex.OVERLAY_COLORS[class]) then
				destroy_rec(rec)
				rec = {
					fills = draw_chunk_fills(surface, scan.x, scan.y, ChunkIndex.OVERLAY_COLORS[class]),
					class = class,
				}
				st.overlay_ids[key] = rec
			else
				rec.class = class
			end
			ensure_outlines(rec, surface, scan.x, scan.y, ChunkIndex.OVERLAY_COLORS.outline_dim)
		else
			-- Unclassified off-phase: hide fill, keep a dim outline pulse.
			if rec then
				destroy_list(rec.fills)
				rec.fills = {}
				ensure_outlines(rec, surface, scan.x, scan.y, ChunkIndex.OVERLAY_COLORS.outline_dim)
				rec.class = nil
			else
				st.overlay_ids[key] = {
					fills = {},
					outlines = draw_chunk_outlines(surface, scan.x, scan.y, ChunkIndex.OVERLAY_COLORS.outline_dim),
					class = nil,
				}
			end
		end
	end
	st.overlay_blink_key = key
end

function ChunkIndex.overlay_tick()
	if not (storage and game) then
		return
	end
	if not ChunkIndex.enabled() or not ChunkIndex.overlay_get() then
		if storage.chunkindex and storage.chunkindex.overlay_ids and next(storage.chunkindex.overlay_ids) then
			ChunkIndex.overlay_clear()
		end
		if storage.chunkindex and storage.chunkindex.overlay and not ChunkIndex.enabled() then
			storage.chunkindex.overlay = false
			ChunkIndex.overlay_sync_shortcuts()
		end
		return
	end
	local st = ChunkIndex.ensure_storage()
	-- Drop any pre-fix world-surface rectangles (2.0.77 default render_mode is game).
	if not st.overlay_chart_only then
		ChunkIndex.overlay_clear()
		st.overlay_chart_only = true
		st.overlay_full = true
	end
	-- One-shot: pick up orange (Tib-border + ore) without waiting for idle reconcile.
	if not st.overlay_orange then
		st.overlay_orange = true
		st.overlay_full = true
	end
	local _, harvest_list = harvester_chunk_set()
	overlay_track_harvesters(st, harvest_list)
	local tick = game.tick
	if st.overlay_full then
		local t0 = overlay_clock()
		overlay_rebuild(st)
		st.overlay_full = false
		st.overlay_dirty = {}
		st.overlay_due = tick + ChunkIndex.OVERLAY_REBUILD_TICKS
		st.overlay_reconcile_due = tick + ChunkIndex.OVERLAY_RECONCILE_TICKS
		local t1 = overlay_clock()
		if t0 and t1 then
			st.overlay_last_ms = (t1 - t0) * 1000
		end
	elseif tick >= (st.overlay_due or 0) then
		st.overlay_due = tick + ChunkIndex.OVERLAY_REBUILD_TICKS
		local t0 = overlay_clock()
		-- Full reconcile only when idle so a first-pass chew cannot spike UPS.
		if tick >= (st.overlay_reconcile_due or 0) and ChunkIndex.queue_len(st) == 0 then
			st.overlay_reconcile_due = tick + ChunkIndex.OVERLAY_RECONCILE_TICKS
			overlay_rebuild(st)
			st.overlay_dirty = {}
		else
			overlay_rebuild_dirty(st)
		end
		local t1 = overlay_clock()
		if t0 and t1 then
			st.overlay_last_ms = (t1 - t0) * 1000
		end
	end
	overlay_update_blink(st)
end
