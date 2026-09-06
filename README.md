# C&C Harvesters (`Red-Alert-Harvester`)

Resource trucks and a dump refinery from Command & Conquer / Red Alert, ported to **public Factorio 2.0 stable**.

This is not a Factorio 2.1 / experimental build. Use a 2.0.x stable client (for example 2.0.77).

## Install naming (Factorio will refuse the wrong zip)

Factorio checks the **file or folder name** against `info.json`. The check is **case-sensitive**. Testers already hit:

```text
Failed to load mod "Red-Alert-Harvesters": Filename of mod .../Red-Alert-Harvesters.zip
doesn't match the expected Red-Alert-Harvester_2.0.0.zip (case sensitive!)
```

| What | Exact value |
| --- | --- |
| GitHub repo | `Red-Alert-Harvesters` (plural) — **do not use this as the zip name** |
| `info.json` `name` | `Red-Alert-Harvester` (singular, no trailing `s`) |
| `info.json` `version` | `2.0.0` |
| Folder in `mods/` | `Red-Alert-Harvester_2.0.0` |
| Zip in `mods/` | `Red-Alert-Harvester_2.0.0.zip` |

The rule is always `{info.json name}_{info.json version}` — here that is **`Red-Alert-Harvester_2.0.0`**.

`info.json` must sit at the **zip root** or **one folder deep** with that same folder name:

```text
Red-Alert-Harvester_2.0.0.zip
  Red-Alert-Harvester_2.0.0/
    info.json
    control.lua
    ...
```

or the same files at the zip root. A zip named `Red-Alert-Harvesters.zip`, `Red-Alert-Harvester.zip`, or `Red-Alert-Harvesters_2.0.0.zip` will fail to load.

### Where to put it

- **Windows:** `%APPDATA%\Factorio\mods\`
- **Linux (native / most Steam Linux installs):** `~/.factorio/mods/`
- **Steam Deck (native):** `~/.factorio/mods/`
- **Steam Deck / Proton:**  
  `~/.steam/steam/steamapps/compatdata/427520/pfx/drive_c/users/steamuser/AppData/Roaming/Factorio/mods/`

### Package from this repo (Linux / Deck / macOS)

```bash
# from a clone of this branch
rm -rf /tmp/Red-Alert-Harvester_2.0.0 /tmp/Red-Alert-Harvester_2.0.0.zip
mkdir /tmp/Red-Alert-Harvester_2.0.0
rsync -a --exclude .git --exclude .vscode --exclude README.md ./ /tmp/Red-Alert-Harvester_2.0.0/
cd /tmp && zip -r Red-Alert-Harvester_2.0.0.zip Red-Alert-Harvester_2.0.0
# copy Red-Alert-Harvester_2.0.0.zip into your Factorio mods folder
```

On Windows: copy the repo into a folder literally named `Red-Alert-Harvester_2.0.0`, then zip that folder (not the GitHub repo folder name).

## Smoke test (2.0 stable)

1. Confirm the Mods list shows **C&C Harvesters** / `Red-Alert-Harvester` **2.0.0** with no load error.
2. New Freeplay / sandbox. Research **Old World Harvesting**. Craft an Ore Truck and a Refinery.
3. Fuel the truck, drive onto iron/copper/coal/stone. It should scoop into the trunk on a timer (see below), then unload when you sit next to the refinery.
4. Optional: Mods → Startup → **Automatic harvester testing**, place a fueled truck near ore and a refinery, then save/reload.

## Drive-and-harvest scoop rate

Player-in-vehicle mining (`control.lua`) runs on `script.on_nth_tick(60)` and scoops when an internal counter hits **`DRIVE_MINE_INTERVAL`**:

| Build | Interval (60 UPS) | Scoops per minute |
| --- | --- | --- |
| 2.0.0 first drop | every **10** seconds | 6 |
| this branch | every **6** seconds | 10 |

That is **10/6 ≈ 1.67×** — just under doubled. Testers called the 10s cadence pedestrian; 5s would be an exact 2×, so **6** is the chosen “just under 2×” value.

Automatic harvesting (the experimental startup flag) uses a short ~32-tick wait as a stand-in for missing scoop animations. That is already much faster than the drive timer and was **not** rebalanced, so auto pathing stay the same.

## Optional dependency

[Factorio and Conquer: Tiberian Dawn](https://mods.factorio.com/mod/Factorio-Tiberium) **2.0.x** (for example 2.0.15). Do not mix that mod’s 2.1 line with this 2.0 pack.
