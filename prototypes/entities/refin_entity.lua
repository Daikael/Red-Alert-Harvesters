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
		-- Factorio 2.0 ContainerPrototype: circuit_wire_max_distance defaults to 0,
		-- so wires will not connect unless set. Mirror vanilla steel-chest: max
		-- distance + circuit_connector. Wired containers always emit inventory
		-- item signals (no extra "read contents" prototype flag).
		circuit_wire_max_distance = default_circuit_wire_max_distance,
		circuit_connector = circuit_connector_definitions.create_vector(
			universal_connector_template,
			{
				{
					variation = 26,
					-- North face (dump / belt side) so the pins are clickable.
					main_offset = util.by_pixel(24, -88),
					shadow_offset = util.by_pixel(28.5, -86),
					show_shadow = true,
				},
			}
		),
		draw_circuit_wires = true,
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