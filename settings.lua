-- Startup settings are the same on Factorio 2.0 and 2.1.
-- Quality radius / hybrid behavior is scripted. Mining modules apply on the slave drill.
data:extend(
	{
		-- Identity is load-bearing. Do not rename, change setting_type, or
		-- change type (bool-setting). Factorio then drops the saved value and
		-- falls back to default_value (false), which looks like auto "died
		-- between zips." Overwriting the same 2.2.0 zip can still reset the
		-- mods-GUI copy to default off — re-enable + restart.
		{
			type = "bool-setting",
			name = "Auto-cncharvester-testing",
			setting_type = "startup",
			default_value = false
		},
		{
			type = "bool-setting",
			name = "harvester-auto-by-default",
			setting_type = "startup",
			default_value = false
		}
		-- Runtime cncharvester-chunk-index removed: the M1 scanner follows
		-- Auto-cncharvester-testing only (one clear gate; restart required).
		--[[ ,
		{
			type = "int-setting",
			name = "Auto-cncharvester-Ragne",
			setting_type = "startup",
			default_value = 200,
			maximum_value = 1000,
			minimum_value = 50
		} ]]
	}
)
