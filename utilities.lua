--[[function Error(text)
	for _, cncharvester in pairs(global.cncharvesters) do
		cncharvester:ErrorDump()
	end
	for _, refinery in pairs(global.refineries) do
		refinery:ErrorDump()
	end
	for _, player in pairs(game.players) do
		if text then
			player.print(text)
		end
		player.print("Active cncharvesters/refineries: " .. #global.cncharvesters .. "/" .. #global.refineries)
	end
	game.speed = 0
end		]]
function on_init()
	global.sortedFuels = getFuelsSortedByValue(items, function(a, b) return a > b end)
end


function getFuelsSortedByValue(tbl, sortFunction)
	local fuelname = {}
	local fuelvalue = {}
	local fuel_list = {}

	for _, proto in pairs(game.get_filtered_item_prototypes({{filter = "fuel-category", ["fuel-category"] = "chemical"}})) do
		if proto.fuel_value > 0 then
			fuel_list[proto.name] = proto.stack_size
		end
	end

	for fuel_name in pairs(fuel_list) do
		if contents[fuel_name] then
			table.sort(fuelvalue, function(a, b)
				return sortFunction(tbl[a], tbl[b])
			end)
			break
		end
	end

	return fuelvalue
end

function DeltaposToOrientation(dPos)
	if dPos.x == 0 then
		if dPos.y > 0 then
			return 0.5
		else
			return 0
		end
	elseif dPos.x > 0 then
		return (math.atan(dPos.y / dPos.x) / (2 * math.pi) + 0.25)
	else
		return (math.atan(dPos.y / dPos.x) / (2 * math.pi) + 0.75)
	end
end

function GetBoundingBox(position, radius)
	return {
		{position.x - radius, position.y - radius},
		{position.x + radius, position.y + radius}
	}
end

function FindNearestEntity(baseEntity, entList)
	local closestEntity = false
	local minDist = math.huge
	for _, entity in pairs(entList) do
		local dPos = Vector.subtract(baseEntity.position, entity.position)
		local dist = Vector.length(dPos)
		
		if dist < minDist then
			closestEntity = entity
			minDist = dist
		end
	end
	return closestEntity
end

function GetOccupiedSlots(inventory)
	local slotsOccupied = 0	
	for itemName, count in pairs(inventory.get_contents()) do
		slotsOccupied = slotsOccupied + math.ceil(count / game.item_prototypes[itemName].stack_size)
	end
	return slotsOccupied
end

Vector = {
	add = function(p1, p2)
		if not p2.x then
			return {x = p1.x + p2[1], y = p1.y + p2[2]}
		end
		return {x = p1.x + p2.x, y = p1.y + p2.y}
	end,

	subtract = function(p1, p2)
		if not p2.x then
			return {x = p1.x - p2[1], y = p1.y - p2[2]}
		end
		return {x = p1.x - p2.x, y = p1.y - p2.y}
	end,
	
	mul = function(p1, c)
		return {x = p1.x * c, y = p1.y * c}
	end,
	
	div = function(p1, c)
		return {x = p1.x / c, y = p1.y / c}
	end,
	
	dist = function(p1, p2)
		return Vector.length(Vector.subtract(p1, p2))
	end,
	
	distsq = function(p1, p2)
		return Vector.lengthsq(Vector.subtract(p1, p2))
	end,
	
	length = function(Vector)
		return math.sqrt((Vector.x * Vector.x) + (Vector.y * Vector.y))
	end,
	
	lengthsq = function(Vector)
		return (Vector.x * Vector.x) + (Vector.y * Vector.y)
	end,
	
	normalized = function(Vector)
		local length = Vector.length(Vector)
		return {x = Vector.x / length, y = Vector.y / length}
	end,
}