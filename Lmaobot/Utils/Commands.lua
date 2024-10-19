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
