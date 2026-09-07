# Factorio 2.0 backdate (pack 2.1.18)

**2.1.19 belt fix (this checkout when bumped):** both `car` prototypes set `has_belt_immunity = true` so self-powered Ore / Tiberium trucks are not dragged or stranded by transport belts. Hitch / hybrid / scoop / Tib boot are unchanged. Still Factorio **2.0**. Still do **not** merge to `master`.

This branch is the **public Factorio 2.0** port of the tester-approved **2.1.17** gameplay. It is **not** the live 2.0 stable pack on `master` (singular `Red-Alert-Harvester` 2.0.0) and it is **not** the 2.1 experimental line.

**Do not merge to `master`.** Do not rename or delete branch `2.1.17` / draft PR #15.

| | 2.1 beta (keep) | This pack | Live 2.0 on master |
| --- | --- | --- | --- |
| Git branch | `2.1.17` | `2.1.18` | `master` |
| Draft PR | #15 | this PR | — |
| `info.json` name | `Red-Alert-Harvester` | `Red-Alert-Harvester` | `Red-Alert-Harvester` |
| `info.json` version | `2.1.17` | `2.1.18` | `2.0.0` |
| `factorio_version` | `2.1` | `2.0` | `2.0` |
| `base` | `>= 2.1.0` | `>= 2.0.0` | `>= 2.0.0` |
| optional Tiberium | `>= 2.1.0` | `>= 2.0.0` | `>= 2.0.0` |
| Folder / zip | `Red-Alert-Harvester_2.1.17` | `Red-Alert-Harvester_2.1.18` | `Red-Alert-Harvester_2.0.0` |

GitHub **Code → Download ZIP** produces repo-prefixed `Red-Alert-Harvesters-2.1.18` (hyphen). That is **not** an install path. Use the GitHub Release zip `Red-Alert-Harvester_2.1.18.zip`.

## Gameplay kept from 2.1.17

- Slave-miner mining (Ore 1.5 / 180 kW, Tiberium 3.0 / 360 kW), native modules, energy bar, SHIFT+E.
- Invisible hitch helpers: pole / EEI / hopper / drill world graphics use `util.empty_sprite()`.
- Isolated micro-grid (`maximum_wire_distance = 0`), hybrid pay-first, EEI starve when the pool cannot pay.
- Hybrid pool / intrinsic 18 kW / grids 2×2 and 3×3 / no Hybrid-drive items.
- Tech: Old World Harvesting requires `solar-energy`. Tiberium Harvesting requires Old World + `electric-engine`; recipe uses `electric-engine-unit`.
- Per-item rates (~1.50 / ~3.00/s), 120 kJ/item, first-sit 40 / 20 ticks.
- Tiberium category boot fix: prototypes list `basic-solid` only; `data-final-fixes.lua` adds real Tib categories to the type-2 bay when they exist.

## 2.0 vs 2.1 deltas

| Area | 2.1.17 (Factorio 2.1) | 2.1.18 (Factorio 2.0) |
| --- | --- | --- |
| Car braking / friction | `braking_force`, `friction_force` | `braking_power`, `friction` |
| Recipes | `categories = {"crafting"}` | `category = "crafting"` |
| Quality prototype keys | always set `quality_affects_* = false`, `allowed_effects` includes `"quality"` | set only if `mods["quality"]` or `mods["space-age"]` |
| Drill enable | `disabled_by_script` only (`.active` is read-only) | try `disabled_by_script`, else write `.active` (legal on 2.0) |
| Entity / stack `.quality` | always present | `SafeQuality()` pcall; missing → level 0 |
| Quality modules | native on the slave drill | native **only with Space Age / quality**; otherwise speed / prod / efficiency / pollution only |
| Entity-quality bonuses | search radius +0.25/level, intrinsic solar +20%/level, moving refill +1.5%/level | same formulas when `entity.quality` exists; **base 2.0 without Space Age is always level 0** |
| Optional Tiberium | 2.1.x line | 2.0.x line (do not mix with Tib 2.1) |

## What was dropped / degraded (no Space Age)

- No quality modules, no quality ore rolls, no uncommon+ stacks from the drill.
- No legendary/rare truck bonuses (radius, idle trickle, refill). Trucks behave as **normal**.
- `fusion-power-cell` remains on the nuclear-ban list (name check only; the item need not exist).
- 2.1-only vehicle force fields and recipe `categories` are not used (they would fail data stage on 2.0).

With Space Age on a 2.0 client, quality modules and `SafeQuality` bonuses apply the same way as 2.1.17. Slot counts stay 2 / 3.

## How to test (Factorio 2.0 stable)

This environment has **no Factorio client**. Static checks: `luac -p` and `lua test_2_1_features.lua`.

1. Install as **`Red-Alert-Harvester_2.1.18`**. Confirm Mods list shows **C&C Harvesters** / `Red-Alert-Harvester` **2.1.18** on a **2.0** client, **with and without** Factorio-Tiberium 2.0.x. Must not ask for 2.1.
2. No AtlasBuilder sprite-rectangle error. No moving pole / accumulator / chest / hitch icon square.
3. Mining, SHIFT+E energy bar, OOF, pay-first, first-sit wait — same as 2.1.17.
4. Without Space Age: no quality modules in the bay GUI; rates stay the no-module baseline.
5. Do not install this zip on a 2.1-only client (use branch `2.1.17` / PR #15).

Mod QA desk-gates 2.1.18 before player retest.
