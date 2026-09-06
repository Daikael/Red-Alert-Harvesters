# Factorio 2.1 development line

This branch is the **2.1 experimental/beta** target for C&C Harvesters. It is **not** the 2.0 stable pack.

## Branch base

- Branched from `cursor/factorio-2.0-compat-98d9` at `c765378`, then **merged `master`** after PR #3 landed (2.0 tester UX/install fixes).
- Do **not** merge this 2.1 line back to live/`master`.
- Tester-facing git branch is the three-part version (`2.1.17`). Mod `info.json` name is plural **`Red-Alert-Harvesters`**. Pack folder is **`Red-Alert-Harvesters_2.1.17`**. GitHub archive folder is `Red-Alert-Harvesters-2.1.17` (hyphen); rename to underscore before install. `factorio_version` is **`2.1`**.
- **Bump by renaming in place** (`2.1.17` → `2.1.18`): `git branch -m`, push the new name, delete the old remote. Do not leave the previous version branch as a parallel head. Prefer retargeting the open draft PR; if GitHub cannot retarget, open a new draft, close the old PR with a pointer, and still delete the old branch.

## Packaging

| Field | 2.0 line (PR #3) | 2.1 line (this branch) |
| --- | --- | --- |
| `info.json` `name` | `Red-Alert-Harvester` | `Red-Alert-Harvesters` |
| `info.json` `version` | `2.0.0` | `2.1.17` |
| `factorio_version` | `2.0` | `2.1` |
| `base` | `>= 2.0.0` | `>= 2.1.0` |
| optional `Factorio-Tiberium` | `>= 2.0.0` | `>= 2.1.0` |

## Ported from 2.0 (`master` / PR #3)

- README zip name: `Red-Alert-Harvesters_<version>` matching plural `info.json` `name` (2.1 experimental). The 2.0 line on `master` still uses singular `Red-Alert-Harvester`.
- Drive mining no-module baseline is **1.50 / 3.00 items/s** (same average as the old 8 / 16 per 320 ticks). 2.1.12 runs that through the slave miner.
- Inventory-full / blocked-harvest toasts: locale keys (`cncharvester.inventory-full` and related), `FLOATING_TEXT_ERROR_RED`, 150 tick TTL. Greens unchanged.

## Feature 1 — Slave miner (native modules)

`CarPrototype` has **no** `module_slots`. Modules live on a **slave mining-drill** hitch that is teleported with the truck. Through 2.1.11 that drill was a dummy (`cncharvester-module-bay` resource category, void energy) and the script inserted ore — so **productivity did not use Factorio’s bonus-production bar**.

2.1.12 runs harvest **through that drill**:

| Vehicle | Drill | Slots | mining_speed | energy_usage | Search radius |
| --- | --- | --- | --- | --- | --- |
| `cncharvester` | `cncharvester-module-bay` | 2 | **1.5** (~1.50/s) | **180 kW** | 2.5 |
| `cncharvester-type2` | `cncharvester-type2-module-bay` | 3 | **3.0** (~3.00/s) | **360 kW** | 3.5 |

`180 kW / 1.5 s⁻¹ = 120 kJ/item` (same 2.1.11 tax). Tiberium is the same tax at 3/s. **No-module baseline cadence is unchanged.** Speed / efficiency / quality / pollution / productivity then apply **natively**. Intentional shifts when modules are installed: prod bonus items from the drill prod bar; efficiency lowers `energy_usage` (20% floor); speed raises rate **and** consumption. Force mining-productivity research also applies (native drill). Vehicle quality is **not** copied onto the bay (slots stay 2 / 3; legendary trucks do not get vanilla +150% machine speed).

### Architecture

1. **Slave drill** — `resource_categories = {"basic-solid"}` only in the prototype (vanilla always has that). **Do not** list `basic-solid-tiberium` unless that category exists — 2.1.12 failed assignID on Deck without Factorio-Tiberium. `data-final-fixes.lua` adds real Tiberium categories to the **type-2** bay only when `data.raw["resource-category"][name]` exists, and strips them from the Ore Truck bay. This pack does not invent a fake Tiberium resource-category. Electric energy source so the vanilla mining-drill GUI shows an **energy use bar**.
2. **Private micro-grid** — `cncharvester-drill-pole` (`maximum_wire_distance = 0`) + `cncharvester-drill-supply` EEI. Both (and the hopper) are **world-invisible**: deepcopy vanilla prototypes, then replace pictures/lights/shadows with `util.empty_sprite()` (`__core__/graphics/empty.png`, 1×1, `x=0`, `y=0`, `direction_count=1`). Do **not** use `graphics/entity/transparent.png` with `direction_count=4` — 2.1.15 crashed AtlasBuilder (`left_top=256x0` outside the 256×256 sheet). Helpers are `selectable_in_game = false`, empty selection box, `hide-alt-info`. They still energize the slave drill. Script sets `power_production` from the hybrid pool after pay-first (`disabled_by_script` / EEI cut — never write `LuaEntity.active`).
3. **Hopper** — invisible `cncharvester-scoop-hopper`. `drop_target` is set to the hopper; contents are moved into the car trunk each tick (including native prod extras). The slave-drill stays **selectable** (SHIFT+E / click) for modules + energy bar but uses empty world graphics — 2.1.16 left `harv_icon.png` at shift `{0.85, 0.85}` on both trucks.
4. **Pay / gate** — `ModuleBay.feed_energy` spends `estimated_draw_w / 60` from the hybrid pool (pool + 90% grid + convertible solids) **before** energizing the micro-grid. Empty / spark-only pool → starve (EEI `power_production` 0, drill energy 0, `disabled_by_script` when present). **Do not write `LuaEntity.active`** — it is read-only in Factorio 2.1 and crashed 2.1.13 `on_nth_tick`. First sit still waits **40 / 20 ticks**.
5. **UI** — SHIFT+E / click the truck opens the drill (modules + vanilla energy bar). A relative GUI also shows **Hybrid mining draw** in kW so efficiency vs speed is obvious.
6. **Toasts** — inventory-full / OOF are throttled to one per 150 ticks per truck.

`Scoop.harvest_area` remains as a unit-test pay-and-insert stand-in. Drive and auto call `Scoop.tick_slave` only.

### Layer A — entity quality (scripted radius gate only)

The enable-gate still uses `vehicle.quality` for **search radius** (+0.25/level). The slave miner is created at **normal** quality so baseline speed stays 1.5 / 3.0 and slots stay 2 / 3. Native resource drain is therefore normal-quality (100%). Documented tradeoff vs 2.1.11’s scripted 1/6 drain table — do not pass vehicle quality onto the bay or vanilla quality speed would jump legendary trucks to 2.5×.

### Layer B — module bay (unchanged slot rules)

- `allowed_effects`: speed, productivity, consumption, pollution, quality.
- **Slot count does not scale with quality.** `quality_affects_module_slots = false`.
- Not minable / not destructible / not blueprintable / empty collision mask.
- Teleported with the truck (mining_progress / bonus_mining_progress restored after teleport); destroyed on truck mine/death (modules go to the mine buffer or trunk). Helpers (pole / supply / hopper) die with it.
- Orphans are reaped on `on_configuration_changed`.

### Harvest tax numbers (no modules)

Same 120 kJ/item as 2.1.11. With modules, native drill math wins (efficiency cheaper, speed more draw and faster).

| Mine | Cadence | No modules | 2× efficiency-3 (−80%) | vs 1 solid fuel |
| --- | --- | --- | --- | --- |
| 1 item | ~40 / 20 ticks | **120 kJ** | **24 kJ** (native 20% floor) | ~100 items |
| Ore Truck 5.33 s | 8 items | **960 kJ** | 192 kJ | ~12.5 windows |
| Tiberium 5.33 s | 16 items | **1.92 MJ** | 384 kJ | ~6.25 windows |

`can_afford` counts pool + 90% of stored grid energy + convertible tank solids. `spend` pulls from the pool, then from stored grid if needed. Out of fuel only when that sum cannot cover the tick. Trunk-full starves the drill (hopper stops transferring).

## Feature 2 — Hybrid energy pool

Solar panel + battery are **recipe ingredients** of the Ore Truck / Tiberium harvester (1 each). They are **consumed at craft**, not placed into the module bay or equipment grid. New trucks spawn with an **empty grid** and **empty module bay**. Those ingredients grant a **built-in recharge** (`INTRINSIC_SOLAR_W` = 18 kW, +20% per quality level, efficiency modules boost). That trickle is not removable equipment. Legendary + efficiency should idle-charge clearly faster than a normal empty truck.

Hybrid also converts **actual stored electric energy** from player-installed **vanilla** portable solar/batteries (or any grid equipment) at the per-tick rate cap. A **charged grid can pay a scoop** by draining stored energy into the pool (90%); a token leftover still cannot. The deprecated Hybrid-drive / Hybrid-drive-battery items were **removed** in 2.1.10.

Common equipment grids are **2×2** (Ore Truck) and **3×3** (Tiberium). Quality does not enlarge those baselines.

**Recycler exploit (blocked):** place → strip gifted solar/battery/modules → recycle the truck for a full ingredient refund + the stripped loot. Nothing removable is script-inserted on place (`HybridDrive.on_built` / `ModuleBay.create`). Recycling the vehicle item may return the recipe’s solar+battery (vanilla recycle of craft cost) — that is fair, not a duplicate gift.

Every tick, `HybridDrive.maintain` then `tick`:

1. Strip nuclear-tier **items** from the fuel inventory. If `currently_burning` is nuclear-fuel / uranium-fuel-cell / fusion-power-cell, wipe remaining and lock to hybrid-charge.
2. Convert chemical fuels (coal, wood, solid fuel, …) **on demand**: consume items until the pool reaches a 4 MJ working floor (or the scoop/spend target). Leftover tank stacks stay in the tank. Cap **80 MJ**.
3. `currently_burning` is **always** hidden `cncharvester-hybrid-charge` (`fuel_category` `cncharvester-hybrid`). Writing it fills remaining to 80 MJ; `lock_charge` immediately writes the intended remaining. This is what stopped Factorio latching `nuclear-fuel` (empty-looking bar, still driving).
4. `has_usable_energy` is true when the pool, stored grid energy, or convertible tank solids can run the truck. Empty solid slots are OK. `enforce_empty` only zeros speed when none of those can supply energy. Scoops use `can_afford` / `spend` (pool + 90% stored grid).
5. Per-tick: moving grid pull stays 10% below drive. Parked grid/battery pull is **6×** that so a charged battery visibly climbs the 80 MJ bar. Intrinsic solar stacks on top while parked. Electric refill can fill up to the **80 MJ** pool (the old 4 s / 300 kJ cap hid the bar). Never shrinks an existing pool and never inserts items.
6. On mine, clear `currently_burning` and strip charge/nuclear from the mine buffer.

Vehicle `fuel_categories` are `cncharvester-hybrid` then `chemical` so the tank still accepts coal, but the engine’s burn identity is only hybrid-charge.

**Quality** (entity quality, not module slots): moving refill rate +1.5% per level. Moving refill stays below driving draw at every quality. Electric add cap is the 80 MJ pool. Module bay stays **2 / 3** slots (`quality_affects_module_slots = false`).

### Kickoff fuel (2.1.5 — hybrid pool only)

2.1.3 inserted free coal/wood. 2.1.4 could latch nuclear-fuel after the spark drained.

On player-built: consume **1** coal (else wood) from the placer and **convert those joules into the hybrid pool**. The item is not left in the tank and is not `currently_burning`.

Otherwise (no coal/wood, or robot/script/clone): **2 kJ spark** of hybrid-charge.

| Source | Energy | Notes |
| --- | --- | --- |
| Empty-tank spark | **2 kJ** | Hybrid-charge identity; sliver on an 80 MJ bar |
| Moving grid refill | 68 / 80 kW | 10% below drive; sustained drive still net-drains |
| Parked battery/grid refill | ~409 / 477 kW | 6× moving pull; charged battery climbs the bar |
| 1 coal converted | 4 MJ | Converted when the pool is below the 4 MJ floor |
| Pool / electric cap | 80 MJ | 20× coal; hidden item `fuel_value` |

Empty / insufficient pool = cannot drive or scoop until the player inserts burnable fuel (converted) or the pool is recharged (intrinsic trickle and/or player-installed grid). The 2 kJ spark does not grant a mining tick.

### Numbers

Prototype `consumption` is 150 kW / 175 kW with `effectivity = 2`. Actual burner draw ≈ consumption / effectivity:

| | Ore Truck | Tiberium harvester |
| --- | --- | --- |
| Prototype consumption | 150 kW | 175 kW |
| Driving draw (consumption / 2) | **75.0 kW** | **87.5 kW** |
| Max electric→burner refill | 68.18 kW (10% below draw) | 79.55 kW |
| Grid pull (90% conversion) | 75.76 kW | 88.38 kW |
| Intrinsic solar (baked-in, normal) | **18.0 kW** | **18.0 kW** |
| Parked battery/grid refill | **~409 kW** | **~477 kW** |

Sustained full-throttle driving therefore net-drains ~6.8 / 8.0 kW on a **normal** truck even with a charged grid. Parked with a charged battery, the hybrid bar should rise by several MJ over a few seconds. Quality raises moving refill slightly (+1.5%/level). Idle charge is no longer stuck at a 300 kJ sliver.

| Quality | Moving refill vs normal |
| --- | --- |
| 0 normal | 1.00× |
| 1 uncommon | 1.015× |
| 2 rare | 1.030× |
| 3 epic | 1.045× |
| 5 legendary | 1.075× |

## How to test (Factorio 2.1 experimental)

This environment has **no Factorio client**. Static checks: `luac -p` and `lua test_2_1_features.lua`.

1. Install as **`Red-Alert-Harvesters_2.1.17`** (plural `info.json` name — see README). If you downloaded a GitHub archive, rename `Red-Alert-Harvesters-2.1.17` → `Red-Alert-Harvesters_2.1.17`. Confirm `factorio_version` is **2.1** and the Mods list loads on a 2.1 client **with and without** Factorio-Tiberium (2.1.12 assignID crash; 2.1.15 AtlasBuilder `transparent.png` left_top=256x0). Loading a 2.1.12-migrated save must not crash `on_nth_tick` (2.1.13 wrote read-only `LuaEntity.active`). Driving must not show a moving pole/accumulator/chest **or** a floating ore-truck icon square (2.1.16 hitch). Inventory-full / blocked-harvest / refuel toasts are locale keys (en), same red/150-tick error style as before.
2. **No free scoop on place:** Place a truck with empty fuel on ore. First sit must **not** dump 100 (Ore Truck) / 80 (type-2) ore. Feedback is localized **Out of fuel** only.
3. **Slave-miner baseline + tax:** No modules → ~1.50 / ~3.00 items/s. A 2 kJ spark cannot keep the drill fed (180 kW ore / 360 kW tib). First sit waits 40 / 20 ticks.
4. **Kickoff / nuclear latch:** Place with coal — lose 1 coal; tank slots empty; bar shows **Hybrid charge** (~4 MJ / 80 MJ), never a raw key, never nuclear. Place with no coal/wood — 2 kJ sliver. Drain completely — cannot drive or mine; bar stays empty (no nuclear flip). Insert coal — pool increases, identity stays hybrid-charge. Mine: no free charge/nuclear loot.
5. **Intrinsic solar + battery:** Fresh truck, empty grid — parked pool climbs slowly from the baked-in 18 kW trickle. Install a charged portable battery: the hybrid bar should rise clearly (several MJ in a few seconds). Recipe still costs solar+battery. Sustained driving+mining still net-drains.
6. **Slave miner GUI:** Place an Ore Truck. No floating hitch icon. SHIFT+E while driving opens the **mining-drill** GUI (modules + energy bar + Hybrid mining draw). **2 slots** / **3** slots, including uncommon+ quality trucks. Insert productivity — bonus products must appear (not a rare coin-flip). Insert efficiency — energy bar / draw kW drops. Insert speed — rate and draw rise. Modules return when the truck is mined.
7. **Harvest fuel tax:** Drive-harvest with an empty bay and real fuel — hybrid pool drops at ~120 kJ/item (180 kW at 1.5/s). Fill 2× efficiency-3; the energy bar and hybrid drain should drop to the 20% floor. Average ore rate still ~1.5/s.
8. **Quality ore rolls:** With quality modules in the bay, drive-harvest iron. Trunk stacks should include uncommon+ with quality preserved on refinery unload (`can_insert` must keep quality). Native drill quality modules apply; this is no longer a scripted `roll_quality` on insert.
9. **Entity quality:** Place a rare/epic Ore Truck. Search radius is still a bit larger. Slot count must stay 2 / 3. Drill rate stays the 1.5 / 3.0 baseline (bay is normal quality). Patch drain is native-normal (not the old 1/6 scripted table).
10. **Craft / grid / recycle:** Recipe lists vanilla solar panel + battery. A freshly placed truck has an **empty 2×2** (Ore Truck) or **3×3** (Tiberium) grid and empty module bay (no free solar/battery/modules; no Hybrid-drive item exists). Strip-recycle-recraft must not mint extra modules or equipment beyond a normal recycle of the craft cost.
11. **Quality hybrid:** A rare/legendary truck should refill faster and hold a larger electric cap than normal. Driving still net-drains. Module slots stay 2 / 3.
12. **Drain empty:** Stuck until fueled or recharged. Type stays hybrid-charge, never nuclear.
13. **Tech gates:** Old World Harvesting lists **solar-energy**. Tiberium Harvesting lists **electric-engine** and unlocks the type-2 recipe (electric-engine-unit, not engine-unit). No Hybrid-drive recipe.

## Remaining 2.1 unknowns

- `LuaEquipment.type` vs `prototype.type` when classifying batteries.
- Whether a disconnected electric drill + private pole/EEI micro-grid stays isolated from nearby substations in every 2.1 build (script still pay-gates `active`).
- Bay `create_entity` no longer passes `quality` (slots stay 2 / 3; baseline rate stays 1.5 / 3.0).
- Factorio-Tiberium 2.1 together with this pack is still untested in-client. `data-final-fixes.lua` adds existing `*tiberium*` resource categories to the **type-2** bay only (never invents `basic-solid-tiberium`).
- Resources that need a fluid (uranium + sulfuric acid) are not mined by the slave drill (no fluid box).

## PR targeting

Draft PR against `master`. Unique 2.1+feature delta is easier to review against PR #3. **Do not merge to master.**
