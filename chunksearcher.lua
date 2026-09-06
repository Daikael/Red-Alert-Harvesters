local result = {}
local Surface = {}

function Surface.lookup(surface)
	for chunk in surface.get_chunks() do
		local resources = surface.find_entities_filtered({area=chunk.area, blah})
		for _, entity in pairs(resources) do
			local cat = entity.prototype.resource_category
			if cat == "basic-solid" or (cat and string.find(cat, "tiberium", 1, true)) then
				for _, resources in pairs(resources) do
					if type(resources) == 'string' then
						if game.surfaces[resources] then
							table.insert(result, game.surfaces[resources])
						end
					elseif type(resources) == 'table' and resources['__self'] then
						table.insert(result, resources)
					end
				end
				return result
			end
		end
	end
end

function Surface.find_all_entities(search_criteria)
	Core.fail_if_missing(search_criteria, "missing search_criteria argument")
	if search_criteria.name == nil and search_criteria.type == nil and search_criteria.area == nil then
		error("Missing search criteria field: name or type	or area of entity", 2)
	end

	local surface_list = Surface.lookup(search_criteria.surface)
	if search_criteria.surface == nil then
		surface_list = game.surfaces
	end

	local result = {}

	for _, surface in pairs(surface_list) do
		local entities = surface.find_entities_filtered(
			{
				area = search_criteria.area,
				name = search_criteria.name,
				type = search_criteria.type,
			})
		for _, entity in pairs(entities) do
			table.insert(result, entity)
		end
	end

	return result
end
function Surface.tiberium()
	Surface.find_all_entities({type = "resource"})
end