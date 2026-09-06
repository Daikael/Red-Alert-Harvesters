data:extend(
{
	{
		type = "recipe",
		name = "cncharvester",
		enabled = false,
		-- 2.1: RecipePrototype.category / additional_categories were removed; use categories.
		categories = {"crafting"},
		ingredients =
		{
			{type = "item", name = "engine-unit", amount = 8},
			{type = "item", name = "iron-plate", amount = 20},
			{type = "item", name = "steel-plate", amount = 5},
			{type = "item", name = "iron-chest", amount = 1},
			{type = "item", name = "steel-chest", amount = 1},
			{type = "item", name = "solar-panel", amount = 1},
			{type = "item", name = "battery", amount = 1}
		},
		results =
		{
			{type = "item", name = "cncharvester", amount = 1}
		}
	},
	{
		type = "recipe",
		name = "cncharvester-type2",
		enabled = false,
		categories = {"crafting"},
		ingredients =
		{
			{type = "item", name = "cncharvester", amount = 1},
			{type = "item", name = "engine-unit", amount = 10},
			{type = "item", name = "iron-plate", amount = 100},
			{type = "item", name = "steel-plate", amount = 25},
			{type = "item", name = "steel-chest", amount = 2},
			{type = "item", name = "solar-panel", amount = 1},
			{type = "item", name = "battery", amount = 1}
		},
		results =
		{
			{type = "item", name = "cncharvester-type2", amount = 1}
		}
	},
	{
		type = "recipe",
		name = "Hybrid-drive",
		enabled = false,
		energy_required = 10,
		categories = {"crafting"},
		ingredients =
		{
			{type = "item", name = "solar-panel", amount = 1},
			{type = "item", name = "advanced-circuit", amount = 2},
			{type = "item", name = "steel-plate", amount = 5}
		},
		results =
		{
			{type = "item", name = "Hybrid-drive", amount = 1}
		}
	},
	{
		type = "recipe",
		name = "Hybrid-drive-battery",
		enabled = false,
		energy_required = 5,
		categories = {"crafting"},
		ingredients =
		{
			{type = "item", name = "battery", amount = 5},
			{type = "item", name = "iron-plate", amount = 5}
		},
		results =
		{
			{type = "item", name = "Hybrid-drive-battery", amount = 1}
		}
	}
	--[[{
		type = "recipe",
		name = "cncharvester-remote",
		enabled = false,
		ingredients =
		{
			{type = "item", name = "engine-unit", amount = 1},
			{type = "item", name = "radar", amount = 1}
		},
		results =
		{
			{type = "item", name = "spidertron-remote", amount = 1}
		}
	},]]
		--[[{
		type = "recipe",
		name = "Hybrid-drive",
		enabled = false,
		energy_required = 10,
		ingredients =
		{
			{type = "item", name = "solar-panel", amount = 1},
			{type = "item", name = "advanced-circuit", amount = 2},
			{type = "item", name = "steel-plate", amount = 5}
		},
		results =
		{
			{type = "item", name = "Hybrid-drive", amount = 1}
		}
	}]]
}
)
