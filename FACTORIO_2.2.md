# Red-Alert-Harvester 2.2.x — autonomy roadmap

Planning doc for pack **2.2.x**. Agreed with the maintainer (Daikael). This file is the locked design; implement against it, do not invent a parallel plan.

**M1 scanner and step-3 physical drive have landed on this branch** (`chunkindex.lua`, `autodrive.lua`). Gated behind startup **Automatic harvester testing**. Pack version is **2.2.0**. No M2 depot. The dump **refinery** can be circuit-wired to read inventory. Teleport autonomy is not used. Do not merge to `master` unprompted. Testers use the GitHub **prerelease** zip `Red-Alert-Harvester_2.2.0.zip` (tag `2.2.0`).

## Shipping baseline

| Line | Git | Pack | `factorio_version` | Status |
| --- | --- | --- | --- | --- |
| Live 2.0 (this line) | `master` | **2.1.18** | **2.0** | PR **#16** merged. Branch `2.2.0` starts here. |
| 2.1 experimental | `2.1.17` / draft PR **#15** | 2.1.17 | 2.1 | Keep. **Do not merge** into `master` or into `2.2.0`. |
| Historical 2.0 backdate branch | `2.1.18` | 2.1.18 | 2.0 | Sibling of `2.1.17`. Already merged via #16. |

See `FACTORIO_2.0.md` / `FACTORIO_2.1.md` for the 2.1.17 ↔ 2.1.18 gameplay port. 2.2.x is **autonomy**, not another hitch / hybrid / slave-miner pass.

## Dual-track (same split as 2.1.17 / 2.1.18)

1. Implement on **`2.2.0` first** — Factorio **2.0** line, branched from current `master` (pack 2.1.18).
2. Later, dual-track a Factorio **2.1** sibling the same way 2.1.17 / 2.1.18 were split (`factorio_version`, API deltas, Tib optional-dep line).
3. **Dev-branch-first.** Never merge a 2.2.x head to live `master` unprompted.

`info.json` on this branch is **2.2.0** (`factorio_version` 2.0). Factorio only accepts three-part versions. This is a tester zip, not a portal/live upload.

## Current auto AI (what we are replacing)

Startup flag **`Auto-cncharvester-testing`** (`settings.lua`) enables **`ChunkIndex` plus physical auto-drive**. The per-truck teleport loop in `harvester.lua` is not used (commented leftovers only). While **Automatic operation** is on and pause-on-enter is off, a player who enters is **demoted to passenger** (`set_driver(nil)` then `set_passenger`) so they stay aboard but cannot steer. Factorio gives the driver seat priority over scripted `riding_state`. Pause-on-enter is the only way to sit as driver (AI yields). `auto_enabled` is written **only** from a real inventory checkbox click — never from occupancy or GUI destroy/close.

What it actually does today:

- Each tracked vehicle (`storage.cncharvesters`) runs `FindingOre` → **drive** → `MiningOre` → `FindingRefinery` → drive → dump / refuel.
- Movement is **`LuaSurface.request_path` + `riding_state`**. Cars on Factorio **2.0.77** are **not** `commandable` (that API is units / spider-vehicles). Spidertron `autopilot_destination` is not present on these `type=car` prototypes. Do not restore `vehicle.teleport`.
- Ore pick is **ChunkIndex**, nearest indexed chunk first, **no 256-tile / 8-chunk cap**. Path failure uses the existing ladder. Not `FindRandomOreInRadius`.
- Refineries are found as today (`refinery.lua`); the trip is a drive.
- Refineries are found by a full-surface `find_entities_filtered{name = "refinery"}` (`refinery.lua`).
- `chunksearcher.lua` (dead stub) is **deleted**. The index lives in `chunkindex.lua`.
- `storage.orechunk` / `storage.tibchunk` are the index home, written by the slow scanner when it is enabled.

`harvester-auto-by-default` exists but is unused by the runtime loop. Commented `Auto-cncharvester-Ragne` is not a design input — range in 2.2.x comes from the **depot** (GUI / circuit), not a startup int.

---

## Milestone 1 — Global slow chunk scanner

**Status (branch `2.2.0`):** implemented. Enable with startup **Automatic harvester testing** (`Auto-cncharvester-testing`; restart required). Default off. That flag runs the **index and the physical auto-drive AI**. `on_pre_chunk_deleted` / `on_chunk_deleted` forget the chunk (queue, ore/tib rows, Tib refcount unwind) so unloaded charted chunks do not leak or ghost-rescan.

`ChunkIndex` is not visible from `/c` (Factorio mod sandbox). Read M1 stats through the **`Red-Alert-Harvester`** remote interface:

```
/c game.print(serpent.line(remote.call("Red-Alert-Harvester", "chunkindex_stats")))
/c game.print(tostring(remote.call("Red-Alert-Harvester", "chunkindex_enabled")))
```

`chunkindex_stats` returns `{enabled, queued, ore_chunks, tib_chunks, overlay, scan, budget_per_tick, scan_interval_ticks, ...}` once the index has storage. `chunkindex_enabled` is the startup flag. `chunkindex_overlay` gets/sets the map overlay (`nil` = get).

`chunkindex_reseed` walks `surface.get_chunks()` (all generated, not the index). **Default is missing-only** (no `orechunk` row). Already-indexed chunks are not re-queued. Full refresh is opt-in: `remote.call(..., "chunkindex_reseed", true)` / `"full"`, or `chunkindex_reseed_full`. Rebuilds `st.queued` from the live queue. Returns `{enabled, mode, surfaces, generated, indexed, missing, enqueued, enqueued_missing, enqueued_refresh}`.

`seed_existing` / player-enter / surface-change also enqueue **missing-only**. After 100% coverage there is no automatic full-map re-chew.

### Cadence (low script cost; hours-long first pass is OK)

Daikael’s tester map is **~200×200 chunks** (~40k generated), not tiles. Prefer cheap idle over fast coverage.

| Knob | Default | Why |
| --- | --- | --- |
| `BUDGET_PER_TICK` | **1** | One `find_entities_filtered` 32×32 classify when a scan tick fires. Do not raise this for normal play. |
| `SCAN_INTERVAL_TICKS` | **10** | Not every tick. 1 chunk / 10 ticks @ 60 UPS. |
| Border requeue | **36000** (10 min) | True Tib-neighbor borders only. **Skipped while the queue is draining.** |
| Harvester requeue | **10800** (3 min) | Chunks under tracked trucks only. **Skipped while the queue is draining.** |

Expected first-pass wall time at 60 UPS: **N generated missing chunks × 10 / 60 seconds**. For ~40k: **40000 × 10 / 60 ≈ 6667 s ≈ 1.85 hours**. A 10-second “pass” at this cadence is only ~60 classify calls — that is a missing subset (or an old every-tick / full-refresh chew), not 40k @ 1/tick.

His F4 ~3.84 / 0.344 / 11.278 ms was the old every-tick full-map classify plus a full overlay walk every 30 ticks. Steady state after coverage is idle (queue empty) plus dirty overlay only.

### Map overlay (M1 debug)

Toggle like pollution: **Alt+I**, or the shortcut-bar **Chunk index overlay** button (harvester icon). Persists in `storage.chunkindex.overlay`. Available while **Automatic harvester testing** is on. Off destroys every overlay render object.

Semi-transparent **map / minimap** rectangles (`render_mode` `chart` only). They do **not** draw on the world surface. Toggle-on does one full build; after that the overlay is **dirty/incremental** (scanned chunk + Tib neighbors + harvester moves). A rare idle reconcile (10 min, queue empty only) is a safety net — a first-pass chew never full-walks the index for draw. Camera radius is not a cull; panning does not drop already-drawn indexed chunks. Uncharted fog and **unscanned** chunks stay blank. Empty-scanned purple is **dim** on purpose.

If the index is behind generated chunks, missing-only reseed then wait for the 1-per-10-tick drain:

```
/c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed')))
/c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed', true)))
```

| Color | Meaning |
| --- | --- |
| **Green** | Tiberium (`storage.tibchunk` true) |
| **Orange** | Tib-proximity border (`storage.chunkindex.border` count > 0) **and** non-empty ore |
| **Yellow** | Tracked harvester on the chunk, or empty/no-ore Tib-border watch |
| **Red** | Ore (`storage.orechunk` with `empty ~= true`), not a Tib border |
| **Purple** | Empty scanned chunk, not border-flagged |
| **Blank** | Not indexed yet |

Priority if several match: **green → orange → yellow → red → purple**. Harvester-on-ore stays yellow (Tib-border + ore is the mix that becomes orange).

**Blink** (~3.75 Hz cyan/white outline pulse) marks the chunk `ChunkIndex.tick` is scanning this budget tick (`storage.chunkindex.scan`). Idle (`queued = 0` / no pop this tick) blinks nothing. The active scan target may blink even if it has no classification yet.

```
/c remote.call("Red-Alert-Harvester", "chunkindex_overlay", true)
/c game.print(tostring(remote.call("Red-Alert-Harvester", "chunkindex_overlay")))
```

Build a **map index** of already-generated chunks. Budget: **one chunk per scan tick**, and scan ticks fire every **`SCAN_INTERVAL_TICKS` (10)**. Do not scan the whole surface in one tick. Do not generate new chunks to look for ore.

### Classify each scanned chunk

- **Ores:** log resource entities / types present (vanilla solids + any other mineable solids we care about). This is the answer to “what ores exist where.”
- **Empty:** note the chunk as empty (no tracked resources).
- **Tiberium:** flag the chunk if Tib is present.

### Tiberium border-rescan (refcount)

Empty chunks that **neighbor** a Tib chunk are not “done.” They get a **border-rescan** so spread / new nodes are noticed.

- Neighbor interest is **refcounted**, not a boolean. Several Tib sources can mark the same empty neighbor. Safe with multiple fields.
- When a Tib chunk **depletes**, decrement the neighbor flags it was holding. A neighbor drops off the rescan set only when the count hits zero.
- Do not treat “one Tib node gone” as “whole neighborhood idle” if another Tib chunk still borders it.

### Depletion rescans

Chunks that have an **active harvester** on them get **periodic depletion rescans** (the index must notice a patch that was mined out). Tib depletion is what drives the neighbor-flag decrement above.

### What M1 does *not* do

- The index can land **without moving any trucks**. Driving is step 3 (landed on this branch, same gate).
- Do **not** send miners to patches (or home) with `vehicle.teleport` / heading-step fakes.

### Physical driving (step 3 — landed)

Deployed, fueled miners **physically drive** to ore patches and **physically drive** home.

**2.0.77 compat:** `LuaEntity.commandable` is nil on `type=car`. Autopilot fields are spidertron-only. Implementation is `surface.request_path` (the unit pathfinder, used with the **car** `collision_box` and `path_resolution_modifier = 0`) then `vehicle.riding_state`. A biter-sized box + coarse grid was tried and **reverted**: those waypoints do not fit a 2.8-wide car and exhausted `OnPathFail` on 2.0.77. `max_gap_size` stays 0. Prototype `collision_box` is centered at 0,0; car `collision_mask` **union** `cncharvester-peer`; `entity_to_ignore` = **self only**; `can_open_gates`; `allow_destroy_friendly_entities=false`. The unit pathfinder does **not** reliably treat other cars as obstacles, so each request may spawn hidden `cncharvester-path-blocker` simple-entities (4×4 tile box) on **local** sibling trucks (within 32 tiles of start or goal; never the whole surface) until the async path returns. Hitch helper `teleport` in `modulebay.lua` is **not** autonomy — it keeps the slave drill on the truck.

**Peer exclusion:** `PEER_EXCLUDE_TILES = 16` still claims a chunk another truck is assigned to (and not going home). Sitting exclusion is `PEER_SIT_TILES = 8` so adjacent chunks of one field do not all pile onto the same edge. Runtime: brake only when about to overlap (`PEER_RAM_TILES = 3.2`). A wider 4-tile ahead cone is a yield/peel hint, not a stuck fail. **Lowest `unit_number` in an 8-tile cluster peels** (reverse if the rear is clear, tank-turn if boxed, drive if not about to ram). Others wait and do **not** consume the stuck ladder. After a reverse peel, soft-repath the same dest (no `OnPathFail` / alerts). **`path_hits_peer` only rejects `needs_destroy_to_reach`.** A waypoint that passes near another truck is accepted — that 4-tile-any-sibling reject burned long home trips. Path blockers skip siblings within 6 tiles of the start (do not seal the cell) and skip anyone far from both start and goal.

**Turn in place:** cars have `tank_driving = true`. If yaw to the next waypoint exceeds `TURN_DEADZONE = 0.04` (~14°), AutoDrive writes `acceleration = nothing` (or `braking` when still rolling faster than `ALIGN_SPEED` with `TURN_HARD` yaw) plus left/right until aligned, then accelerates. It must not creep forward in a wide arc just to change heading when stopped or nearly stopped.

**Assignment range:** nearest indexed, filter-ok, peer-free chunk on this surface. `RANGE_TILES = 1e7` is an unlimited-distance sentinel — not an 8-chunk cap. After a successful scoop, `RANGE_NEAR_TILES = 96` is tried first, then the search expands. Accept any non-empty indexed chunk the truck can mine: ore truck skips Tib-only (mixed OK via iron/copper/etc.); `cncharvester-type2` may take Tib only if **Tiberium-Harvesting** is researched. No depot GUI.

**Trees:** while auto-driving (and before each `StartDrive`), `clear_nearby_trees` removes `type=tree` inside `TREE_CLEAR_RADIUS = 8` if it is touching or ahead. Wood goes to the trunk when there is room; otherwise the tree is **destroyed** so the hull can move. Not a forest-clearing wander.

**Refinery dock:** dump/approach offsets are **north** of the building (dump / belt / circuit face: collision to y=-3), not the south chest face. `PATH_RADIUS_HOME = 10`, `ARRIVE_HOME = 8`, `DOCK_ACCEPT_TILES = 8` so a truck ~7 tiles out still dumps/refuels. A pad holder within `DOCK_DUMP_TILES = 12` dumps immediately (no extra path). Home path fails rotate through `DOCK_OFFSETS` (north, west, east, south). `HOME_REPATH_MAX = 5`.

**Dump queue:** `FindingRefinery` **reserves before** `StartDrive`. Waiters stop and recheck; they toast `no-empty-refinery` only when every pad is **full** or missing — not when the pad is merely reserved. `IsOccupied` reclaims a leaked lock (reserved with no living holder). Non-holders abort if they wander onto an occupied pad. The pad holder has peel priority so queued trucks do not ram the dumper. Dump inserts if the chest is not full (no 21-empty-stack gate). UnReserve on dump-done / path-give-up / leave.

**Fuel-low:** `HybridDrive.potential_joules` below **8 MJ** (10% of the 80 MJ pool) → drive to a fueled refinery (`FindingRefuelRefinery` → `ApproachedForRefuel` → `Refueling`). On arrival the refinery chest transfers **convertible burnables** (coal/wood/chemical; not nuclear / hybrid-charge) into the vehicle fuel inventory until the tank is full (Ore Truck 2 slots, type-2 3 slots) or potential is ≥ 8 MJ. Then `convert_inventory_fuels` fills the hybrid pool to the 4 MJ working floor (leftover solids stay in the tank). Belt drop still withholds one fuel stack so inserters cannot empty the chest of truck fuel. No convertible fuel → toast `no-fuel-refinery` and try another refinery. Cargo full → drive to an unoccupied refinery. **Impact** damage is ignored (rocks). Other damage → drive home.

**Refinery circuit (not M2 depot):** the `refinery` container has Factorio **2.0** `circuit_connector` + `circuit_wire_max_distance` (vanilla default 9; container default is **0**, which blocks wires). Red/green wires connect on the north/dump face and **read chest contents** as item signals (vanilla container behavior — no extra read-mode flag). Use that to enable inserters when e.g. iron-ore < N. Depot GUI / spawn / filter circuit I/O is still M2.

#### Locked: stuck / path failure (implemented tunables)

1. **Repath** same target — `AutoDrive.REPATH_MAX = 3`. No-progress window: `STUCK_TICKS = 180` (~3 s) without `STUCK_MIN_MOVE = 0.75` tiles.
2. Abandon assignment, pick another in-range index chunk — `ALT_PATCH_MAX = 3`. Failed chunks excluded for `FAILED_CHUNK_TTL = 18000` (5 min).
3. **Drive home early** to the current refinery. Home repaths: `HOME_REPATH_MAX = 5` (alternate dock faces).
4. Still failing: **yellow** custom alert on the home refinery (depot placeholder) + **red** custom alert on the miner or the ore entity if still around. `force.print` + floating text. Cooldown `ALERT_COOLDOWN = 3600`. No teleport past the obstacle.

Pathfinder busy (`try_again_later`) retries after `BUSY_RETRY_TICKS = 30` and does not consume a repath.

#### Per-vehicle inventory toggles

Relative Factorio 2.0 GUI on the **left of the harvester car inventory** (`defines.relative_gui_type.car_gui`). Not a global startup setting. Hidden when **Automatic harvester testing** is off.

| Toggle | Default | Persist |
| --- | --- | --- |
| **Automatic operation** | **On** for tracked trucks (testers with the flag already on keep AI) | `storage.cncharvesters[].auto_enabled` |
| **Pause when somebody jumps in** | **Off** | `storage.cncharvesters[].pause_on_enter` |

| Auto | Pause on enter | Player |
| --- | --- | --- |
| OFF | either | Normal enter + drive |
| ON | ON | Can enter; AI yields and freezes assignment while occupied; resume on exit |
| ON | OFF (default) | Ride as **passenger**; AI drives with empty driver seat; WASD does nothing. Auto stays on. |

Behavior:

- **Auto off:** no FindingOre / path / riding AI. Manual drive works. Scoop / hitch / hybrid unchanged. Turning auto off while unmanned cancels the path and releases leftover AI accel once (does not brake every tick).
- **Auto on** + empty seat: current physical drive AI.
- **Auto on + pause off:** demote the driver to passenger every tick / on enter (`set_driver(nil)` then `set_passenger`). Do **not** `player.driving = false`. `riding_state` runs with an empty driver seat. A passenger must not cancel `StartDrive` / Tick pathing. If the prototype has no passenger seat, still clear driver so AI keeps the wheel (brief ground exit) and print that pause-on-enter or auto-off is required. Player input must **not** write `auto_enabled=false`.
- **Auto on + pause on:** player may sit as **driver**. Never write `riding_state` while they drive. Freeze assignment (cancel pending path). Resume / repath on exit if auto is still on.
- Checkbox writes: **`on_gui_click` only**, and only while the car inventory is genuinely open. Toggle feedback uses ~5 s floating text plus `player.print`.
- Ore assignment drives to a **resource entity** when `resource_in_chunk` finds one (tight path/arrive). If `MiningOre` is off-patch, short-range retarget (up to 3) then mark the chunk failed / `FindingOre`.
- **Do not write these fields in `on_load`.** Factorio CRC-checks `storage` and will refuse the save (`Detected modifications to the 'storage' table`). Missing keys mean auto ON / pause OFF until a later mutable event (tick / GUI) writes them. Empty + auto ON calls `KickAuto` (repath or `FindingOre` → `StartDrive`).

### Suggested storage shape (implementer hint, not frozen)

`storage.orechunk` / `storage.tibchunk` are the index tables (`surface_index` → `chunk_x` → `chunk_y`). Refcount neighbor flags live in `storage.chunkindex.border` / `tib_holds`. Exact keying is an implementation detail; the **refcount + border-rescan** rules above are not.

Wire `on_chunk_generated` (and surface create / first visit — see below) to **enqueue**, not to scan inline. The slow tick drains the queue.

---

## Surface / Tiberium scope

Factorio-Tiberium (**James-Fire**) world presence is **startup map-gen**, not slurry research. Tib can exist on a surface with **no** slurry / slurry-centrifuging tech.

### Tib startup flags (Factorio-Tiberium)

Read these from the Tib mod’s startup settings (names as shipped by James-Fire). Do not invent RAH copies.

**`tiberium-on`** (where Tib is allowed to generate):

| Space Age | Allowed values | Default |
| --- | --- | --- |
| **With** Space Age | `nauvis` \| `pure-nauvis` \| `tiber` \| `tiber-start` | **`tiber`** |
| **Without** Space Age | `nauvis` \| `pure-nauvis` only | (Tib’s own default; do not assume `tiber`) |

**Extra planet bools** (all **default false**):

- `tiberium-on-nauvis`
- `tiberium-on-vulcanus`
- `tiberium-on-gleba`
- `tiberium-on-fulgora`
- `tiberium-on-aquilo`
- `tiberium-on-all-other-planets`

**Slurry / slurry-centrifuging** does **not** gate Tib existence on a surface. Do not use those techs as a “is there Tib here?” check.

### Scanner enqueue rules

- **Enqueue surfaces** from Tib startup flags **plus** normal ore interest (vanilla / other solids). A Nauvis-only ore world still gets an index.
- **Tib-border work** (refcount neighbors, border-rescan) is keyed off **runtime Tib presence** and those **startup flags**, **not** research.
- **Skip** a planet when Tib **cannot spawn there** (flags say no) **and** the player has **not visited**. No point indexing a void we will never see.
- **Unvisited but eligible** surfaces: do **not** pre-scan empty void. Enqueue on **surface create** / **`chunk_generated`** / **first visit**, then drain with the slow scanner.
- **Do not gate the map index** on slurry research. The index may list Tib chunks the player cannot auto-mine yet.
- **Do gate auto-mining Tib** on **RAH’s own unlock**: Tiberium harvester tech (`Tiberium-Harvesting` in `prototypes/technology/technology.lua`) — prerequisites **Old World Harvesting** + **electric engines**. Ore trucks (`cncharvester`) must not be assigned Tib. Type-2 (`cncharvester-type2`) is the Tib miner.

---

## Milestone 2+ — Ore depot as AI config hub

Miners do **not** configure themselves. They depend on their **ore depot**.

The existing **refinery** (`refinery.lua`, entity `refinery`) is the dump / belt / (today) fuel chest. The **depot** is the AI config + spawn hub. Whether depot is a new entity, a refinery GUI mode, or a companion building is an open question — behavior below is locked.

### Spawn

While the depot still has supplies, it spawns **one** vehicle type with a **fixed** module list (including **quality**) and equipment loadout.

Example loadout (illustrative, not a recipe):

- Ore trucks
- 2× **uncommon** efficiency module 1
- 2× **common** personal solar panels
- 1× personal battery mk1

Spawned miners **stay tied** to that depot (home, filter, range, return target). They do not shop around for a different depot’s job.

### Return-home triggers

A tied miner returns to its depot when:

- **Nearly out of fuel / hybrid charge** (same energy model as `HybridDrive` / `harvester.lua` `CheckFuel` — pool + grid + burnables, not “empty tank slots”).
- **Cargo full.**
- **Non-collision damage** — biters, Tiberium, fire, etc. **Ignore bump / impact** (driving into rocks / other vehicles must not send the truck home).

The trip home is a **physical drive**, same as the outbound trip. Do not teleport to the depot on these triggers.

Path failure on the way home uses the same locked escalation (see **Locked: stuck / path failure**): repath to the depot first. There is no outbound assignment to swap if the truck is already going home; if repathing home keeps failing after that cycle, raise the yellow-depot / red-miner-or-approach alert. Do not teleport home.

### Ore filter (inserter-style)

| Rule | Behavior |
| --- | --- |
| Default mode | **Whitelist** |
| Toggle | Whitelist **or** blacklist |
| Slots | **5** filter slots |
| Empty whitelist | **Nothing** allowed |
| Empty blacklist | **Everything** allowed |

Same mental model as a vanilla filter inserter. Circuit signals must **align with the GUI mode** (whitelist signals in whitelist mode, blacklist signals in blacklist mode). Do not apply both lists at once.

### Circuit I/O on the depot

**Inputs**

- Ore whitelist / blacklist signals (same mode as the GUI).
- **Max travel range:** signal value → **tiles**.

**Outputs**

- Count of **active miners** tied to this depot.
- **Valid ore types within configured range** — patches that are in the **index**, pass the **filter**, and sit inside the **range**.
- **Inventory contents** of the depot.

### Who decides the job

```text
index  →  “what ores exist where” (M1)
depot  →  filter (GUI / circuit) + range + spawn loadout
miner  →  assigned patch, mine, return home on the triggers above
```

The truck no longer grows a random radius and hopes. `FindingOre` (later) asks the depot, and the depot asks the index. The miner then **drives** to the assigned patch and **drives** home.

---

## Non-goals (this 2.2.x line)

- **Do not merge** the Factorio 2.1 beta (`2.1.17` / PR #15) into this branch or into `master`.
- **Do not merge `2.2.0` to live `master` unprompted.** Dev-branch-first.
- No version bump / portal upload as part of a docs-only change.
- No rewrite of slave-miner / hitch / hybrid / scoop (`modulebay.lua`, `hybriddrive.lua`, `scoop.lua`) unless a later ticket says the depot spawn path requires it.
- Do **not** keep `vehicle.teleport` / `States.MovingToLocation` as the 2.2.x movement path, including as a temporary “index first, drive later” bridge. Once a fueled miner is sent to a patch or home, it must physically drive.
- No fluid mining (uranium + acid, etc.). Slave drill still has no fluid box.
- No pre-scan of unvisited / ineligible surfaces.
- Do not use Tib **slurry** tech as a surface or index gate.
- Do not revive `chunksearcher.lua`. The stub is gone; use `chunkindex.lua`.
- Do not implement depot / circuit / spawn loadout in this drop. Driving + `FindingOre` retarget is **landed** (step 3).

---

## Suggested implementation order

1. **M1 index** — queue + one-chunk-per-budget-tick classify; fill `orechunk` / `tibchunk` (or replacement); Tib refcount borders; depletion rescans on active-harvester chunks. Hidden behind the existing auto-test flag or a new debug flag until it is trustworthy. **No truck movement required in this step.**
2. **Surface policy** — enqueue from Tib flags + ore interest; skip unvisited-ineligible; hook surface create / `chunk_generated` / first visit.
3. **Physical driving + retarget `FindingOre`** — **landed** on `2.2.0`. `request_path` + `riding_state`. Index lookup is nearest indexed chunk (no 256-tile cap). Stuck escalation as locked. No depot yet.
4. **M2 depot** — entity/GUI, 5-slot filter + toggle, spawn-one-type + fixed modules/equipment, tie miners to depot, return-home triggers (drive back; same stuck escalation if the home path fails).
5. **Circuit I/O** — inputs (filter + range), outputs (miner count, in-range valid ores, inventory).
6. **Dual-track 2.1 sibling** — after the 2.0 line works, same split as 2.1.17 / 2.1.18.

---

## Open questions

Not blocking M1. Resolve before or during M2.

1. **Depot vs refinery.** New entity, extra GUI on `refinery`, or a placed “AI port” next to the dump? Today `refinery.lua` already owns reservation, dump offsets, fuel-in-chest, and belt drop. Spawning trucks from the same chest that holds fuel + ore may fight belt emptying (`DropOnBelt` already withholds one fuel stack).
2. **“Supplies” for spawn.** What does the depot consume to spawn a truck — the vehicle item, modules, equipment, or a dedicated “harvester order” item? The example loadout implies the depot must *have* those items (or a configured ghost list plus ingredients).
3. **How many live miners per depot.** “One vehicle **type**” is locked; concurrent count is not. Circuit output “active miners” implies more than one is allowed. Cap? Soft cap from supplies only?
4. **Tib vs ore depots.** One depot mode that refuses Tib unless the spawn type is `cncharvester-type2` and `Tiberium-Harvesting` is researched? Or separate depot prototypes?
5. **Range signal scale.** 1 signal = 1 tile is the written rule. Confirm overflow / negative / zero (zero = no assignments?).
6. **Circuit vs GUI when both set.** Vanilla inserters: circuit can set filters. Pick one: circuit overrides GUI, or GUI is the default and circuit replaces the 5 slots when a wire is connected.
7. **Chunk budget.** “One chunk per budget tick” — is the budget tick `on_nth_tick(1)` with a 1-chunk cap, or a slower nth-tick? UPS target on a fully explored Nauvis + Tib moon?
8. **`harvester-auto-by-default`.** Keep as “legacy per-truck AI without a depot,” or retire once depot ships?
9. **Damage-return details.** HP threshold vs any non-impact damage event? Do we interrupt a scoop mid-cycle? `on_entity_damaged` with `force` / `damage_type` filters (ignore `impact` / `physical` from collision)?
10. **Index persistence.** Full rebuild on `on_configuration_changed` vs migrate in place when Tib flags or resource prototypes change?

Stuck / path failure (former #11) is **locked** — see **Physical driving → Locked: stuck / path failure**. Retry counts / “no progress” windows stay implementer-tunable.

---

## File map (today)

| File | Role for 2.2.x |
| --- | --- |
| `control.lua` | `require "chunkindex"` / `autodrive` / `autopanel`. Seeds / ticks the scanner. When the testing flag is on, tracks trucks/refineries and calls `harvester:Tick()`. Path-finished + non-impact damage hooks. Relative auto-toggle GUI. Remote `harvester_ai`. |
| `harvester.lua` | State machine. `FindingOre` reads ChunkIndex (`PickIndexTarget`). `MovingToLocation` is physical AutoDrive. Per-truck `auto_enabled` / `pause_on_enter`. Teleport leftovers commented only. |
| `autodrive.lua` | `request_path` + car `collision_box` + `riding_state`. Peer reverse-wiggle, in-place turn, tree clear (mine or destroy), dock accept. |
| `autopanel.lua` | Left-of-inventory checkboxes. `on_gui_click` writes toggles while the car GUI is open; checked-state unchecks are ignored. |
| `harvesterstats.lua` | Dump / approach offsets still used. `MovementSpeed` / `RotationSpeed` are unused by AutoDrive. |
| `chunkindex.lua` | M1 slow index plus `find_ore_chunks` / `row_allows_vehicle` for FindingOre. Overlay dirty/incremental. |
| `refinery.lua` | Dump, reserve, fuel chest, belts. Home target until the M2 depot exists. |
| `settings.lua` | `Auto-cncharvester-testing` (startup; index + auto-drive gate), unused `harvester-auto-by-default`. Tib world flags live in **Factorio-Tiberium**, not here. |
| `prototypes/technology/technology.lua` | `Old-World-Harvesting` (ore truck + refinery). `Tiberium-Harvesting` (electric engines) — **auto-mine Tib gate**. |
| `specialOres.lua` | Resource entity name ≠ item name. Index stores item names. |
| `modulebay.lua` / `hybriddrive.lua` / `scoop.lua` | Unchanged except hitch still follows the truck. |
| `FACTORIO_2.0.md` / `FACTORIO_2.1.md` | Port notes. Not the autonomy design. |

---

## Success checks (when implementation PRs start)

Docs + M1 scanner are on branch `2.2.0`. Pack version is **2.2.0**.

M1 (landed):

- Generated chunks on visited, in-scope surfaces eventually appear in `storage.orechunk` / `storage.tibchunk`.
- Empty-next-to-Tib chunks keep a **refcount > 0** while any bordering Tib chunk exists; count drops on Tib deplete.
- Unvisited ineligible planets are never scanned. Eligible unvisited surfaces stay off the queue until create / chunk / visit.
- Slurry research does not change what the index lists. Type-2 tech still gates **auto-mining** Tib.
- UPS stays flat-ish on a large map: 1 classify / 10 ticks, no automatic full-map re-chew after coverage, overlay dirty-only after toggle-on.

Step 3 (landed):

- A deployed, fueled miner sent to a patch or home **drives** there (`request_path` + `riding_state`). No `vehicle.teleport` on that path. **Auto on + pause off:** rider is passenger; AI keeps the empty driver seat. **Pause-on-enter:** driver seat, AI yields. **Auto off:** normal drive. Enter / WASD / inventory must not clear `auto_enabled`. Uncheck Automatic operation in the open inventory to take the wheel.
- `FindingOre` uses ChunkIndex, nearest indexed first (96 tiles after a scoop, then the rest of the index). Drive to a harvestable **resource entity** when known, not only `chunk.center`. Off-patch `MiningOre` retargets in-chunk / nearby.
- Return-home (fuel / full / non-impact damage) is a physical drive to the **refinery**.
- Stuck / path failure escalates **repath (3) → other in-range patch (3) → drive home early (3 home repaths)**, then yellow/red global alerts. No teleport past the block.

Later (M2 depot — not this drop):

- Depot entity/GUI, 5-slot filter, spawn loadout, circuit I/O.
