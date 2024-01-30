---@alias Connection { count: integer, connections: integer[] }
---@alias Node { x: number, y: number, z: number, id: integer, c: { [1]: Connection, [2]: Connection, [3]: Connection, [4]: Connection } }

local Common = require("Lmaobot.Common")
local SourceNav = require("Lmaobot.SourceNav")
local AStar = require("Lmaobot.A-Star")
local Lib, Log = Common.Lib, Common.Log

local FS = Lib.Utils.FileSystem

---@class Pathfinding
local Navigation = {}

---@type Node[]
local Nodes = {}

---@type Node[]|nil
local CurrentPath = nil

---@param nodes Node[]
function Navigation.SetNodes(nodes)
    Nodes = nodes
end

---@return Node[]
function Navigation.GetNodes()
    return Nodes
end

---@return Node[]|nil
---@return Node[]|nil
function Navigation.GetCurrentPath()
    return CurrentPath
end

function Navigation.ClearPath()
    CurrentPath = nil
end

---@param id integer
---@return Node
function Navigation.GetNodeByID(id)
    return Nodes[id]
end

function Navigation.RemoveConnection(nodeA, nodeB)
    -- If nodeA or nodeB is nil, exit the function
    if not nodeA or not nodeB then
        print("One or both nodes are nil, exiting function")
        return
    end

    --remove the reverse connection from nodeB to nodeA
    for dir = 1, 4 do
        local conDir = nodeB.c[dir]
        for i, con in ipairs(conDir.connections) do
            if con == nodeA.id then
                print("Removing reverse connection between " .. nodeB.id .. " and " .. nodeA.id)
                table.remove(conDir.connections, i)
                conDir.count = conDir.count - 1
                break  -- Exit the loop once the connection is found and removed
            end
        end
    end
end

-- Constants for hull dimensions and trace masks
local HULL_MIN = Vector3(-24, -24, 0)
local HULL_MAX = Vector3(24, 24, 82)
local TRACE_MASK = MASK_PLAYERSOLID

-- Fixes a node by adjusting its height based on TraceHull and TraceLine results
-- Moves the node 18 units up and traces down to find a new valid position
---@param node NavNode
function Navigation.FixNode(node)
    local upVector = Vector3(0, 0, 27) -- Move node 18 units up
    local downVector = Vector3(0, 0, -72) -- Trace down a large distance
    local traceMin = Vector3(-24, -24, 0)
    local traceMax = Vector3(24, 24, 82)

    -- Perform a TraceHull directly downwards from the node's center position
    local nodePos = node.pos
    if nodePos == nil then
        print("Node position is nil, exiting function")
        return
    end

    -- Perform a TraceHull directly downwards from the node's center position
    local centerTraceResult = engine.TraceHull(nodePos + upVector, nodePos + downVector, traceMin, traceMax, TRACE_MASK)

    if centerTraceResult.fraction < 1 then
        -- Update node's center position
        node.z = centerTraceResult.endpos.z
        node.pos = centerTraceResult.endpos
    end
end

-- Checks for an obstruction between two points using a hull trace.
local function isPathClear(startPos, endPos)
    local traceResult = engine.TraceHull(startPos, endPos, HULL_MIN, HULL_MAX, TRACE_MASK)
    return traceResult.fraction == 1  -- If fraction is 1, path is clear.
end

-- Checks if the ground is stable at a given position.
local function isGroundStable(position)
    local groundTraceStart = position + Vector3(0, 0, 5)  -- Start a bit above the ground
    local groundTraceEnd = position + Vector3(0, 0, -67)  -- Check 72 units down
    local groundTraceResult = engine.TraceLine(groundTraceStart, groundTraceEnd, TRACE_MASK)
    return groundTraceResult.fraction < 1  -- If fraction is less than 1, ground is stable.
end

-- Recursive binary search function to check path walkability.
local function binarySearch(startPos, endPos, depth)
    if depth == 0 then
        return true
    end

    if not isPathClear(startPos, endPos) then
        return false
    end

    local midPos = (startPos + endPos) / 2
    if not isGroundStable(midPos) then
        return false
    end

    -- Recurse for each half of the path
    return binarySearch(startPos, midPos, depth - 1) and binarySearch(midPos, endPos, depth - 1)
end

-- Main function to check if the path between the current position and the node is walkable.
function Navigation.isWalkable(startPos, endPos)
    local maxDepth = 5
    return binarySearch(startPos, endPos, maxDepth)
end


--- Finds the closest walkable node from the player's current position in reverse order (from last to first).
-- @param currentPath table The current path consisting of nodes.
-- @param myPos Vector3 The player's current position.
-- @param currentNodeIndex number The index of the current node in the path.
-- @return number, Node, Vector3 The index, node, and position of the closest walkable node in reverse order.
function Navigation.FindBestNode(currentPath, myPos, currentNodeIndex)
    -- Initialize variables for storing the last walkable node information
    local lastWalkableNodeIndex = nil
    local lastWalkableNode = nil
    local lastWalkableNodePos = nil

    -- Start the search from the current node, moving towards the first node
    for i = currentNodeIndex, 1, -1 do
        local node = currentPath[i]
        Navigation.FixNode(node) -- Ensure the node is fixed before checking
        local nodePos = node.pos

        -- Check if the node is walkable
        if Navigation.isWalkable(myPos, nodePos) then
            -- Update the last walkable node information
            lastWalkableNodeIndex = i
            lastWalkableNode = node
            lastWalkableNodePos = nodePos
        else
            -- Stop searching when a non-walkable node is found
            break
        end
    end

    -- Return the last walkable node information found in the search
    return lastWalkableNodeIndex, lastWalkableNode, lastWalkableNodePos
end



---@param node NavNode
---@param pos Vector3
---@return Vector3
function Navigation.GetMeshPos(node, pos)
    -- Calculate the closest point on the node's 3D plane to the given position
    return Vector3(
        math.max(node.nw.x, math.min(node.se.x, pos.x)),
        math.max(node.nw.y, math.min(node.se.y, pos.y)),
        math.max(node.nw.z, math.min(node.se.z, pos.z))
    )
end

-- Attempts to read and parse the nav file
---@param navFilePath string
---@return table|nil, string|nil
local function tryLoadNavFile(navFilePath)
    local file = io.open(navFilePath, "rb")
    if not file then
        return nil, "File not found"
    end

    local content = file:read("*a")
    file:close()

    local navData = SourceNav.parse(content)
    if not navData or #navData.areas == 0 then
        return nil, "Failed to parse nav file or no areas found."
    end

    return navData
end

-- Generates the nav file
local function generateNavFile()
    client.RemoveConVarProtection("sv_cheats")
    client.RemoveConVarProtection("nav_generate")
    client.SetConVar("sv_cheats", "1")
    client.Command("nav_generate", true)
    Log:Info("Generating nav file. Please wait...")

    local navGenerationDelay = 10  -- in seconds
    local startTime = os.time()
    repeat
        if os.time() - startTime > navGenerationDelay then
            break
        end
    until false
end

-- Processes nav data to create nodes
---@param navData table
---@return table
local function processNavData(navData)
    local navNodes = {}
    for _, area in ipairs(navData.areas) do
        local cX = (area.north_west.x + area.south_east.x) / 2
        local cY = (area.north_west.y + area.south_east.y) / 2
        local cZ = (area.north_west.z + area.south_east.z) / 2

        navNodes[area.id] = {
            x = cX,
            y = cY,
            z = cZ,
            pos = Vector3(cX, cY, cZ),
            id = area.id,
            c = area.connections,
            nw = area.north_west,
            se = area.south_east,
        }
    end
    return navNodes
end

-- Main function to load the nav file
---@param navFile string
function Navigation.LoadFile(navFile)
    local fullPath = "tf/" .. navFile
    local navData, error = tryLoadNavFile(fullPath)

    if not navData and error == "File not found" then
        generateNavFile()
        navData, error = tryLoadNavFile(fullPath)
        if not navData then
            Log:Error("Failed to load or parse generated nav file: " .. error)
            return
        end
    elseif not navData then
        Log:Error(error)
        return
    end

    local navNodes = processNavData(navData)
    Log:Info("Parsed %d areas from nav file.", #navNodes)
    Navigation.SetNodes(navNodes)
end

---@param pos Vector3|{ x:number, y:number, z:number }
---@return Node
function Navigation.GetClosestNode(pos)
    local closestNode = nil
    local closestDist = math.huge

    for _, node in pairs(Nodes) do
        local dist = (node.pos - pos):Length()
        if dist < closestDist then
            closestNode = node
            closestDist = dist
        end
    end

    return closestNode
end

-- Returns all adjacent nodes of the given node
---@param node Node
---@param nodes Node[]
local function GetAdjacentNodes(node, nodes)
	local adjacentNodes = {}

	for dir = 1, 4 do
		local conDir = node.c[dir]
        for _, con in pairs(conDir.connections) do
            local conNode = nodes[con]
            if conNode and node.z + 70 > conNode.z then
                table.insert(adjacentNodes, conNode)
            end
        end
	end

	return adjacentNodes
end

---@param startNode Node
---@param goalNode Node
function Navigation.FindPath(startNode, goalNode)
    if not startNode then
        Log:Warn("Invalid start node %d!", startNode.id)
        return
    end

    if not goalNode then
        Log:Warn("Invalid goal node %d!", goalNode.id)
        return
    end

    CurrentPath = AStar.Path(startNode, goalNode, Nodes, GetAdjacentNodes)
    if not CurrentPath then
        Log:Error("Failed to find path from %d to %d!", startNode.id, goalNode.id)
    end
end

return Navigation