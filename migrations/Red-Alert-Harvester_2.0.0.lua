-- Re-apply recipe unlocks after the 2.0 recipe format migration.
for _, force in pairs(game.forces) do
	local tech = force.technologies["Old-World-Harvesting"]
	if tech and tech.researched then
		if force.recipes["cncharvester"] then
			force.recipes["cncharvester"].enabled = true
		end
		if force.recipes["cncharvester-type2"] then
			force.recipes["cncharvester-type2"].enabled = true
		end
		if force.recipes["refinery"] then
			force.recipes["refinery"].enabled = true
		end
	end
end
