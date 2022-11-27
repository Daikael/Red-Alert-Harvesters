data:extend (
    {
          {
            type = "solar-panel-equipment",
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
              buffer_capacity = "7MJ",
              usage_priority = "tertiary"
            },
            power = "0.4kW",
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
            power = "0.4kW",
            categories = {"armor"}
          }
    }
)