---@alias Connection { count: integer, connections: integer[] }
---@alias Node { x: number, y: number, z: number, id: integer, c: { [1]: Connection, [2]: Connection, [3]: Connection, [4]: Connection } }
---@class Pathfinding
local Navigation = {}

local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local AStar = require("Lmaobot.Utils.A-Star")

assert(G, "G is nil")

local Log = Common.Log
local Lib = Common.Lib
assert(Lib, "Lib is nil")

-- Constants

local DROP_HEIGHT = 450  -- Define your constants outside the function
local Jump_Height = 72 --duck jump height

local HULL_MIN = G.pLocal.vHitbox.Min
local HULL_MAX = G.pLocal.vHitbox.Max
local TRACE_MASK = MASK_PLAYERSOLID

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

--[[-- Perform a trace hull down from the given position to the ground
---@param position Vector3 The start position of the trace
---@param hullSize table The size of the hull
---@return Vector3 The normal of the ground at that point
local function traceHullDown(position, hullSize)
    local endPos = position - Vector3(0, 0, DROP_HEIGHT)  -- Adjust the distance as needed
    local traceResult = engine.TraceHull(position, endPos, hullSize.min, hullSize.max, MASK_PLAYERSOLID_BRUSHONLY)
    return traceResult.plane  -- Directly using the plane as the normal
end

-- Perform a trace line down from the given position to the ground
---@param position Vector3 The start position of the trace
---@return Vector3 The hit position
local function traceLineDown(position)
    local endPos = position - Vector3(0, 0, DROP_HEIGHT)
    local traceResult = engine.TraceLine(position, endPos, TRACE_MASK)
    return traceResult.endpos
end

-- Calculate the remaining two corners based on the adjusted corners and ground normal
---@param corner1 Vector3 The first adjusted corner
---@param corner2 Vector3 The second adjusted corner
---@param normal Vector3 The ground normal
---@param height number The height of the rectangle
---@return table The remaining two corners
local function calculateRemainingCorners(corner1, corner2, normal, height)
    local widthVector = corner2 - corner1
    local widthLength = widthVector:Length2D()

    local heightVector = Vector3(-widthVector.y, widthVector.x, 0)

    local function rotateAroundNormal(vector, angle)
        local cosTheta = math.cos(angle)
        local sinTheta = math.sin(angle)
        return Vector3(
            (cosTheta + (1 - cosTheta) * normal.x^2) * vector.x + ((1 - cosTheta) * normal.x * normal.y - normal.z * sinTheta) * vector.y + ((1 - cosTheta) * normal.x * normal.z + normal.y * sinTheta) * vector.z,
            ((1 - cosTheta) * normal.x * normal.y + normal.z * sinTheta) * vector.x + (cosTheta + (1 - cosTheta) * normal.y^2) * vector.y + ((1 - cosTheta) * normal.y * normal.z - normal.x * sinTheta) * vector.z,
            ((1 - cosTheta) * normal.x * normal.z - normal.y * sinTheta) * vector.x + ((1 - cosTheta) * normal.y * normal.z + normal.x * sinTheta) * vector.y + (cosTheta + (1 - cosTheta) * normal.z^2) * vector.z
        )
    end

    local rotatedHeightVector = rotateAroundNormal(heightVector, math.pi / 2)

    local corner3 = corner1 + rotatedHeightVector * (height / widthLength)
    local corner4 = corner2 + rotatedHeightVector * (height / widthLength)

    return { corner3, corner4 }
end

-- Fix a node by adjusting its height based on TraceLine results from the corners
---@param nodeId integer The index of the node in the Nodes table
function Navigation.FixNode(nodeId)
    local nodes = G.Navigation.nodes
    local node = nodes[nodeId]
    if not node or not node.pos then
        print("Node with ID " .. tostring(nodeId) .. " is invalid or missing position, exiting function")
        return
    end

    -- Step 1: Raise the corners by a defined height
    local raiseVector = Vector3(0, 0, Jump_Height)
    local raisedNWPos = node.nw + raiseVector
    local raisedSEPos = node.se + raiseVector

    -- Step 2: Calculate the middle position after raising the corners
    local middlePos = (raisedNWPos + raisedSEPos) / 2

    -- Step 3: Perform trace hull down from the middle position to get the ground normal
    local traceHullSize = {
        -- Clamp the size to player hitbox size to avoid staircase issues
        min = Vector3(math.max(-math.abs(raisedNWPos.x - raisedSEPos.x) / 2, HULL_MIN.x), math.max(-math.abs(raisedNWPos.y - raisedSEPos.y) / 2, HULL_MIN.y), 0),
        max = Vector3(math.min(math.abs(raisedNWPos.x - raisedSEPos.x) / 2, HULL_MAX.x), math.min(math.abs(raisedNWPos.y - raisedSEPos.y) / 2, HULL_MAX.y), 45)
    }

   --local groundNormal = traceHullDown(middlePos, traceHullSize)

    -- Step 4: Calculate the remaining corners based on the ground normal
    --local height = math.abs(node.nw.y - node.se.y)
    --local remainingCorners = calculateRemainingCorners(raisedNWPos, raisedSEPos, groundNormal, height)

    -- Step 5: Adjust corners to align with the ground normal
    raisedNWPos = traceLineDown(raisedNWPos)
    raisedSEPos = traceLineDown(raisedSEPos)
    --remainingCorners[1] = traceLineDown(remainingCorners[1])
    --remainingCorners[2] = traceLineDown(remainingCorners[2])

    -- Step 6: Update node with new corners and position
    node.nw = raisedNWPos
    node.se = raisedSEPos
    --node.ne = remainingCorners[1]
    --node.sw = remainingCorners[2]

    -- Step 7: Recalculate the middle position based on the fixed corners
    local finalMiddlePos = (raisedNWPos + raisedSEPos) / 2
    node.pos = finalMiddlePos

    G.Navigation.nodes[nodeId] = node -- Set the fixed node to the global node
end

-- Adjust all nodes by fixing their positions and adding missing corners.
function Navigation.FixAllNodes()
    --local nodes = Navigation.GetNodes()
    --for id in pairs(nodes) do
        Navigation.FixNode(id)
    end
end]]

-- Set the raw nodes and copy them to the fixed nodes table
---@param nodes Node[]
function Navigation.SetNodes(Nodes)
    G.Navigation.nodes = Nodes
end

function Navigation.Setup()
    Navigation.LoadNavFile() --load nodes
    G.State = G.StateDefinition.Pathfinding
    Common.Reset("Objective")
end

-- Get the fixed nodes used for calculations
---@return Node[]
function Navigation.GetNodes()
    return G.Navigation.nodes
end

-- Get the current path
---@return Node[]|nil
function Navigation.GetCurrentPath()
    return G.Navigation.path
end

-- Clear the current path
function Navigation.ClearPath()
    G.Navigation.path = {}
end

-- Get a node by its ID
---@param id integer
---@return Node
function Navigation.GetNodeByID(id)
    return G.Navigation.nodes[id]
end

-- Set the current path
---@param path Node[]
function Navigation.SetCurrentPath(path)
    if not path then
        Log:Error("Failed to set path, it's nil")
        return
    end
    G.Navigation.path = path
end

-- Remove the current node from the path
function Navigation.RemoveCurrentNode()
    G.Navigation.currentNodeTicks = 0
    table.remove(G.Navigation.path)
end

-- Function to increment the current node ticks
function Navigation.increment_ticks()
    G.Navigation.currentNodeTicks =  G.Navigation.currentNodeTicks + 1
end

-- Function to increment the current node ticks
function Navigation.ResetTickTimer()
    G.Navigation.currentNodeTicks = 0
end

-- Function to get forward speed by class
function Navigation.GetMaxSpeed(entity)
    return entity:GetPropFloat("m_flMaxspeed")
end

-- Function to calculate the time needed to stop completely
local function CalculateStopTime(velocity, decelerationPerSecond)
    return velocity / decelerationPerSecond
end

-- Converts time to game ticks
---@param time number
---@return integer
local function Time_to_Ticks(time)
    return math.floor(0.5 + time / globals.TickInterval())
end

-- Function to calculate the number of ticks needed to stop completely
local function CalculateStopTicks(velocity, decelerationPerSecond)
    local stopTime = CalculateStopTime(velocity, decelerationPerSecond)
    return Time_to_Ticks(stopTime)
end

-- Constants for minimum and maximum speed
local MAX_SPEED = 450 -- Maximum speed the player can move

-- Function to compute the move direction
local function ComputeMove(pCmd, a, b)
    if not a or not b then
        Log:Error("ComputeMove: 'a' or 'b' is nil")
        return Vector3(0, 0, 0)
    end

    local diff = b - a
    if not diff or diff:Length() == 0 then
        return Vector3(0, 0, 0)
    end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw = pCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    --MAX_SPEED = Navigation.GetMaxSpeed(entities.GetLocalPlayer())
    local move = Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, -math.cos(pitch) * MAX_SPEED)

    return move
end

-- Function to make the player walk to a destination smoothly
function Navigation.WalkTo(pCmd, pLocal, pDestination)
    if not pLocal or not pDestination then
        Log:Error("WalkTo: 'pLocal' or 'pDestination' is nil")
        return
    end

    local localPos = pLocal:GetAbsOrigin()
    if not localPos then
        Log:Error("WalkTo: 'localPos' is nil")
        return
    end

    local distVector = pDestination - localPos
    if not distVector then
        Log:Error("WalkTo: 'distVector' is nil")
        return
    end

    local dist = distVector:Length()
    local velocity = pLocal:EstimateAbsVelocity():Length()
    local tickInterval = globals.TickInterval()
    local tickRate = 1 / tickInterval

    -- Calculate the deceleration per second
    local AccelerationPerSecond = 84 * tickRate  -- Converting units per tick to units per second

    -- Calculate the number of ticks to stop
    local stopTicks = CalculateStopTicks(velocity, AccelerationPerSecond)
    print(string.format("Ticks to stop: %d", stopTicks))

    -- Calculate the stop distance
    local speedPerTick = velocity / tickRate
    local stopDistance = math.max(10, math.min(speedPerTick * stopTicks, 450))
    print(string.format("Stop Distance: %.2f units", stopDistance))

    local result = ComputeMove(pCmd, localPos, pDestination)
    if dist <= stopDistance then
        -- Calculate precise movement needed to stop perfectly at the target
        local neededVelocity = dist / stopTicks
        local currentVelocity = velocity / tickRate
        local velocityAdjustment = neededVelocity - currentVelocity

        -- Apply the velocity adjustment
        if stopTicks <= 0 then
            pCmd:SetForwardMove(result.x * velocityAdjustment)
            pCmd:SetSideMove(result.y * velocityAdjustment)
        else
            local scaleFactor = dist / 1000
            pCmd:SetForwardMove(result.x * scaleFactor)
            pCmd:SetSideMove(result.y * scaleFactor)
        end
    else
        pCmd:SetForwardMove(result.x)
        pCmd:SetSideMove(result.y)
    end
end

---@param node NavNode
---@param pos Vector3
---@return Vector3
function Navigation.GetMeshPos(node, pos)
    -- Calculate the closest point on the node's 3D plane to the given position
    return Vector3(
        math.max(node.nw.pos.x, math.min(node.se.pos.x, pos.x)),
        math.max(node.nw.pos.y, math.min(node.se.pos.y, pos.y)),
        math.max(node.nw.pos.z, math.min(node.se.pos.z, pos.z))
    )
end

---@param pos Vector3|{ x:number, y:number, z:number }
---@return Node
function Navigation.GetClosestNode(pos)
    local closestNode = {}
    local closestDist = math.huge

    for _, node in pairs(G.Navigation.nodes or {}) do
        if node and node.pos then
            local dist = (node.pos - pos):Length()
            if dist < closestDist then
                closestNode = node
                closestDist = dist
            end
        else
            error("GetClosestNode: Node or node.pos is nil")
        end
    end

    return closestNode
end

-- Perform a trace line down from a given height to check ground position
---@param startPos table The start position of the trace
---@param endPos table The end position of the trace
---@return boolean Whether the trace line reaches the ground at the target position
local function canTraceDown(startPos, endPos)
    local traceResult = engine.TraceLine(startPos.pos, endPos.pos, MASK_PLAYERSOLID)
    return traceResult.fraction == 1
end

-- Returns all adjacent nodes of the given node
---@param node Node
---@param nodes Node[]
---@return Node[]
local function GetAdjacentNodes(node, nodes)
    local adjacentNodes = {}

    -- Check if node and its connections table exist
    if not node or not node.c then
        print("Error: Node or its connections table (c) is missing.")
        return adjacentNodes  -- Return an empty table
    end

    -- Iterate through the possible directions (assuming 1 to 4 for directions)
    for dir = 1, 4 do
        local conDir = node.c[dir]

        -- Check if the direction has any valid connections
        if not conDir or not conDir.connections then
            print(string.format("Warning: No connections found for direction %d of node %d.", dir, node.id))
        else
            -- Loop through the connections in the given direction
            for _, con in pairs(conDir.connections) do
                local conNode = nodes[con]

                -- Check if the connected node exists in the node table
                if not conNode then
                    print(string.format("Warning: Connection ID %d in direction %d of node %d does not have a valid node.", con, dir, node.id))
                else
                    -- Calculate horizontal checks
                    local conNodeNW = conNode.nw
                    local conNodeSE = conNode.se

                    -- Ensure corners are valid for the node
                    if not conNodeNW or not conNodeSE then
                        print(string.format("Error: Node %d has invalid corners (NW or SE) in direction %d.", conNode.id, dir))
                    else
                        -- Horizontal check
                        local horizontalCheck = (conNode.pos - node.pos):Length() < 750

                        -- Adjust vertical check logic
                        local verticalDiff = conNode.pos.z - node.pos.z

                        -- Ensure vertical movement is allowed:
                        -- - Only go up if the vertical difference is <= 72 units.
                        -- - Always allow going down, so verticalDiff < 0 is valid.
                        if horizontalCheck and (verticalDiff <= 72 or verticalDiff < 0) then
                            table.insert(adjacentNodes, conNode)
                        end
                    end
                end
            end
        end
    end

    return adjacentNodes
end


function Navigation.FindPath(startNode, goalNode)
    if not startNode or not startNode.pos then
        Log:Warn("Navigation.FindPath: startNode or startNode.pos is nil")
        return
    end

    if not goalNode or not goalNode.pos then
        Log:Warn("Navigation.FindPath: goalNode or goalNode.pos is nil")
        return
    end

    G.Navigation.path = AStar.Path(startNode, goalNode, G.Navigation.nodes, GetAdjacentNodes)

    if not G.Navigation.path or #G.Navigation.path == 0 then
        Log:Error("Failed to find path from %d to %d!", startNode.id, goalNode.id)
    else
        Log:Info("Path found from %d to %d with %d nodes", startNode.id, goalNode.id, #G.Navigation.path)
    end
end

function Navigation.MoveToNextNode()
    if G.Navigation.path and #G.Navigation.path > 0 then
        -- Remove the last node from the path
        table.remove(G.Navigation.path)
        G.Navigation.currentNodeIndex = #G.Navigation.path

        -- If there are still nodes left, set the current node to the new last node
        if #G.Navigation.path > 0 then
            G.Navigation.currentNode = G.Navigation.path[#G.Navigation.path]
            G.Navigation.currentNodePos = G.Navigation.currentNode.pos
        else
            -- If no nodes are left, clear currentNode and currentNodePos
            G.Navigation.currentNode = nil
            G.Navigation.currentNodePos = nil
        end
    else
        -- If there is no path or it's empty, clear currentNode and currentNodePos
        G.Navigation.currentNode = nil
        G.Navigation.currentNodePos = nil
    end
end



return Navigation