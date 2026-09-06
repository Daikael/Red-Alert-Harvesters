# Factorio 2.1 development line

This branch is the **2.1 experimental/beta** target for C&C Harvesters. It is **not** the 2.0 stable pack.

## Branch base

- Branched from `cursor/factorio-2.0-compat-98d9` at `c765378` (PR #3, Factorio 2.0 port).
- Do **not** start from stale `master` for 2.1 work.
- Do **not** merge this line to live/default until the 2.0 port is settled and 2.1 APIs stabilize.

## Packaging bump

| Field | 2.0 line (PR #3) | 2.1 line (this branch) |
| --- | --- | --- |
| `info.json` `version` | `2.0.0` | `2.1.0` |
| `factorio_version` | `2.0` | `2.1` |
| `base` | `>= 2.0.0` | `>= 2.1.0` |
| optional `Factorio-Tiberium` | `>= 2.0.0` (use 2.0.15 on Factorio 2.0) | `>= 2.1.0` (portal 2.1.16+; 2.0.x is not 2.1-compatible) |

A Factorio 2.0 client will refuse this pack. Keep the 2.0 branch for 2.0 players.

## Known 2.0 → 2.1 changes applied here

Checked against the public 2.1 changelog / prototype docs (through 2.1.12+; docs currently labeled 2.1.17). Only changes that would **fail data-stage load** or mis-declare this mod were applied.

1. **Vehicles** — `VehiclePrototype.braking_power` and `friction` were removed. Harvesters now use `braking_force = kW * 1000 / 60` (same conversion as vanilla car/tank in `factorio-data`) and `friction_force` with the old friction numbers (`0.045` / `0.04`).
2. **Recipes** — `RecipePrototype.category` / `additional_categories` were removed. Crafting recipes now set `categories = {"crafting"}`. Typed 2.0 ingredients/results are unchanged.
3. **Refinery picture** — `ContainerPrototype.picture` is now `Sprite4Way`. A single `Sprite` is still valid (applies to all directions); no art rewrite.
4. **Technology ingredients** — science packs are plain items in 2.1. Official docs still accept `{name, amount}` tuples; left as-is.

## Intentionally not rewritten

These 2.1 changelog items do **not** affect this mod's current prototypes or runtime paths:

- Fluid box / `LuaEntity.fluidbox` removal (no fluids).
- Recipe-category collapse (`basic-crafting`, `electronics`, metallurgy-or-assembling, etc.).
- `LuaEntity.active` / `minable` write removals.
- Inventory define aliases for assembling machines / furnaces.
- Custom input key names, deconstruction filters, asteroid / space-platform-only prototypes.

2.0 port behavior is kept: `storage`, `prototypes.*`, quality-aware `get_contents()`, `energy_source` burners, `place_as_equipment_result`, `rendering.draw_text`, drive-and-harvest limited to Ore Truck / Tiberium harvester.

## Quality system — out of scope

A separate design pass will handle quality. This branch only keeps the 2.0 inventory quality preservation (`EachInventoryItem` / `InventoryItemStack`).

**TODO (do not implement here unless required to load):**

- Auto-harvester `insert{name, count}` and fuel moves do not request or roll quality.
- Recipe `can_set_quality`, `ItemIngredientPrototype.quality_min` / `quality_max` / `quality_change`, product `affected_by_quality`.
- 2.1 quality **effect values were divided by 10**; any future quality modifiers must use the new scale.
- `LuaQualityPrototype.roll_quality()` and quality-aware mining of resource entities.
- Space Age recycling (`auto_recycle`) interaction for harvester / refinery items.

## Remaining 2.1 unknowns (API still moving)

2.1 is experimental. Treat the following as unverified until loaded in a current 2.1 client:

- Exact default when `RecipePrototype.categories` is omitted (we set it explicitly to be safe).
- Whether later 2.1 builds tighten `Sprite4Way` so a bare sprite on the refinery fails.
- Optional **Factorio-Tiberium 2.1** resource categories, damage type `"tiberium"`, and `basic-solid-tiberium` — portal 2.1.16 exists, but this branch was not loaded with it.
- Runtime-only 2.1 changes that do not show up until save/load or a specific event (space platforms, quality GUI, circuit connectors as arrays).
- Further experimental patches after 2.1.12 may still rename prototype fields.

## How to test (when a 2.1 client is available)

This environment does **not** include Factorio, so data-stage load was not executed here.

1. Copy as `mods/Red-Alert-Harvester_2.1.0` (or zip with `info.json` one folder deep).
2. Use Factorio **2.1 experimental**, not 2.0 stable.
3. Confirm the pack is listed as 2.1 and the data stage loads with no prototype errors.
4. Repeat the PR #3 2.0 smoke tests (research, craft, drive-and-harvest, optional auto-harvest, save/reload).
5. Optional: enable Factorio-Tiberium **2.1.x** (not 2.0.15) and confirm tiberium resistance / solid tiberium mining.

## PR targeting

Opened against `master` so the 2.1 line is visible next to the 2.0 port. The unique 2.1 delta is easier to review against `cursor/factorio-2.0-compat-98d9` (PR #3). Retarget onto the 2.0 branch if a 2.1-only diff is preferred. **Do not merge to master** from this PR.
