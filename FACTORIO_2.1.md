# Factorio 2.1 development line

This branch is the **2.1 experimental/beta** target for C&C Harvesters. It is **not** the 2.0 stable pack.

## Branch base

- Branched from `cursor/factorio-2.0-compat-98d9` at `c765378`, then **merged `master`** after PR #3 landed (2.0 tester UX/install fixes).
- Do **not** merge this 2.1 line back to live/`master`.

## Packaging

| Field | 2.0 line (PR #3) | 2.1 line (this branch) |
| --- | --- | --- |
| `info.json` `version` | `2.0.0` | `2.1.5` |
| `factorio_version` | `2.0` | `2.1` |
| `base` | `>= 2.0.0` | `>= 2.1.0` |
| optional `Factorio-Tiberium` | `>= 2.0.0` | `>= 2.1.0` |

## Ported from 2.0 (`master` / PR #3)

- README zip name: `Red-Alert-Harvester_<version>` matching singular `info.json` `name`.
- Drive scoop **frequency** 320 ticks (~5.33s, 1.875× vs 600). Volume per scoop still 4.
- Inventory-full / blocked-harvest toasts: `FLOATING_TEXT_ERROR_RED`, 150 tick TTL. Greens unchanged.

## Feature 1 — Modular Ore Truck

`CarPrototype` has **no** `module_slots`. Modules live on a companion mining-drill shell that never mines (dummy `cncharvester-module-bay` resource category).

### Layer A — entity quality

Read from `vehicle.quality`:

| Quality level | Drain (if prototype field missing) | Scoop radius | Scoop interval |
| --- | --- | --- | --- |
| 0 normal | 100% | base | base |
| 1 uncommon | 5/6 | +0.25 | / 1.05 |
| 2 rare | 4/6 | +0.50 | / 1.10 |
| 3 epic | 3/6 | +0.75 | / 1.15 |
| 5 legendary | 1/6 | +1.25 | / 1.25 |

When present, `LuaQualityPrototype.mining_drill_resource_drain_multiplier` wins over the 1/6 table (vanilla drill values). A successful scoop decrements the patch only if `math.random() < drain`.

### Layer B — companion module bay

| Vehicle | Bay prototype | Module slots |
| --- | --- | --- |
| `cncharvester` | `cncharvester-module-bay` | 2 |
| `cncharvester-type2` | `cncharvester-type2-module-bay` | 3 |

- `allowed_effects`: speed, productivity, consumption, pollution, quality.
- **Slot count does not scale with quality.** `quality_affects_module_slots = false`. The bay is created at normal quality (vehicle quality is not passed to `create_entity`). Uncommon/rare/epic/legendary trucks still have **2** or **3** slots.
- Not minable / not destructible / not blueprintable / empty collision mask.
- Teleported with the truck; destroyed on truck mine/death (modules go to the mine buffer or trunk).
- Orphans are reaped on `on_configuration_changed`.
- Open: click the small hitch, or **SHIFT+E** (`cncharvester-open-module-bay`) while driving / with the truck selected.

### Scripted scoop (drive + auto)

1. Read `bay.effects` (fallback: sum module inventory, scaled by module-item quality multipliers).
2. Quality chance → `LuaQualityPrototype.roll_quality(effect, seed, force)` on 2.1; else `next` / `next_probability` chain.
3. Insert `{name, count=1, quality}` into the trunk. `can_insert` is quality-aware. Unload still preserves quality.
4. Resource drain from Layer A; efficiency modules (`consumption < 0`) still shave a little drain (`drain * (1 + consumption * 0.25)`).
5. **Parasitic harvest fuel tax** (2.1.3): each successful `harvest_area` (drive or auto) drains the burner / fuel inventory. Base **1.2 MJ**. Factor is `max(0.2, 1 + consumption)` so 2× efficiency-3 (−80%) costs **0.24 MJ**. Empty trucks pay a clear tax (~3 scoops per coal at 4 MJ); full efficiency is 5× cheaper. Speed modules that raise `consumption` make the tax worse.
6. Productivity: extra product with probability `effects.productivity`, **no** extra drain.
7. Speed + quality level shorten the scoop interval (`base / (1 + speed + 0.05*level)`, min 12 ticks). Drive base interval is **320 ticks** (~5.33 s, same as the 2.0 tester-approved cadence). Volume per scoop stays 4.
8. Auto-harvest scoop energy is `EnergyUsedPerTick * max(0.2, 1 + consumption)` (animation stand-in; the parasitic tax above is the real harvest fuel cost).
9. Pollution effect, if any, adds a tiny `surface.pollute`.

### Harvest parasitic tax numbers

| Bay modules | `consumption` | Cost per successful scoop |
| --- | --- | --- |
| None | 0 | **1.2 MJ** (~3 scoops / coal) |
| 1× efficiency-3 | −40% | 0.72 MJ |
| 2× efficiency-3 (Ore Truck full) | −80% | **0.24 MJ** (floor) |
| 3× efficiency-3 (type-2 full) | −80% (floored) | **0.24 MJ** |

Tax is taken from `remaining_burning_fuel` first, then cheap fuel items in the tank.

## Feature 2 — Hybrid-drive converter

Hybrid-drive is **battery-equipment** (converter identity), not a 0.4 kW solar panel. Hybrid-drive-battery remains 7 MJ storage. Auto-equip both on **first enter only**; later removals are left alone. Grids are 4×4 / 5×5 so a third-party armor generator can fit.

Every tick, `HybridDrive.maintain`:

1. Strip nuclear-tier **items** from the fuel inventory. If `currently_burning` is nuclear-fuel / uranium-fuel-cell / fusion-power-cell, wipe remaining and lock to hybrid-charge.
2. Convert remaining chemical fuels (coal, wood, solid fuel, …) into the hybrid pool: consume the items, add `fuel_value` joules, cap **80 MJ**.
3. `currently_burning` is **always** hidden `cncharvester-hybrid-charge` (`fuel_category` `cncharvester-hybrid`). Writing it fills remaining to 80 MJ; `lock_charge` immediately writes the intended remaining. This is what stopped Factorio latching `nuclear-fuel` (empty-looking bar, still driving).
4. If the pool is **0 J**, `has_energy` is false: no drive scoop, no auto scoop, car `speed` forced to 0.
5. If Hybrid-drive is installed, pull grid energy and add `pulled * 0.90` only while remaining is below the **4 s** electric cap. Electric refill never shrinks a solid-converted pool and never inserts items.
6. On mine, clear `currently_burning` and strip charge/nuclear from the mine buffer.

Vehicle `fuel_categories` are `cncharvester-hybrid` then `chemical` so the tank still accepts coal, but the engine’s burn identity is only hybrid-charge.

### Kickoff fuel (2.1.5 — hybrid pool only)

2.1.3 inserted free coal/wood. 2.1.4 could latch nuclear-fuel after the spark drained.

On player-built: consume **1** coal (else wood) from the placer and **convert those joules into the hybrid pool**. The item is not left in the tank and is not `currently_burning`.

Otherwise (no coal/wood, or robot/script/clone): **2 kJ spark** of hybrid-charge.

| Source | Energy | Notes |
| --- | --- | --- |
| Empty-tank spark | **2 kJ** | Hybrid-charge identity; sliver on an 80 MJ bar |
| Hybrid idle cap | 300 / 350 kJ | Paid from grid, 10% below drive draw |
| 1 coal converted | 4 MJ | Player-paid; tank stays empty of items |
| Pool cap | 80 MJ | 20× coal; hidden item `fuel_value` |

Empty pool = cannot drive or scoop until the player inserts burnable fuel (converted) or Hybrid refills from the grid.

### Numbers

Prototype `consumption` is 150 kW / 175 kW with `effectivity = 2`. Actual burner draw ≈ consumption / effectivity:

| | Ore Truck | Tiberium harvester |
| --- | --- | --- |
| Prototype consumption | 150 kW | 175 kW |
| Driving draw (consumption / 2) | **75.0 kW** | **87.5 kW** |
| Max electric→burner refill | 68.18 kW (10% below draw) | 79.55 kW |
| Grid pull (90% conversion) | 75.76 kW | 88.38 kW |
| Max idle buffer | 300 kJ (4 s) | 350 kJ |

Sustained full-throttle driving therefore net-drains ~6.8 / 8.0 kW even with full batteries and a huge generator. Idle or slow driving can refill the 4 s buffer, then stops.

## How to test (Factorio 2.1 experimental)

This environment has **no Factorio client**. Static checks: `luac -p` and `lua test_2_1_features.lua`.

1. Install as **`Red-Alert-Harvester_2.1.5`** (singular `info.json` name — see README). Confirm data stage loads.
2. **Kickoff / nuclear latch:** Place with coal — lose 1 coal; tank slots empty; bar shows hybrid-charge (~4 MJ / 80 MJ), never nuclear. Place with no coal/wood — 2 kJ sliver. Drain completely — cannot drive or scoop; bar stays empty (no nuclear flip). Insert coal — pool increases, identity stays hybrid-charge. Mine: no free charge/nuclear loot.
3. **Module bay:** Place an Ore Truck. A small hitch should exist; SHIFT+E while driving opens the vanilla module GUI. **2 slots** on Ore Truck / **3** on Tiberium, including uncommon+ quality trucks. Insert speed/quality/productivity/efficiency modules. Confirm they are not left behind when the truck is mined (modules return to you).
4. **Harvest fuel tax:** Drive-harvest with an empty bay — coal should drop clearly. Fill 2× efficiency-3 and scoop again; fuel use should feel much cheaper.
5. **Quality ore rolls:** With quality modules in the bay, drive-harvest iron. Trunk stacks should include uncommon+ with quality preserved on refinery unload (`can_insert` must keep quality).
6. **Entity quality / drain:** Place a rare/epic Ore Truck (editor or quality crafting). The same patch should last longer than a normal truck; scoop radius/rate should feel slightly better. Slot count must stay 2 / 3.
7. **Hybrid drain-while-driving:** First enter auto-inserts Hybrid-drive + battery. Fill the grid with a high-power armor generator if you have one, and fill batteries. Drive at full throttle: burner fuel / remaining burn should slowly fall. Park: remaining burn should climb back toward the 4 s cap, then hold.

## Remaining 2.1 unknowns

- `LuaEquipment.type` vs `prototype.type` when classifying batteries.
- Whether a later 2.1 build rejects dummy resource categories or void-energy mining drills.
- Bay `create_entity` no longer passes `quality` (slots stay 2 / 3).
- Factorio-Tiberium 2.1 together with this pack is still untested in-client.

## PR targeting

Draft PR against `master`. Unique 2.1+feature delta is easier to review against PR #3. **Do not merge to master.**
