-- A-Star Algorithm for Lmaobox
-- Credits: github.com/GlorifiedPig/Luafinding

local Heap = require("Lmaobot.Utils.Heap")

---@alias PathNode { id : integer, pos : Vector3 }

---@class AStar
local AStar = {}

local function HeuristicCostEstimate(nodeA, nodeB)
    return (nodeB.pos - nodeA.pos):Length()
end

local function ReconstructPath(current, previous)
    local path = { current }
    while previous[current.id] do
        current = previous[current.id]
        table.insert(path, current)
    end
    return path
end

function AStar.Path(startNode, goalNode, nodes, adjacentFun)
    local openSet = Heap.new()
    local closedSet = {}
    local gScore = {}
    local fScore = {}
    local previous = {}

    gScore[startNode.id] = 0
    fScore[startNode.id] = HeuristicCostEstimate(startNode, goalNode)

    openSet.Compare = function(a, b) return fScore[a.id] < fScore[b.id] end
    openSet:push(startNode)

    while not openSet:empty() do
        local current = openSet:pop()

        if not closedSet[current.id] then
            if current.id == goalNode.id then
                openSet:clear()
                return ReconstructPath(current, previous)
            end

            closedSet[current.id] = true

            local adjacentNodes = adjacentFun(current, nodes)
            for _, neighbor in ipairs(adjacentNodes) do
                if not closedSet[neighbor.id] then
                    local tentativeGScore = gScore[current.id] + HeuristicCostEstimate(current, neighbor)

                    if not gScore[neighbor.id] or tentativeGScore < gScore[neighbor.id] then
                        gScore[neighbor.id] = tentativeGScore
                        fScore[neighbor.id] = tentativeGScore + HeuristicCostEstimate(neighbor, goalNode)
                        previous[neighbor.id] = current
                        openSet:push(neighbor)
                    end
                end
            end
        end
    end

    return nil
end

return AStar
