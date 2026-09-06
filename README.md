# C&C Harvesters (`Red-Alert-Harvesters`)

Resource trucks and a dump refinery from Command & Conquer / Red Alert.

This branch is the **Factorio 2.1 experimental/beta** line (pack `2.1.11`). It is **not** the live 2.0 stable pack on `master`.

Factorio only accepts three-part `major.minor.patch` versions. This pack is **`2.1.11`**. Later unreleased test revs stay on three-part patch bumps (`2.1.12`, `2.1.13`, …). `factorio_version` is **`2.1`** (not 2.0).

- **2.0 stable players:** use `master` / `Red-Alert-Harvester_2.0.0` (that line still uses the singular `info.json` name).
- **2.1 experimental:** this branch / pack **`Red-Alert-Harvesters_2.1.11`**.

## Development branch names

Tester-facing development branches are **just the three-part version**: `2.1.11`, then `2.1.12`, … Do not use `cursor/…` names. The Factorio mod `info.json` **name** is plural **`Red-Alert-Harvesters`**. The pack folder is **`Red-Alert-Harvesters_<version>`**.

**Version bumps rename the branch in place.** Do not open a parallel `2.1.12` next to `2.1.11`. Rename (`git branch -m 2.1.12`, push the new name, delete the old remote). Prefer retargeting the open draft PR; if GitHub cannot retarget the head, open a new draft PR, close the old one with a pointer, and still delete the old version branch.

GitHub **Code → Download ZIP** produces a folder like **`Red-Alert-Harvesters-2.1.11`** (hyphen before the version). Factorio requires an underscore: rename `-` → `_` so the mods folder is exactly **`Red-Alert-Harvesters_2.1.11`**.

## Install naming (Factorio will refuse the wrong zip)

Factorio checks the **file or folder name** against `info.json`. The check is **case-sensitive**.

| What | Exact value |
| --- | --- |
| GitHub repo | `Red-Alert-Harvesters` |
| Git branch (this pack) | `2.1.11` |
| `info.json` `name` | `Red-Alert-Harvesters` |
| `info.json` `version` | `2.1.11` |
| `info.json` `factorio_version` | `2.1` |
| Folder in `mods/` | `Red-Alert-Harvesters_2.1.11` |
| Zip in `mods/` | `Red-Alert-Harvesters_2.1.11.zip` |
| GitHub archive folder | `Red-Alert-Harvesters-2.1.11` (hyphen — **rename to underscore**) |

The rule is always `{info.json name}_{info.json version}` — here that is **`Red-Alert-Harvesters_2.1.11`**.

`info.json` must sit at the **zip root** or **one folder deep** with that same folder name:

```text
Red-Alert-Harvesters_2.1.11.zip
  Red-Alert-Harvesters_2.1.11/
    info.json
    control.lua
    ...
```

or the same files at the zip root. A zip named `Red-Alert-Harvesters.zip`, `Red-Alert-Harvester_2.1.11.zip`, or `Red-Alert-Harvesters-2.1.11.zip` will fail to load.

### Where to put it

- **Windows:** `%APPDATA%\Factorio\mods\`
- **Linux (native / most Steam Linux installs):** `~/.factorio/mods/`
- **Steam Deck (native):** `~/.factorio/mods/`
- **Steam Deck / Proton:**  
  `~/.steam/steam/steamapps/compatdata/427520/pfx/drive_c/users/steamuser/AppData/Roaming/Factorio/mods/`

### Package from this repo (Linux / Deck / macOS)

```bash
# from a clone of this branch
rm -rf /tmp/Red-Alert-Harvesters_2.1.11 /tmp/Red-Alert-Harvesters_2.1.11.zip
mkdir /tmp/Red-Alert-Harvesters_2.1.11
rsync -a --exclude .git --exclude .vscode ./ /tmp/Red-Alert-Harvesters_2.1.11/
cd /tmp && zip -r Red-Alert-Harvesters_2.1.11.zip Red-Alert-Harvesters_2.1.11
# copy Red-Alert-Harvesters_2.1.11.zip into your Factorio mods folder
```

On Windows: copy the repo into a folder literally named `Red-Alert-Harvesters_2.1.11`, then zip that folder.

## Smoke test (2.1 experimental)

1. Confirm the Mods list shows **C&C Harvesters** / `Red-Alert-Harvesters` **2.1.11** with no load error. Use a **2.1 experimental** client, not 2.0 stable. `factorio_version` must be **2.1**.
2. New Freeplay / sandbox. **Old World Harvesting** requires **solar energy**. Craft an Ore Truck (2×2 grid) and a Refinery. There is **no Hybrid-drive** item. The Tiberium harvester is unlocked by **Tiberium Harvesting** (requires electric engines) and crafts with electric engines.
3. Fuel the truck, drive onto iron/copper/coal/stone. It should mine **1 item at a time** about every **40 ticks** (~0.67 s; same average as the old 8 items / 5.3 s). Tiberium is **20 ticks** (~0.33 s). Unload when you sit next to the refinery.
4. SHIFT+E (or click the hitch) opens the companion **module bay** (starts empty). The truck recipe spends a solar panel + battery at craft; they are **not** in the grid or bay (no strip-recycle extra loot). Those ingredients give a **slow built-in recharge**. Install a charged portable battery — parked, the hybrid bar should climb clearly. An empty or undercharged pool will not scoop.
5. Optional: Mods → Startup → **Automatic harvester testing**, place a fueled truck near ore and a refinery, then save/reload.

## Drive-and-harvest rate

Mining is **1 item per tick period** (drill-like). Average throughput matches the old 8 / 16 items per 320 ticks (~5.33 s).

| Vehicle | Ticks per item | Interval at 60 UPS | Items per second | Fuel |
| --- | --- | --- | --- | --- |
| Ore Truck | **40** | **~0.67 s** | **~1.50** (8 / 5.33 s) | 120 kJ/item |
| Tiberium | **20** | **~0.33 s** | **~3.00** (16 / 5.33 s) | 120 kJ/item |

120 kJ/item is **4×** the 2.1.10 tax. One solid fuel (12 MJ) ≈ **100 items** (~67 s ore / ~33 s Tiberium). Cost still scales with efficiency / speed / quality. Speed modules and entity quality may shorten the 40 / 20 tick bases (min 4 ticks). Auto-harvest uses the same cadence.

## Inventory-full warning

When a drive-harvest scoop cannot fit in the trunk, the truck shows **error-red** localized `Inventory full` floating text (`cncharvester.inventory-full`) for **150 ticks** (~2.5 seconds at 60 UPS). Auto-harvester blocked warnings (`no-empty-refinery`, `no-fuel-refinery`) use the same red/TTL. Informational green `Heading for refuel` is also localized. Colors and TTLs are unchanged.

## 2.1-only features

See `FACTORIO_2.1.md`: companion module bay (fixed 2 / 3 slots), quality/drain scooping, per-item harvest tax (120 kJ/item), hybrid-charge pool (never nuclear). Truck recipes cost solar panel + battery and grant a slow built-in recharge (not removable). Hybrid converts player-installed grid/battery energy (parked pull is faster; moving stays below drive). Each item must be paid before insert.

## Optional dependency

[Factorio and Conquer: Tiberian Dawn](https://mods.factorio.com/mod/Factorio-Tiberium) **2.1.x** (for example 2.1.16). Do not mix that mod’s 2.0.15 line with this 2.1 pack.
