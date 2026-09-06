# Factorio 2.1 development line

This branch is the **2.1 experimental/beta** target for C&C Harvesters. It is **not** the 2.0 stable pack.

## Branch base

- Branched from `cursor/factorio-2.0-compat-98d9` at `c765378`, then **merged `master`** after PR #3 landed (2.0 tester UX/install fixes).
- Do **not** merge this 2.1 line back to live/`master`.

## Packaging

| Field | 2.0 line (PR #3) | 2.1 line (this branch) |
| --- | --- | --- |
| `info.json` `version` | `2.0.0` | `2.1.2` |
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
- `quality_affects_module_slots = true` (bay created at the truck’s quality).
- Not minable / not destructible / not blueprintable / empty collision mask.
- Teleported with the truck; destroyed on truck mine/death (modules go to the mine buffer or trunk).
- Orphans are reaped on `on_configuration_changed`.
- Open: click the small hitch, or **SHIFT+E** (`cncharvester-open-module-bay`) while driving / with the truck selected.

### Scripted scoop (drive + auto)

1. Read `bay.effects` (fallback: sum module inventory, scaled by module-item quality multipliers).
2. Quality chance → `LuaQualityPrototype.roll_quality(effect, seed, force)` on 2.1; else `next` / `next_probability` chain.
3. Insert `{name, count=1, quality}` into the trunk. `can_insert` is quality-aware. Unload still preserves quality.
4. Resource drain from Layer A; efficiency modules (`consumption < 0`) shave a little more drain (`drain * (1 + consumption * 0.25)`).
5. Productivity: extra product with probability `effects.productivity`, **no** extra drain.
6. Speed + quality level shorten the scoop interval (`base / (1 + speed + 0.05*level)`, min 12 ticks). Drive base interval is **320 ticks** (~5.33 s, same as the 2.0 tester-approved cadence). Volume per scoop stays 4.
7. Auto-harvest scoop energy is `EnergyUsedPerTick * max(0.2, 1 + consumption)`.
8. Pollution effect, if any, adds a tiny `surface.pollute`.

## Feature 2 — Hybrid-drive converter

Hybrid-drive is **battery-equipment** (converter identity), not a 0.4 kW solar panel. Hybrid-drive-battery remains 7 MJ storage. Auto-equip both on **first enter only**; later removals are left alone. Grids are 4×4 / 5×5 so a third-party armor generator can fit.

Each tick, if Hybrid-drive is installed:

1. Pull up to `grid_j_per_tick` from batteries first, then other equipment `energy` (fusion/solar/etc.).
2. Add `pulled * 0.90` to `LuaBurner.remaining_burning_fuel`.
3. If nothing is burning, set `currently_burning` to hidden `cncharvester-hybrid-charge` (never inserted as a fuel item).
4. Cap stored burner energy at **4 seconds** of driving draw.

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

1. Install as **`Red-Alert-Harvester_2.1.2`** (singular `info.json` name — see README). Confirm data stage loads.
2. **Module bay:** Place an Ore Truck. A small hitch should exist; SHIFT+E while driving opens the vanilla module GUI. Insert speed/quality/productivity modules. Confirm they are not left behind when the truck is mined (modules return to you).
3. **Quality ore rolls:** With quality modules in the bay, drive-harvest iron. Trunk stacks should include uncommon+ with quality preserved on refinery unload (`can_insert` must keep quality).
4. **Entity quality / drain:** Place a rare/epic Ore Truck (editor or quality crafting). The same patch should last longer than a normal truck; scoop radius/rate should feel slightly better.
5. **Hybrid drain-while-driving:** First enter auto-inserts Hybrid-drive + battery. Fill the grid with a high-power armor generator if you have one, and fill batteries. Drive at full throttle: burner fuel / remaining burn should slowly fall. Park: remaining burn should climb back toward the 4 s cap, then hold.

## Remaining 2.1 unknowns

- `LuaEquipment.type` vs `prototype.type` when classifying batteries.
- Whether a later 2.1 build rejects dummy resource categories or void-energy mining drills.
- `create_entity{quality=}` on the bay (we pass `quality.name`).
- Factorio-Tiberium 2.1 together with this pack is still untested in-client.

## PR targeting

Draft PR against `master`. Unique 2.1+feature delta is easier to review against PR #3. **Do not merge to master.**
