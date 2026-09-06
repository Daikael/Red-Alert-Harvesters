for _, force in pairs(game.forces) do
	if force.technologies["Old-World-Harvesting"] then
		force.recipes["cncharvester-type2"].enabled = true
	end
end
