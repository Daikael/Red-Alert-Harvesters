# C&C Harvesters (`Red-Alert-Harvester`)

Resource trucks and a dump refinery from Command & Conquer / Red Alert.

This branch is pack **`2.2.0`**: Factorio **2.0** experimental **M1 chunk scanner** on top of the 2.1.18 gameplay. It is **not** the live 2.0 pack on `master`, and it does **not** replace the 2.1 experimental line.

Factorio only accepts three-part `major.minor.patch` versions. This pack is **`2.2.0`**. `factorio_version` is **`2.0`**.

- **2.1 experimental (keep):** branch `2.1.17` / draft PR #15 / `Red-Alert-Harvester_2.1.17` (`factorio_version` **2.1**).
- **This pack:** branch `2.2.0` / draft PR #17 / `Red-Alert-Harvester_2.2.0` (`factorio_version` **2.0**). M1 index only.
- **Prior 2.0 backdate:** pack `2.1.18` (merged to `master` via PR #16).

## Development branch names

Tester-facing development branches are **just the three-part version**. The Factorio mod `info.json` **name** is singular **`Red-Alert-Harvester`** (portal slug). The pack folder is **`Red-Alert-Harvester_<version>`**.

Do not delete or close the 2.1.17 branch / PR #15. **Do not merge `2.2.0` to `master`.**

GitHub **Code → Download ZIP** produces a folder like **`Red-Alert-Harvesters-2.2.0`** (repo-prefixed, hyphen before the version). That is **not** a Factorio install folder. Use **`Red-Alert-Harvester_2.2.0.zip`**.

## Install naming (Factorio will refuse the wrong zip)

Factorio checks the **file or folder name** against `info.json`. The check is **case-sensitive**.

| What | Exact value |
| --- | --- |
| GitHub repo | `Red-Alert-Harvesters` |
| Git branch (this pack) | `2.2.0` |
| `info.json` `name` | `Red-Alert-Harvester` |
| `info.json` `version` | `2.2.0` |
| `info.json` `factorio_version` | `2.0` |
| Folder in `mods/` | `Red-Alert-Harvester_2.2.0` |
| Zip in `mods/` | `Red-Alert-Harvester_2.2.0.zip` |
| GitHub archive folder | `Red-Alert-Harvesters-2.2.0` (repo-prefixed — **not** an install path) |

The rule is always `{info.json name}_{info.json version}` — here that is **`Red-Alert-Harvester_2.2.0`**.

`info.json` must sit at the **zip root** or **one folder deep** with that same folder name:

```text
Red-Alert-Harvester_2.2.0.zip
  Red-Alert-Harvester_2.2.0/
    info.json
    control.lua
    ...
```

or the same files at the zip root. A zip named `Red-Alert-Harvesters.zip`, `Red-Alert-Harvesters_2.2.0.zip`, or `Red-Alert-Harvesters-2.2.0.zip` will fail to load.

### Where to put it

- **Windows:** `%APPDATA%\Factorio\mods\`
- **Linux (native / most Steam Linux installs):** `~/.factorio/mods/`
- **Steam Deck (native):** `~/.factorio/mods/`
- **Steam Deck / Proton:**  
  `~/.steam/steam/steamapps/compatdata/427520/pfx/drive_c/users/steamuser/AppData/Roaming/Factorio/mods/`

### Package from this repo (Linux / Deck / macOS)

```bash
# from a clone of this branch
rm -rf /tmp/Red-Alert-Harvester_2.2.0 /tmp/Red-Alert-Harvester_2.2.0.zip
mkdir /tmp/Red-Alert-Harvester_2.2.0
rsync -a --exclude .git --exclude .vscode ./ /tmp/Red-Alert-Harvester_2.2.0/
cd /tmp && zip -r Red-Alert-Harvester_2.2.0.zip Red-Alert-Harvester_2.2.0
# copy Red-Alert-Harvester_2.2.0.zip into your Factorio mods folder
```

On Windows: copy the repo into a folder literally named `Red-Alert-Harvester_2.2.0`, then zip that folder.

## Smoke test (Factorio 2.0)

1. Confirm the Mods list shows **C&C Harvesters** / `Red-Alert-Harvester` **2.2.0** with no load error **without** Factorio-Tiberium installed. Use a **2.0 stable** client, not 2.1 experimental. `factorio_version` must be **2.0**. Also boot **with** Tiberium 2.0.x (not the Tib 2.1 line).
2. New Freeplay / sandbox. **Old World Harvesting** requires **solar energy**. Craft an Ore Truck (2×2 grid) and a Refinery. There is **no Hybrid-drive** item. The Tiberium harvester is unlocked by **Tiberium Harvesting** (requires electric engines) and crafts with electric engines.
3. Fuel the truck, drive onto iron/copper/coal/stone. The **slave miner** on the hitch should produce **~1.50 ore/s** with no modules (one item about every 40 ticks). Tiberium is **~3.00/s**. Unload when you sit next to the refinery.
4. SHIFT+E (or click the truck) opens the slave **mining-drill** (starts empty). That GUI is the energy bar: efficiency should lower draw, speed should raise it. Productivity modules should produce bonus ore (native drill prod, not a scripted coin-flip). Recipe solar+battery are **not** in the grid or bay. A charged portable battery should climb the hybrid bar while parked. An empty pool will not mine. Driving must **not** show a moving power pole, accumulator, chest, or floating ore-truck icon square.
5. Optional: Mods → Startup → **Automatic harvester testing** (restart). That turns on the slow chunk index **and** physical auto-drive (pathfinder + car physics, no teleport). Open a truck’s inventory: **Automatic operation** (default on) and **Pause when somebody jumps in** (default off) sit on the left. Auto on + pause off: you ride as **passenger**, AI keeps rolling, WASD does nothing. Auto on + pause on: take the driver seat, AI yields, exit resumes. Uncheck Automatic operation (real click, inventory open) to drive. Enter must **not** dump you on the ground or turn auto off. Low-fuel auto trucks drive to a **fueled refinery** and pull burnables from the chest into the tank (no manual loading). Wire the refinery with red/green to **read chest contents** (enable inserters when iron-ore < N). Two autos will not path through each other (16-tile patch exclusion + pathfinder blockers). Nose-to-nose: one **reverses if the rear is clear, then repaths** (does not freeze). From a stop, trucks **rotate in place** to face the next waypoint, then accelerate. Remotes:

```
/c game.print(serpent.line(remote.call("Red-Alert-Harvester", "chunkindex_stats")))
/c game.print(tostring(remote.call("Red-Alert-Harvester", "chunkindex_enabled")))
/c remote.call("Red-Alert-Harvester", "chunkindex_overlay", true)
/c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed')))
/c game.print(serpent.line(remote.call('Red-Alert-Harvester','chunkindex_reseed', true)))
/c game.print(serpent.line(remote.call('Red-Alert-Harvester','harvester_ai')))
```

**Alt+I** (or the shortcut-bar **Chunk index overlay** button) toggles a pollution-style **map/minimap** overlay (not the world surface): **all** indexed charted chunks on the viewed surface. Green Tib, **orange** Tib-border+ore, yellow harvester / empty Tib-border, red ore, **dim** purple empty scanned, blank unscanned/fog. The chunk being scanned this tick blinks cyan. If the overlay looks striped, those blanks are still unindexed. Default reseed is **missing-only** (no automatic full-map re-chew). Full refresh is `chunkindex_reseed` + `true` or `chunkindex_reseed_full`. Scanner is **1 chunk / 10 ticks** (~1.85 h for 40k generated). Auto-drive assigns from the index within **256 tiles**. Off destroys the overlay render objects.

## Drive-and-harvest rate

No-module baseline is the slave miner’s `mining_speed` (same average as the old 8 / 16 items per 320 ticks). Modules change rate and draw **natively**.

| Vehicle | mining_speed | Interval at 60 UPS | Items per second | Drill draw |
| --- | --- | --- | --- | --- |
| Ore Truck | **1.5** | **~0.67 s** | **~1.50** | **180 kW** (120 kJ/item) |
| Tiberium | **3.0** | **~0.33 s** | **~3.00** | **360 kW** (120 kJ/item) |

One solid fuel (12 MJ) ≈ **100 items** at the no-module tax. Efficiency lowers the energy bar / hybrid drain; speed raises both rate and draw. Productivity adds bonus products on the drill’s prod bar. First sit still waits 40 / 20 ticks so place-on-ore is not free.

## Inventory-full warning

When a drive-harvest scoop cannot fit in the trunk, the truck shows **error-red** localized `Inventory full` floating text (`cncharvester.inventory-full`) for **150 ticks** (~2.5 seconds at 60 UPS). Auto-harvester blocked warnings (`no-empty-refinery`, `no-fuel-refinery`) use the same red/TTL. Informational green `Heading for refuel` is also localized. Colors and TTLs are unchanged.

## Features (same as 2.1.17, on 2.0)

See `FACTORIO_2.0.md` for 2.0 vs 2.1 deltas. Slave mining-drill (fixed 2 / 3 slots, native modules), hybrid-fed micro-grid, 120 kJ/item baseline tax, hybrid-charge pool (never nuclear). Truck recipes cost solar panel + battery and grant a slow built-in recharge (not removable). Hybrid converts player-installed grid/battery energy (parked pull is faster; moving stays below drive). The drill cannot run if the pool cannot pay that tick. Quality bonuses apply only if Space Age / quality is loaded; otherwise they degrade to normal.

## Optional dependency

[Factorio and Conquer: Tiberian Dawn](https://mods.factorio.com/mod/Factorio-Tiberium) **2.0.x**. Do not mix that mod’s 2.1 line with this 2.0 pack. The 2.1 experimental harvester pack is branch `2.1.17`.
