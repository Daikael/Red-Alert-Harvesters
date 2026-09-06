-- 2.1: no known startup-setting prototype break vs 2.0.
-- Quality / module / hybrid behavior is scripted (see scoop.lua, hybriddrive.lua).
data:extend(
	{
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
