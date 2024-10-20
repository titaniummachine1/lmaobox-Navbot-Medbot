--[[ Annotations ]]
---@alias NavConnection { count: integer, connections: integer[] }
---@alias NavNode { id: integer, x: number, y: number, z: number, c: { [1]: NavConnection, [2]: NavConnection, [3]: NavConnection, [4]: NavConnection } }

--[[ Imports ]]
local G = require("Lmaobot.Utils.Globals")
local Common = require("Lmaobot.Common")
require("Lmaobot.Utils.Commands")
require("Lmaobot.Modules.SmartJump")
require("Lmaobot.Visuals")
require("Lmaobot.Menu")

local Navigation = require("Lmaobot.Utils.Navigation")
local WorkManager = require("Lmaobot.WorkManager")

--last to speed up develeopment of stuff
require("Lmaobot.Modules.Setup")

local Lib = Common.Lib
local Log = Common.Log

local Notify, WPlayer = Lib.UI.Notify, Lib.TF2.WPlayer

--[[ Functions ]]
local function HealthLogic(pLocal)
    if not pLocal then return end
    local health = pLocal:GetHealth()
    local maxHealth = pLocal:GetMaxHealth()
    if health and maxHealth and (health / maxHealth) * 100 < G.Menu.Main.SelfHealTreshold and not pLocal:InCond(TFCond_Healing) then
        if not G.Current_Tasks[G.Tasks.Health] and G.Menu.Main.shouldfindhealth then
            Log:Info("Switching to health task")
            Common.AddCurrentTask("Health")
            Navigation.ClearPath()
        end
    else
        if G.Current_Tasks[G.Tasks.Health] then
            Log:Info("Health task no longer needed, switching back to objective task")
            Common.RemoveCurrentTask("Health")
            Navigation.ClearPath()
        end
    end
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        Navigation.ClearPath()
        return
    end

    local currentTask = Common.GetHighestPriorityTask()
    if not currentTask then
        Common.AddCurrentTask("Objective") -- default task
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
        if G.Navigation.currentNodePos then
            if G.Menu.Movement.lookatpath then
                local pLocalWrapped = WPlayer.GetLocal()
                if pLocalWrapped then
                    local eyePos = pLocalWrapped:GetEyePos()
                    if eyePos then
                        local angles = Lib.Utils.Math.PositionAngles(eyePos, G.Navigation.currentNodePos)
                        angles.x = 0

                        if G.Menu.Movement.smoothLookAtPath then
                            local currentAngles = userCmd.viewangles
                            local deltaAngles = { x = angles.x - currentAngles.x, y = angles.y - currentAngles.y }

                            deltaAngles.y = ((deltaAngles.y + 180) % 360) - 180

                            angles = EulerAngles(currentAngles.x + deltaAngles.x * 0.05, currentAngles.y + deltaAngles.y * G.Menu.Main.smoothFactor, 0)
                        end
                        engine.SetViewAngles(angles)
                    else
                        Log:Warn("Eye position is nil.")
                    end
                else
                    Log:Warn("Failed to wrap local player.")
                end
            end
        else
            Log:Warn("Current node position is nil.")
        end

        local LocalOrigin = G.pLocal.Origin or Vector3(0, 0, 0)
        local nodePos = G.Navigation.currentNodePos or Vector3(0, 0, 0)
        local horizontalDist = math.abs(LocalOrigin.x - nodePos.x) + math.abs(LocalOrigin.y - nodePos.y)
        local verticalDist = math.abs(LocalOrigin.z - nodePos.z)

        if G.Menu.Main.Walking then
            Common.WalkTo(userCmd, pLocal, nodePos)
        end

        if (horizontalDist < G.Misc.NodeTouchDistance) and verticalDist <= G.Misc.NodeTouchHeight then
            -- Move to the next node when close enough
            Navigation.MoveToNextNode()  -- Will remove the last node in the path
            Navigation.ResetTickTimer()
            -- Check if the path is empty after removing the node
            if not G.Navigation.path or #G.Navigation.path == 0 then
                Navigation.ClearPath()
                Log:Info("Reached end of path.")
                Common.RemoveCurrentTask(currentTask)
                return
            end
        else
            -- Node skipping logic (check if player is closer to the next node than the current node is)
            if G.Menu.Main.Skip_Nodes then
                local path = G.Navigation.path
                local pathLength = #path

                -- Ensure there are at least two nodes in the path to perform skipping
                if pathLength >= 2 then
                    local currentNode = G.Navigation.path[#G.Navigation.path]  -- Current node (last node in path)
                    local nextNode = G.Navigation.path[#G.Navigation.path - 1]  -- Next node (second last node in path)

                    -- Ensure currentNode and nextNode are valid
                    if currentNode and nextNode then
                        -- Get the distances: (1) currentNode to nextNode, and (2) player to nextNode
                        local currentToNextDist = (currentNode.pos - nextNode.pos):Length()
                        local playerToNextDist = (LocalOrigin - nextNode.pos):Length()

                        -- Perform a trace check (line-of-sight) to ensure there's no obstacle between the player and the next node
                        if playerToNextDist < currentToNextDist and Common.isWalkable(LocalOrigin, nextNode.pos) then
                            -- Additionally, check if the path between the current node and the next node is walkable
                            if Common.isWalkable(currentNode.pos, nextNode.pos) then
                                Log:Info("Player is closer to the next node and path is clear. Skipping current node %d and moving to next node %d", currentNode.id, nextNode.id)
                                Navigation.MoveToNextNode()  -- Skip to the next node
                            else
                                Log:Warn("Path between current node %d and next node %d is not walkable, not skipping.", currentNode.id, nextNode.id)
                            end
                        end
                    end


                    -- Full path check every 16 ticks
                    if WorkManager.attemptWork(7, "node skip all") then
                        local closestNodeIndex = #G.Navigation.path
                        local currentToPlayerDist = 1000

                        -- Loop through nodes to find the closest walkable node
                        for i = #G.Navigation.path - 1, 1, -1 do
                            local node = G.Navigation.path[i]
                            local playerToNodeDist = (LocalOrigin - node.pos):Length()

                            -- Check if it's closer and walkable
                            if playerToNodeDist < currentToPlayerDist and Common.isWalkable(LocalOrigin, node.pos) then
                                if Common.isWalkable(G.Navigation.path[#G.Navigation.path].pos, node.pos) then
                                    closestNodeIndex = i
                                    currentToPlayerDist = playerToNodeDist
                                end
                            end
                        end

                        -- Skip to the closest node if it's not the current node
                        if closestNodeIndex ~= #G.Navigation.path then
                            Navigation.SkipToNode(closestNodeIndex)
                        end
                    end
                end
            end
            -- Increment movement timer for the current node
            G.Navigation.currentNodeTicks = (G.Navigation.currentNodeTicks or 0) + 1
        end


        if (G.pLocal.flags & FL_ONGROUND == 1) or (pLocal:EstimateAbsVelocity():Length() < 50) then
            -- If bot is on the ground or moving very slowly, attempt to get unstuck
            if not Common.isWalkable(LocalOrigin, nodePos) then
                -- Attempt to jump if stuck for more than 66 ticks
                if G.Navigation.currentNodeTicks > 66 and WorkManager.attemptWork(66, "Unstuck_Jump") then
                    -- Basic auto-jump when on ground
                    userCmd:SetButtons(userCmd.buttons & (~IN_DUCK))
                    userCmd:SetButtons(userCmd.buttons | IN_JUMP)
                    Log:Info("Attempting to jump to get unstuck.")
                end
            end

            -- If still stuck after multiple attempts, remove the connection and re-path
            if WorkManager.attemptWork(177, "get unstuck") then
                if not Common.isWalkable(LocalOrigin, nodePos) then
                    local currentNode = G.Navigation.path[#G.Navigation.path]
                    local NextNode = G.Navigation.path[#G.Navigation.path - 1]
                    if currentNode and NextNode then
                        Log:Warn("Path blocked, removing connection between node %d and node %d", currentNode.id, NextNode.id)
                        -- Remove the connection between the previousNode and nodeBeforePrevious
                        Navigation.RemoveConnection(currentNode, NextNode)
                        Navigation.ClearPath()
                        Navigation.ResetTickTimer()
                        Log:Info("Connection removed, re-pathing initiated.")
                    else
                        Log:Warn("Previous node or node before previous is nil, unable to remove connection.")
                    end
                else
                    -- If path is not blocked but still stuck, clear and re-path
                    if not WorkManager.attemptWork(5, "pathCheck") then
                        Log:Warn("Path is stuck but walkable, re-pathing...")
                        Navigation.ClearPath()
                        Navigation.ResetTickTimer()
                    end
                end
            end
        end
    elseif G.State == G.StateDefinition.Pathfinding then
        local LocalOrigin = G.pLocal.Origin or Vector3(0, 0, 0)
        local startNode = Navigation.GetClosestNode(LocalOrigin)
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
                    return Navigation.GetClosestNode(entity:GetAbsOrigin())
                end
            end
        end

        local function findFlagGoal()
            local myItem = pLocal:GetPropInt("m_hItem")
            G.World.flags = entities.FindByClass("CCaptureFlag")
            for _, entity in pairs(G.World.flags or {}) do
                local myTeam = entity:GetTeamNumber() == pLocal:GetTeamNumber()
                if (myItem > 0 and myTeam) or (myItem <= 0 and not myTeam) then
                    return Navigation.GetClosestNode(entity:GetAbsOrigin())
                end
            end
        end

        local function findHealthGoal()
            local closestDist = math.huge
            local closestNode = nil
            for _, pos in pairs(G.World.healthPacks or {}) do
                local healthNode = Navigation.GetClosestNode(pos)
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
                Log:Warn("Unsupported gamemode. Try CTF, PL, or PLR.")
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