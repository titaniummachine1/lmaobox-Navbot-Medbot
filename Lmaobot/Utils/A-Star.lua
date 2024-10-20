-- A-Star Algorithm for Lmaobox
-- Credits: github.com/GlorifiedPig/Luafinding.

local Heap = require("Lmaobot.Utils.Heap")

---@alias PathNode { id : integer, pos : Vector3 }

---@class AStar
local AStar = {}

-- Function to calculate the heuristic cost (distance between two nodes)
local function HeuristicCostEstimate(nodeA, nodeB)
    return (nodeB.pos - nodeA.pos):Length()
end

-- Function to reconstruct the path from the start node to the goal node
local function ReconstructPath(current, previous)
    local path = { current }
    while previous[current.id] do
        current = previous[current.id]
        table.insert(path, current)
    end
    return path
end

-- Function to find the shortest path using A-Star algorithm
---@param startNode PathNode
---@param goalNode PathNode
---@param nodes table<number, PathNode>
---@param adjacentFun function
---@return PathNode[]|nil
function AStar.Path(startNode, goalNode, nodes, adjacentFun)
    local openSet = Heap.new()
    local closedSet = {}
    local gScore = {}
    local fScore = {}
    local previous = {}

    -- Initialize the starting node with gScore and fScore
    gScore[startNode.id] = 0
    fScore[startNode.id] = HeuristicCostEstimate(startNode, goalNode)

    openSet.Compare = function(a, b) return fScore[a.id] < fScore[b.id] end
    openSet:push(startNode)

    -- Variables to track the best node and score found so far
    local bestNode = startNode
    local bestFScore = fScore[startNode.id]

    while not openSet:empty() do
        local current = openSet:pop()

        if not closedSet[current.id] then
            -- If we have reached the goal node, return the reconstructed path
            if current.id == goalNode.id then
                openSet:clear()
                return ReconstructPath(current, previous)
            end

            closedSet[current.id] = true

            -- Get adjacent nodes for current node
            local adjacentNodes = adjacentFun(current, nodes)
            for _, neighbor in ipairs(adjacentNodes) do
                if not closedSet[neighbor.id] then
                    -- Calculate tentative gScore
                    local tentativeGScore = gScore[current.id] + HeuristicCostEstimate(current, neighbor)

                    -- If this path is better than previous or the neighbor hasn't been explored
                    if not gScore[neighbor.id] or tentativeGScore < gScore[neighbor.id] then
                        gScore[neighbor.id] = tentativeGScore
                        fScore[neighbor.id] = tentativeGScore + HeuristicCostEstimate(neighbor, goalNode)
                        previous[neighbor.id] = current
                        openSet:push(neighbor)

                        -- Update best node and best score found so far
                        if fScore[neighbor.id] < bestFScore then
                            bestNode = neighbor
                            bestFScore = fScore[neighbor.id]
                        end
                    end
                end
            end
        end
    end

    -- If no complete path is found, return the best path we had so far
    return ReconstructPath(bestNode, previous)
end

return AStar