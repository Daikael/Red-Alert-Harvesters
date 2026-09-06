# Factorio 2.1 development line

This branch is the **2.1 experimental/beta** target for C&C Harvesters. It is **not** the 2.0 stable pack.

## Branch base

- Branched from `cursor/factorio-2.0-compat-98d9` at `c765378`, then **merged `master`** after PR #3 landed (2.0 tester UX/install fixes).
- Do **not** merge this 2.1 line back to live/`master`.

## Packaging

| Field | 2.0 line (PR #3) | 2.1 line (this branch) |
| --- | --- | --- |
| `info.json` `version` | `2.0.0` | `2.1.1.8` (test rev 8; not a released 2.1.8) |
| `factorio_version` | `2.0` | `2.1` |
| `base` | `>= 2.0.0` | `>= 2.1.0` |
| optional `Factorio-Tiberium` | `>= 2.0.0` | `>= 2.1.0` |

## Ported from 2.0 (`master` / PR #3)

- README zip name: `Red-Alert-Harvester_<version>` matching singular `info.json` `name`.
- Drive scoop **frequency** 320 ticks (~5.33s, 1.875× vs 600). Volume per scoop still 4.
- Inventory-full / blocked-harvest toasts: locale keys (`cncharvester.inventory-full` and related), `FLOATING_TEXT_ERROR_RED`, 150 tick TTL. Greens unchanged.

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
5. **Parasitic harvest fuel tax:** `harvest_area` (drive or auto) must **afford the full planned budget** from the hybrid pool **before** any ore is inserted. Cost is `items × 300 kJ × max(0.2, 1 + consumption) × (1 + max(0, speed) + 0.05×quality_level)`. The budget is **8** (Ore Truck) / **16** (type-2) items per period — not 4 per ore tile. A token spark still cannot buy a scoop; a charged grid can pay by draining stored energy into the pool (90%).
6. Productivity: extra product with probability `effects.productivity`, **no** extra drain.
7. Speed + quality level shorten the scoop interval (`base / (1 + speed + 0.05*level)`, min 12 ticks). Drive base interval is **320 ticks** (~5.33 s). Volume per period is **8 / 16**.
8. Auto-harvest scoop energy is `EnergyUsedPerTick * max(0.2, 1 + consumption)` (animation stand-in; the parasitic tax above is the real harvest fuel cost).
9. Pollution effect, if any, adds a tiny `surface.pollute`.

### Harvest parasitic tax numbers

Costs below use **300 kJ/item**. Speed modules multiply further via the speed term (not shown).

| Scoop | Items | No modules | 2× efficiency-3 (−80%) |
| --- | --- | --- | --- |
| Ore Truck period | **8** | **2.4 MJ** | 0.48 MJ |
| Tiberium period | **16** | **4.8 MJ** | 0.96 MJ |
| 4 items (formula check) | 4 | 1.2 MJ | 0.24 MJ |

`can_afford` counts pool + 90% of stored grid energy + convertible tank solids. `spend` pulls from the pool, then from stored grid if needed. Out of fuel only when that sum cannot cover the action. Inventory-full refunds the tax.

## Feature 2 — Hybrid energy pool

Solar panel + battery are **recipe ingredients** of the Ore Truck / Tiberium harvester (1 each). They are **consumed at craft**, not placed into the module bay or equipment grid. New trucks spawn with an **empty grid** and **empty module bay**. Those ingredients grant a **built-in recharge** (`INTRINSIC_SOLAR_W` = 18 kW, +20% per quality level, efficiency modules boost). That trickle is not removable equipment. Legendary + efficiency should idle-charge clearly faster than a normal empty truck.

Hybrid also converts **actual stored electric energy** from player-installed grid equipment at the per-tick rate cap. A **charged grid can pay a scoop** by draining stored energy into the pool (90%); a token leftover still cannot. Optional Hybrid-drive / Hybrid-drive-battery items still exist as extra storage; they are not required and are not auto-inserted.

**Recycler exploit (blocked):** place → strip gifted solar/battery/modules → recycle the truck for a full ingredient refund + the stripped loot. Nothing removable is script-inserted on place (`HybridDrive.on_built` / `ModuleBay.create`). Recycling the vehicle item may return the recipe’s solar+battery (vanilla recycle of craft cost) — that is fair, not a duplicate gift.

Every tick, `HybridDrive.maintain` then `tick`:

1. Strip nuclear-tier **items** from the fuel inventory. If `currently_burning` is nuclear-fuel / uranium-fuel-cell / fusion-power-cell, wipe remaining and lock to hybrid-charge.
2. Convert remaining chemical fuels (coal, wood, solid fuel, …) into the hybrid pool: consume the items, add `fuel_value` joules, cap **80 MJ**.
3. `currently_burning` is **always** hidden `cncharvester-hybrid-charge` (`fuel_category` `cncharvester-hybrid`). Writing it fills remaining to 80 MJ; `lock_charge` immediately writes the intended remaining. This is what stopped Factorio latching `nuclear-fuel` (empty-looking bar, still driving).
4. `has_usable_energy` is true when the pool, stored grid energy, or convertible tank solids can run the truck. Empty solid slots are OK. `enforce_empty` only zeros speed when none of those can supply energy. Scoops use `can_afford` / `spend` (pool + 90% stored grid).
5. Per-tick: grid pull is rate-capped; intrinsic is added on top while parked. While moving, combined conversion stays at or below refill so driving still net-drains. Electric refill never shrinks a solid-converted pool and never inserts items.
6. On mine, clear `currently_burning` and strip charge/nuclear from the mine buffer.

Vehicle `fuel_categories` are `cncharvester-hybrid` then `chemical` so the tank still accepts coal, but the engine’s burn identity is only hybrid-charge.

**Quality** (entity quality, not module slots): refill rate +1.5% per level, electric cap +25% per level. Refill stays below driving draw at every quality. Module bay stays **2 / 3** slots (`quality_affects_module_slots = false`).

### Kickoff fuel (2.1.5 — hybrid pool only)

2.1.3 inserted free coal/wood. 2.1.4 could latch nuclear-fuel after the spark drained.

On player-built: consume **1** coal (else wood) from the placer and **convert those joules into the hybrid pool**. The item is not left in the tank and is not `currently_burning`.

Otherwise (no coal/wood, or robot/script/clone): **2 kJ spark** of hybrid-charge.

| Source | Energy | Notes |
| --- | --- | --- |
| Empty-tank spark | **2 kJ** | Hybrid-charge identity; sliver on an 80 MJ bar |
| Hybrid idle cap (normal) | 300 / 350 kJ | Paid from grid, 10% below drive draw; quality enlarges this |
| 1 coal converted | 4 MJ | Player-paid; tank stays empty of items |
| Pool cap | 80 MJ | 20× coal; hidden item `fuel_value` |

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
| Max idle buffer | 300 kJ (4 s) | 350 kJ |

Sustained full-throttle driving therefore net-drains ~6.8 / 8.0 kW on a **normal** truck even with a charged grid. Quality raises refill slightly (+1.5%/level) and the parked electric cap (+25%/level → legendary ~9 s). Idle or slow driving can refill that cap, then stops.

| Quality | Refill vs normal | Electric cap vs normal |
| --- | --- | --- |
| 0 normal | 1.00× | 4.0 s |
| 1 uncommon | 1.015× | 5.0 s |
| 2 rare | 1.030× | 6.0 s |
| 3 epic | 1.045× | 7.0 s |
| 5 legendary | 1.075× | 9.0 s |

## How to test (Factorio 2.1 experimental)

This environment has **no Factorio client**. Static checks: `luac -p` and `lua test_2_1_features.lua`.

1. Install as **`Red-Alert-Harvester_2.1.1.8`** (singular `info.json` name — see README). Confirm data stage loads. Inventory-full / blocked-harvest / refuel toasts are locale keys (en), same red/150-tick error style as before.
2. **No free scoop on place:** Place a truck with empty fuel on ore. First sit must **not** dump 100 (Ore Truck) / 80 (type-2) ore. Feedback is localized **Out of fuel** only.
3. **Cost matches yield/speed:** A 2 kJ spark or leftover sliver cannot buy a full max-speed scoop. More ores / speed modules / quality cost more. One personal solar’s stored charge must not authorize an underpriced full scoop (grid→pool stays rate-capped and separate).
4. **Kickoff / nuclear latch:** Place with coal — lose 1 coal; tank slots empty; bar shows **Hybrid charge** (~4 MJ / 80 MJ), never a raw key, never nuclear. Place with no coal/wood — 2 kJ sliver. Drain completely — cannot drive or scoop; bar stays empty (no nuclear flip). Insert coal — pool increases, identity stays hybrid-charge. Mine: no free charge/nuclear loot.
5. **Intrinsic solar:** Fresh truck, empty grid, no removable solar/battery to strip. Parked pool should climb slowly from the baked-in 4 kW trickle. Recipe still costs solar+battery. Player-installed equipment still matters; sustained driving/mining still net-drains.
6. **Module bay:** Place an Ore Truck. A small hitch should exist; SHIFT+E while driving opens the vanilla module GUI. **2 slots** on Ore Truck / **3** on Tiberium, including uncommon+ quality trucks. Insert speed/quality/productivity/efficiency modules. Confirm they are not left behind when the truck is mined (modules return to you).
7. **Harvest fuel tax:** Drive-harvest with an empty bay and real fuel — pool should drop with ore count. Fill 2× efficiency-3 and scoop again; fuel use should feel much cheaper.
8. **Quality ore rolls:** With quality modules in the bay, drive-harvest iron. Trunk stacks should include uncommon+ with quality preserved on refinery unload (`can_insert` must keep quality).
9. **Entity quality / drain:** Place a rare/epic Ore Truck (editor or quality crafting). The same patch should last longer than a normal truck; scoop radius/rate should feel slightly better. Slot count must stay 2 / 3.
10. **Craft / grid / recycle:** Recipe lists solar panel + battery. A freshly placed truck has an **empty grid** and empty module bay (no free solar/battery/Hybrid-drive/modules). Strip-recycle-recraft must not mint extra modules or equipment beyond a normal recycle of the craft cost.
11. **Quality hybrid:** A rare/legendary truck should refill faster and hold a larger electric cap than normal. Driving still net-drains. Module slots stay 2 / 3.
12. **Drain empty:** Stuck until fueled or recharged. Type stays hybrid-charge, never nuclear.

## Remaining 2.1 unknowns

- `LuaEquipment.type` vs `prototype.type` when classifying batteries.
- Whether a later 2.1 build rejects dummy resource categories or void-energy mining drills.
- Bay `create_entity` no longer passes `quality` (slots stay 2 / 3).
- Factorio-Tiberium 2.1 together with this pack is still untested in-client.

## PR targeting

Draft PR against `master`. Unique 2.1+feature delta is easier to review against PR #3. **Do not merge to master.**
