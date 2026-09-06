data:extend(
{
	{
		type = "recipe",
		name = "refinery",
		enabled = false,
		-- 2.1: RecipePrototype.category / additional_categories were removed; use categories.
		categories = {"crafting"},
		ingredients =
		{
			{type = "item", name = "stone-brick", amount = 100},
			{type = "item", name = "steel-plate", amount = 10}
		},
		results =
		{
			{type = "item", name = "refinery", amount = 1}
		}
	}
}
)
