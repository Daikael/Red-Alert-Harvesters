data:extend (
	{
		-- Optional extra grid buffer. Hybrid conversion reads any stored
		-- equipment energy and does not require this item to be installed.
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