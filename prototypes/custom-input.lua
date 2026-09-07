data:extend({
	{
		type = "custom-input",
		name = "cncharvester-open-module-bay",
		key_sequence = "SHIFT + E",
		consuming = "none"
	},
	{
		type = "custom-input",
		name = "cncharvester-chunkindex-overlay",
		key_sequence = "ALT + I",
		consuming = "none"
	},
	{
		type = "shortcut",
		name = "cncharvester-chunkindex-overlay",
		action = "lua",
		toggleable = true,
		associated_control_input = "cncharvester-chunkindex-overlay",
		localised_name = {"shortcut-name.cncharvester-chunkindex-overlay"},
		order = "c[toggles]-h[chunkindex-overlay]",
		icon = "__Red-Alert-Harvester__/graphics/icons/harv_icon.png",
		icon_size = 32,
		small_icon = "__Red-Alert-Harvester__/graphics/icons/harv_icon.png",
		small_icon_size = 32
	}
})
