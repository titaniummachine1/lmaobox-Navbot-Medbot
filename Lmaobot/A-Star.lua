--[[
	A-Star Algorithm for Lmaobox
	Credits: github.com/GlorifiedPig/Luafinding
]]

local Heap = require("Lmaobot.Heap")

---@alias PathNode { id : integer, x : number, y : number, z : number }

---@class AStar
local AStar = {}

-- Calculates Manhattan Distance between two nodes
local function ManhattanDistance(nodeA, nodeB)
    return math.abs(nodeB.pos.x - nodeA.pos.x) + math.abs(nodeB.pos.y - nodeA.pos.y)
end

local function HeuristicCostEstimate(nodeA, nodeB)
    return ManhattanDistance(nodeA, nodeB)
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

    openSet.Compare = function(a, b) return fScore[a.node] < fScore[b.node] end
    openSet:push({node = start, path = {start}})

    while not openSet:empty() do
        local currentData = openSet:pop()
        local current = currentData.node
        local currentPath = currentData.path

        if current.id == goal.id then
            local reversedPath = {}
            for i = #currentPath, 1, -1 do
                table.insert(reversedPath, currentPath[i])
            end
            return reversedPath
        end

        closedSet[current] = true

        local adjacentNodes = adjacentFun(current, nodes)
        for _, neighbor in ipairs(adjacentNodes) do
            if not closedSet[neighbor] then
                local tentativeGScore = gScore[current] + HeuristicCostEstimate(current, neighbor)

                if not gScore[neighbor] or tentativeGScore < gScore[neighbor] then
                    gScore[neighbor] = tentativeGScore
                    fScore[neighbor] = tentativeGScore + HeuristicCostEstimate(neighbor, goal)

                    local newPath = {table.unpack(currentPath)}
                    table.insert(newPath, neighbor)

                    openSet:push({node = neighbor, path = newPath})
                end
            end
        end
    end

    return nil -- Path not found if loop exits
end

return AStar
