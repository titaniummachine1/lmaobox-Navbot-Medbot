-- A-Star Algorithm for Lmaobox
-- Credits: github.com/GlorifiedPig/Luafinding..

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

local function isvalid(node, connode)
    return node and connode and (connode.pos.z - node.pos.z) < 90
end

-- Returns all adjacent nodes of the given node, including visible ones
---@param node Node
---@param nodes Node[]
---@return Node[]
local function GetAdjacentNodes(node, nodes)
    local adjacentNodes = {}

    -- Check if node and its connections table exist
    if not node or not node.c then
        print("Error: Node or its connections table (c) is missing.")
        return adjacentNodes
    end

    -- Iterate through connections (directions 1 to 4)
    for dir = 1, 27 do
        if not node.c[dir] then break end

        local conDir = node.c[dir]

        if conDir and conDir.connections then
            for _, con in pairs(conDir.connections) do
                local conNode = nodes[con]
                if conNode and isvalid(node, conNode) then
                    table.insert(adjacentNodes, conNode)
                end
            end
        else
            print(string.format("Warning: No connections for direction %d of node %d.", dir, node.id))
        end
    end

    return adjacentNodes
end


function AStar.Path(startNode, goalNode, nodes)
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

            local adjacentNodes = GetAdjacentNodes(current, nodes)
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
