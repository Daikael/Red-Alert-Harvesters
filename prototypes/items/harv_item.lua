for i=1,2 do
	local suffix = (i > 1) and ("-type"..i) or ""
	data:extend(
	{
		{
			type = "item-with-entity-data",
			name = "cncharvester"..suffix,
			icon = "__Red-Alert-Harvester__/graphics/icons/harv_icon"..suffix..".png",
			icon_size = 32,
			subgroup = "transport",
			order = "b[personal-transport]-a[cncharvester]-b[car]",
			place_result = "cncharvester"..suffix,
			stack_size = 1
		},
		--[[{
			type = "selection-tool",
			name = "cncharvester-remote",
			icon = "__base__/graphics/icons/spidertron-remote.png",
			icon_color_indicator_mask = "__base__/graphics/icons/spidertron-remote-mask.png",
			icon_size = 64,
			subgroup = "tool",
			order = "b[personal-transport]-c[cncharvester]-b[remote]",
			stack_size = 1,
			stackable = false,
			selection_color = {r = 0.3, g = 0.9, b = 0.3},
			alt_selection_color = {r = 0.9, g = 0.9, b = 0.3},
			selection_mode = {"same-force"},
			alt_selection_mode = {"same-force"},
			selection_cursor_box_type = "copy",
			alt_selection_cursor_box_type = "entity"
		},]]
	}
	)
end