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
