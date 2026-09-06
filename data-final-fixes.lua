-- Attach any Tiberium (or similarly named) solid resource categories to the
-- slave miners. Prototype defaults already include basic-solid / basic-solid-tiberium.

local function add_category(drill, category)
	if not (drill and category) then
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

local ore_bay = data.raw["mining-drill"]["cncharvester-module-bay"]
local tib_bay = data.raw["mining-drill"]["cncharvester-type2-module-bay"]

add_category(ore_bay, "basic-solid")
add_category(ore_bay, "basic-solid-tiberium")
add_category(tib_bay, "basic-solid")
add_category(tib_bay, "basic-solid-tiberium")

for _, resource in pairs(data.raw.resource or {}) do
	local category = resource.category
	if category and string.find(category, "tiberium", 1, true) then
		add_category(ore_bay, category)
		add_category(tib_bay, category)
	end
end
