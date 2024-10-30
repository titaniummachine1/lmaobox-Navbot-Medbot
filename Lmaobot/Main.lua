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

        if WorkManager.attemptWork(66, "Pathfinding") then
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