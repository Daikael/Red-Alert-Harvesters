# Red-Alert-Harvester 2.2.x — autonomy roadmap

Planning doc for pack **2.2.x**. Agreed with the maintainer (Daikael). This file is the locked design; implement against it, do not invent a parallel plan.

**This PR is documentation only.** Do not bump `info.json`, do not implement the scanner or depot in this change.

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

`info.json` on this branch stays **2.1.18** until a later implementation PR is told to bump. Factorio only accepts three-part versions; the first shipping autonomy pack will be something like `2.2.0`, not a rename of 2.1.18.

## Current auto AI (what we are replacing)

Startup flag **`Auto-cncharvester-testing`** (`settings.lua`) turns on a **per-truck** loop in `harvester.lua`, ticked from `control.lua` when the flag is on.

What it actually does today:

- Each tracked vehicle (`storage.cncharvesters`) runs its own state machine (`FindingOre` → move → `MiningOre` → `FindingRefinery` → dump / refuel).
- Movement is **`vehicle.teleport`** along a heading (`States.MovingToLocation`). No pathfinder, no collision avoidance.
- Ore pick is **local and random**: `FindRandomOreInRadius` / `FindOresInRadius` scan a growing box around the truck (`Stats.DefaultSearchRadius` = 15, then +5). Not a map index.
- Refineries are found by a full-surface `find_entities_filtered{name = "refinery"}` (`refinery.lua`).
- `chunksearcher.lua` is a **dead stub** (`Surface.lookup` / `Surface.find_all_entities` / `Surface.tiberium`). It is `require`d from `control.lua` but never called. The `blah` area filter is leftover junk. Do not “finish” this file as-is; replace or rewrite.
- `storage.orechunk` and `storage.tibchunk` are allocated in `control.lua` `ensure_storage()` and **never written or read**.

`harvester-auto-by-default` exists but is unused by the runtime loop. Commented `Auto-cncharvester-Ragne` is not a design input — range in 2.2.x comes from the **depot** (GUI / circuit), not a startup int.

---

## Milestone 1 — Global slow chunk scanner

Build a **map index** of already-generated chunks. Budget: about **one chunk per budget tick** (slow, UPS-safe). Do not scan the whole surface in one tick. Do not generate new chunks to look for ore.

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

- Do **not** retarget `FindingOre` at the index in the same drop unless that work is already cheap and obviously correct. Planned **later**: `FindingOre` reads the index instead of growing a local random radius.
- **Pathfinding is later polish.** Teleport movement can stay until a follow-up. Do not block the index on a pathfinder.

### Suggested storage shape (implementer hint, not frozen)

Keep using (or replace) `storage.orechunk` / `storage.tibchunk` as the index tables. Today they are unused placeholders — that is the intended home, not a reason to leave them empty. Exact keying (`surface_index` → `chunk_x` → `chunk_y`, plus a refcount side table) is an implementation detail; the **refcount + border-rescan** rules above are not.

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

The truck no longer grows a random radius and hopes. `FindingOre` (later) asks the depot, and the depot asks the index.

---

## Non-goals (this 2.2.x line)

- **Do not merge** the Factorio 2.1 beta (`2.1.17` / PR #15) into this branch or into `master`.
- **Do not merge `2.2.0` to live `master` unprompted.** Dev-branch-first.
- No version bump / portal upload as part of a docs-only change.
- No rewrite of slave-miner / hitch / hybrid / scoop (`modulebay.lua`, `hybriddrive.lua`, `scoop.lua`) unless a later ticket says the depot spawn path requires it.
- No pathfinder in M1. Teleport AI can stay until polish.
- No fluid mining (uranium + acid, etc.). Slave drill still has no fluid box.
- No pre-scan of unvisited / ineligible surfaces.
- Do not use Tib **slurry** tech as a surface or index gate.
- Do not treat `chunksearcher.lua` as salvageable API — it is a stub.
- Do not implement scanner or depot code in the docs PR that lands this file.

---

## Suggested implementation order

1. **M1 index** — queue + one-chunk-per-budget-tick classify; fill `orechunk` / `tibchunk` (or replacement); Tib refcount borders; depletion rescans on active-harvester chunks. Hidden behind the existing auto-test flag or a new debug flag until it is trustworthy.
2. **Surface policy** — enqueue from Tib flags + ore interest; skip unvisited-ineligible; hook surface create / `chunk_generated` / first visit.
3. **Retarget `FindingOre`** at the index (still per-truck, still teleport). Prove the index is better than `FindRandomOreInRadius` before building the depot.
4. **M2 depot** — entity/GUI, 5-slot filter + toggle, spawn-one-type + fixed modules/equipment, tie miners to depot, return-home triggers.
5. **Circuit I/O** — inputs (filter + range), outputs (miner count, in-range valid ores, inventory).
6. **Pathfinding polish** — last.
7. **Dual-track 2.1 sibling** — after the 2.0 line works, same split as 2.1.17 / 2.1.18.

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

---

## File map (today)

| File | Role for 2.2.x |
| --- | --- |
| `control.lua` | `require "chunksearcher"` (unused). Allocates `storage.orechunk` / `storage.tibchunk`. Ticks auto AI when `Auto-cncharvester-testing`. Hooks built/removed for `cncharvester` / `cncharvester-type2` / `refinery`. Natural place for chunk-queue drain + surface events. |
| `harvester.lua` | Per-truck state machine. `FindingOre` / `FindRandomOreInRadius` is the retarget point. `teleport` movement. Fuel / full already send the truck to a refinery — depot return-home should reuse this shape. |
| `harvesterstats.lua` | Local search radii (`DefaultSearchRadius`, `CloseMineSearchRadius`) become obsolete once the index + depot range exist. Movement / dump offsets stay until pathfinding. |
| `refinery.lua` | Dump, reserve, fuel chest, belts. Not an index. Candidate to grow a depot GUI **or** stay dump-only. |
| `chunksearcher.lua` | Dead stub. Replace or delete when M1 lands. Do not hard-code `basic-solid-tiberium` (see `test_2_1_features.lua`). |
| `settings.lua` | `Auto-cncharvester-testing`, unused `harvester-auto-by-default`. Tib world flags live in **Factorio-Tiberium**, not here. |
| `prototypes/technology/technology.lua` | `Old-World-Harvesting` (ore truck + refinery). `Tiberium-Harvesting` (electric engines) — **auto-mine Tib gate**. |
| `specialOres.lua` | Resource entity name ≠ item name. Index should store something the depot filter and circuit can name (item, not only entity). |
| `modulebay.lua` / `hybriddrive.lua` / `scoop.lua` | Unchanged for M1. Depot spawn must apply the **fixed** module list + equipment to the same slave-drill / grid those files own. |
| `FACTORIO_2.0.md` / `FACTORIO_2.1.md` | Port notes. Not the autonomy design. |

---

## Success checks (when implementation PRs start)

Docs PR (this file): branch `2.2.0`, file present, draft PR to `master`, no gameplay / version edits.

Later M1 PR (not this one):

- Generated chunks on visited, in-scope surfaces eventually appear in the index.
- Empty-next-to-Tib chunks keep a **refcount > 0** while any bordering Tib chunk exists; count drops on Tib deplete.
- Unvisited ineligible planets are never scanned. Eligible unvisited surfaces stay off the queue until create / chunk / visit.
- Slurry research does not change what the index lists. Type-2 tech still gates **auto-mining** Tib.
- UPS stays flat-ish on a large map (queue drain, not a full `get_chunks()` sweep per tick).
