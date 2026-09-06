data:extend(
{
	{
		type = "container",
		name = "refinery",
		icon = "__Red-Alert-Harvester__/graphics/icons/refin_icon.png",
		icon_size = 32,
		flags = {"placeable-neutral", "player-creation"},
		minable = {mining_time = 1, result = "refinery"},
		max_health = 10000,
		corpse = "big-remnants",
		collision_box = {{-2, -3}, {3.5, 1.2}},
		selection_box = {{-2, -3}, {3.5, 1.2}},
 		--{{left,up}{right,down}},--
		inventory_size = 160,
		-- 2.1: ContainerPrototype.picture is Sprite4Way, which still accepts a single Sprite
		-- (applied to all directions). Directional art is not required to load.
		picture =
		{
			filename = "__Red-Alert-Harvester__/graphics/entity/refinery/refinery.png",
			priority = "extra-high",
			width = 216,
			height = 216,
			shift = {0.3, 0}
		},
	}
}
)