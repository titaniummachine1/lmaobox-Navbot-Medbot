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

    -- Remove the connection from nodeA to nodeB
    for dir = 1, 4 do
        local conDir = nodeA.c[dir]
        for i, con in ipairs(conDir.connections) do
            if con == nodeB.id then
                print("Removing connection between " .. nodeA.id .. " and " .. nodeB.id)
                table.remove(conDir.connections, i)
                conDir.count = conDir.count - 1
                break  -- Exit the loop once the connection is found and removed
            end
        end
    end

    -- Remove the reverse connection from nodeB to nodeA
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

function Navigation.AddCostToConnection(nodeA, nodeB, cost)
    -- If nodeA or nodeB is nil, exit the function
    if not nodeA or not nodeB then
        print("One or both nodes are nil, exiting function")
        return
    end

    -- Add the cost from nodeA to nodeB
    for dir = 1, 4 do
        local conDir = nodeA.c[dir]
        for i, con in ipairs(conDir.connections) do
            if con == nodeB.id then
                print("Adding cost between " .. nodeA.id .. " and " .. nodeB.id)
                conDir.connections[i] = {node = con, cost = cost}
                break  -- Exit the loop once the connection is found
            end
        end
    end

    -- Add the cost from nodeB to nodeA
    for dir = 1, 4 do
        local conDir = nodeB.c[dir]
        for i, con in ipairs(conDir.connections) do
            if con == nodeA.id then
                print("Adding cost between " .. nodeB.id .. " and " .. nodeA.id)
                conDir.connections[i] = {node = con, cost = cost}
                break  -- Exit the loop once the connection is found
            end
        end
    end
end

function Navigation.AddConnection(nodeA, nodeB)
    -- If nodeA or nodeB is nil, exit the function
    if not nodeA or not nodeB then
        print("One or both nodes are nil, exiting function")
        return
    end

    -- Add the connection from nodeA to nodeB
    for dir = 1, 4 do
        local conDir = nodeA.c[dir]
        if not conDir.connections[nodeB.id] then
            print("Adding connection between " .. nodeA.id .. " and " .. nodeB.id)
            table.insert(conDir.connections, nodeB.id)
            conDir.count = conDir.count + 1
        end
    end

    -- Add the reverse connection from nodeB to nodeA
    for dir = 1, 4 do
        local conDir = nodeB.c[dir]
        if not conDir.connections[nodeA.id] then
            print("Adding reverse connection between " .. nodeB.id .. " and " .. nodeA.id)
            table.insert(conDir.connections, nodeA.id)
            conDir.count = conDir.count + 1
        end
    end
end

-- Constants for hull dimensions and trace masks
local HULL_MIN = Vector3(-24, -24, 0)
local HULL_MAX = Vector3(24, 24, 82)
local TRACE_MASK = MASK_PLAYERSOLID

-- Fixes a node by adjusting its height based on TraceHull and TraceLine results
-- Moves the node 18 units up and traces down to find a new valid position
---@param nodeId integer The index of the node in the Nodes table
---@return Node The fixed node
function Navigation.FixNode(nodeId)
    local node = Navigation.GetNodeByID(nodeId)
    if not node or not node.pos then
        print("Node with ID " .. tostring(nodeId) .. " is invalid or missing position, exiting function")
        return nil
    end

    -- Check if the node has already been fixed
    if node.fixed then
        return Nodes[nodeId]
    end

    local upVector = Vector3(0, 0, 72) -- Move node 18 units up
    local downVector = Vector3(0, 0, -72) -- Trace down a large distance

    -- Perform a TraceHull directly downwards from the node's center position
    local nodePos = node.pos
    local centerTraceResult = engine.TraceHull(nodePos + upVector, nodePos + downVector, HULL_MIN, HULL_MAX, TRACE_MASK)

    -- Check if the trace result is more than 0
    if centerTraceResult.fraction > 0 then
        -- Update node's center position in the Nodes table directly
        Nodes[nodeId].z = centerTraceResult.endpos.z
        Nodes[nodeId].pos = centerTraceResult.endpos
    else
        -- Lift the node 18 units up and keep it there
        Nodes[nodeId].z = nodePos.z + 18
        Nodes[nodeId].pos = Vector3(nodePos.x, nodePos.y, nodePos.z + 18)
    end

    -- Mark the node as fixed
    Nodes[nodeId].fixed = true

    return Nodes[nodeId]  -- Return the fixed node
end



--- Finds the furthest walkable node from the player's current position in reverse order (from last to first).
-- @param currentPath table The current path consisting of nodes.
-- @param myPos Vector3 The player's current position.
-- @param currentNodeIndex number The index of the current node in the path.
-- @return number, Node, Vector3 The index, node, and position of the furthest walkable node.
function Navigation.FindBestNode(currentPath, myPos, currentNodeIndex)
    -- Initialize variables for storing the furthest walkable node information
    local furthestWalkableNodeIndex = currentNodeIndex
    local furthestWalkableNode = currentPath[currentNodeIndex]
    local furthestWalkableNodePos = furthestWalkableNode.pos

    -- Start the search from the node before the current node, moving towards the first node
    for i = currentNodeIndex - 1, 1, -1 do
        local node = currentPath[i]
        if node and node.pos then
            -- Ensure the node is fixed before checking (if necessary)
            Navigation.FixNode(node.id)

            local nodePos = node.pos

            -- Check if the node is walkable from the current position
            if Common.IsWalkable(myPos, nodePos) then
                -- Update the furthest walkable node information
                furthestWalkableNodeIndex = i
                furthestWalkableNode = node
                furthestWalkableNodePos = nodePos
            else
                -- Cannot walk to this node; stop checking further
                break
            end
        else
            -- Invalid node; stop checking further
            break
        end
    end

    -- If the furthest walkable node is different from the current node, return it
    if furthestWalkableNodeIndex < currentNodeIndex then
        return furthestWalkableNodeIndex, furthestWalkableNode, furthestWalkableNodePos
    else
        -- No further node found
        return nil, nil, nil
    end
end


-- Constants
local MIN_SPEED = 0   -- Minimum speed to avoid jittery movements
local MAX_SPEED = 450 -- Maximum speed the player can move
local TICK_RATE = 66  -- Number of ticks per second

local ClassForwardSpeeds = {
    [E_Character.TF2_Scout] = 400,
    [E_Character.TF2_Soldier] = 240,
    [E_Character.TF2_Pyro] = 300,
    [E_Character.TF2_Demoman] = 280,
    [E_Character.TF2_Heavy] = 230,
    [E_Character.TF2_Engineer] = 300,
    [E_Character.TF2_Medic] = 320,
    [E_Character.TF2_Sniper] = 300,
    [E_Character.TF2_Spy] = 320
}

-- Function to get forward speed by class
function Navigation.GetForwardSpeedByClass(pLocal)
    local pLocalClass = pLocal:GetPropInt("m_iClass")
    return ClassForwardSpeeds[pLocalClass]
end

-- Function to compute the move direction
local function ComputeMove(pCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = pCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local move = Vector3(math.cos(yaw), -math.sin(yaw), 0)

    return move
end

local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

-- Function to make the player walk to a destination smoothly
function Navigation.WalkTo(pCmd, pLocal, pDestination)
    local localPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos
    local dist = math.abs(distVector.x) + math.abs(distVector.y)
    local currentSpeed = Navigation.GetForwardSpeedByClass(pLocal)  -- Max speed for the class
    local currentVelocity = pLocal:EstimateAbsVelocity()
    local velocityDirection = Normalize(currentVelocity)
    local velocitySpeed = currentVelocity:Length()

    -- Calculate distance that would be covered in one tick at the current speed
    local distancePerTick = currentSpeed / TICK_RATE

    -- Check if we are close enough to potentially overshoot the target in the next tick
    if dist > distancePerTick then
        -- If we are not close enough to overshoot, proceed at max speed
        local result = ComputeMove(pCmd, localPos, pDestination)
        pCmd:SetForwardMove(result.x * currentSpeed)
        pCmd:SetSideMove(result.y * currentSpeed)
    else
        -- Calculate the required deceleration per tick to stop at the target
        local decelPerTick = (velocitySpeed * velocitySpeed) / (2 * dist * TICK_RATE)
        local requiredSpeed = velocitySpeed - decelPerTick
        requiredSpeed = math.max(requiredSpeed, 0)  -- Ensure speed doesn't go below 0

        -- Apply the calculated speed in the direction of the target
        local result = ComputeMove(pCmd, localPos, pDestination)
        pCmd:SetForwardMove(result.x * requiredSpeed)
        pCmd:SetSideMove(result.y * requiredSpeed)
    end
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

local InSearch = false
function Navigation.isSearching()
    return InSearch
end

---@param startNode Node
---@param goalNode Node
function Navigation.FindPath(startNode, goalNode, maxNodes)
    if not startNode then
        Log:Warn("Invalid start node %d!", startNode.id)
        return
    end

    if not goalNode then
        Log:Warn("Invalid goal node %d!", goalNode.id)
        return
    end

    InSearch = false
    CurrentPath, InSearch = AStar.Path(startNode, goalNode, Nodes, GetAdjacentNodes, maxNodes)
    if not CurrentPath and not InSearch then
        Log:Error("Failed to find path from %d to %d!", startNode.id, goalNode.id)
    end
end

return Navigation