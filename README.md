# C&C Harvesters (`Red-Alert-Harvester`)

Resource trucks and a dump refinery from Command & Conquer / Red Alert.

This branch is the **Factorio 2.1 experimental/beta** line (pack `2.1.8`). It is **not** the live 2.0 stable pack on `master`.

Factorio only accepts three-part `major.minor.patch` versions. This pack is **`2.1.8`**. Later unreleased test revs stay on three-part patch bumps (`2.1.9`, `2.1.10`, …).

- **2.0 stable players:** use `master` / `Red-Alert-Harvester_2.0.0`.
- **2.1 experimental:** this branch / `Red-Alert-Harvester_2.1.8`.

## Install naming (Factorio will refuse the wrong zip)

Factorio checks the **file or folder name** against `info.json`. The check is **case-sensitive**. Testers already hit:

```text
Failed to load mod "Red-Alert-Harvesters": Filename of mod .../Red-Alert-Harvesters.zip
doesn't match the expected Red-Alert-Harvester_2.1.8.zip (case sensitive!)
```

| What | Exact value |
| --- | --- |
| GitHub repo | `Red-Alert-Harvesters` (plural) — **do not use this as the zip name** |
| `info.json` `name` | `Red-Alert-Harvester` (singular, no trailing `s`) |
| `info.json` `version` | `2.1.8` |
| Folder in `mods/` | `Red-Alert-Harvester_2.1.8` |
| Zip in `mods/` | `Red-Alert-Harvester_2.1.8.zip` |

The rule is always `{info.json name}_{info.json version}` — here that is **`Red-Alert-Harvester_2.1.8`**.

`info.json` must sit at the **zip root** or **one folder deep** with that same folder name:

```text
Red-Alert-Harvester_2.1.8.zip
  Red-Alert-Harvester_2.1.8/
    info.json
    control.lua
    ...
```

or the same files at the zip root. A zip named `Red-Alert-Harvesters.zip`, `Red-Alert-Harvester.zip`, or `Red-Alert-Harvesters_2.1.8.zip` will fail to load.

### Where to put it

- **Windows:** `%APPDATA%\Factorio\mods\`
- **Linux (native / most Steam Linux installs):** `~/.factorio/mods/`
- **Steam Deck (native):** `~/.factorio/mods/`
- **Steam Deck / Proton:**  
  `~/.steam/steam/steamapps/compatdata/427520/pfx/drive_c/users/steamuser/AppData/Roaming/Factorio/mods/`

### Package from this repo (Linux / Deck / macOS)

```bash
# from a clone of this branch
rm -rf /tmp/Red-Alert-Harvester_2.1.8 /tmp/Red-Alert-Harvester_2.1.8.zip
mkdir /tmp/Red-Alert-Harvester_2.1.8
rsync -a --exclude .git --exclude .vscode ./ /tmp/Red-Alert-Harvester_2.1.8/
cd /tmp && zip -r Red-Alert-Harvester_2.1.8.zip Red-Alert-Harvester_2.1.8
# copy Red-Alert-Harvester_2.1.8.zip into your Factorio mods folder
```

On Windows: copy the repo into a folder literally named `Red-Alert-Harvester_2.1.8`, then zip that folder (not the GitHub repo folder name).

## Smoke test (2.1 experimental)

1. Confirm the Mods list shows **C&C Harvesters** / `Red-Alert-Harvester` **2.1.8** with no load error. Use a **2.1 experimental** client, not 2.0 stable.
2. New Freeplay / sandbox. Research **Old World Harvesting**. Craft an Ore Truck and a Refinery.
3. Fuel the truck, drive onto iron/copper/coal/stone. It should scoop into the trunk about every **5.3 seconds** (320 ticks) with no speed modules, then unload when you sit next to the refinery.
4. SHIFT+E (or click the hitch) opens the companion **module bay** (starts empty). The truck recipe spends a solar panel + battery at craft; they are **not** in the grid or bay (no strip-recycle extra loot). Those ingredients give a **slow built-in recharge**. Install your own portable solar/battery for faster Hybrid refill. An empty or undercharged pool will not scoop.
5. Optional: Mods → Startup → **Automatic harvester testing**, place a fueled truck near ore and a refinery, then save/reload.

## Drive-and-harvest scoop rate

Player-in-vehicle mining uses a **total budget per ~5.3 s period**: **8** items on the Ore Truck, **16** on the Tiberium harvester (not 4 items per ore tile). Fuel cost scales with that yield.

| Build | Ticks between scoops | Interval at 60 UPS | Scoops per minute |
| --- | --- | --- | --- |
| 2.0.0 first drop | 600 (`on_nth_tick(60)` × 10) | every **10** seconds | 6 |
| 2.0 tester fix / this 2.1 base | **320** (countdown ≡ `on_nth_tick(320)`) | every **~5.33** seconds | ~11.25 |

That is **600/320 = 1.875×** as often — just under doubled. Per-period yield is 8 / 16, not a multi-stack dump.

On 2.1, speed modules and entity quality may **shorten** that 320-tick base. Automatic harvesting still uses a short animation stand-in between scoops and was not rebalanced to 320 ticks.

## Inventory-full warning

When a drive-harvest scoop cannot fit in the trunk, the truck shows **error-red** localized `Inventory full` floating text (`cncharvester.inventory-full`) for **150 ticks** (~2.5 seconds at 60 UPS). Auto-harvester blocked warnings (`no-empty-refinery`, `no-fuel-refinery`) use the same red/TTL. Informational green `Heading for refuel` is also localized. Colors and TTLs are unchanged.

## 2.1-only features

See `FACTORIO_2.1.md`: companion module bay (fixed 2 / 3 slots), quality/drain scooping, yield-scaled harvest fuel tax, hybrid-charge pool (never nuclear). Truck recipes cost solar panel + battery and grant a slow built-in recharge (not removable). Hybrid also converts player-installed grid energy (rate-capped; quality scales refill). A scoop requires enough pool energy for the full action.

## Optional dependency

[Factorio and Conquer: Tiberian Dawn](https://mods.factorio.com/mod/Factorio-Tiberium) **2.1.x** (for example 2.1.16). Do not mix that mod’s 2.0.15 line with this 2.1 pack.
