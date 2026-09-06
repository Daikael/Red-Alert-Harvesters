data:extend({
	{
		type = "technology",
		name = "Old-World-Harvesting",
		-- solar-energy matches the solar-panel already in the Ore Truck recipe.
		prerequisites = {"steel-processing", "engine", "solar-energy"},
		icon = "__Red-Alert-Harvester__/graphics/icons/refin_icon.png",
		icon_size = 32,
		effects =
		{
			{
				type = "unlock-recipe",
				recipe = "cncharvester"
			},
			{
				type = "unlock-recipe",
				recipe = "refinery"
			}
		},
		unit =
		{
			count = 100,
			-- 2.1: science packs are plain items. Official docs still accept {name, amount} tuples.
			ingredients =
			{
				{"automation-science-pack", 2},
				{"logistic-science-pack", 1}
			},
			time = 20
		}
	},
	{
		type = "technology",
		name = "Tiberium-Harvesting",
		prerequisites = {"Old-World-Harvesting", "electric-engine"},
		icon = "__Red-Alert-Harvester__/graphics/icons/harv_icon-type2.png",
		icon_size = 32,
		effects =
		{
			{
				type = "unlock-recipe",
				recipe = "cncharvester-type2"
			}
		},
		unit =
		{
			count = 150,
			ingredients =
			{
				{"automation-science-pack", 1},
				{"logistic-science-pack", 1},
				{"chemical-science-pack", 1}
			},
			time = 30
		}
	}
})
