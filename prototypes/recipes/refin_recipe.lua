data:extend(
{
	{
		type = "recipe",
		name = "refinery",
		enabled = false,
		-- Factorio 2.0 RecipePrototype.category (string). 2.1 replaced this with categories.
		category = "crafting",
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
