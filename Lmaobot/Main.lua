--[[ Annotations ]]
---@alias NavConnection { count: integer, connections: integer[] }
---@alias NavNode { id: integer, x: number, y: number, z: number, c: { [1]: NavConnection, [2]: NavConnection, [3]: NavConnection, [4]: NavConnection } }

--[[ Imports ]]
local Common = require("Lmaobot.Common")
local Navigation = require("Lmaobot.Navigation")
local Lib = Common.Lib

-- Unload package for debugging
Lib.Utils.UnloadPackages("Lmaobot")

local Notify, FS, Fonts, Commands, Timer = Lib.UI.Notify, Lib.Utils.FileSystem, Lib.UI.Fonts, Lib.Utils.Commands, Lib.Utils.Timer
local Log = Lib.Utils.Logger.new("Lmaobot")
Log.Level = 0

--[[ Variables ]]

local options = {
    memoryUsage = false, -- Shows memory usage in the top left corner
    drawNodes = false, -- Draws all nodes on the map
    drawPath = true, -- Draws the path to the current goal
    drawCurrentNode = false, -- Draws the current node
    autoPath = true, -- Automatically walks to the goal
}

local currentNodeIndex = 1
local currentNodeTicks = 0

---@type Vector3[]
local healthPacks = {}

local Tasks = table.readOnly {
    None = 0,
    Objective = 1,
    Health = 2,
}

local currentTask = Tasks.Objective
local taskTimer = Timer.new()
local jumptimer = 0;
local jumpmax = 50

--[[ Functions ]]

-- Loads the nav file of the current map
local function LoadNavFile()
    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, ".bsp", ".nav")

    Navigation.LoadFile(navFile)
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

            -- Node IDs
            draw.Text(screenPos[1], screenPos[2], tostring(id))

            ::continue::
        end
    end

    -- Draw current path
    if options.drawPath and currentPath then
        draw.Color(255, 255, 0, 255)

        for i = 1, #currentPath - 1 do
            local node1 = currentPath[i]
            local node2 = currentPath[i + 1]

            local node1Pos = Vector3(node1.x, node1.y, node1.z)
            local node2Pos = Vector3(node2.x, node2.y, node2.z)

            local screenPos1 = client.WorldToScreen(node1Pos)
            local screenPos2 = client.WorldToScreen(node2Pos)
            if not screenPos1 or not screenPos2 then goto continue end

            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])

            ::continue::
        end
    end

    -- Draw current node
    if options.drawCurrentNode and currentPath then
        draw.Color(255, 0, 0, 255)

        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = Vector3(currentNode.x, currentNode.y, currentNode.z)

        local screenPos = client.WorldToScreen(currentNodePos)
        if screenPos then
            draw.Text(screenPos[1], screenPos[2], tostring(currentNodeIndex))
        end
    end
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not options.autoPath then return end

    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then
        Navigation.ClearPath()
        return
    end

    -- Update the current task
    if taskTimer:Run(0.7) then
        if me:GetHealth() < 75 then
            if currentTask ~= Tasks.Health then
                Log:Info("Switching to health task")
                Navigation.ClearPath()
            end
    
            currentTask = Tasks.Health
        else
            if currentTask ~= Tasks.Objective then
                Log:Info("Switching to objective task")
                Navigation.ClearPath()
            end
    
            currentTask = Tasks.Objective
        end
    end

    local myPos = me:GetAbsOrigin()
    local currentPath = Navigation.GetCurrentPath()

    if currentTask == Tasks.None then return end

    if currentPath then
        -- Move along path

        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = Vector3(currentNode.x, currentNode.y, currentNode.z)

        local dist = (myPos - currentNodePos):Length()
        if dist < 22 then
            currentNodeTicks = 0
            currentNodeIndex = currentNodeIndex - 1
            if currentNodeIndex < 1 then
                Navigation.ClearPath()
                --options.autoPath = false
                Log:Info("Reached end of path")
                currentTask = Tasks.None
            end
        else
            currentNodeTicks = currentNodeTicks + 1
            Lib.TF2.Helpers.WalkTo(userCmd, me, currentNodePos)
        end

        -- Jump if stuck
        if currentNodeTicks > 150 and not me:InCond(TFCond_Zoomed) then
            --hold down jump for half a second
            jumptimer = jumptimer + 1;
            userCmd.buttons = userCmd.buttons | IN_JUMP
            if jumptimer == jumpmax then 
                jumptimer = 0;
                currentNodeTicks = 0
            end    
        end

        -- Repath if stuck
        if currentNodeTicks > 250 then
            Log:Warn("Stuck on node %d, removing connection and repathing...", currentNodeIndex)
            Navigation.RemoveConnection(currentNode, currentPath[currentNodeIndex - 1])
            Navigation.ClearPath()
            currentNodeTicks = 0
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
		        objectives = entities.FindByClass("CObjectControlPoint")
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
                        Log:Info("Found flag at node %d", goalNode.id)
                        break
                    end
                end
		    else
		        Log:Warn("Unsupported Gamemode, try CTF or PL")
		        return
		    end
		
		    -- Iterate through objectives and find the closest one
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
		
		    -- Check if the distance between player and payload is greater than a threshold
		    if entity then
		        local distanceToPayload = (myPos - entity:GetAbsOrigin()):Length()
		        local thresholdDistance = 300
		
		        if distanceToPayload > thresholdDistance then
		            -- If too far, update the path to get closer
		            Navigation.FindPath(startNode, goalNode)
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
		        local dist = (myPos - pos):Length()
		        if dist < closestDist then
		            closestDist = dist
		            goalNode = Navigation.GetClosestNode(pos)
		            Log:Info("Found health pack at node %d", goalNode.id)
		        end
		    end
		else
		    Log:Debug("Unknown task: %d", currentTask)
		    return
		end
		
		-- Check if we found a start and goal node
		if not startNode or not goalNode then
		    Log:Warn("Could not find new start or goal node")
		    return
		end
		
		-- Update the pathfinder
		Log:Info("Generating new path from node %d to node %d", startNode.id, goalNode.id)
		Navigation.FindPath(startNode, goalNode)
		currentNodeIndex = #Navigation.GetCurrentPath()
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

    Navigation.FindPath(startNode, goalNode)
end)

Commands.Register("pf_auto", function (args)
    options.autoPath = not options.autoPath
    print("Auto path: " .. tostring(options.autoPath))
end)

Notify.Alert("Lmaobot loaded!")
LoadNavFile()
