-- Slave-miner resource categories.
--
-- Boot (2.1.12 Deck, no Tiberium mod):
--   assignID: resource-category 'basic-solid-tiberium' does not exist
--   at ROOT.mining-drill.cncharvester-module-bay.resource_categories[1]
--
-- That name is defined by Factorio-Tiberium (prototype/resource.lua), not by
-- vanilla and not by this pack. Do not invent a fake category to satisfy the
-- drill. Prototypes ship with basic-solid only.
--
-- When Factorio-Tiberium is loaded, its data-updates.lua adds
-- basic-solid-tiberium to every drill that already mines basic-solid. This
-- file runs after that:
--   Ore Truck bay  → vanilla solids only (strip any injected Tiberium cats)
--   Type-2 bay     → keep basic-solid, plus any *existing* Tiberium categories

local function category_exists(name)
	return name and data.raw["resource-category"] and data.raw["resource-category"][name] ~= nil
end

local function add_category(drill, category)
	if not (drill and category_exists(category)) then
		return
	end
	drill.resource_categories = drill.resource_categories or {}
	for _, existing in pairs(drill.resource_categories) do
		if existing == category then
			return
		end
	end
	table.insert(drill.resource_categories, category)
end

local function is_tiberium_category(name)
	return name and name ~= "basic-solid" and string.find(name, "tiberium", 1, true) ~= nil
end

local function strip_tiberium_categories(drill)
	if not (drill and drill.resource_categories) then
		return
	end
	local kept = {}
	for _, category in pairs(drill.resource_categories) do
		if category == "basic-solid" or not is_tiberium_category(category) then
			table.insert(kept, category)
		end
	end
	if #kept == 0 then
		kept = {"basic-solid"}
	end
	drill.resource_categories = kept
end

local ore_bay = data.raw["mining-drill"]["cncharvester-module-bay"]
local tib_bay = data.raw["mining-drill"]["cncharvester-type2-module-bay"]

-- Ore Truck: vanilla ores only, even if Tiberium injected its category.
if ore_bay then
	strip_tiberium_categories(ore_bay)
	add_category(ore_bay, "basic-solid")
end

-- Tiberium harvester: vanilla solids plus real Tiberium categories only.
if tib_bay then
	add_category(tib_bay, "basic-solid")
	if category_exists("basic-solid-tiberium") then
		add_category(tib_bay, "basic-solid-tiberium")
	end
	for name in pairs(data.raw["resource-category"] or {}) do
		if is_tiberium_category(name) then
			add_category(tib_bay, name)
		end
	end
	for _, resource in pairs(data.raw.resource or {}) do
		if is_tiberium_category(resource.category) then
			add_category(tib_bay, resource.category)
		end
	end
end
