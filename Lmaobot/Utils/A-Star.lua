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

-- Determines if a node is flat (difference between 'nw' and 'se' corners is <= 18 units)
local function isFlat(node)
    local z_nw = node.corners.nw.z
    local z_se = node.corners.se.z
    return math.abs(z_nw - z_se) <= 18
end

local MAX_HEIGHT_DIFFERENCE_UP = 72     -- Maximum height the agent can climb up
local MAX_HEIGHT_DIFFERENCE_DOWN = 250  -- Maximum height the agent can step down
local TOLERANCE = 5                     -- Tolerance for floating-point comparisons
local function isvalid(node, connode)


    local nodeIsFlat = isFlat(node)
    local conNodeIsFlat = isFlat(connode)

    if nodeIsFlat and conNodeIsFlat then
        -- Both nodes are flat
        local heightDifference = connode.pos.z - node.pos.z
        if heightDifference > 0 then
            -- Moving up
            return heightDifference <= MAX_HEIGHT_DIFFERENCE_UP
        else
            -- Moving down or same level
            return math.abs(heightDifference) <= MAX_HEIGHT_DIFFERENCE_DOWN
        end
    else
        -- At least one node is sloped
        -- Check for matching corners
        local node_corners_z = {node.corners.nw.z, node.corners.se.z}
        local connode_corners_z = {connode.corners.nw.z, connode.corners.se.z}

        local found_match = false
        for _, node_z in ipairs(node_corners_z) do
            for _, connode_z in ipairs(connode_corners_z) do
                if math.abs(node_z - connode_z) <= TOLERANCE then
                    found_match = true
                    break
                end
            end
            if found_match then
                break
            end
        end

        if found_match then
            -- Valid connection on a slope
            return true
        else
            -- No matching corners, check height difference
            local heightDifference = connode.pos.z - node.pos.z
            if heightDifference > 0 then
                -- Moving up
                return heightDifference <= MAX_HEIGHT_DIFFERENCE_UP
            else
                -- Moving down
                return math.abs(heightDifference) <= MAX_HEIGHT_DIFFERENCE_DOWN
            end
        end
    end
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

    -- Iterate up to 27 connections
    for dir, conDir in ipairs(node.c) do
        if dir > 27 then break end  -- Limit to 27 directions

        if conDir and conDir.connections then
            for _, con in ipairs(conDir.connections) do
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
