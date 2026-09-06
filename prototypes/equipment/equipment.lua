data:extend (
	{
		-- Converter identity. Script pulls grid energy when this is installed.
		-- Battery-equipment (not solar): generation is not the conversion path.
		{
			type = "battery-equipment",
			name = "Hybrid-drive",
			sprite =
			{
				filename = "__Red-Alert-Harvester__/graphics/equipment/Hybrid-drive.png",
				width = 64,
				height = 64,
				priority = "medium"
			},
			shape =
			{
				width = 1,
				height = 1,
				type = "full"
			},
			energy_source =
			{
				type = "electric",
				buffer_capacity = "1MJ",
				usage_priority = "tertiary"
			},
			categories = {"armor"}
		},
		{
			type = "battery-equipment",
			name = "Hybrid-drive-battery",
			sprite =
			{
				filename = "__Red-Alert-Harvester__/graphics/equipment/Hybrid-drive.png",
				width = 64,
				height = 64,
				priority = "medium"
			},
			shape =
			{
				width = 1,
				height = 1,
				type = "full"
			},
			energy_source =
			{
				type = "electric",
				buffer_capacity = "7MJ",
				usage_priority = "tertiary"
			},
			categories = {"armor"}
		}
	}
)