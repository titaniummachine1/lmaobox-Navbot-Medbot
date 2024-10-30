local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Annotations ]]
---@alias NavConnection { count: integer, connections: integer[] }
---@alias NavNode { id: integer, x: number, y: number, z: number, c: { [1]: NavConnection, [2]: NavConnection, [3]: NavConnection, [4]: NavConnection } }

--[[ Imports ]]
local G = require("Lmaobot.Utils.Globals")
local Common = require("Lmaobot.Common")

require("Lmaobot.Modules.Setup")

local Node = require("Lmaobot.Utils.Node")  -- Using Node module
local Navigation = require("Lmaobot.Utils.Navigation")
local WorkManager = require("Lmaobot.WorkManager")
local TaskManager = require("Lmaobot.TaskManager") -- Adjust the path as necessary

local Lib = Common.Lib
local Log = Common.Log

local Notify, WPlayer = Lib.UI.Notify, Lib.TF2.WPlayer

--[[ Functions ]]
local function HealthLogic(pLocal)
    if not pLocal then return end

    local health = pLocal:GetHealth()
    local maxHealth = pLocal:GetMaxHealth()
    local healthPercentage = (health / maxHealth) * 100

    -- Ensure G.Menu.Main.SelfHealTreshold and shouldfindhealth exist
    local selfHealThreshold = G.Menu.Main.SelfHealTreshold or 50  -- Default to 50% if not set
    local shouldFindHealth = G.Menu.Main.shouldfindhealth

    if health and maxHealth and healthPercentage < selfHealThreshold and not pLocal:InCond(TFCond_Healing) then
        if not TaskManager.IsTaskActive("Health") and shouldFindHealth then
            Log:Info("Switching to health task")
            TaskManager.AddTask("Health")
            Navigation.ClearPath()
        end
    else
        if TaskManager.IsTaskActive("Health") then
            Log:Info("Health task no longer needed, switching back to previous task")
            TaskManager.RemoveTask("Health")
            Navigation.ClearPath()
        end
    end
end

-- Helper function to smoothly adjust view angles
local function smoothViewAngles(userCmd, targetAngles)
    local currentAngles = userCmd.viewangles
    local deltaAngles = { x = targetAngles.x - currentAngles.x, y = targetAngles.y - currentAngles.y }
    deltaAngles.y = ((deltaAngles.y + 180) % 360) - 180  -- Normalize to [-180, 180]

    return EulerAngles(
        currentAngles.x + deltaAngles.x * 0.05,
        currentAngles.y + deltaAngles.y * G.Menu.Main.smoothFactor,
        0
    )
end

-- Helper function to get eye position and calculate view angles towards the current node
local function getViewAnglesToNode(pLocalWrapped, targetPos)
    local eyePos = pLocalWrapped:GetEyePos()
    if not eyePos then
        Log:Warn("Eye position is nil.")
        return nil
    end
    return Lib.Utils.Math.PositionAngles(eyePos, targetPos)
end

-- Main function to handle path-walking view adjustments
local function handlePathWalkingView(userCmd)
    if not (G.Navigation.currentNodePos and G.Menu.Movement.lookatpath) then
        return
    end

    local pLocalWrapped = WPlayer.GetLocal()
    if not pLocalWrapped then
        Log:Warn("Failed to wrap local player.")
        return
    end

    local angles = getViewAnglesToNode(pLocalWrapped, G.Navigation.currentNodePos)
    if not angles then return end

    angles.x = 0  -- Keep horizontal view steady
    if G.Menu.Movement.smoothLookAtPath then
        angles = smoothViewAngles(userCmd, angles)
    end
    engine.SetViewAngles(angles)
end

-- Helper to check if we're close enough to move to the next node
local function shouldMoveToNextNode(horizontalDist, verticalDist)
    return (horizontalDist < G.Misc.NodeTouchDistance) and (verticalDist <= G.Misc.NodeTouchHeight)
end

-- Helper to determine if we can skip to the next node in the path
local function shouldSkipToNextNode(currentNode, nextNode, LocalOrigin)
    local currentToNextDist = (currentNode.pos - nextNode.pos):Length()
    local playerToNextDist = (LocalOrigin - nextNode.pos):Length()
    return playerToNextDist < currentToNextDist
       and Common.isWalkable(LocalOrigin, nextNode.pos)
       and Common.isWalkable(currentNode.pos, nextNode.pos)
end

-- Function to skip to the closest walkable node from the player's position
local function skipToClosestWalkableNode(LocalOrigin)
    local path = G.Navigation.path
    local closestIndex = #path  -- Start from the end of the path

    -- Find the closest walkable node from the player's position
    for i = #path, 1, -1 do
        local node = path[i]
        if Common.isWalkable(LocalOrigin, node.pos) then
            closestIndex = i
            break  -- Stop at the first reachable node
        end
    end

    -- Skip to the closest node, removing nodes with a higher index
    if closestIndex < #path then
        Navigation.SkipToNode(closestIndex)
    end
end

-- Function to optimize the path by skipping intermediate nodes within a distance limit
local function optimizePath()
    local path = G.Navigation.path
    local lastIndex = #path

    -- Start optimization from the last node in the path
    for i = lastIndex - 1, 1, -1 do
        local lastNode = path[lastIndex]
        local currentNode = path[i]

        -- Check if the current node is within 750 units and directly reachable from the last node
        if (lastNode.pos - currentNode.pos):Length() <= 750 
           and Common.isWalkable(lastNode.pos, currentNode.pos) then
            -- Skip intermediate nodes by updating the last index to the current node
            lastIndex = i
        end
    end

    -- If an optimization was made, skip to the new lastIndex node
    if lastIndex < #path then
        Navigation.SkipToNode(lastIndex)
    end
end


-- Helper to attempt jumping if stuck for too long
local function attemptJumpIfStuck(userCmd)
    if G.Navigation.currentNodeTicks > 66 and WorkManager.attemptWork(66, "Unstuck_Jump") then
        userCmd:SetButtons(userCmd.buttons | IN_JUMP)
        Log:Info("Attempting to jump to get unstuck.")
    end
end

-- Helper to remove blocked connections and re-path if path is still blocked after multiple attempts
local function attemptToRemoveBlockedConnection()
    local currentNode = G.Navigation.path[#G.Navigation.path]
    local nextNode = G.Navigation.path[#G.Navigation.path - 1]
    if currentNode and nextNode then
        Log:Warn("Path blocked, removing connection between node %d and node %d", currentNode.id, nextNode.id)
        Node.RemoveConnection(currentNode, nextNode)
        Navigation.ClearPath()
        Navigation.ResetTickTimer()
        Log:Info("Connection removed, re-pathing initiated.")
    else
        Log:Warn("Unable to remove connection: one or more nodes are nil.")
    end
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    local pLocal = entities.GetLocalPlayer()
    G.pLocal.entity = pLocal
    if not pLocal or not pLocal:IsAlive() then
        Navigation.ClearPath()
        return
    end

    local currentTask = TaskManager.GetCurrentTask()
    if not currentTask then
        TaskManager.AddTask("Objective") -- default task
        Navigation.ClearPath()
        return
    end

    G.pLocal.flags = pLocal:GetPropInt("m_fFlags") or 0
    G.pLocal.Origin = pLocal:GetAbsOrigin()

    -- Determine the bot's state
    if (userCmd:GetForwardMove() ~= 0 or userCmd:GetSideMove() ~= 0) then
        G.State = G.StateDefinition.ManualBypass
    elseif G.Navigation.path and #G.Navigation.path > 0 then -- you got path
        G.State = G.StateDefinition.PathWalking
    else
        G.State = G.StateDefinition.Pathfinding
    end

    if G.State == G.StateDefinition.PathWalking then
        handlePathWalkingView(userCmd) --viewangle manager
        --HealthLogic(pLocal) -- health manager

        local LocalOrigin = G.pLocal.Origin
        local nodePos = Node.currentNodePos()
        local horizontalDist = math.abs(LocalOrigin.x - nodePos.x) + math.abs(LocalOrigin.y - nodePos.y)
        local verticalDist = math.abs(LocalOrigin.z - nodePos.z)

        if G.Menu.Main.Walking then
            Common.WalkTo(userCmd, pLocal, nodePos)
        end

        
        if shouldMoveToNextNode(horizontalDist, verticalDist) then
            Navigation.MoveToNextNode()
            if not G.Navigation.path or #G.Navigation.path == 0 then
                Navigation.ClearPath()
                Log:Info("Reached end of path.")
                TaskManager.RemoveTask(currentTask)
                return
            end
        else
            if G.Menu.Main.Skip_Nodes then
                local path = G.Navigation.path
                if path and #path >= 2 then
                    local currentNode = path[#path]
                    local nextNode = path[#path - 1]
                    
                    if currentNode and nextNode and shouldSkipToNextNode(currentNode, nextNode, LocalOrigin) then
                        Log:Info("Skipping to next node %d", nextNode.id)
                        Navigation.MoveToNextNode()
                    end

                    if G.Menu.Main.Optymise_Path and WorkManager.attemptWork(17, "optymise path") then
                        skipToClosestWalkableNode(LocalOrigin)
                    end
                end
            end
            G.Navigation.currentNodeTicks = (G.Navigation.currentNodeTicks or 0) + 1
        end

        if (G.pLocal.flags & FL_ONGROUND == 1) or (pLocal:EstimateAbsVelocity():Length() < 50) then
            if not Common.isWalkable(LocalOrigin, nodePos) then
                attemptJumpIfStuck(userCmd)  -- Try jumping to get unstuck

                if G.Navigation.currentNodeTicks > 244 then
                    -- Remove blocked path or re-path if stuck
                    if not Common.isWalkable(LocalOrigin, nodePos) then
                        attemptToRemoveBlockedConnection()
                    elseif not WorkManager.attemptWork(5, "pathCheck") then
                        Log:Warn("Path is stuck but walkable, re-pathing...")
                        Navigation.ClearPath()
                        Navigation.ResetTickTimer()
                    end
                end
            end
        end
    elseif G.State == G.StateDefinition.Pathfinding then
        local LocalOrigin = G.pLocal.Origin or Vector3(0, 0, 0)
        local startNode = Node.GetClosest(LocalOrigin)
        if not startNode then
            Log:Warn("Could not find start node.")
            return
        end

        local goalNode = nil
        local mapName = engine.GetMapName():lower()

        local function findPayloadGoal()
            G.World.payloads = entities.FindByClass("CObjectCartDispenser")
            for _, entity in pairs(G.World.payloads or {}) do
                if entity:GetTeamNumber() == pLocal:GetTeamNumber() then
                    return Node.GetClosest(entity:GetAbsOrigin())
                end
            end
        end

        local function findFlagGoal()
            local myItem = pLocal:GetPropInt("m_hItem")
            G.World.flags = entities.FindByClass("CCaptureFlag")
            for _, entity in pairs(G.World.flags or {}) do
                local myTeam = entity:GetTeamNumber() == pLocal:GetTeamNumber()
                if (myItem > 0 and myTeam) or (myItem <= 0 and not myTeam) then
                    return Node.GetClosest(entity:GetAbsOrigin())
                end
            end
        end

        local function findHealthGoal()
            local closestDist = math.huge
            local closestNode = nil
            for _, pos in pairs(G.World.healthPacks or {}) do
                local healthNode = Node.GetClosest(pos)
                if healthNode then
                    local dist = (LocalOrigin - pos):Length()
                    if dist < closestDist then
                        closestDist = dist
                        closestNode = healthNode
                    end
                end
            end
            return closestNode
        end

        if currentTask == "Objective" then
            if mapName:find("plr_") or mapName:find("pl_") then
                goalNode = findPayloadGoal()
            elseif mapName:find("ctf_") then
                goalNode = findFlagGoal()
            else
                --Log:Warn("Unsupported gamemode. Try CTF, PL, or PLR.")
                return
            end
        elseif currentTask == "Health" then
            goalNode = findHealthGoal()
        else
            Log:Debug("Unknown task: %s", currentTask)
            return
        end

        if not goalNode then
            Log:Warn("Could not find goal node.")
            return
        end

        if WorkManager.attemptWork(33, "Pathfinding") then
            Log:Info("Generating new path from node %d to node %d", startNode.id, goalNode.id)
            Navigation.ClearPath() -- Ensure we clear the current path before generating a new one
            Navigation.FindPath(startNode, goalNode) -- Run pathfinding synchronously

            -- Check if pathfinding succeeded
            if G.Navigation.path and #G.Navigation.path > 0 then
                G.Navigation.currentNodeinPath = #G.Navigation.path  -- Start at the last node
                G.Navigation.currentNode = G.Navigation.path[G.Navigation.currentNodeinPath]
                G.Navigation.currentNodePos = G.Navigation.currentNode.pos
                Navigation.ResetTickTimer()
                Log:Info("Path found.")
            else
                Log:Warn("No path found.")
            end
        end
    else
        Log:Warn("Unknown state: %s", tostring(G.State))
    end
end

---@param ctx DrawModelContext
local function OnDrawModel(ctx)
    if ctx:GetModelName():find("medkit") then
        local entity = ctx:GetEntity()
        G.World.healthPacks[entity:GetIndex()] = entity:GetAbsOrigin()
    end
end

callbacks.Unregister("CreateMove", "LNX.Lmaobot.CreateMove")
callbacks.Unregister("DrawModel", "LNX.Lmaobot.DrawModel")

callbacks.Register("CreateMove", "LNX.Lmaobot.CreateMove", OnCreateMove)
callbacks.Register("DrawModel", "LNX.Lmaobot.DrawModel", OnDrawModel)

Notify.Alert("Lmaobot loaded!")
end)
__bundle_register("Lmaobot.TaskManager", function(require, _LOADED, __bundle_register, __bundle_modules)
-- TaskManager.lua

--[[ TaskManager Module ]]
local TaskManager = {}

--[[ Dependencies ]]
local G = require("Lmaobot.Utils.Globals") -- Adjust the path as necessary
local Log = require("Lmaobot.Common").Log   -- Assuming Log is in Common module

--[[ TaskManager Functions ]]

--- Adds a task to the current tasks if it doesn't already exist.
---@param taskKey string The key of the task to add.
function TaskManager.AddTask(taskKey)
    local taskPriority = G.Tasks[taskKey]
    if taskPriority then
        if not G.Current_Tasks[taskKey] then
            G.Current_Tasks[taskKey] = taskPriority
            Log:Info("Added task: %s with priority %d", taskKey, taskPriority)
        else
            Log:Info("Task %s is already in the current tasks.", taskKey)
        end
    else
        Log:Warn("Task '%s' does not exist in G.Tasks.", taskKey)
    end
end

--- Removes a task from the current tasks.
---@param taskKey string The key of the task to remove.
function TaskManager.RemoveTask(taskKey)
    if G.Current_Tasks[taskKey] then
        G.Current_Tasks[taskKey] = nil
        Log:Info("Removed task: %s", taskKey)
    else
        Log:Info("Task %s is not in the current tasks.", taskKey)
    end
end

--- Retrieves the task with the highest priority.
---@return string|nil The key of the highest priority task, or nil if no tasks are active.
function TaskManager.GetCurrentTask()
    local highestPriorityTaskKey = nil
    local highestPriority = -math.huge  -- Start with negative infinity

    for taskKey, priority in pairs(G.Current_Tasks) do
        if priority > highestPriority then  -- Higher numerical value means higher priority
            highestPriority = priority
            highestPriorityTaskKey = taskKey
        end
    end

    if highestPriorityTaskKey then
        G.Current_Task = G.Tasks[highestPriorityTaskKey]
    else
        G.Current_Task = G.Tasks.None
    end

    return highestPriorityTaskKey
end

--- Resets the current tasks to only include the default task.
---@param defaultTaskKey string The key of the default task to reset to.
function TaskManager.Reset(defaultTaskKey)
    G.Current_Tasks = {}
    if defaultTaskKey and G.Tasks[defaultTaskKey] then
        TaskManager.AddTask(defaultTaskKey)
        Log:Info("Tasks reset to default task: %s", defaultTaskKey)
    else
        Log:Warn("Default task key '%s' is invalid.", tostring(defaultTaskKey))
    end
end

--- Checks if a task is currently active.
---@param taskKey string The key of the task to check.
---@return boolean True if the task is active, false otherwise.
function TaskManager.IsTaskActive(taskKey)
    return G.Current_Tasks[taskKey] ~= nil
end

return TaskManager

end)
__bundle_register("Lmaobot.Common", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-set-field, undefined-field
---@class Common
local Common = {}

local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")

Common.Lib = Lib
Common.Utils = Common.Lib.Utils
Common.Notify = Lib.UI.Notify
Common.TF2 = Common.Lib.TF2

Common.Math, Common.Conversion = Common.Utils.Math, Common.Utils.Conversion
Common.WPlayer, Common.PR = Common.TF2.WPlayer, Common.TF2.PlayerResource
Common.Helpers = Common.TF2.Helpers
Common.WalkTo = Common.Helpers.WalkTo

Common.Notify = Lib.UI.Notify
Common.Json = require("Lmaobot.Utils.Json") -- Require Json.lua directly
Common.Log = Common.Utils.Logger.new("Lmaobot")
Common.Log.Level = 0

local G = require("Lmaobot.Utils.Globals")
local IsWalkable = require("Lmaobot.Modules.IsWalkable")

Common.isWalkable = IsWalkable.Path

function Common.horizontal_manhattan_distance(pos1, pos2)
    return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function Common.Normalize(vec)
    return vec / vec:Length()
end

--[[ Callbacks ]]
local function OnUnload() -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

callbacks.Unregister("Unload", "CD_Unload")
callbacks.Register("Unload", "CD_Unload", OnUnload)

return Common
end)
__bundle_register("Lmaobot.Modules.IsWalkable", function(require, _LOADED, __bundle_register, __bundle_modules)

--[[           IsWalkable module         ]]--
--[[       Made and optimized by        ]]--
--[[         Titaniummachine1           ]]--
--[[ https://github.com/Titaniummachine1 ]]--

local IsWalkable = {}

--Limits
local MAX_ITERATIONS = 37         -- Maximum number of iterations to prevent infinite loops

-- Constants
local pLocal = entities.GetLocalPlayer()
local PLAYER_HULL = {Min = Vector3(-24, -24, 0), Max = Vector3(24, 24, 82)} -- Player collision hull
local MaxSpeed = pLocal:GetPropFloat("m_flMaxspeed") or 450 -- Default to 450 if max speed not available
local gravity = client.GetConVar("sv_gravity") or 800 -- Gravity or default one
local STEP_HEIGHT = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18 -- Maximum height the player can step up
local STEP_HEIGHT_Vector = Vector3(0, 0, STEP_HEIGHT)
local MAX_FALL_DISTANCE = 250     -- Maximum distance the player can fall without taking fall damage
local MAX_FALL_DISTANCE_Vector = Vector3(0, 0, MAX_FALL_DISTANCE)
local STEP_FRACTION = STEP_HEIGHT / MAX_FALL_DISTANCE

local UP_VECTOR = Vector3(0, 0, 1)
local MIN_STEP_SIZE = MaxSpeed * globals.TickInterval() -- Minimum step size to consider for ground checks
local MAX_SURFACE_ANGLE = 45       -- Maximum angle for ground surfaces

-- Helper Functions
local function shouldHitEntity(entity)
    return entity ~= pLocal -- Ignore self (the player being simulated)
end

-- Normalize a vector
local function Normalize(vec)
    return vec / vec:Length()
end

-- Calculate horizontal Manhattan distance between two points
local function getHorizontalManhattanDistance(point1, point2)
    return math.abs(point1.x - point2.x) + math.abs(point1.y - point2.y)
end

-- Perform a hull trace to check for obstructions between two points
local function performTraceHull(startPos, endPos)
    return engine.TraceHull(startPos, endPos, PLAYER_HULL.Min, PLAYER_HULL.Max, MASK_PLAYERSOLID, shouldHitEntity)
end

-- Adjust the direction vector to align with the surface normal
local function adjustDirectionToSurface(direction, surfaceNormal)
    direction = Normalize(direction)
    local angle = math.deg(math.acos(surfaceNormal:Dot(UP_VECTOR)))

    -- Check if the surface is within the maximum allowed angle for adjustment
    if angle > MAX_SURFACE_ANGLE then
        return direction
    end

    local dotProduct = direction:Dot(surfaceNormal)

    -- Adjust the z component of the direction in place
    direction.z = direction.z - surfaceNormal.z * dotProduct

    -- Normalize the direction after adjustment
    return Normalize(direction)
end

-- Main function to check walkability
function IsWalkable.Path(startPos, goalPos)
    -- Clear trace tables for debugging
    hullTraces = {}
    local blocked = false

    -- Initialize variables
    local currentPos = startPos

    -- Adjust start position to ground level
    local startGroundTrace = performTraceHull(
        startPos + STEP_HEIGHT_Vector,
        startPos - MAX_FALL_DISTANCE_Vector
    )

    currentPos = startGroundTrace.endpos

    -- Initial direction towards goal, adjusted for ground normal
    local lastPos = currentPos
    local lastDirection = adjustDirectionToSurface(goalPos - currentPos, startGroundTrace.plane)

    local MaxDistance = getHorizontalManhattanDistance(startPos, goalPos)

    -- Main loop to iterate towards the goal
    for iteration = 1, MAX_ITERATIONS do
        -- Calculate distance to goal and update direction
        local distanceToGoal = (currentPos - goalPos):Length()
        local direction = lastDirection

        -- Calculate next position
        local NextPos = lastPos + direction * distanceToGoal

        -- Forward collision check
        local wallTrace = performTraceHull(
            lastPos + STEP_HEIGHT_Vector,
            NextPos + STEP_HEIGHT_Vector
        )
        currentPos = wallTrace.endpos

        if wallTrace.fraction == 0 then
            blocked = true -- Path is blocked by a wall
        end

        -- Ground collision with segmentation
        local totalDistance = (currentPos - lastPos):Length()
        local numSegments = math.max(1, math.floor(totalDistance / MIN_STEP_SIZE))

        for seg = 1, numSegments do
            local t = seg / numSegments
            local segmentPos = lastPos + (currentPos - lastPos) * t
            local segmentTop = segmentPos + STEP_HEIGHT_Vector
            local segmentBottom = segmentPos - MAX_FALL_DISTANCE_Vector

            local groundTrace = performTraceHull(segmentTop, segmentBottom)

            if groundTrace.fraction == 1 then
                return false -- No ground beneath; path is unwalkable
            end

            if groundTrace.fraction > STEP_FRACTION or seg == numSegments then
                -- Adjust position to ground
                direction = adjustDirectionToSurface(direction, groundTrace.plane)
                currentPos = groundTrace.endpos
                blocked = false
                break
            end
        end

        -- Calculate current horizontal distance to goal
        local currentDistance = getHorizontalManhattanDistance(currentPos, goalPos)
        if blocked or currentDistance > MaxDistance then --if target is unreachable
            return false
        elseif currentDistance < 24 then --within range
            local verticalDist = math.abs(goalPos.z - currentPos.z)
            if verticalDist < 24 then  --within vertical range
                return true -- Goal is within reach; path is walkable
            else --unreachable
                return false -- Goal is too far vertically; path is unwalkable
            end
        end

        -- Prepare for the next iteration
        lastPos = currentPos
        lastDirection = direction
    end

    return false -- Max iterations reached without finding a path
end

return IsWalkable
end)
__bundle_register("Lmaobot.Utils.Globals", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Define the G module
local G = {}

G.Lua__fileName = GetScriptName():match("([^/\\]+)%.lua$")

G.default_menu = {
    Tabs = {
        Main = true,
        Settings = false,
        Visuals = false,
        Movement = false,
    },

    Main = {
        Loading = 100,
        Walking = true,
        Skip_Nodes = true, -- skips nodes if it can go directly to ones closer to target.
        Optymise_Path = true,-- straighten the nodes into segments so you would go in straight line
        shouldfindhealth = true, -- Path to health
        SelfHealTreshold = 45, -- Health percentage to start looking for healthPacks
        smoothFactor = 0.05
    },
    Visuals = {
        EnableVisuals = true,
        memoryUsage = true,
        drawNodes = true, -- Draws all nodes on the map
        drawPath = true, -- Draws the path to the current goal
        drawCurrentNode = true, -- Draws the current node
    },
    Movement = {
        lookatpath = false, -- Look at where we are walking
        smoothLookAtPath = true, -- Set this to true to enable smooth look at path
        Smart_Jump = true, -- jumps perfectly before obstacle to be at peek of jump height when at collision point
    }
}

G.Menu = G.Default_Menu

G.Default = {
    flags = 1,
    vHitbox = {Min = Vector3(-24, -24, 0), Max = Vector3(24, 24, 82)},
}

G.pLocal = G.Default

G.World_Default = {
    healthPacks = {},  -- Stores positions of health packs
    spawns = {},       -- Stores positions of spawn points
    payloads = {},     -- Stores payload entities in payload maps
    flags = {},        -- Stores flag entities in CTF maps (implicitly included in the logic)
}

G.World = G.World_Default

G.Gui = {
    IsVisible = false,
}

G.Misc = {
    NodeTouchDistance = 14,
    NodeTouchHeight = 82,
}

G.Navigation = {
    path = nil,
    nodes = nil,
    currentNode = nil,
    currentNodePos = nil,
    currentNodeinPath = 1000,
    currentNodeTicks = 0,
    nodesCount = 0,
}

G.Tasks = {
    None = 0,
    Objective = 1,
    Follow = 2,
    Health = 3,
    Medic = 4,
    Goto = 5,
}

G.Current_Tasks = {}
G.Current_Task = G.Tasks.Objective

G.Benchmark = {
    MemUsage = 0
}

G.StateDefinition = {
    Pathfinding = 1,
    PathWalking = 2,
    Walking = 3,
    Parkour = 4,
    ManualBypass = 5,
}

G.State = nil

function G.ReloadNodes()
    G.Navigation.nodes = G.Navigation.rawNodes
end

return G
end)
__bundle_register("Lmaobot.Utils.Json", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
David Kolf's JSON module for Lua 5.1 - 5.4

Version 2.6


For the documentation see the corresponding readme.txt or visit
<http://dkolf.de/src/dkjson-lua.fsl/>.

You can contact the author by sending an e-mail to 'david' at the
domain 'dkolf.de'.


Copyright (C) 2010-2021 David Heiko Kolf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

---@alias JsonState { indent : boolean?, keyorder : integer[]?, level : integer?, buffer : string[]?, bufferlen : integer?, tables : table[]?, exception : function? }

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset =
    pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat =
    string.rep, string.gsub, string.sub, string.byte, string.char,
    string.find, string.len, string.format
local strmatch = string.match
local concat = table.concat

---@class Json
local json = { version = "dkjson 2.6.1 L" }

local _ENV = nil -- blocking globals in Lua 5.2 and later

json.null = setmetatable({}, {
    __tojson = function() return "null" end
})

local function isarray(tbl)
    local max, n, arraylen = 0, 0, 0
    for k, v in pairs(tbl) do
        if k == 'n' and type(v) == 'number' then
            arraylen = v
            if v > max then
                max = v
            end
        else
            if type(k) ~= 'number' or k < 1 or floor(k) ~= k then
                return false
            end
            if k > max then
                max = k
            end
            n = n + 1
        end
    end
    if max > 10 and max > arraylen and max > n * 2 then
        return false -- don't create an array with too many holes
    end
    return true, max
end

local escapecodes = {
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
}

local function escapeutf8(uchar)
    local value = escapecodes[uchar]
    if value then
        return value
    end
    local a, b, c, d = strbyte(uchar, 1, 4)
    a, b, c, d = a or 0, b or 0, c or 0, d or 0
    if a <= 0x7f then
        value = a
    elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
        value = (a - 0xc0) * 0x40 + b - 0x80
    elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
        value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
    elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
        value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
    else
        return ""
    end
    if value <= 0xffff then
        return strformat("\\u%.4x", value)
    elseif value <= 0x10ffff then
        -- encode as UTF-16 surrogate pair
        value = value - 0x10000
        local highsur, lowsur = 0xD800 + floor(value / 0x400), 0xDC00 + (value % 0x400)
        return strformat("\\u%.4x\\u%.4x", highsur, lowsur)
    else
        return ""
    end
end

local function fsub(str, pattern, repl)
    -- gsub always builds a new string in a buffer, even when no match
    -- exists. First using find should be more efficient when most strings
    -- don't contain the pattern.
    if strfind(str, pattern) then
        return gsub(str, pattern, repl)
    else
        return str
    end
end

local function quotestring(value)
    -- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
    value = fsub(value, "[%z\1-\31\"\\\127]", escapeutf8)
    if strfind(value, "[\194\216\220\225\226\239]") then
        value = fsub(value, "\194[\128-\159\173]", escapeutf8)
        value = fsub(value, "\216[\128-\132]", escapeutf8)
        value = fsub(value, "\220\143", escapeutf8)
        value = fsub(value, "\225\158[\180\181]", escapeutf8)
        value = fsub(value, "\226\128[\140-\143\168-\175]", escapeutf8)
        value = fsub(value, "\226\129[\160-\175]", escapeutf8)
        value = fsub(value, "\239\187\191", escapeutf8)
        value = fsub(value, "\239\191[\176-\191]", escapeutf8)
    end
    return "\"" .. value .. "\""
end
json.quotestring = quotestring

local function replace(str, o, n)
    local i, j = strfind(str, o, 1, true)
    if i then
        return strsub(str, 1, i - 1) .. n .. strsub(str, j + 1, -1)
    else
        return str
    end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint()
    decpoint = strmatch(tostring(0.5), "([^05+])")
    -- build a filter that can be used to remove group separators
    numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function num2str(num)
    return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

local function str2num(str)
    local num = tonumber(replace(str, ".", decpoint))
    if not num then
        updatedecpoint()
        num = tonumber(replace(str, ".", decpoint))
    end
    return num
end

local function addnewline2(level, buffer, buflen)
    buffer[buflen + 1] = "\n"
    buffer[buflen + 2] = strrep("  ", level)
    buflen = buflen + 2
    return buflen
end

function json.addnewline(state)
    if state.indent then
        state.bufferlen = addnewline2(state.level or 0,
            state.buffer, state.bufferlen or #(state.buffer))
    end
end

local encode2 -- forward declaration

local function addpair(key, value, prev, indent, level, buffer, buflen, tables, globalorder, state)
    local kt = type(key)
    if kt ~= 'string' and kt ~= 'number' then
        return nil, "type '" .. kt .. "' is not supported as a key by JSON."
    end
    if prev then
        buflen = buflen + 1
        buffer[buflen] = ","
    end
    if indent then
        buflen = addnewline2(level, buffer, buflen)
    end
    buffer[buflen + 1] = quotestring(key)
    buffer[buflen + 2] = ":"
    return encode2(value, indent, level, buffer, buflen + 2, tables, globalorder, state)
end

local function appendcustom(res, buffer, state)
    local buflen = state.bufferlen
    if type(res) == 'string' then
        buflen = buflen + 1
        buffer[buflen] = res
    end
    return buflen
end

local function exception(reason, value, state, buffer, buflen, defaultmessage)
    defaultmessage = defaultmessage or reason
    local handler = state.exception
    if not handler then
        return nil, defaultmessage
    else
        state.bufferlen = buflen
        local ret, msg = handler(reason, value, state, defaultmessage)
        if not ret then return nil, msg or defaultmessage end
        return appendcustom(ret, buffer, state)
    end
end

function json.encodeexception(reason, value, state, defaultmessage)
    return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function(value, indent, level, buffer, buflen, tables, globalorder, state)
    local valtype = type(value)
    local valmeta = getmetatable(value)
    valmeta = type(valmeta) == 'table' and valmeta -- only tables
    local valtojson = valmeta and valmeta.__tojson
    if valtojson then
        if tables[value] then
            return exception('reference cycle', value, state, buffer, buflen)
        end
        tables[value] = true
        state.bufferlen = buflen
        local ret, msg = valtojson(value, state)
        if not ret then return exception('custom encoder failed', value, state, buffer, buflen, msg) end
        tables[value] = nil
        buflen = appendcustom(ret, buffer, state)
    elseif value == nil then
        buflen = buflen + 1
        buffer[buflen] = "null"
    elseif valtype == 'number' then
        local s
        if value ~= value or value >= huge or -value >= huge then
            -- This is the behaviour of the original JSON implementation.
            s = "null"
        else
            s = num2str(value)
        end
        buflen = buflen + 1
        buffer[buflen] = s
    elseif valtype == 'boolean' then
        buflen = buflen + 1
        buffer[buflen] = value and "true" or "false"
    elseif valtype == 'string' then
        buflen = buflen + 1
        buffer[buflen] = quotestring(value)
    elseif valtype == 'table' then
        if tables[value] then
            return exception('reference cycle', value, state, buffer, buflen)
        end
        tables[value] = true
        level = level + 1
        local isa, n = isarray(value)
        if n == 0 and valmeta and valmeta.__jsontype == 'object' then
            isa = false
        end
        local msg
        if isa then -- JSON array
            buflen = buflen + 1
            buffer[buflen] = "["
            for i = 1, n do
                buflen, msg = encode2(value[i], indent, level, buffer, buflen, tables, globalorder, state)
                if not buflen then return nil, msg end
                if i < n then
                    buflen = buflen + 1
                    buffer[buflen] = ","
                end
            end
            buflen = buflen + 1
            buffer[buflen] = "]"
        else -- JSON object
            local prev = false
            buflen = buflen + 1
            buffer[buflen] = "{"
            local order = valmeta and valmeta.__jsonorder or globalorder
            if order then
                local used = {}
                n = #order
                for i = 1, n do
                    local k = order[i]
                    local v = value[k]
                    if v ~= nil then
                        used[k] = true
                        buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                        prev = true -- add a seperator before the next element
                    end
                end
                for k, v in pairs(value) do
                    if not used[k] then
                        buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                        if not buflen then return nil, msg end
                        prev = true -- add a seperator before the next element
                    end
                end
            else -- unordered
                for k, v in pairs(value) do
                    buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                    if not buflen then return nil, msg end
                    prev = true -- add a seperator before the next element
                end
            end
            if indent then
                buflen = addnewline2(level - 1, buffer, buflen)
            end
            buflen = buflen + 1
            buffer[buflen] = "}"
        end
        tables[value] = nil
    else
        return exception('unsupported type', value, state, buffer, buflen,
            "type '" .. valtype .. "' is not supported by JSON.")
    end
    return buflen
end

---Encodes a lua table to a JSON string.
---@param value any
---@param state JsonState
---@return string|boolean
function json.encode(value, state)
    state = state or {}
    local oldbuffer = state.buffer
    local buffer = oldbuffer or {}
    state.buffer = buffer
    updatedecpoint()
    local ret, msg = encode2(value, state.indent, state.level or 0,
        buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state)
    if not ret then
        error(msg, 2)
    elseif oldbuffer == buffer then
        state.bufferlen = ret
        return true
    else
        state.bufferlen = nil
        state.buffer = nil
        return concat(buffer)
    end
end

local function loc(str, where)
    local line, pos, linepos = 1, 1, 0
    while true do
        pos = strfind(str, "\n", pos, true)
        if pos and pos < where then
            line = line + 1
            linepos = pos
            pos = pos + 1
        else
            break
        end
    end
    return "line " .. line .. ", column " .. (where - linepos)
end

local function unterminated(str, what, where)
    return nil, strlen(str) + 1, "unterminated " .. what .. " at " .. loc(str, where)
end

local function scanwhite(str, pos)
    while true do
        pos = strfind(str, "%S", pos)
        if not pos then return nil end
        local sub2 = strsub(str, pos, pos + 1)
        if sub2 == "\239\187" and strsub(str, pos + 2, pos + 2) == "\191" then
            -- UTF-8 Byte Order Mark
            pos = pos + 3
        elseif sub2 == "//" then
            pos = strfind(str, "[\n\r]", pos + 2)
            if not pos then return nil end
        elseif sub2 == "/*" then
            pos = strfind(str, "*/", pos + 2)
            if not pos then return nil end
            pos = pos + 2
        else
            return pos
        end
    end
end

local escapechars = {
    ["\""] = "\"",
    ["\\"] = "\\",
    ["/"] = "/",
    ["b"] = "\b",
    ["f"] = "\f",
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t"
}

local function unichar(value)
    if value < 0 then
        return nil
    elseif value <= 0x007f then
        return strchar(value)
    elseif value <= 0x07ff then
        return strchar(0xc0 + floor(value / 0x40),
            0x80 + (floor(value) % 0x40))
    elseif value <= 0xffff then
        return strchar(0xe0 + floor(value / 0x1000),
            0x80 + (floor(value / 0x40) % 0x40),
            0x80 + (floor(value) % 0x40))
    elseif value <= 0x10ffff then
        return strchar(0xf0 + floor(value / 0x40000),
            0x80 + (floor(value / 0x1000) % 0x40),
            0x80 + (floor(value / 0x40) % 0x40),
            0x80 + (floor(value) % 0x40))
    else
        return nil
    end
end

local function scanstring(str, pos)
    local lastpos = pos + 1
    local buffer, n = {}, 0
    while true do
        local nextpos = strfind(str, "[\"\\]", lastpos)
        if not nextpos then
            return unterminated(str, "string", pos)
        end
        if nextpos > lastpos then
            n = n + 1
            buffer[n] = strsub(str, lastpos, nextpos - 1)
        end
        if strsub(str, nextpos, nextpos) == "\"" then
            lastpos = nextpos + 1
            break
        else
            local escchar = strsub(str, nextpos + 1, nextpos + 1)
            local value
            if escchar == "u" then
                value = tonumber(strsub(str, nextpos + 2, nextpos + 5), 16)
                if value then
                    local value2
                    if 0xD800 <= value and value <= 0xDBff then
                        -- we have the high surrogate of UTF-16. Check if there is a
                        -- low surrogate escaped nearby to combine them.
                        if strsub(str, nextpos + 6, nextpos + 7) == "\\u" then
                            value2 = tonumber(strsub(str, nextpos + 8, nextpos + 11), 16)
                            if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
                                value = (value - 0xD800) * 0x400 + (value2 - 0xDC00) + 0x10000
                            else
                                value2 = nil -- in case it was out of range for a low surrogate
                            end
                        end
                    end
                    value = value and unichar(value)
                    if value then
                        if value2 then
                            lastpos = nextpos + 12
                        else
                            lastpos = nextpos + 6
                        end
                    end
                end
            end
            if not value then
                value = escapechars[escchar] or escchar
                lastpos = nextpos + 2
            end
            n = n + 1
            buffer[n] = value
        end
    end
    if n == 1 then
        return buffer[1], lastpos
    elseif n > 1 then
        return concat(buffer), lastpos
    else
        return "", lastpos
    end
end

local scanvalue -- forward declaration

local function scantable(what, closechar, str, startpos, nullval, objectmeta, arraymeta)
    local tbl, n = {}, 0
    local pos = startpos + 1
    if what == 'object' then
        setmetatable(tbl, objectmeta)
    else
        setmetatable(tbl, arraymeta)
    end
    while true do
        pos = scanwhite(str, pos)
        if not pos then return unterminated(str, what, startpos) end
        local char = strsub(str, pos, pos)
        if char == closechar then
            return tbl, pos + 1
        end
        local val1, err
        val1, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
        if err then return nil, pos, err end
        pos = scanwhite(str, pos)
        if not pos then return unterminated(str, what, startpos) end
        char = strsub(str, pos, pos)
        if char == ":" then
            if val1 == nil then
                return nil, pos, "cannot use nil as table index (at " .. loc(str, pos) .. ")"
            end
            pos = scanwhite(str, pos + 1)
            if not pos then return unterminated(str, what, startpos) end
            local val2
            val2, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
            if err then return nil, pos, err end
            tbl[val1] = val2
            pos = scanwhite(str, pos)
            if not pos then return unterminated(str, what, startpos) end
            char = strsub(str, pos, pos)
        else
            n = n + 1
            tbl[n] = val1
        end
        if char == "," then
            pos = pos + 1
        end
    end
end

scanvalue = function(str, pos, nullval, objectmeta, arraymeta)
    pos = pos or 1
    pos = scanwhite(str, pos)
    if not pos then
        return nil, strlen(str) + 1, "no valid JSON value (reached the end)"
    end
    local char = strsub(str, pos, pos)
    if char == "{" then
        return scantable('object', "}", str, pos, nullval, objectmeta, arraymeta)
    elseif char == "[" then
        return scantable('array', "]", str, pos, nullval, objectmeta, arraymeta)
    elseif char == "\"" then
        return scanstring(str, pos)
    else
        local pstart, pend = strfind(str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
        if pstart then
            local number = str2num(strsub(str, pstart, pend))
            if number then
                return number, pend + 1
            end
        end
        pstart, pend = strfind(str, "^%a%w*", pos)
        if pstart then
            local name = strsub(str, pstart, pend)
            if name == "true" then
                return true, pend + 1
            elseif name == "false" then
                return false, pend + 1
            elseif name == "null" then
                return nullval, pend + 1
            end
        end
        return nil, pos, "no valid JSON value at " .. loc(str, pos)
    end
end

local function optionalmetatables(...)
    if select("#", ...) > 0 then
        return ...
    else
        return { __jsontype = 'object' }, { __jsontype = 'array' }
    end
end

---@param str string
---@param pos integer?
---@param nullval any?
---@param ... table?
function json.decode(str, pos, nullval, ...)
    local objectmeta, arraymeta = optionalmetatables(...)
    return scanvalue(str, pos, nullval, objectmeta, arraymeta)
end

return json

end)
__bundle_register("Lmaobot.WorkManager", function(require, _LOADED, __bundle_register, __bundle_modules)
local WorkManager = {}
WorkManager.works = {}
WorkManager.sortedIdentifiers = {}
WorkManager.workLimit = 1
WorkManager.executedWorks = 0

local function getCurrentTick()
    return globals.TickCount()
end

--- Adds work to the WorkManager and executes it if possible
--- @param func function The function to be executed
--- @param args table The arguments to pass to the function
--- @param delay number The delay (in ticks) before the function should be executed
--- @param identifier string A unique identifier for the work
function WorkManager.addWork(func, args, delay, identifier)
    local currentTime = getCurrentTick()
    args = args or {}

    -- Check if the work already exists
    if WorkManager.works[identifier] then
        -- Update existing work details (function, delay, args)
        WorkManager.works[identifier].func = func
        WorkManager.works[identifier].delay = delay or 1
        WorkManager.works[identifier].args = args
        WorkManager.works[identifier].wasExecuted = false
    else
        -- Add new work
        WorkManager.works[identifier] = {
            func = func,
            delay = delay,
            args = args,
            lastExecuted = currentTime,
            wasExecuted = false,
            result = nil
        }
        -- Insert identifier and sort works based on their delay, in descending order
        table.insert(WorkManager.sortedIdentifiers, identifier)
        table.sort(WorkManager.sortedIdentifiers, function(a, b)
            return WorkManager.works[a].delay > WorkManager.works[b].delay
        end)
    end

    -- Attempt to execute the work immediately if within the work limit
    if WorkManager.executedWorks < WorkManager.workLimit then
        local entry = WorkManager.works[identifier]
        if not entry.wasExecuted and currentTime - entry.lastExecuted >= entry.delay then
            -- Execute the work
            entry.result = {func(table.unpack(args))}
            entry.wasExecuted = true
            entry.lastExecuted = currentTime
            WorkManager.executedWorks = WorkManager.executedWorks + 1
            return table.unpack(entry.result)
        end
    end

    -- Return cached result if the work cannot be executed immediately
    local entry = WorkManager.works[identifier]
    return table.unpack(entry.result or {})
end

--- Attempts to execute work if conditions are met
--- @param delay number The delay (in ticks) before the function should be executed again
--- @param identifier string A unique identifier for the work
--- @return boolean Whether the work was executed
function WorkManager.attemptWork(delay, identifier)
    local currentTime = getCurrentTick()

    -- Check if the work already exists and was executed recently
    if WorkManager.works[identifier] and currentTime - WorkManager.works[identifier].lastExecuted < delay then
        return false
    end

    -- If the work does not exist or the delay has passed, create/update the work entry
    if not WorkManager.works[identifier] then
        WorkManager.works[identifier] = {
            lastExecuted = currentTime,
            delay = delay
        }
    else
        WorkManager.works[identifier].lastExecuted = currentTime
    end

    return true
end

--- Processes the works based on their priority
function WorkManager.processWorks()
    local currentTime = getCurrentTick()
    WorkManager.executedWorks = 0

    for _, identifier in ipairs(WorkManager.sortedIdentifiers) do
        local work = WorkManager.works[identifier]
        if not work.wasExecuted and currentTime - work.lastExecuted >= work.delay then
            -- Execute the work
            work.result = {work.func(table.unpack(work.args))}
            work.wasExecuted = true
            work.lastExecuted = currentTime
            WorkManager.executedWorks = WorkManager.executedWorks + 1

            -- Stop if the work limit is reached
            if WorkManager.executedWorks >= WorkManager.workLimit then
                break
            end
        end
    end
end

return WorkManager

end)
__bundle_register("Lmaobot.Utils.Navigation", function(require, _LOADED, __bundle_register, __bundle_modules)
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
end)
__bundle_register("Lmaobot.Utils.A-Star", function(require, _LOADED, __bundle_register, __bundle_modules)
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
    return (connode.pos.z - node.pos.z) < 100
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

end)
__bundle_register("Lmaobot.Utils.Heap", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Enhanced Heap implementation in Lua.
    Modifications made for robustness and preventing memory leaks.
    Credits: github.com/GlorifiedPig/Luafinding
]]

local Heap = {}
Heap.__index = Heap

-- Constructor for the heap.
-- @param compare? Function for comparison, defining the heap property. Defaults to a min-heap.
function Heap.new(compare)
    return setmetatable({
        _data = {},
        _size = 0,
        Compare = compare or function(a, b) return a < b end
    }, Heap)
end

-- Helper function to maintain the heap property while inserting an element.
local function sortUp(heap, index)
    while index > 1 do
        local parentIndex = math.floor(index / 2)
        if heap.Compare(heap._data[index], heap._data[parentIndex]) then
            heap._data[index], heap._data[parentIndex] = heap._data[parentIndex], heap._data[index]
            index = parentIndex
        else
            break
        end
    end
end

-- Helper function to maintain the heap property after removing the root element.
local function sortDown(heap, index)
    while true do
        local leftIndex, rightIndex = 2 * index, 2 * index + 1
        local smallest = index

        if leftIndex <= heap._size and heap.Compare(heap._data[leftIndex], heap._data[smallest]) then
            smallest = leftIndex
        end
        if rightIndex <= heap._size and heap.Compare(heap._data[rightIndex], heap._data[smallest]) then
            smallest = rightIndex
        end

        if smallest ~= index then
            heap._data[index], heap._data[smallest] = heap._data[smallest], heap._data[index]
            index = smallest
        else
            break
        end
    end
end

-- Checks if the heap is empty.
function Heap:empty()
    return self._size == 0
end

-- Clears the heap, allowing Lua's garbage collector to reclaim memory.
function Heap:clear()
    for i = 1, self._size do
        self._data[i] = nil
    end
    self._size = 0
end

-- Adds an item to the heap.
-- @param item The item to be added.
function Heap:push(item)
    self._size = self._size + 1
    self._data[self._size] = item
    sortUp(self, self._size)
end

-- Removes and returns the root element of the heap.
function Heap:pop()
    if self._size == 0 then
        return nil
    end
    local root = self._data[1]
    self._data[1] = self._data[self._size]
    self._data[self._size] = nil  -- Clear the reference to the removed item
    self._size = self._size - 1
    if self._size > 0 then
        sortDown(self, 1)
    end
    return root
end

return Heap

end)
__bundle_register("Lmaobot.Utils.Node", function(require, _LOADED, __bundle_register, __bundle_modules)
local Node = {}

local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")


-- Clear all nodes
function Node.clearNodes()
    G.Navigation.nodes = {}
    G.Navigation.nodesCount = 0
end

-- Set new nodes into the global state
function Node.SetNodes(nodes)
    G.Navigation.nodes = nodes
end

-- Get all nodes from the global state
function Node.GetNodes()
    return G.Navigation.nodes
end

-- Get a node by its ID
function Node.GetNodeByID(id)
    return G.Navigation.nodes[id]
end

function Node.currentNodePos()
    return G.Navigation.currentNodePos
end

-- Function to process a single node and calculate its position
function Node.create(area)
    local cX = (area.north_west.x + area.south_east.x) / 2
    local cY = (area.north_west.y + area.south_east.y) / 2
    local cZ = (area.north_west.z + area.south_east.z) / 2

    return {
        pos = Vector3(cX, cY, cZ),
        id = area.id,
        c = area.connections or {},  -- Ensure connections exist
        corners = {
            nw = area.north_west,
            se = area.south_east,
        },
    }
end

-- Function to process connections for a node, checking against all nodes
function Node.processConnections(node)
    node.c = node.c or {}  -- Initialize connections table
    local nodes = Node.GetNodes()
    for _, targetNode in pairs(nodes) do
        if targetNode.id ~= node.id and Common.isWalkable(node.pos, targetNode.pos) then
            -- Use a specific direction (e.g., 5) for adding connections
            node.c[5] = node.c[5] or { count = 0, connections = {} }
            table.insert(node.c[5].connections, targetNode.id)
            node.c[5].count = node.c[5].count + 1
        end
    end
end

-- Function to remove a connection between two nodes
function Node.RemoveConnection(nodeA, nodeB)
    local nodes = Node.GetNodes()
    if not nodes or not nodes[nodeA.id] or not nodes[nodeB.id] then return end
    local nodeAGlobal = nodes[nodeA.id]
    local nodeBGlobal = nodes[nodeB.id]

    if not nodeAGlobal or not nodeBGlobal then return end

    -- Remove the connection from nodeA to nodeB
    for dir = 1, 4 do
        local conDir = nodeAGlobal.c[dir]
        if conDir then
            for i, con in ipairs(conDir.connections) do
                if con == nodeBGlobal.id then
                    table.remove(conDir.connections, i)
                    conDir.count = conDir.count - 1
                    break
                end
            end
        end
    end
end

---@param pos Vector3|{ x:number, y:number, z:number }
---@return Node
function Node.GetClosest(pos)
    local closestDist = math.huge
    local nodes = Node.GetNodes()
    local closestNode = {}

    for _, node in pairs(nodes) do
        if node and node.pos then
            local dist = (node.pos - pos):Length()
            if dist < closestDist and Common.isWalkable(pos, node.pos)  then
                closestNode = node
                closestDist = dist
            end
        else
            error("GetClosestNode: Node or node.pos is nil")
        end
    end

    return closestNode
end

-- Function to reindex nodes sequentially
function Node.reindexNodesSequentially()
    local nodes = Node.GetNodes()
    local newNodes = {}
    local idMap = {}  -- Map old IDs to new sequential IDs
    local index = 1   -- Start with the first sequential ID

    -- First pass: assign new sequential IDs while keeping original connections
    for oldID, node in pairs(nodes) do
        idMap[oldID] = index  -- Map old ID to new sequential ID
        node.id = index       -- Assign the new ID
        newNodes[index] = node  -- Store the node in the new table
        index = index + 1
    end

    -- Second pass: update all connections to use the new sequential IDs
    for _, node in pairs(newNodes) do
        if node.c then
            for _, connData in pairs(node.c) do
                if connData.connections then
                    for i, connID in ipairs(connData.connections) do
                        connData.connections[i] = idMap[connID]  -- Update to new ID
                    end
                end
            end
        end
    end

    return newNodes  -- Return the new table with sequential IDs
end

return Node

end)
__bundle_register("Lmaobot.Modules.Setup", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Setup Module ]]
---@class SetupModule
local SetupModule = {}
SetupModule.__index = SetupModule

-- Required libraries
local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local SourceNav = require("Lmaobot.Utils.SourceNav")
local Node = require("Lmaobot.Utils.Node")  -- Using Node module
local Navigation = require("Lmaobot.Utils.Navigation")
local TaskManager = require("Lmaobot.TaskManager") -- Adjust the path as necessary
--local loader = require("Lmaobot.Utils.loader")
local Log = Common.Log

require("Lmaobot.Utils.Config")  -- Using Node module
require("Lmaobot.Utils.Commands")
require("Lmaobot.Modules.SmartJump")
require("Lmaobot.Visuals")
require("Lmaobot.Menu")

-- Variables to handle asynchronous nav file loading
local isNavGenerationInProgress = false
local navGenerationStartTime = 0
local navCheckElapsedTime = 0
local navCheckMaxTime = 60  -- maximum time to wait for nav generation

-- Attempts to read and parse the nav file
function SetupModule.tryLoadNavFile(navFilePath)
    local file = io.open(navFilePath, "rb")
    if not file then
        print("Nav file not found: " .. navFilePath)
        return nil, "File not found"
    end

    local content = file:read("*a")
    file:close()

    local navData = SourceNav.parse(content)
    if not navData or #navData.areas == 0 then
        print("Failed to parse nav file or no areas found: " .. navFilePath)
        return nil, "Failed to parse nav file or no areas found."
    end

    return navData
end

-- Generates the nav file
function SetupModule.generateNavFile()
    print("Starting nav file generation...")
    client.RemoveConVarProtection("sv_cheats")
    client.RemoveConVarProtection("nav_generate")
    client.SetConVar("sv_cheats", "1")
    client.Command("nav_generate", true)
    print("Nav file generation command sent. Please wait...")

    -- Set the flag to indicate that nav generation is in progress
    isNavGenerationInProgress = true
    navGenerationStartTime = globals.RealTime()
    navCheckElapsedTime = 0
end

-- Processes nav data and creates nodes using the Node module
function SetupModule.processNavData(navData)
    local navNodes = {}
    local totalNodes = 0

    for _, area in pairs(navData.areas) do
        navNodes[area.id] = Node.create(area)  -- Use Node module for node creation
        totalNodes = totalNodes + 1
    end

    Node.SetNodes(navNodes)  -- Use Node module to set nodes globally
    Log:Info("Processed %d nodes in nav data.", totalNodes)
    return navNodes
end

-- Main function to load the nav file
---@param navFile string
function SetupModule.LoadFile(navFile)
    local fullPath = "tf/" .. navFile

    local navData, error = SetupModule.tryLoadNavFile(fullPath)

    if not navData and error == "File not found" then
        Log:Warn("Nav file not found, generating new one.")
        SetupModule.generateNavFile()
    elseif not navData then
        Log:Error("Error loading nav file: %s", error)
        return
    else
        SetupModule.processNavDataAndSet(navData)
    end
end

-- Processes nav data and sets the navigation nodes
function SetupModule.processNavDataAndSet(navData)
    local navNodes = SetupModule.processNavData(navData)
    if not navNodes or next(navNodes) == nil then
        Log:Error("No nodes found in nav data after processing.")
    else
        Node.SetNodes(navNodes)  -- Set nodes in global state
        Log:Info("Nav nodes set")
    end
end

-- Periodically checks if the nav file is available
function SetupModule.checkNavFileGeneration()
    if not isNavGenerationInProgress then
        return
    end

    navCheckElapsedTime = globals.RealTime() - navGenerationStartTime

    if navCheckElapsedTime >= navCheckMaxTime then
        Log:Error("Nav file generation failed or took too long.")
        isNavGenerationInProgress = false
        return
    end

    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, "%.bsp$", ".nav")
    local fullPath = "tf/" .. navFile

    local navData, error = SetupModule.tryLoadNavFile(fullPath)
    if navData then
        Log:Info("Nav file generated successfully.")
        isNavGenerationInProgress = false
        SetupModule.processNavDataAndSet(navData)
    else
        if math.floor(navCheckElapsedTime) % 10 == 0 then
            Log:Info("Waiting for nav file generation... (%d seconds elapsed)", math.floor(navCheckElapsedTime))
        end
    end
end

-- Loads the nav file of the current map
function SetupModule.LoadNavFile()
    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, "%.bsp$", ".nav")
    Log:Info("Loading nav file for current map: %s", navFile)
    SetupModule.LoadFile(navFile)
end

-- Total number of nodes and other variables
local processedNodes = 0
local totalNodes = 0

-- Function to setup the navigation by loading the navigation file
function SetupModule.SetupNavigation()
    -- Reload nodes from the navigation file
    SetupModule.LoadNavFile()
    Navigation.ClearPath() -- Clear path after loading nav file
    TaskManager.Reset(G.Tasks.Objective) --Rseset any ongoing objective
    Log:Info("Navigation setup initiated.")

    --reindex all nodes
    Node.SetNodes(Node.reindexNodesSequentially(Node.GetNodes()))
    Log:Info(string.format("Total nodes: %d", #Node.GetNodes()))
end

-- Initial setup
SetupModule.SetupNavigation()

-- Function to process a single node and its visible areas
local function processSingleNode(node, nodes)
    Node.processConnections(node, nodes)  -- Use Node module for connection processing
end

-- Main batch processing function
local function processVisibleNodesBatch(nodes)
    local processedCount = 0  -- Track nodes processed within this batch

    -- Iterate through nodes
    for id, node in pairs(nodes) do
        if processedNodes >= totalNodes then
            return true  -- All nodes processed, task is complete
        end

        -- Process a single node
        processSingleNode(node, nodes)

        -- Update progress bar and clamp to 2 decimal places
        processedNodes = processedNodes + 1
        G.Menu.Main.Loading = tonumber(string.format("%.2f", math.min((processedNodes / totalNodes) * 100, 100)))

        processedCount = processedCount + 1

        -- Check if batch size limit is reached
        if processedCount >= loader.batch_size then
            return false  -- Yield control back to the loader
        end
    end

    -- Return true if all nodes have been processed
    return processedNodes >= totalNodes
end

-- Function to initiate the node processing task with the loader
local function startNodeProcessingTask(nodes)
    loader.create(function()
        return processVisibleNodesBatch(nodes)
    end)
end

---@param event GameEvent
local function OnGameEvent(event)
    local eventName = event:GetName()
    if eventName == "game_newmap" then
        Log:Info("New map detected, reloading nav file...")
        SetupModule.SetupNavigation()

        processedNodes = 0
        --startNodeProcessingTask(Node.getNodes())  -- Restart node processing after map reload

        Navigation.ClearPath()  -- Clear the path using Node module
    end
end

callbacks.Unregister("FireGameEvent", "LNX.Lmaobot.FireGameEvent")
callbacks.Register("FireGameEvent", "LNX.Lmaobot.FireGameEvent", OnGameEvent)

-- Cleanup before loading the rest of the code
collectgarbage("collect")

return SetupModule

end)
__bundle_register("Lmaobot.Menu", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[debug commands
    client.SetConVar("cl_vWeapon_sway_interp",              0)             -- Set cl_vWeapon_sway_interp to 0
    client.SetConVar("cl_jiggle_bone_framerate_cutoff", 0)             -- Set cl_jiggle_bone_framerate_cutoff to 0
    client.SetConVar("cl_bobcycle",                     10000)         -- Set cl_bobcycle to 10000
    client.SetConVar("sv_cheats", 1)                                    -- debug fast setup
    client.SetConVar("mp_disable_respawn_times", 1)
    client.SetConVar("mp_respawnwavetime", -1)
    client.SetConVar("mp_teams_unbalance_limit", 1000)

    -- debug command: ent_fire !picker Addoutput "health 99999" --superbot
]]
local MenuModule = {}

--[[ Imports ]]
local G = require("Lmaobot.Utils.Globals")
local Common = require("Lmaobot.Common")

local Input = Common.Utils.Input
local Fonts = Common.Lib.UI.Fonts

---@type boolean, ImMenu
local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local lastToggleTime = 0
local Lbox_Menu_Open = true
local toggleCooldown = 0.1  -- 100 milliseconds

function MenuModule.toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= toggleCooldown then
        Lbox_Menu_Open = not Lbox_Menu_Open  -- Toggle the state
        G.Gui.IsVisible = Lbox_Menu_Open
        lastToggleTime = currentTime  -- Reset the last toggle time
    end
end

function MenuModule.GetPressedkey()
    local pressedKey = Input.GetPressedKey()
        if not pressedKey then
            -- Check for standard mouse buttons
            if input.IsButtonDown(MOUSE_LEFT) then return MOUSE_LEFT end
            if input.IsButtonDown(MOUSE_RIGHT) then return MOUSE_RIGHT end
            if input.IsButtonDown(MOUSE_MIDDLE) then return MOUSE_MIDDLE end

            -- Check for additional mouse buttons
            for i = 1, 10 do
                if input.IsButtonDown(MOUSE_FIRST + i - 1) then return MOUSE_FIRST + i - 1 end
            end
        end
        return pressedKey
end

--[[
local bindTimer = 0
local bindDelay = 0.25  -- Delay of 0.25 seconds

local function handleKeybind(noKeyText, keybind, keybindName)
    if KeybindName ~= "Press The Key" and ImMenu.Button(KeybindName or noKeyText) then
        bindTimer = os.clock() + bindDelay
        KeybindName = "Press The Key"
    elseif KeybindName == "Press The Key" then
        ImMenu.Text("Press the key")
    end

    if KeybindName == "Press The Key" then
        if os.clock() >= bindTimer then
            local pressedKey = MenuModule.GetPressedkey()
            if pressedKey then
                if pressedKey == KEY_ESCAPE then
                    -- Reset keybind if the Escape key is pressed
                    keybind = 0
                    KeybindName = "Always On"
                    Notify.Simple("Keybind Success", "Bound Key: " .. KeybindName, 2)
                else
                    -- Update keybind with the pressed key
                    keybind = pressedKey
                    KeybindName = Input.GetKeyName(pressedKey)
                    Notify.Simple("Keybind Success", "Bound Key: " .. KeybindName, 2)
                end
            end
        end
    end
    return keybind, keybindName
end]]

local function OnDrawMenu()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)
    local Menu = G.Menu
    local Main = Menu.Main

    -- Inside your OnCreateMove or similar function where you check for input
    if input.IsButtonDown(KEY_INSERT) then  -- Replace 72 with the actual key code for the button you want to use
        MenuModule.toggleMenu()
    end

    if Lbox_Menu_Open == true and ImMenu and ImMenu.Begin("Lmaobot V2", true) then
        local Tabs = G.Menu.Tabs
        local TabsOrder = { "Main", "Visuals", "Movement"}

        -- Render tab buttons and manage visibility state
        ImMenu.BeginFrame(1)
        for _, tab in ipairs(TabsOrder) do
            if ImMenu.Button(tab) then
                for otherTab, _ in pairs(Tabs) do
                    Tabs[otherTab] = (otherTab == tab)
                end
            end
        end
        ImMenu.EndFrame()

        -- Handle Main tab options
        if Tabs.Main then
            ImMenu.BeginFrame(1)
                G.Menu.Main.Walking = ImMenu.Checkbox("Walking", G.Menu.Main.Walking)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                G.Menu.Main.Skip_Nodes = ImMenu.Checkbox("Skip Nodes", G.Menu.Main.Skip_Nodes)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                G.Menu.Main.Optimise_Path = ImMenu.Checkbox("Optimise Path", G.Menu.Main.Optimise_Path)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                G.Menu.Main.shouldfindhealth = ImMenu.Checkbox("Path to Health", G.Menu.Main.shouldfindhealth)
                if G.Menu.Main.shouldfindhealth then
                    G.Menu.Main.SelfHealTreshold = ImMenu.Slider("Self Heal Threshold", G.Menu.Main.SelfHealTreshold, 0, 100)
                end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                G.Menu.Main.smoothFactor = ImMenu.Slider("Smooth Factor", G.Menu.Main.smoothFactor, 0.01, 20, 0.01)
            ImMenu.EndFrame()
        end


        -- Handle Visuals tab options
        if Tabs.Visuals then
            ImMenu.BeginFrame(1)
                G.Menu.Visuals.EnableVisuals = ImMenu.Checkbox("Enable Visuals", G.Menu.Visuals.EnableVisuals)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
                G.Menu.Visuals.drawNodes = ImMenu.Checkbox("Draw Nodes", G.Menu.Visuals.drawNodes)
                G.Menu.Visuals.drawPath = ImMenu.Checkbox("Draw Path", G.Menu.Visuals.drawPath)
                G.Menu.Visuals.drawCurrentNode = ImMenu.Checkbox("Draw Current Node", G.Menu.Visuals.drawCurrentNode)
            ImMenu.EndFrame()
        end

        -- Handle Movement tab options
        if Tabs.Movement then
            ImMenu.BeginFrame(1)
                G.Menu.Movement.lookatpath = ImMenu.Checkbox("Look at Path", G.Menu.Movement.lookatpath)
                G.Menu.Movement.smoothLookAtPath = ImMenu.Checkbox("Smooth Look At Path", G.Menu.Movement.smoothLookAtPath)
                G.Menu.Movement.Smart_Jump = ImMenu.Checkbox("Smart Jump", G.Menu.Movement.Smart_Jump)
            ImMenu.EndFrame()
        end
        ImMenu.End()
    end

    if G.Menu.Main.Loading < 100 and ImMenu and ImMenu.Begin("Loading Resources", true) then
        -- Slider for loading progress (non-modifiable)
        ImMenu.BeginFrame()
            ImMenu.Slider("Loading Progress", G.Menu.Main.Loading, 0, 100, nil, true) -- Last argument makes it read-only
        ImMenu.EndFrame()

        ImMenu.End()
    end
end

--[[ Callbacks ]]
callbacks.Unregister("Draw", "OnDrawMenu")                                   -- unregister the "Draw" callback
callbacks.Register("Draw", "OnDrawMenu", OnDrawMenu)                              -- Register the "Draw" callback 

return MenuModule
end)
__bundle_register("Lmaobot.Visuals", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Imports ]]
local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local Visuals = {}

local Log = Common.Log
local Lib = Common.Lib
local Notify = Lib.UI.Notify
local Fonts = Lib.UI.Fonts
local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)


--[[ Functions ]]

local function Draw3DBox(size, pos)
    local halfSize = size / 2
    if not corners then
        corners1 = {
            Vector3(-halfSize, -halfSize, -halfSize),
            Vector3(halfSize, -halfSize, -halfSize),
            Vector3(halfSize, halfSize, -halfSize),
            Vector3(-halfSize, halfSize, -halfSize),
            Vector3(-halfSize, -halfSize, halfSize),
            Vector3(halfSize, -halfSize, halfSize),
            Vector3(halfSize, halfSize, halfSize),
            Vector3(-halfSize, halfSize, halfSize)
        }
    end

    local linesToDraw = {
        {1, 2}, {2, 3}, {3, 4}, {4, 1},
        {5, 6}, {6, 7}, {7, 8}, {8, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
    }

    local screenPositions = {}
    for _, cornerPos in ipairs(corners1) do
        local worldPos = pos + cornerPos
        local screenPos = client.WorldToScreen(worldPos)
        if screenPos then
            table.insert(screenPositions, { x = screenPos[1], y = screenPos[2] })
        end
    end

    for _, line in ipairs(linesToDraw) do
        local p1, p2 = screenPositions[line[1]], screenPositions[line[2]]
        if p1 and p2 then
            draw.Line(p1.x, p1.y, p2.x, p2.y)
        end
    end
end

local function ArrowLine(start_pos, end_pos, arrowhead_length, arrowhead_width, invert)
    if not (start_pos and end_pos) then return end

    -- If invert is true, swap start_pos and end_pos
    if invert then
        start_pos, end_pos = end_pos, start_pos
    end

    -- Calculate direction from start to end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then return end

    -- Normalize the direction vector
    local normalized_direction = Common.Normalize(direction)

    -- Calculate the arrow base position by moving back from end_pos in the direction of start_pos
    local arrow_base = end_pos - normalized_direction * arrowhead_length

    -- Calculate the perpendicular vector for the arrow width
    local perpendicular = Vector3(-normalized_direction.y, normalized_direction.x, 0) * (arrowhead_width / 2)

    -- Convert world positions to screen positions
    local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
    local w2s_arrow_base = client.WorldToScreen(arrow_base)
    local w2s_perp1 = client.WorldToScreen(arrow_base + perpendicular)
    local w2s_perp2 = client.WorldToScreen(arrow_base - perpendicular)

    if not (w2s_start and w2s_end and w2s_arrow_base and w2s_perp1 and w2s_perp2) then return end

    -- Draw the line from start to the base of the arrow (not all the way to the end)
    draw.Line(w2s_start[1], w2s_start[2], w2s_arrow_base[1], w2s_arrow_base[2])

    -- Draw the sides of the arrowhead
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp1[1], w2s_perp1[2])
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp2[1], w2s_perp2[2])

    -- Optionally, draw the base of the arrowhead to close it
    draw.Line(w2s_perp1[1], w2s_perp1[2], w2s_perp2[1], w2s_perp2[2])
end


local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 0, 0, 255)
    local me = entities.GetLocalPlayer()
    if not me then return end

    local myPos = me:GetAbsOrigin()

    -- Draw all nodes
    if G.Menu.Visuals.drawNodes then
        draw.Color(0, 255, 0, 255)

        local navNodes = G.Navigation.nodes

        if navNodes then
            for id, node in pairs(navNodes) do
                local nodePos = node.pos
                local dist = (myPos - nodePos):Length()
                if dist > 700 then goto continue end

                local screenPos = client.WorldToScreen(nodePos)
                if not screenPos then goto continue end

                local x, y = screenPos[1], screenPos[2]
                draw.FilledRect(x - 4, y - 4, x + 4, y + 4)  -- Draw a small square centered at (x, y)

                -- Node IDs
                draw.Text(screenPos[1], screenPos[2] + 10, tostring(id))

                ::continue::
            end
        else
            print("errror printing nodes")
        end
    end

    -- Draw current path
    if G.Menu.Visuals.drawPath and G.Navigation.path then
        draw.Color(255, 255, 255, 255)

        for i = 1, #G.Navigation.path - 1 do
            local node1 = G.Navigation.path[i]
            local node2 = G.Navigation.path[i + 1]

            local node1Pos = node1.pos
            local node2Pos = node2.pos

            local screenPos1 = client.WorldToScreen(node1Pos)
            local screenPos2 = client.WorldToScreen(node2Pos)
            if not screenPos1 or not screenPos2 then goto continue end

            if node1Pos and node2Pos then
                ArrowLine(node1Pos, node2Pos, 22, 15, true)  -- Adjust the size for the perpendicular segment as needed
            end
            ::continue::
        end

        -- Draw a line from the player to the second node from the end
        local node1 = G.Navigation.path[#G.Navigation.path]
        if node1 then
            node1 = node1.pos
            ArrowLine(myPos, node1, 22, 15, false)
        end
    end

    -- Draw current node
    if G.Menu.Visuals.drawCurrentNode and G.Navigation.path then
        draw.Color(255, 0, 0, 255)

        local currentNode = G.Navigation.path[#G.Navigation.path]
        if not currentNode then return end

        local currentNodePos = currentNode.pos

        local screenPos = client.WorldToScreen(currentNodePos)
        if screenPos then
            Draw3DBox(20, currentNodePos)
            draw.Text(screenPos[1], screenPos[2] + 40, tostring(G.Navigation.currentNodeinPath))
        end
    end
end

--[[ Callbacks ]]
callbacks.Unregister("Draw", "Navbot_Draw") -- unregister the "Draw" callback
callbacks.Register("Draw", "Navbot_Draw", OnDraw) -- Register the "Draw" callback 

return Visuals
end)
__bundle_register("Lmaobot.Modules.SmartJump", function(require, _LOADED, __bundle_register, __bundle_modules)
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local G = require("Lmaobot.Utils.Globals")

local Math = lnxLib.Utils.Math
local Prediction = lnxLib.TF2.Prediction
local WPlayer = lnxLib.TF2.WPlayer

-- Globals
local lastAngle = nil            ---@type number
local pLocal = entities.GetLocalPlayer()
local onGround = true
local isDucking = false
local predictedPosition = Vector3(0, 0, 0)
local jumpPeakPosition = Vector3(0, 0, 0)
local shouldJump = false

-- Constants
local HITBOX_MIN = Vector3(-23.99, -23.99, 0)
local HITBOX_MAX = Vector3(23.99, 23.99, 82)
local MAX_JUMP_HEIGHT = Vector3(0, 0, 72)   -- Maximum jump height vector
local STEP_HEIGHT = Vector3(0, 0, 18)   -- Maximum jump height vector
local MAX_WALKABLE_ANGLE = 45               -- Maximum angle considered walkable
local GRAVITY = 800                         -- Gravity per second squared
local JUMP_FORCE = 277                      -- Initial vertical boost for a duck jump

-- State Definitions
local STATE_AWAITING_JUMP = "STATE_AWAITING_JUMP"
local STATE_CTAP = "STATE_CTAP"
local STATE_JUMP = "STATE_JUMP"
local STATE_ASCENDING = "STATE_ASCENDING"
local STATE_DESCENDING = "STATE_DESCENDING"

-- Initial state
local jumpState = STATE_AWAITING_JUMP

-- Function to rotate a vector by yaw angle
local function RotateVectorByYaw(vector, yaw)
    local rad = math.rad(yaw)
    local cosYaw, sinYaw = math.cos(rad), math.sin(rad)
    return Vector3(
        cosYaw * vector.x - sinYaw * vector.y,
        sinYaw * vector.x + cosYaw * vector.y,
        vector.z
    )
end

-- Function to normalize a vector
local function Normalize(vec)
    return vec / vec:Length()
end

-- Function to check if the surface is walkable based on its normal
local function IsSurfaceWalkable(normal)
    local upVector = Vector3(0, 0, 1)
    local angle = math.deg(math.acos(normal:Dot(upVector)))
    return angle < MAX_WALKABLE_ANGLE
end

-- Helper function to check if the player is on the ground
local function IsPlayerOnGround(player)
    local flags = player:GetPropInt("m_fFlags")
    return (flags & FL_ONGROUND) == FL_ONGROUND
end

-- Helper function to check if the player is ducking
local function IsPlayerDucking(player)
    local flags = player:GetPropInt("m_fFlags")
    return (flags & FL_DUCKING) == FL_DUCKING
end

local function isSmaller(player)
    return player:GetPropVector("m_vecViewOffset[0]").z < 65
end

-- Function to calculate the strafe angle delta
---@param player WPlayer?
local function CalcStrafe(player)
    if not player then return 0 end
    local velocityAngle = player:EstimateAbsVelocity():Angles()
    local delta = 0
    if lastAngle then
        delta = Math.NormalizeAngle(velocityAngle.y - lastAngle)
    end
    lastAngle = velocityAngle.y
    return delta
end

-- Function to calculate the jump peak position and direction
local function GetJumpPeak(horizontalVelocity, startPos)
    -- Calculate the time to reach the jump peak
    local timeToPeak = JUMP_FORCE / GRAVITY

    -- Calculate horizontal velocity length
    local horizontalSpeed = horizontalVelocity:Length()

    -- Calculate distance traveled horizontally during time to peak
    local distanceTravelled = horizontalSpeed * timeToPeak

    -- Calculate peak position vector
    local peakPosition = startPos + Normalize(horizontalVelocity) * distanceTravelled

    -- Calculate direction to peak position
    local directionToPeak = Normalize(peakPosition - startPos)

    return peakPosition, directionToPeak
end

-- Function to adjust player's velocity towards the movement input direction
local function AdjustVelocity(cmd)
    if not pLocal then return Vector3(0, 0, 0) end

    -- Get movement input
    local moveInput = Vector3(cmd.forwardmove, -cmd.sidemove, 0)
    if moveInput:Length() == 0 then
        return pLocal:EstimateAbsVelocity()
    end

    -- Get view angles
    local viewAngles = engine.GetViewAngles()
    -- Rotate movement input by yaw
    local rotatedMoveDir = RotateVectorByYaw(moveInput, viewAngles.yaw)
    local normalizedMoveDir = Normalize(rotatedMoveDir)

    -- Get current velocity
    local velocity = pLocal:EstimateAbsVelocity()
    local intendedSpeed = math.max(10, velocity:Length())

    -- Adjust velocity to match intended direction and speed
    if onGround then
        velocity = normalizedMoveDir * intendedSpeed
    end

    return velocity
end

-- Smart jump logic
local function SmartJump(cmd)
    if not pLocal then return end
    if not G.Menu.Movement.Smart_Jump then return end
    shouldJump = false

    if onGround then
        local adjustedVelocity = AdjustVelocity(cmd)
        local playerPos = pLocal:GetAbsOrigin()

        -- Calculate jump peak position and direction
        local jumpPeakPos, jumpDirection = GetJumpPeak(adjustedVelocity, playerPos)

       -- Move up
       local startTracePos = playerPos + STEP_HEIGHT
       jumpPeakPos = jumpPeakPos + STEP_HEIGHT

       -- Trace from player position to forward direction
       local trace = engine.TraceHull(startTracePos, jumpPeakPos, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
       local ForwardPos = trace.endpos

        -- Trace down to snap to ground
        local downTrace = engine.TraceHull(ForwardPos , ForwardPos - MAX_JUMP_HEIGHT, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
        ForwardPos = downTrace.endpos

        if trace.fraction < 1 then
            -- Move forward slightly
            local JumpPos = ForwardPos + jumpDirection * 1

            -- Trace down to check for landing
            local downTrace = engine.TraceHull(JumpPos + MAX_JUMP_HEIGHT, JumpPos, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
            JumpPos = downTrace.endpos

            if downTrace.fraction > 0 and downTrace.fraction < 0.75 then
                local normal = downTrace.plane
                if IsSurfaceWalkable(normal) then
                    shouldJump = true
                end
            end
        end
    elseif input.IsButtonDown(KEY_SPACE) then
        shouldJump = true
    end
end

-- OnCreateMove callback
local function OnCreateMove(cmd)
    -- Get local player
    pLocal = entities.GetLocalPlayer()
    local wLocal = WPlayer.GetLocal()

    if not pLocal or not pLocal:IsAlive() or not wLocal then
        jumpState = STATE_AWAITING_JUMP -- Previously STATE_IDLE
        return
    end

    -- Update player states
    onGround = IsPlayerOnGround(pLocal)
    isDucking = IsPlayerDucking(pLocal)

    -- Adjust hitbox based on ducking state
    if isDucking then
        HITBOX_MAX.z = 62
    else
        HITBOX_MAX.z = 82
    end

    -- Calculate strafe angle delta
    local strafeDelta = CalcStrafe(wLocal)

    -- Handle edge case when player is on ground and ducking.
    if onGround and isDucking or onGround and isSmaller(pLocal) then
        jumpState = STATE_AWAITING_JUMP --jump if youre duckign already means we could have gotten stuck ducking
    end

    -- State machine for jump logic
    if jumpState == STATE_AWAITING_JUMP then
        -- Waiting for jump
        SmartJump(cmd)
        if shouldJump then
            jumpState = STATE_CTAP -- Previously STATE_PREPARE_JUMP
        end
    elseif jumpState == STATE_CTAP then
        -- Start crouching
        cmd:SetButtons(cmd.buttons | IN_DUCK)
        cmd:SetButtons(cmd.buttons & (~IN_JUMP))
        jumpState = STATE_JUMP -- Previously STATE_CTAP
        return
    elseif jumpState == STATE_JUMP then
        -- Uncrouch and jump
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))
        cmd:SetButtons(cmd.buttons | IN_JUMP)
        jumpState = STATE_ASCENDING
        return
    elseif jumpState == STATE_ASCENDING then
        -- Ascending after jump
        cmd:SetButtons(cmd.buttons | IN_DUCK)
        if pLocal:EstimateAbsVelocity().z <= 0 then
            jumpState = STATE_DESCENDING
        elseif onGround then
            jumpState = STATE_AWAITING_JUMP --we landed prematurely
        end
        return
    elseif jumpState == STATE_DESCENDING then
        -- Descending
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))

        local predData = Prediction.Player(wLocal, 1, strafeDelta, nil)
        if not predData then return end

        predictedPosition = predData.pos[1]

        if not predData.onGround[1] or not onGround then
            SmartJump(cmd)
            if shouldJump then
                cmd:SetButtons(cmd.buttons & (~IN_DUCK))
                cmd:SetButtons(cmd.buttons | IN_JUMP)
                jumpState = STATE_CTAP -- Previously STATE_PREPARE_JUMP
            end
        else
            cmd:SetButtons(cmd.buttons | IN_DUCK)
            jumpState = STATE_AWAITING_JUMP -- Previously STATE_IDLE
        end
    end
end

-- OnDraw callback for visual debugging
local function OnDraw()
    pLocal = entities.GetLocalPlayer()
    if not pLocal or jumpState ~= STATE_AWAITING_JUMP then return end

    -- Draw predicted position
    local screenPredPos = client.WorldToScreen(predictedPosition)
    if not predictedPosition then return end
    if screenPredPos then
        draw.Color(255, 0, 0, 255)  -- Red color
        draw.FilledRect(screenPredPos[1] - 5, screenPredPos[2] - 5, screenPredPos[1] + 5, screenPredPos[2] + 5)
    end

    -- Draw jump peak position
    local screenJumpPeakPos = client.WorldToScreen(jumpPeakPosition)
    if screenJumpPeakPos then
        draw.Color(0, 255, 0, 255)  -- Green color
        draw.FilledRect(screenJumpPeakPos[1] - 5, screenJumpPeakPos[2] - 5, screenJumpPeakPos[1] + 5, screenJumpPeakPos[2] + 5)
    end

    -- Draw bounding box at jump peak position
    local minPoint = HITBOX_MIN + jumpPeakPosition
    local maxPoint = HITBOX_MAX + jumpPeakPosition

    -- Define the vertices of the bounding box
    local vertices = {
        Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
        Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
        Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
        Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
        Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
    }

    -- Convert 3D coordinates to 2D screen coordinates
    for i, vertex in ipairs(vertices) do
        vertices[i] = client.WorldToScreen(vertex)
    end

    -- Draw lines between vertices to visualize the bounding box
    if vertices[1] and vertices[2] and vertices[3] and vertices[4] and
       vertices[5] and vertices[6] and vertices[7] and vertices[8] then
        draw.Color(255, 255, 255, 255)  -- White color
        -- Draw bottom face
        draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
        draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
        draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
        draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])
        -- Draw top face
        draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
        draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
        draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
        draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])
        -- Draw sides
        draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
        draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
        draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
        draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
    end
end

-- Register callbacks
callbacks.Unregister("CreateMove", "SmartJumpNavbot_CreateMove")
callbacks.Register("CreateMove", "SmartJumpNavbot_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "SmartJumpNavbot_Draw")
callbacks.Register("Draw", "SmartJumpNavbot_Draw", OnDraw)

end)
__bundle_register("Lmaobot.Utils.Commands", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Commands Module with Specific Commands Execution ]]
---@class CommandsModule
local CommandsModule = {}
CommandsModule.__index = CommandsModule

-- Required libraries
local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local Navigation = require("Lmaobot.Utils.Navigation")
local Setup = require("Lmaobot.Modules.Setup")

local Lib = Common.Lib
local Commands = Lib.Utils.Commands


-- Reloads the navigation setup
Commands.Register("pf_reload", function()
    Setup.SetupNavigation()
    print("Navigation setup reloaded.")
end)

-- Finds a path between two nodes
Commands.Register("pf", function(args)
    if #args ~= 2 then
        print("Usage: pf <Start Node ID> <Goal Node ID>")
        return
    end

    local start = tonumber(args[1])
    local goal = tonumber(args[2])

    if not start or not goal then
        print("Start/Goal must be valid numbers!")
        return
    end

    local startNode = Navigation.GetNodeByID(start)
    local goalNode = Navigation.GetNodeByID(goal)

    if not startNode or not goalNode then
        print("Start/Goal node not found!")
        return
    end

    Navigation.FindPath(startNode, goalNode)
    print("Pathfinding task added from node " .. start .. " to node " .. goal)
end)

-- Pathfind from current position to the closest node to where the player is looking
Commands.Register("pf_look", function()
    local player = entities.GetLocalPlayer()  -- Get the local player entity
    local playerPos = player:GetAbsOrigin()   -- Get the player's current position
    local lookPos = playerPos + engine.GetViewAngles():Forward() * 1000   -- Project the look direction

    local startNode = Navigation.GetClosestNode(playerPos)  -- Find the closest node to player's position
    local goalNode = Navigation.GetClosestNode(lookPos)     -- Find the closest node to where player is looking

    if not startNode or not goalNode then
        print("No valid pathfinding nodes found!")
        return
    end

    Navigation.FindPath(startNode, goalNode)
    print("Pathfinding task added from current position to the target area.")
end)

-- Toggles automatic pathfinding
Commands.Register("pf_auto", function()
    G.Menu.Main.Walking = not G.Menu.Main.Walking
    print("Auto path: " .. tostring(G.Menu.Main.Walking))
end)

return CommandsModule

end)
__bundle_register("Lmaobot.Utils.Config", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Config.lua

--[[ Config Module ]]
local Config = {}

--[[ Imports ]]
local G = require("Lmaobot.Utils.Globals") -- Adjust this path as necessary
local Common = require("Lmaobot.Common")    -- Adjust this path as necessary

local Log = Common.Log
local Notify = Common.Notify
Log.Level = 0

local folder_name = string.format([[Lua %s]], G.Lua__fileName)

-- Default configuration
local default_menu = G.default_menu

-- Function to check if all keys exist in loaded config
local function checkAllKeysExist(expectedMenu, loadedMenu)
    if type(expectedMenu) ~= "table" then
        print("Error: Expected 'expectedMenu' to be a table, but got " .. type(expectedMenu))
        return false
    end
    if type(loadedMenu) ~= "table" then
        print("Error: Loaded menu is nil or not a table.")
        return false
    end

    for key, value in pairs(expectedMenu) do
        if loadedMenu[key] == nil then
            print("Error: Missing key '" .. key .. "' in loaded configuration.")
            return false
        end

        if type(value) ~= type(loadedMenu[key]) then
            print("Error: Type mismatch for key '" .. key .. "'. Expected " .. type(value) .. ", got " .. type(loadedMenu[key]))
            return false
        end

        if type(value) == "table" then
            local result = checkAllKeysExist(value, loadedMenu[key])
            if not result then
                print("Error: Issue found within nested table for key '" .. key .. "'")
                return false
            end
        end
    end
    return true
end

-- Function to get the file path
local function GetFilePath()
    local _, fullPath = filesystem.CreateDirectory(folder_name)
    local path = tostring(fullPath .. "/config.cfg")
    return path
end

-- Function to serialize the table into a string
local function serializeTable(tbl, level)
    if type(tbl) ~= "table" then
        print("Error: Invalid table structure during serialization.")
        return "{}"
    end
    level = level or 0
    local result = string.rep("    ", level) .. "{\n"
    for key, value in pairs(tbl) do
        result = result .. string.rep("    ", level + 1)
        if type(key) == "string" then
            result = result .. '["' .. key .. '"] = '
        else
            result = result .. "[" .. key .. "] = "
        end
        if type(value) == "table" then
            result = result .. serializeTable(value, level + 1) .. ",\n"
        elseif type(value) == "string" then
            result = result .. '"' .. value .. '",\n'
        else
            result = result .. tostring(value) .. ",\n"
        end
    end
    result = result .. string.rep("    ", level) .. "}"
    return result
end

-- Function to create and save the configuration file
local function CreateCFG(table)
    local filepath = GetFilePath()
    local file = io.open(filepath, "w")
    if file then
        local serializedConfig = serializeTable(table)
        file:write(serializedConfig)
        file:close()
        local successMessage = filepath
        printc(100, 183, 0, 255, "Success Saving Config: Path: " .. successMessage)
        Notify.Simple("Success! Saved Config to:", successMessage, 5)
    else
        local errorMessage = "Failed to open: " .. tostring(filepath)
        printc(255, 0, 0, 255, errorMessage)
        Notify.Simple("Error", errorMessage, 5)
    end
end

-- Function to load the configuration file
local function LoadCFG()
    local filepath = GetFilePath()
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            local loadedMenu = chunk()
            if checkAllKeysExist(default_menu, loadedMenu) and not input.IsButtonDown(KEY_LSHIFT) then
                local successMessage = filepath
                printc(100, 183, 0, 255, "Success Loading Config: Path: " .. successMessage)
                Notify.Simple("Success! Loaded Config from", successMessage, 5)
                return loadedMenu
            else
                local warningMessage = "Config is outdated or invalid. Creating a new config."
                printc(255, 0, 0, 255, warningMessage)
                Notify.Simple("Warning", warningMessage, 5)
                CreateCFG(default_menu)
                return default_menu
            end
        else
            local errorMessage = "Error executing configuration file: " .. tostring(err)
            printc(255, 0, 0, 255, errorMessage)
            Notify.Simple("Error", errorMessage, 5)
            CreateCFG(default_menu)
            return default_menu
        end
    else
        local warningMessage = "Config file not found. Creating a new config."
        printc(255, 0, 0, 255, warningMessage)
        Notify.Simple("Warning", warningMessage, 5)
        CreateCFG(default_menu)
        return default_menu
    end
end

-- Initialize the Config module
Config.menu = LoadCFG()

-- Update G.Menu with the loaded configuration
G.Menu = Config.menu

-- Function to save the current configuration (e.g., on script unload)
function Config.Save()
    CreateCFG(G.Menu)
end

-- Function to register the Unload callback
local function RegisterUnloadCallback()
    -- Unregister any existing Unload callback with the same name
    callbacks.Unregister("Unload", G.Lua__fileName)

    -- Register a new Unload callback with the unique name
    callbacks.Register("Unload", G.Lua__fileName, function()
        Config.Save()
    end)
end

-- Register the Unload callback
RegisterUnloadCallback()

return Config

end)
__bundle_register("Lmaobot.Utils.SourceNav", function(require, _LOADED, __bundle_register, __bundle_modules)
-- author : https://github.com/sapphyrus
-- ported to tf2 by moonverse

local unpack = table.unpack
local struct = {
    unpack = string.unpack,
    pack = string.pack
}

local struct_buffer_mt = {
    __index = {
        seek = function(self, seek_val, seek_mode)
            if seek_mode == nil or seek_mode == "CUR" then
                self.offset = self.offset + seek_val
            elseif seek_mode == "END" then
                self.offset = self.len + seek_val
            elseif seek_mode == "SET" then
                self.offset = seek_val
            end
        end,
        unpack = function(self, format_str)
            local unpacked = { struct.unpack(format_str, self.raw, self.offset) }

            if self.size_cache[format_str] == nil then
                self.size_cache[format_str] = struct.pack(format_str, unpack(unpacked)):len()
            end
            self.offset = self.offset + self.size_cache[format_str]

            return unpack(unpacked)
        end,
        unpack_vec = function(self)
            local x, y, z = self:unpack("fff")
            return {
                x = x,
                y = y,
                z = z
            }
        end
    }
}

local function struct_buffer(raw)
    return setmetatable({
        raw = raw,
        len = raw:len(),
        size_cache = {},
        offset = 1
    }, struct_buffer_mt)
end

-- cache
local navigation_mesh_cache = {}

-- use checksum so we dont have to keep the whole thing in memory
local function crc32(s, lt)
    -- return crc32 checksum of string as an integer
    -- use lookup table lt if provided or create one on the fly
    -- if lt is empty, it is initialized.
    lt = lt or {}
    local b, crc, mask
    if not lt[1] then -- setup table
        for i = 1, 256 do
            crc = i - 1
            for _ = 1, 8 do -- eight times
                mask = -(crc & 1)
                crc = (crc >> 1) ~ (0xedb88320 & mask)
            end
            lt[i] = crc
        end
    end

    -- compute the crc
    crc = 0xffffffff
    for i = 1, #s do
        b = string.byte(s, i)
        crc = (crc >> 8) ~ lt[((crc ~ b) & 0xFF) + 1]
    end
    return ~crc & 0xffffffff
end

local function parse(raw, use_cache)
    local checksum
    if use_cache == nil or use_cache then
        checksum = crc32(raw)
        if navigation_mesh_cache[checksum] ~= nil then
            return navigation_mesh_cache[checksum]
        end
    end

    local buf = struct_buffer(raw)

    local self = {}
    self.magic, self.major, self.minor, self.bspsize, self.analyzed, self.places_count = buf:unpack("IIIIbH")

    assert(self.magic == 0xFEEDFACE, "invalid magic, expected 0xFEEDFACE")
    assert(self.major == 16, "invalid major version, expected 16")

    -- place names
    self.places = {}
    for i = 1, self.places_count do
        local place = {}
        place.name_length = buf:unpack("H")

        -- read but ignore null byte
        place.name = buf:unpack(string.format("c%db", place.name_length - 1))

        self.places[i] = place
    end

    -- areas
    self.has_unnamed_areas, self.areas_count = buf:unpack("bI")
    self.areas = {}
    for i = 1, self.areas_count do
        local area = {}
        area.id, area.flags = buf:unpack("II")

        area.north_west = buf:unpack_vec()
        area.south_east = buf:unpack_vec()

        area.north_east_z, area.south_west_z = buf:unpack("ff")

        -- connections
        area.connections = {}
        for dir = 1, 4 do
            local connections_dir = {}
            connections_dir.count = buf:unpack("I")

            connections_dir.connections = {}
            for i = 1, connections_dir.count do
                local target
                target = buf:unpack("I")
                connections_dir.connections[i] = target
            end
            area.connections[dir] = connections_dir
        end

        -- hiding spots
        area.hiding_spots_count = buf:unpack("B")
        area.hiding_spots = {}
        for i = 1, area.hiding_spots_count do
            local hiding_spot = {}
            hiding_spot.id = buf:unpack("I")
            hiding_spot.location = buf:unpack_vec()
            hiding_spot.flags = buf:unpack("b")
            area.hiding_spots[i] = hiding_spot
        end

        -- encounter paths
        area.encounter_paths_count = buf:unpack("I")
        area.encounter_paths = {}
        for i = 1, area.encounter_paths_count do
            local encounter_path = {}
            encounter_path.from_id, encounter_path.from_direction, encounter_path.to_id, encounter_path.to_direction,
                encounter_path.spots_count =
            buf:unpack("IBIBB")

            encounter_path.spots = {}
            for i = 1, encounter_path.spots_count do
                encounter_path.spots[i] = {}
                encounter_path.spots[i].order_id, encounter_path.spots[i].distance = buf:unpack("IB")
            end
            area.encounter_paths[i] = encounter_path
        end

        area.place_id = buf:unpack("H")

        -- ladders
        area.ladders = {}
        for i = 1, 2 do
            area.ladders[i] = {}
            area.ladders[i].connection_count = buf:unpack("I")

            area.ladders[i].connections = {}
            for i = 1, area.ladders[i].connection_count do
                area.ladders[i].connections[i] = buf:unpack("I")
            end
        end

        area.earliest_occupy_time_first_team, area.earliest_occupy_time_second_team = buf:unpack("ff")
        area.light_intensity_north_west, area.light_intensity_north_east, area.light_intensity_south_east,
            area.light_intensity_south_west =
        buf:unpack("ffff")

        -- visible areas
        area.visible_areas = {}
        area.visible_area_count = buf:unpack("I")
        for i = 1, area.visible_area_count do
            area.visible_areas[i] = {}
            area.visible_areas[i].id, area.visible_areas[i].attributes = buf:unpack("Ib")
        end
        area.inherit_visibility_from_area_id = buf:unpack("I")

        -- NOTE: Differnet value in CSGO/TF2
        -- garbage?
        self.garbage = buf:unpack('I')

        self.areas[i] = area
    end

    -- ladders
    self.ladders_count = buf:unpack("I")
    self.ladders = {}
    for i = 1, self.ladders_count do
        local ladder = {}
        ladder.id, ladder.width = buf:unpack("If")

        ladder.top = buf:unpack_vec()
        ladder.bottom = buf:unpack_vec()

        ladder.length, ladder.direction = buf:unpack("fI")

        ladder.top_forward_area_id, ladder.top_left_area_id, ladder.top_right_area_id, ladder.top_behind_area_id =
        buf:unpack("IIII")
        ladder.bottom_area_id = buf:unpack("I")

        self.ladders[i] = ladder
    end

    if checksum ~= nil and navigation_mesh_cache[checksum] == nil then
        navigation_mesh_cache[checksum] = self
    end

    return self
end

return {
    parse = parse
}
end)
return __bundle_require("__root")