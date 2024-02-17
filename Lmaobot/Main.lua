--[[ Annotations ]]
---@alias NavConnection { count: integer, connections: integer[] }
---@alias NavNode { id: integer, x: number, y: number, z: number, c: { [1]: NavConnection, [2]: NavConnection, [3]: NavConnection, [4]: NavConnection } }

--[[ Imports ]]
local Common = require("Lmaobot.Common")
local Navigation = require("Lmaobot.Navigation")
local Lib = Common.Lib
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")

-- Unload package for debugging
Lib.Utils.UnloadPackages("Lmaobot")

local Notify, FS, Fonts, Commands, Timer = Lib.UI.Notify, Lib.Utils.FileSystem, Lib.UI.Fonts, Lib.Utils.Commands, Lib.Utils.Timer
local Log = Lib.Utils.Logger.new("Lmaobot")
Log.Level = 0

--[[ Variables ]]

local options = {
    memoryUsage = true, -- Shows memory usage in the top left corner
    MaxNodesPerTick = 77, -- Maximum nodes to process per tick_count
    MaxMemUsage = 1400, -- Maximum memory usage before triggering garbage collection
    drawNodes = false, -- Draws all nodes on the map
    drawPath = true, -- Draws the path to the current goal
    drawCurrentNode = true, -- Draws the current node
    lookatpath = false, -- Look at where we are walking
    smoothLookAtPath = true, -- Set this to true to enable smooth look at path
    autoPath = true, -- Automatically walks to the goal
    shouldfindhealth = true, -- Path to health
    SelfHealTreshold = 45, -- Health percentage to start looking for healthPacks
}

local smoothFactor = 0.05
local currentNodeIndex = 1
local currentNodeTicks = 0

---@type Vector3[]
local healthPacks = {}

local Tasks = table.readOnly {
    None = 0,
    Objective = 1,
    Health = 2,
    Follow = 3,
    Medic = 4,
}

local currentTask = Tasks.Objective
local taskTimer = Timer.new()
local Math = lnxLib.Utils.Math
local WPlayer = lnxLib.TF2.WPlayer

--[[ Functions ]]

-- Loads the nav file of the current map
local function LoadNavFile()
    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, ".bsp", ".nav")
    --AStar.ResetCache()
    Navigation.LoadFile(navFile)
end


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

local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function L_line(start_pos, end_pos, secondary_line_size)
    if not (start_pos and end_pos) then
        return
    end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then
        return
    end
    local normalized_direction = Normalize(direction)
    local perpendicular = Vector3(normalized_direction.y, -normalized_direction.x, 0) * secondary_line_size
    local w2s_start_pos = client.WorldToScreen(start_pos)
    local w2s_end_pos = client.WorldToScreen(end_pos)
    if not (w2s_start_pos and w2s_end_pos) then
        return
    end
    local secondary_line_end_pos = start_pos + perpendicular
    local w2s_secondary_line_end_pos = client.WorldToScreen(secondary_line_end_pos)
    if w2s_secondary_line_end_pos then
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_end_pos[1], w2s_end_pos[2])
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_secondary_line_end_pos[1], w2s_secondary_line_end_pos[2])
    end
end

--[[ Callbacks ]]

local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 0, 0, 255)

    local me = entities.GetLocalPlayer()
    if not me then return end

    local myPos = me:GetAbsOrigin()
    local currentPath = Navigation.GetCurrentPath()
    local currentY = 120

    -- Memory usage
    if options.memoryUsage then
        local memUsage = collectgarbage("count")
        draw.Text(20, currentY, string.format("Memory usage: %.2f MB", memUsage / 1024))
        currentY = currentY + 20
    end

    -- Auto path informaton
    if options.autoPath then
        draw.Text(20, currentY, string.format("Current Node: %d", currentNodeIndex))
        currentY = currentY + 20
    end

    -- Draw all nodes
    if options.drawNodes then
        draw.Color(0, 255, 0, 255)

        local navNodes = Navigation.GetNodes()
        for id, node in pairs(navNodes) do
            local nodePos = Vector3(node.x, node.y, node.z)
            local dist = (myPos - nodePos):Length()
            if dist > 700 then goto continue end

            local screenPos = client.WorldToScreen(nodePos)
            if not screenPos then goto continue end

            draw.FilledRect(x - 4, y - 4, x + 4, y + 4)  -- Draw a small square centered at (x, y)

            -- Node IDs
            draw.Text(screenPos[1], screenPos[2] + 10, tostring(id))

            ::continue::
        end
    end

    -- Draw current path
    if options.drawPath and currentPath then
        draw.Color(255, 255, 255, 255)

        for i = 1, #currentPath - 1 do
            local node1 = currentPath[i]
            local node2 = currentPath[i + 1]

            local node1Pos = Vector3(node1.x, node1.y, node1.z)
            local node2Pos = Vector3(node2.x, node2.y, node2.z)

            local screenPos1 = client.WorldToScreen(node1Pos)
            local screenPos2 = client.WorldToScreen(node2Pos)
            if not screenPos1 or not screenPos2 then goto continue end

            if node1Pos and node2Pos then
                L_line(node1Pos, node2Pos, 22)  -- Adjust the size for the perpendicular segment as needed
            end
            ::continue::
        end

        -- Draw a line from the player to the second node from the end
        local node1 = currentPath[#currentPath]
        if node1 then
            local node1 = Vector3(node1.x, node1.y, node1.z)
            L_line(myPos, node1, 22)
        end
    end

    -- Draw current node
    if options.drawCurrentNode and currentPath then
        draw.Color(255, 0, 0, 255)

        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = currentNode.pos

        local screenPos = client.WorldToScreen(currentNodePos)
        if screenPos then
            Draw3DBox(20, currentNodePos)
            draw.Text(screenPos[1], screenPos[2], tostring(currentNodeIndex))
        end
    end
end

local nodeTouchDistance = 27

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not options.autoPath then return end

    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then
        Navigation.ClearPath()
        return
    end

    --manual movement bypass
    if userCmd:GetForwardMove() ~= 0 or userCmd:GetSideMove() ~= 0 then
        currentNodeTicks = 0
        return
    end

    --if not gamerules.IsMatchTypeCasual() then return end -- return if not in casual.

    -- emergency healthpack task
    if taskTimer:Run(1) then
        -- make sure we're not being healed by a medic before running health logic
        if (me:GetHealth() / me:GetMaxHealth()) * 100 < options.SelfHealTreshold and not me:InCond(TFCond_Healing) then
            if currentTask ~= Tasks.Health and options.shouldfindhealth then
                Log:Info("Switching to health task")
                Navigation.ClearPath()
                previousTask = currentTask
            end

            currentTask = Tasks.Health
        else
            if previousTask and currentTask ~= previousTask then
                Log:Info("Switching back to previous task")
                Navigation.ClearPath()
                currentTask = previousTask
                previousTask = nil
            end
        end
        local memUsage2 = collectgarbage("count")
        if memUsage2 / 1024 > options.MaxMemUsage then
            collectgarbage()
            collectgarbage()
            collectgarbage()
            Log:Info("Trigger GC")
        end
    end

    local flags = me:GetPropInt( "m_fFlags" );
    local myPos = me:GetAbsOrigin()
    local currentPath = Navigation.GetCurrentPath()

    if currentTask == Tasks.None then return end

    if currentPath then
        -- Move along path
        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = currentNode.pos

        if options.lookatpath then
            if currentNodePos == nil then
                return
            else
            local melnx = WPlayer.GetLocal()    
            local angles = Lib.Utils.Math.PositionAngles(melnx:GetEyePos(), currentNodePos)--Math.PositionAngles(me:GetAbsOrigin() + me:GetPropVector("localdata", "m_vecViewOffset[0]"), currentNodePos)
            angles.x = 0

            if options.smoothLookAtPath then
                local currentAngles = userCmd.viewangles
                local deltaAngles = {x = angles.x - currentAngles.x, y = angles.y - currentAngles.y}

                while deltaAngles.y > 180 do deltaAngles.y = deltaAngles.y - 360 end
                while deltaAngles.y < -180 do deltaAngles.y = deltaAngles.y + 360 end

                angles = EulerAngles(currentAngles.x + deltaAngles.x * 0.5, currentAngles.y + deltaAngles.y * smoothFactor, 0)
            end
            --Credits to catt (pp021)
            engine.SetViewAngles(angles)
            end
        end

        local dist = (myPos - currentNodePos):Length()
        if dist < nodeTouchDistance then
            currentNodeTicks = 0
            currentNodeIndex = currentNodeIndex - 1
            table.remove(currentPath)

            if currentNodeIndex < 1 then
                Navigation.ClearPath()
                Log:Info("Reached end of path")
                --currentTask = Tasks.None
            end
        else
            -- Increment the current node ticks
            currentNodeTicks = currentNodeTicks + 1

            -- Check if the next node is closer
            if currentNodeIndex > 1 then
                local nextNode = currentPath[currentNodeIndex - 1]
                local nextNodePos = Vector3(nextNode.x, nextNode.y, nextNode.z)
                local nextDist = (myPos - nextNodePos):Length()

                if nextDist < dist then
                    -- Closer node found, update current node and path
                    Log:Info("Skipping to closer node %d", currentNodeIndex - 1)
                    currentNodeIndex = currentNodeIndex - 1
                    currentNode = nextNode
                    currentNodePos = nextNodePos
                    dist = nextDist
                    currentNodeTicks = 0
                    for i = #currentPath, currentNodeIndex + 1, -1 do
                        table.remove(currentPath, i)
                    end
                end
            end

            -- Once at the closest node, check for the furthest walkable node with smallest index
            if currentNodeIndex > 1 then
                local furthestNodeIndex, furthestNode, furthestNodePos = Navigation.FindBestNode(currentPath, myPos, currentNodeIndex)

                if furthestNodeIndex and furthestNodeIndex < currentNodeIndex then
                    -- Furthest walkable node found, update current node and path
                    Log:Info(string.format("Skipping to furthest walkable node %d", furthestNodeIndex))
                    currentNodeIndex = furthestNodeIndex
                    currentNode = furthestNode
                    currentNodePos = furthestNodePos

                    for i = #currentPath, currentNodeIndex + 1, -1 do
                        table.remove(currentPath, i)
                    end
                end
            end

            -- Check if the path is completed
            if #currentPath == 0 then
                Navigation.ClearPath()
                Log:Info("Reached end of path")
                --currentTask = Tasks.None
            else
                -- Continue path following towards the current node
                Navigation.WalkTo(userCmd, me, currentNodePos)
            end
        end

        -- Repath if stuck
        local Flatdistance = math.abs(myPos.x - currentNodePos.x) + math.abs(myPos.y - currentNodePos.y)
        if currentNodeTicks > 40 and me:EstimateAbsVelocity():Length() < 50 or currentNodeTicks > 40 and Flatdistance < nodeTouchDistance then
            local minVector = Vector3(-24, -24, 0)
            local maxVector = Vector3(24, 24, 82)
            local traceResult1 = engine.TraceHull(myPos, currentNodePos, minVector, maxVector, MASK_SHOT_HULL)
            if traceResult1.fraction < 0.9 then

                -- Jump if stuck
                if not me:InCond(TFCond_Zoomed) then
                    --basic autojump when on ground
                    if flags & FL_ONGROUND == 1 then
                        userCmd:SetButtons(userCmd.buttons & (~IN_DUCK))
                        userCmd:SetButtons(userCmd.buttons | IN_JUMP) --userCmd.buttons = userCmd.buttons | IN_JUMP
                    else
                        userCmd:SetButtons(userCmd.buttons & (~IN_JUMP))
                    end
                end

                -- Path to the next node is blocked
                Log:Warn("Path to node %d is blocked, removing connection and repathing...", currentNodeIndex)
                -- Check that the current node and the next node exist in the path
                if currentPath[currentNodeIndex] and currentPath[currentNodeIndex + 1] then
                    -- Remove the connection between the current node and the next node
                    Navigation.RemoveConnection(currentPath[currentNodeIndex], currentPath[currentNodeIndex + 1])
                elseif currentPath[currentNodeIndex] and not currentPath[currentNodeIndex + 1] and currentNodeIndex > 1 then
                    -- If there's no next node, but there is a previous node, remove connection between the previous and the current node
                    Navigation.RemoveConnection(currentPath[currentNodeIndex - 1], currentPath[currentNodeIndex])
                end
                -- Clear the current path and recalculate
                Navigation.ClearPath()
                currentNodeTicks = 0
                -- Trigger repathing logic here if necessary (depends on the rest of your code)
            else
                -- Clear the current path and recalculate
                Log:Warn("Path to node %d is stuck but not blocked, repathing...", currentNodeIndex)
                Navigation.ClearPath()
                currentNodeTicks = 0
            end
        end
    else
        -- Generate new path
        local startNode = Navigation.GetClosestNode(myPos)
        local goalNode = nil
        local entity = nil

        if currentTask == Tasks.Objective then
            local objectives = nil

            -- map check
            if engine.GetMapName():lower():find("cp_") then
                -- cp
                objectives = entities.FindByClass("CTFObjectiveResource")
            elseif engine.GetMapName():lower():find("pl_") then
                -- pl
                objectives = entities.FindByClass("CObjectCartDispenser")
            elseif engine.GetMapName():lower():find("ctf_") then
                -- ctf
                local myItem = me:GetPropInt("m_hItem")
                local flags = entities.FindByClass("CCaptureFlag")
                for idx, entity in pairs(flags) do
                    local myTeam = entity:GetTeamNumber() == me:GetTeamNumber()
                    if (myItem > 0 and myTeam) or (myItem < 0 and not myTeam) then
                        goalNode = Navigation.GetClosestNode(entity:GetAbsOrigin())
                        if not Navigation.isSearching() then
                            Log:Info("Found flag at node %d", goalNode.id)
                        end
                        break
                    end
                end
            else
                Log:Warn("Unsupported Gamemode, try CTF or PL")
            end

            -- Ensure objectives is a table before iterating
            if objectives and type(objectives) ~= "table" then
                Log:Info("No objectives available")
                return
            end

            -- Iterate through objectives and find the closest one
            if objectives then
                local closestDist = math.huge
                for idx, ent in pairs(objectives) do
                    local dist = (myPos - ent:GetAbsOrigin()):Length()
                    if dist < closestDist then
                        closestDist = dist
                        goalNode = Navigation.GetClosestNode(ent:GetAbsOrigin())
                        entity = ent
                        Log:Info("Found objective at node %d", goalNode.id)
                    end
                end
            else
                --Log:Warn("No objectives found; iterate failure.")
            end

            -- Specific checks for PL gamemode
            if engine.GetMapName():lower():find("pl_") and entity and goalNode then
                local distanceToPayload = (myPos - entity:GetAbsOrigin()):Length()
                local thresholdDistance = 80

                if distanceToPayload > thresholdDistance then
                    Log:Info("Payload too far from player, pathing closer.")
                    -- If too far, update the path to get closer
                    Navigation.FindPath(startNode, goalNode, options.MaxNodesPerTick)
                    currentNodeIndex = #Navigation.GetCurrentPath()
                end
            end

            if not goalNode then
                Log:Warn("No objectives found. Continuing with default objective task.")
                currentTask = Tasks.Objective
                Navigation.ClearPath()
            end
        elseif currentTask == Tasks.Health then
            local closestDist = math.huge
            for idx, pos in pairs(healthPacks) do
                local healthNode = Navigation.GetClosestNode(pos)
                if healthNode then
                    local dist = (myPos - pos):Length()
                    if dist < closestDist then
                        closestDist = dist
                        goalNode = healthNode
                        Log:Info("Found health pack at node %d", goalNode.id)
                    end
                end
            end
        else
            Log:Debug("Unknown task: %d", currentTask)
            return
        end

        -- Check if we found a start and goal node
        if not goalNode then
            Log:Warn("Could not find new goal node")
            return
        end

        -- Update the pathfinder
        if not Navigation.isSearching() then
            Log:Info("Generating new path from node %d to node %d", startNode.id, goalNode.id)
        end
        Navigation.FindPath(startNode, goalNode, options.MaxNodesPerTick)

        local currentPath = Navigation.GetCurrentPath()
        if currentPath then
            currentNodeIndex = #currentPath
        elseif not Navigation.isSearching() then
            Log:Warn("Failed to find a path from node %d to node %d", startNode.id, goalNode.id)
        end
    end
end

---@param ctx DrawModelContext
local function OnDrawModel(ctx)
    -- TODO: This find a better way to do this
    if ctx:GetModelName():find("medkit") then
        local entity = ctx:GetEntity()
        healthPacks[entity:GetIndex()] = entity:GetAbsOrigin()
    end
end

---@param event GameEvent
local function OnGameEvent(event)
    local eventName = event:GetName()

    -- Reload nav file on new map
    if eventName == "game_newmap" then
        Log:Info("New map detected, reloading nav file...")

        healthPacks = {}
        LoadNavFile()
    end
end

callbacks.Unregister("Draw", "LNX.Lmaobot.Draw")
callbacks.Unregister("CreateMove", "LNX.Lmaobot.CreateMove")
callbacks.Unregister("DrawModel", "LNX.Lmaobot.DrawModel")
callbacks.Unregister("FireGameEvent", "LNX.Lmaobot.FireGameEvent")

callbacks.Register("Draw", "LNX.Lmaobot.Draw", OnDraw)
callbacks.Register("CreateMove", "LNX.Lmaobot.CreateMove", OnCreateMove)
callbacks.Register("DrawModel", "LNX.Lmaobot.DrawModel", OnDrawModel)
callbacks.Register("FireGameEvent", "LNX.Lmaobot.FireGameEvent", OnGameEvent)

--[[ Commands ]]

-- Reloads the nav file
Commands.Register("pf_reload", function()
    LoadNavFile()
end)

-- credits: snipergaming888 (Sydney)

local switch = 0;
local switchmax = 1;


local function newmap_eventNav(event)
    if event:GetName() == "game_newmap" then
        LoadNavFile()
    end
end

local function Restart(event)

    --[[local eventName = event:GetName()
    Log:Info("Event occurred: " .. eventName)]] --debug

    if event:GetName() == "teamplay_round_start" then
        switch = switch + 1;
        LoadNavFile()
            if switch == switchmax then 
                switch = 0;
            end
            Log:Warn("path outdated repathing...", currentNodeIndex)
            Navigation.ClearPath()
            currentNodeTicks = 0
    end
    if event:GetName() == "teamplay_round_active" then
        Log:Warn("now players can move repathing...", currentNodeIndex)
        Navigation.ClearPath()
        currentNodeTicks = 0
    end
end

callbacks.Register("FireGameEvent", "newm_event", newmap_eventNav)
callbacks.Register("FireGameEvent", "teamplay_restart_round", Restart)

-- Calculates the path from start to goal
Commands.Register("pf", function(args)
    if args:size() ~= 2 then
        print("Usage: pf <Start> <Goal>")
        return
    end

    local start = tonumber(args:popFront())
    local goal = tonumber(args:popFront())

    if not start or not goal then
        print("Start/Goal must be numbers!")
        return
    end

    local startNode = Navigation.GetNodeByID(start)
    local goalNode = Navigation.GetNodeByID(goal)

    if not startNode or not goalNode then
        print("Start/Goal node not found!")
        return
    end

    Navigation.FindPath(startNode, goalNode, options.MaxNodesPerTick)
end)

Commands.Register("pf_auto", function (args)
    options.autoPath = not options.autoPath
    print("Auto path: " .. tostring(options.autoPath))
end)

Notify.Alert("Lmaobot loaded!")
LoadNavFile()