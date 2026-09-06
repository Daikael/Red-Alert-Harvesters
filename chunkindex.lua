-- Milestone 1: global slow chunk index.
-- Event handlers only enqueue. The budget tick scans ~one generated chunk.
-- Do not generate chunks. Do not teleport or drive trucks.

ChunkIndex = ChunkIndex or {}

ChunkIndex.BUDGET_PER_TICK = 1
-- Empty neighbors of Tib are re-queued this often so spread is noticed.
ChunkIndex.BORDER_REQUEUE_TICKS = 600
-- Chunks under tracked harvesters are re-queued this often for depletion.
ChunkIndex.HARVESTER_REQUEUE_TICKS = 300

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
	if not (si and x and y) then
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

local function runtime_value(name)
	if not (settings and settings.global and settings.global[name]) then
		return nil
	end
	return settings.global[name].value
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
	if startup_value("Auto-cncharvester-testing") == true then
		return true
	end
	return runtime_value("cncharvester-chunk-index") == true
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
	st.seeded = st.seeded or false
	return st
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

function ChunkIndex.enqueue(surface_index, x, y)
	if not (surface_index and x and y) then
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
	if not (surface_index and x and y) then
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
end

-- on_pre_chunk_deleted / on_chunk_deleted: positions[] on one surface.
-- Run even if the scanner setting is off so leftover index rows die.
function ChunkIndex.on_chunks_deleted(event)
	if not event then
		return
	end
	local si = event.surface_index
	local positions = event.positions
	if not (si and positions) then
		return
	end
	for _, pos in pairs(positions) do
		if pos and pos.x and pos.y then
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

-- Enqueue already-generated chunk positions only. Never find_entities here.
function ChunkIndex.enqueue_generated(surface)
	if not (surface and surface.valid) then
		return
	end
	if not ChunkIndex.surface_eligible(surface) then
		return
	end
	for chunk in surface.get_chunks() do
		ChunkIndex.enqueue(surface.index, chunk.x, chunk.y)
	end
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
end

function ChunkIndex.tick()
	if not ChunkIndex.enabled() then
		return
	end
	if not game then
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
	if tick >= (st.border_due or 0) then
		st.border_due = tick + ChunkIndex.BORDER_REQUEUE_TICKS
		enqueue_border(st)
	end
	if tick >= (st.harvest_due or 0) then
		st.harvest_due = tick + ChunkIndex.HARVESTER_REQUEUE_TICKS
		enqueue_harvester_chunks(st)
	end
	local budget = ChunkIndex.BUDGET_PER_TICK
	while budget > 0 do
		local item = pop_queue(st)
		if not item then
			break
		end
		local surface = game.get_surface(item[1])
		scan_chunk(surface, item[2], item[3])
		budget = budget - 1
	end
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

function ChunkIndex.debug_stats()
	local st = storage.chunkindex
	if not st then
		return {enabled = ChunkIndex.enabled(), queued = 0}
	end
	local queued = #st.queue - (st.head or 1) + 1
	if queued < 0 then
		queued = 0
	end
	local ore_n, tib_n = 0, 0
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
	return {enabled = ChunkIndex.enabled(), queued = queued, ore_chunks = ore_n, tib_chunks = tib_n}
end
