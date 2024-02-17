--[[
	A-Star Algorithm for Lmaobox
	Credits: github.com/GlorifiedPig/Luafinding
	fixed by: titaniummachine1 (https://github.com/titaniummachine1)
]]

local Heap = require("Lmaobot.Heap")

local AStar = {}

AStar.costCache = {}

local function HeuristicCostEstimate(nodeA, nodeB)
	-- Check if the nodes are valid
	if not nodeA or not nodeB then
		print("One or both nodes are nil, exiting function")
		return nil
	end

	-- Check if the nodes have an id and pos
	if not nodeA.id or not nodeA.pos or not nodeB.id or not nodeB.pos then
		print("One or both nodes are missing required properties, exiting function")
		return nil
	end

	-- Check if the cost is already cached
	local costKey = nodeA.id .. "-" .. nodeB.id
	local cachedCost = AStar.costCache[costKey]
	if cachedCost then
		-- Check if the cost is outdated
		local currentTime = os.time()
		if currentTime - cachedCost.time < 120 then
			return cachedCost.cost
		end
	end

	-- Calculate the cost directly from the nodes if it exists
	if nodeA.cost and nodeB.cost then
		local cost = nodeA.cost + nodeB.cost
		AStar.costCache[costKey] = {cost = cost, time = os.time()}
		return cost
	end

	-- If the cost does not exist, calculate the Manhattan distance
	local dx = math.abs(nodeA.x - nodeB.x)
	local dy = math.abs(nodeA.y - nodeB.y)
	local dz = math.abs(nodeA.z - nodeB.z)
	local cost = dx + dy + dz
	AStar.costCache[costKey] = {cost = cost, time = os.time()}
	return cost
end

local function ReconstructPath(current, previous)
	local path = {}
	while current do
		table.insert(path, current)
		current = previous[current]
	end
	return path  -- No need to reverse if you are ok with the path being from end to start
end

local cachedData

function AStar.Path(start, goal, nodes, adjacentFun, maxNodes)
	maxNodes = maxNodes or 100
	local openSet, closedSet, gScore, fScore, previous, processedNodes

	if cachedData then
		-- Continue from cached data
		openSet, closedSet, gScore, fScore, previous, processedNodes = table.unpack(cachedData)
		processedNodes = 0  -- Reset the processedNodes counter
	else
		-- Start a new pathfinding operation
		openSet, closedSet = Heap.new(), {}
		gScore, fScore = {}, {}
		gScore[start] = 0
		fScore[start] = HeuristicCostEstimate(start, goal)
		openSet.Compare = function(a, b) return fScore[a] < fScore[b] end
		openSet:push(start)
		previous = {}
		processedNodes = 0
	end

	while not openSet:empty() and processedNodes < maxNodes do
		local current = openSet:pop()
		if not closedSet[current] then
			processedNodes = processedNodes + 1
			--print("Processed nodes: ", processedNodes)  -- Print the current progress
			if current.id == goal.id then
				openSet:clear()
				cachedData = nil
				return ReconstructPath(current, previous), false
			end

			closedSet[current] = true
			local adjacentNodes = adjacentFun(current, nodes)
			for _, neighbor in ipairs(adjacentNodes) do
				if not closedSet[neighbor] then
					local tentativeGScore = gScore[current] + HeuristicCostEstimate(current, neighbor)
					if not gScore[neighbor] or tentativeGScore < gScore[neighbor] then
						previous[neighbor], gScore[neighbor] = current, tentativeGScore
						fScore[neighbor] = tentativeGScore + HeuristicCostEstimate(neighbor, goal)
						openSet:push(neighbor)
					end
				end
			end
		end
	end

	if not openSet:empty() then
		-- Node limit reached, cache data and stop
		cachedData = {openSet, closedSet, gScore, fScore, previous, processedNodes}
		return nil, true
	end

	return nil, false
end

return AStar
