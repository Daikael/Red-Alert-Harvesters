data:extend({
	{
		type = "technology",
		name = "Old-World-Harvesting",
		prerequisites = {"steel-processing", "engine"},
		icon = "__Red-Alert-Harvesters__/graphics/icons/refin_icon.png",
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
			},
			{
				type = "unlock-recipe",
				recipe = "cncharvester-type2"
			},
			{
				type = "unlock-recipe",
				recipe = "Hybrid-drive"
			},
			{
				type = "unlock-recipe",
				recipe = "Hybrid-drive-battery"
			}
			--[[{
				type = "unlock-recipe",
				recipe = "cncharvester-remote"
			}]]
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
	}
	--[[{
		type = "technology",
		name = "Hybrid-Electric_Engines",
			prerequisites = {"Old-World-Harvesting"},
		icon = "__Red-Alert-Harvesters__/graphics/equipment/Hybrid-drive.png",
		icon_size = 64,
		effects = 
		{
			{
				type = "unlock-recipe",
				recipe = "Hybrid-drive"
			}
		},
		unit =
		{
			count = 50,
			ingredients =
			{
				{"automation-science-pack", 1},
				{"logistic-science-pack", 1}
			},
			time = 20
		}
	}]]
})