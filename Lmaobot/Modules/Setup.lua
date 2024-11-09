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
local Log = Common.Log

require("Lmaobot.Modules.SmartJump")
require("Lmaobot.Utils.Config")
require("Lmaobot.Utils.Commands")
require("Lmaobot.Visuals")
require("Lmaobot.Menu")

-- Variables to handle asynchronous nav file loading
local isNavGenerationInProgress = false
local navGenerationStartTime = 0
local navCheckElapsedTime = 0
local navCheckMaxTime = 60  -- maximum time to wait for nav generation

-- Initial variables and local player setup
local pLocal = nil
local function checkGameReady()
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return false end  -- Exit if player is not ready
    return true  -- Game is ready when pLocal is defined
end

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

    isNavGenerationInProgress = true
    navGenerationStartTime = globals.RealTime()
    navCheckElapsedTime = 0
end

-- Processes nav data and creates nodes
function SetupModule.processNavData(navData)
    local navNodes = {}
    local totalNodes = 0

    for _, area in pairs(navData.areas) do
        navNodes[area.id] = Node.create(area)
        totalNodes = totalNodes + 1
    end

    Node.SetNodes(navNodes)
    Log:Info("Processed %d nodes in nav data.", totalNodes)
    return navNodes
end

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

function SetupModule.processNavDataAndSet(navData)
    local navNodes = SetupModule.processNavData(navData)
    if not navNodes or next(navNodes) == nil then
        Log:Error("No nodes found in nav data after processing.")
    else
        Node.SetNodes(navNodes)
        Log:Info("Nav nodes set")
    end
end

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

function SetupModule.LoadNavFile()
    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, "%.bsp$", ".nav")
    Log:Info("Loading nav file for current map: %s", navFile)
    SetupModule.LoadFile(navFile)
end

local processedNodes = 0
local totalNodes = 0

function SetupModule.SetupNavigation()
    SetupModule.LoadNavFile()
    Navigation.ClearPath()
    TaskManager.Reset(G.Tasks.Objective)
    Log:Info("Navigation setup initiated.")

    Node.SetNodes(Node.reindexNodesSequentially(Node.GetNodes()))
    Log:Info(string.format("Total nodes: %d", #Node.GetNodes()))
end

local function processSingleNode(node, nodes)
    Node.processConnections(node, nodes)
end

local function processVisibleNodesBatch(nodes)
    local processedCount = 0

    for id, node in pairs(nodes) do
        if processedNodes >= totalNodes then
            return true
        end

        processSingleNode(node, nodes)
        processedNodes = processedNodes + 1
        G.Menu.Main.Loading = tonumber(string.format("%.2f", math.min((processedNodes / totalNodes) * 100, 100)))
        processedCount = processedCount + 1

        if processedCount >= loader.batch_size then
            return false
        end
    end

    return processedNodes >= totalNodes
end

local function startNodeProcessingTask(nodes)
    loader.create(function()
        return processVisibleNodesBatch(nodes)
    end)
end

local function OnGameEvent(event)
    local eventName = event:GetName()
    if eventName == "game_newmap" then
        Log:Info("New map detected, reloading nav file...")
        SetupModule.SetupNavigation()

        processedNodes = 0
        Navigation.ClearPath()
    end
end

-- Registering callbacks with a check for game readiness
callbacks.Unregister("FireGameEvent", "LNX.Lmaobot.FireGameEvent")
callbacks.Register("FireGameEvent", "LNX.Lmaobot.FireGameEvent", OnGameEvent)

local function delayedSetup()
    if not checkGameReady() then return end
    SetupModule.SetupNavigation()
    callbacks.Unregister("CreateMove", "delayedSetupCallback")
end

collectgarbage("collect")

callbacks.Register("CreateMove", "delayedSetupCallback", delayedSetup)

return SetupModule
