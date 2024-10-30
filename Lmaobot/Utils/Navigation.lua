---@alias Connection { count: integer, connections: integer[] }
---@alias Node { x: number, y: number, z: number, id: integer, c: { [1]: Connection, [2]: Connection, [3]: Connection, [4]: Connection } }
---@class Pathfinding
local Navigation = {}

local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local AStar = require("Lmaobot.Utils.A-Star")
local WorkManager = require("Lmaobot.WorkManager")

assert(G, "G is nil")

local Log = Common.Log
local Lib = Common.Lib
assert(Lib, "Lib is nil")

-- Get the current path
---@return Node[]|nil
function Navigation.GetCurrentPath()
    return G.Navigation.path
end

-- Clear the current path
function Navigation.ClearPath()
    G.Navigation.path = {}
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
function Navigation.RemoveLastNode()
    G.Navigation.currentNodeTicks = 0
    table.remove(G.Navigation.path[#G.Navigation.path])
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

function Navigation.FindPath(startNode, goalNode)
    if WorkManager.attemptWork(66, "Pathfinding") then
        Log:Info("Generating new path from node %d to node %d", startNode.id, goalNode.id)
        Navigation.ClearPath() -- Ensure we clear the current path before generating a new one
        Navigation.ResetTickTimer()
    
        if not startNode or not startNode.pos then
            Log:Warn("Navigation.FindPath: startNode or startNode.pos is nil")
            return false
        end

        if not goalNode or not goalNode.pos then
            Log:Warn("Navigation.FindPath: goalNode or goalNode.pos is nil")
            return false
        end

        G.Navigation.path = AStar.Path(startNode, goalNode, G.Navigation.nodes)

        if not G.Navigation.path or #G.Navigation.path == 0 then
            Log:Error("Failed to find path from %d to %d!", startNode.id, goalNode.id)
            return false
        else
            Log:Info("Path found from %d to %d with %d nodes", startNode.id, goalNode.id, #G.Navigation.path)
        end

        -- Check if pathfinding succeeded
        if G.Navigation.path and #G.Navigation.path > 0 then
            G.Navigation.currentNodeinPath = #G.Navigation.path  -- Start at the last node
            G.Navigation.currentNode = G.Navigation.path[G.Navigation.currentNodeinPath]
            G.Navigation.currentNodePos = G.Navigation.currentNode.pos
            Log:Info("Path found.")
        else
            Log:Warn("No path found.")
        end

        return true
    end
end

-- Helper function to remove all nodes after a specific index in the path
---@param path table The navigation path table
---@param targetIndex integer The target index to keep up to
local function removeNodesAfter(path, targetIndex)
    for i = #path, targetIndex + 1, -1 do
        table.remove(path)
    end
end

-- Skip to a specific node in the path, removing all nodes with a higher index
---@param nodeIndexFromStart integer The target index to skip to
function Navigation.SkipToNode(nodeIndexFromStart)
    Navigation.ResetTickTimer()

    if G.Navigation.path and #G.Navigation.path > 0 then
        -- Ensure nodeIndexFromStart is within the bounds of the path
        local targetIndex = math.max(1, math.min(#G.Navigation.path, nodeIndexFromStart))

        -- Set the currentNode and currentNodePos to the target node
        G.Navigation.currentNode = G.Navigation.path[targetIndex]
        G.Navigation.currentNodePos = G.Navigation.currentNode.pos

        -- Remove nodes beyond the target index
        removeNodesAfter(G.Navigation.path, targetIndex)
        G.Navigation.currentNodeIndex = targetIndex
    else
        -- Clear the current node and position if no path exists
        G.Navigation.currentNode = nil
        G.Navigation.currentNodePos = nil
    end
end

-- Move to the next node in the path, effectively removing the last node
function Navigation.MoveToNextNode()
    Navigation.ResetTickTimer()
    if G.Navigation.path and #G.Navigation.path > 0 then
        -- Remove the current node by skipping to the next-to-last node
        removeNodesAfter(G.Navigation.path, #G.Navigation.path - 1)
        G.Navigation.currentNodeIndex = #G.Navigation.path

        -- Update current node to the last one in the remaining path
        if #G.Navigation.path > 0 then
            G.Navigation.currentNode = G.Navigation.path[#G.Navigation.path]
            G.Navigation.currentNodePos = G.Navigation.currentNode.pos
        else
            -- Clear currentNode and currentNodePos if no nodes are left
            G.Navigation.currentNode = nil
            G.Navigation.currentNodePos = nil
        end
    else
        -- If the path is empty, clear currentNode and currentNodePos
        G.Navigation.currentNode = nil
        G.Navigation.currentNodePos = nil
    end
end

return Navigation