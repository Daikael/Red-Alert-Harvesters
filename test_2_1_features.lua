-- Pure-function checks for scoop / hybrid math. Run with: lua test_2_1_features.lua
-- Does not require Factorio.

package.path = "./?.lua;" .. package.path

-- Minimal stubs so scoop.lua can load without Factorio.
package.loaded.utilities = true
package.loaded.modulebay = true
package.loaded.specialOres = true
prototypes = {quality = {}}
SpecialOres = {}
function ResourceProductItemName() return "iron-ore" end
function IsHarvestableResource() return true end
function InventoryItemStack(name, count, quality)
	return {name = name, count = count, quality = quality}
end
ModuleBay = {effects = function() return {speed=0,productivity=0,consumption=0,pollution=0,quality=0} end}

dofile("scoop.lua")
dofile("hybriddrive.lua")

local fails = 0
local function expect(cond, msg)
	if not cond then
		fails = fails + 1
		print("FAIL: " .. msg)
	else
		print("ok  " .. msg)
	end
end

-- Quality drain: missing prototype field uses 1/6 per level.
expect(math.abs(Scoop.drain_multiplier({level = 0}, 0) - 1) < 1e-9, "normal drain 100%")
expect(math.abs(Scoop.drain_multiplier({level = 1}, 0) - (5/6)) < 1e-9, "uncommon drain 5/6")
expect(Scoop.drain_multiplier({mining_drill_resource_drain_multiplier = 0.5}, 0) == 0.5, "uses prototype drain field")
local with_eff = Scoop.drain_multiplier({mining_drill_resource_drain_multiplier = 1}, -0.4)
expect(with_eff < 1 and with_eff > 0.8, "efficiency slightly reduces drain")

expect(Scoop.radius(1, 0) == 1, "normal radius")
expect(Scoop.radius(1, 2) == 1.5, "rare radius +0.5")

expect(Scoop.BASE_DRIVE_INTERVAL_TICKS == 320, "drive base is 320 ticks (1.875× vs 600)")
expect(Scoop.interval_ticks(320, 0, 0) == 320, "unmodified drive interval 320")
expect(Scoop.DRIVE_ITEMS_PER_SCOOP == 4, "volume per scoop unchanged")
local interval = Scoop.interval_ticks(320, 0.5, 2)
expect(interval < 320 and interval >= Scoop.MIN_INTERVAL_TICKS, "speed+quality shortens from 320")

local q = {name = "normal", next = {name = "uncommon", next_probability = 0, next = nil}}
local always = Scoop.roll_quality_fallback(q, 1, function() return 0 end)
expect(always.name == "uncommon", "quality effect 100% promotes")
local never = Scoop.roll_quality_fallback(q, 0, function() return 0 end)
expect(never.name == "normal", "quality effect 0 stays")

local ore = HybridDrive.rates("cncharvester")
expect(ore ~= nil, "ore truck rates")
expect(math.abs(ore.drive_w - 75000) < 1, "drive draw 75 kW (150kW / effectivity 2)")
expect(ore.drive_w > ore.refill_w, "driving outstrips refill")
expect(math.abs(ore.drive_w / ore.refill_w - 1.10) < 1e-6, "drive is 10% above refill")
expect(math.abs(ore.grid_pull_w * HybridDrive.CONVERSION_EFFICIENCY - ore.refill_w) < 1e-6, "90% conversion")

local tib = HybridDrive.rates("cncharvester-type2")
expect(math.abs(tib.drive_w - 87500) < 1, "type2 drive draw 87.5 kW")
expect(tib.drive_w > tib.refill_w, "type2 driving outstrips refill")

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all scoop/hybrid rate checks passed")
