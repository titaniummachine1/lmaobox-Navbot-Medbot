--[[
	A-Star Algorithm for Lmaobox
	Credits: github.com/GlorifiedPig/Luafinding
	fixed by: titaniummachine1 (https://github.com/titaniummachine1)
]]

local Heap = require("Lmaobot.Heap")

local AStar = {}

-- Precompute adjacent nodes to reduce calculations in the main loop if possible.

local function HeuristicCostEstimate(nodeA, nodeB)
	return math.abs(nodeB.x - nodeA.x) + math.abs(nodeB.y - nodeA.y) + math.abs(nodeB.z - nodeA.z) -- Manhattan distance
end

local function ReconstructPath(current, previous)
	local path = {}
	while current do
		table.insert(path, current)
		current = previous[current]
	end
	return path  -- No need to reverse if you are ok with the path being from end to start
end

function AStar.Path(start, goal, nodes, adjacentFun)
	local openSet, closedSet = Heap.new(), {}
	local gScore, fScore = {}, {}
	gScore[start] = 0
	fScore[start] = HeuristicCostEstimate(start, goal)

	openSet.Compare = function(a, b) return fScore[a] < fScore[b] end
	openSet:push(start)

	local previous = {}
	while not openSet:empty() do
		local current = openSet:pop()
		if not closedSet[current] then
			if current.id == goal.id then
				openSet:clear()
				return ReconstructPath(current, previous)
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
	return nil
end

return AStar