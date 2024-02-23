--[[
	A-Star Algorithm for Lmaobox
	Credits: github.com/GlorifiedPig/Luafinding
]]

local Heap = require("Lmaobot.Heap")

---@alias PathNode { id : integer, x : number, y : number, z : number }

---@class AStar
local AStar = {}

local function HeuristicCostEstimate(nodeA, nodeB)
	return math.sqrt((nodeB.x - nodeA.x) ^ 2 + (nodeB.y - nodeA.y) ^ 2 + (nodeB.z - nodeA.z) ^ 2)
end

local function ReconstructPath(current, previous)
	local path = { current }
	while previous[current] do
		current = previous[current]
		table.insert(path, current)
	end

	return path
end

---@param start PathNode
---@param goal PathNode
---@param nodes PathNode[]
---@param adjacentFun fun(node : PathNode, nodes : PathNode[]) : PathNode[]
---@return PathNode[]|nil
function AStar.Path(start, goal, nodes, adjacentFun)
	local openSet, closedSet = Heap.new(), {}
	local gScore, fScore = {}, {}
	gScore[start] = 0
	fScore[start] = HeuristicCostEstimate(start, goal)

	openSet.Compare = function(a, b) return fScore[a] < fScore[b] end
	openSet:push(start)

	local previous = {}
	while not openSet:empty() do
		---@type PathNode
		local current = openSet:pop()

		if not closedSet[current] then

			-- Found the goal
			if current.id == goal.id then
				openSet:clear()
				return ReconstructPath(current, previous)
			end

			closedSet[current] = true

			-- Traverse adjacent nodes
			local adjacentNodes = adjacentFun(current, nodes)
			for i = 1, #adjacentNodes do
				local neighbor = adjacentNodes[i]
				if not closedSet[neighbor] then
					local tentativeGScore = gScore[current] + HeuristicCostEstimate(current, neighbor)

					local neighborGScore = gScore[neighbor]
					if not neighborGScore or tentativeGScore < neighborGScore then
						gScore[neighbor] = tentativeGScore
						fScore[neighbor] = tentativeGScore + HeuristicCostEstimate(neighbor, goal)
						previous[neighbor] = current
						openSet:push(neighbor)
					end
				end
			end
		end
	end

	return nil
end

return AStar