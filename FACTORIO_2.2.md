# Red-Alert-Harvester 2.2.x — autonomy roadmap

Planning doc for pack **2.2.x**. Agreed with the maintainer (Daikael). This file is the locked design; implement against it, do not invent a parallel plan.

**M1 scanner has landed on this branch** (`chunkindex.lua`), gated and UPS-safe. Pack version is **2.2.0**. No physical driving, no depot / circuit I/O. Legacy teleport AI is commented out. Do not merge to `master` unprompted. Testers use the GitHub **prerelease** zip `Red-Alert-Harvester_2.2.0.zip` (tag `2.2.0`).

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

Startup flag **`Auto-cncharvester-testing`** (`settings.lua`) now enables **`ChunkIndex` only**. The per-truck teleport loop in `harvester.lua` is commented out (kept for reference). Manual drive / hitch / scoop / hybrid / refinery dump are unchanged.

What it actually does today:

- Each tracked vehicle (`storage.cncharvesters`) runs its own state machine (`FindingOre` → move → `MiningOre` → `FindingRefinery` → dump / refuel).
- Movement is **`vehicle.teleport`** along a heading (`States.MovingToLocation`). No pathfinder, no collision avoidance. **This is legacy test AI to replace, not keep.** 2.2.x autonomy must not reuse it — not even as a temporary M1 bridge.
- Ore pick is **local and random**: `FindRandomOreInRadius` / `FindOresInRadius` scan a growing box around the truck (`Stats.DefaultSearchRadius` = 15, then +5). Not a map index.
- Refineries are found by a full-surface `find_entities_filtered{name = "refinery"}` (`refinery.lua`).
- `chunksearcher.lua` (dead stub) is **deleted**. The index lives in `chunkindex.lua`.
- `storage.orechunk` / `storage.tibchunk` are the index home, written by the slow scanner when it is enabled.

`harvester-auto-by-default` exists but is unused by the runtime loop. Commented `Auto-cncharvester-Ragne` is not a design input — range in 2.2.x comes from the **depot** (GUI / circuit), not a startup int.

---

## Milestone 1 — Global slow chunk scanner

**Status (branch `2.2.0`):** implemented. Enable with startup **Automatic harvester testing** (`Auto-cncharvester-testing`; restart required). Default off. That flag runs the **index only** — the legacy teleport auto-harvester is commented out. `on_pre_chunk_deleted` / `on_chunk_deleted` forget the chunk (queue, ore/tib rows, Tib refcount unwind) so unloaded charted chunks do not leak or ghost-rescan.

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
| **Yellow** | Tracked harvester on the chunk, or Tib-proximity border (`storage.chunkindex.border` count > 0) |
| **Red** | Ore (`storage.orechunk` with `empty ~= true`) |
| **Purple** | Empty scanned chunk, not border-flagged |
| **Blank** | Not indexed yet |

Priority if several match: **green → yellow → red → purple**.

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

- The index can land **without moving any trucks**. Do not block the scanner on driving code.
- Do **not** retarget `FindingOre` at the index in the same drop unless driving is already real. Planned **later**: `FindingOre` reads the index instead of growing a local random radius — and then **drives** to the assigned patch.
- Do **not** send miners to patches (or home) with `vehicle.teleport` / `States.MovingToLocation`. Teleport is not an M1 stand-in.

### Physical driving (locked, once trucks move)

Deployed, fueled miners must **physically drive** to ore patches and **physically drive** home. Teleport movement is **not acceptable** for 2.2.x autonomy.

- Prefer Factorio **pathfinder** / **`commandable`** / autopilot-style movement over scripted teleports or heading-step hacks.
- Handle **collision** (other vehicles, buildings, cliffs, trees). Driving into a rock must not count as a *return-home trigger* (see M2), but the truck still has to steer around it.
- **Return-home** uses the same physical drive — fuel / cargo-full / non-collision damage still mean “drive back to the depot,” not “snap there.”

#### Locked: stuck / path failure

When pathfinding fails, or the truck **stops making progress** toward an assigned patch (or home), escalate **in this order**:

1. **Repath** — retry pathfinding to the **same** target.
2. If that keeps failing: **abandon the assignment** and pick **another in-range** patch that still passes the depot filter / index.
3. If that keeps failing: **drive home early** to the depot.

Do **not** teleport past the obstacle at any step.

How many repaths, how long “no progress” lasts, and how many failed alternate patches count as “keeps failing” are **implementer-tunable**. This doc does not freeze retry counts or cooldowns.

**Repeated failures** after cycling that escalation: raise a **global alert** in the same spirit as Factorio’s entity-damaged / entity-destroyed notifications (map alert / console-style player attention). Not a silent log.

Alert coloring / pins (Daikael):

- **Yellow** on the **erroring depot** — the AI hub that owns the stuck miner.
- **Red** on the **erroring deposit** — the problematic **ore deposit / patch** the miner could not reach (the assignment target), **not** a second building type. If the failure is on the **home trip** with no ore target, red can pin the **miner** or the **blocked approach**; prefer the ore deposit when an outbound assignment is the cause.

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
- Do not implement depot / driving / `FindingOre` retarget in the M1 scanner drop.

---

## Suggested implementation order

1. **M1 index** — queue + one-chunk-per-budget-tick classify; fill `orechunk` / `tibchunk` (or replacement); Tib refcount borders; depletion rescans on active-harvester chunks. Hidden behind the existing auto-test flag or a new debug flag until it is trustworthy. **No truck movement required in this step.**
2. **Surface policy** — enqueue from Tib flags + ore interest; skip unvisited-ineligible; hook surface create / `chunk_generated` / first visit.
3. **Physical driving + retarget `FindingOre`** — any autonomy that sends a deployed, fueled truck to a patch (or home) uses Factorio pathfinder / `commandable` / autopilot-style driving. Collision handling and the locked stuck / path-failure escalation (repath → other in-range patch → drive home early; then yellow/red global alert) land with that movement, not later. Prove the index + real driving beat `FindRandomOreInRadius` + teleport before building the depot.
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
| `control.lua` | `require "chunkindex"`. Seeds / ticks the scanner. Registers `remote` `Red-Alert-Harvester` (`chunkindex_stats` / `chunkindex_enabled` / `chunkindex_overlay` / `chunkindex_reseed` / `chunkindex_reseed_full`). Alt+I / shortcut toggles the map overlay. Hooks built/removed for `cncharvester` / `cncharvester-type2` / `refinery`. |
| `harvester.lua` | Per-truck state machine. `FindingOre` / `FindRandomOreInRadius` is the retarget point. `States.MovingToLocation` + `vehicle.teleport` is **legacy test AI to delete**, not a movement API to keep. Fuel / full already mean “go home” — depot return-home keeps those *triggers*, but the trip must be a real drive. |
| `harvesterstats.lua` | Local search radii (`DefaultSearchRadius`, `CloseMineSearchRadius`) become obsolete once the index + depot range exist. `MovementSpeed` / `RotationSpeed` are teleport-step leftovers; dump / approach offsets may still matter at the depot pad. |
| `refinery.lua` | Dump, reserve, fuel chest, belts. Not an index. Candidate to grow a depot GUI **or** stay dump-only. |
| `chunkindex.lua` | M1 slow index. Queue + 1-chunk-per-10-tick classify, Tib refcount borders, harvester depletion requeue. Chart overlay (dirty/incremental) + scan blink. No `basic-solid-tiberium` string. |
| `settings.lua` | `Auto-cncharvester-testing` (startup; the only M1 gate), unused `harvester-auto-by-default`. Tib world flags live in **Factorio-Tiberium**, not here. |
| `prototypes/technology/technology.lua` | `Old-World-Harvesting` (ore truck + refinery). `Tiberium-Harvesting` (electric engines) — **auto-mine Tib gate**. |
| `specialOres.lua` | Resource entity name ≠ item name. Index should store something the depot filter and circuit can name (item, not only entity). |
| `modulebay.lua` / `hybriddrive.lua` / `scoop.lua` | Unchanged for M1. Depot spawn must apply the **fixed** module list + equipment to the same slave-drill / grid those files own. |
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

Later autonomy PRs (not this docs PR):

- A deployed, fueled miner sent to a patch or home **drives** there (pathfinder / `commandable` / autopilot). No `vehicle.teleport` on that path.
- Return-home (fuel / full / non-collision damage) is a physical drive back.
- Stuck / path failure escalates **repath → abandon + other in-range filtered patch → drive home early**, in that order. After cycling that without progress: **global alert** (yellow on the owning depot; red on the unreachable ore deposit, or miner / blocked approach on a home trip with no ore target). Not a silent log. No teleport past the block.
