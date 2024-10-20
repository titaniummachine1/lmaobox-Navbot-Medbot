--[[ Setup Module ]]
---@class SetupModule
local SetupModule = {}
SetupModule.__index = SetupModule

-- Required libraries
local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local SourceNav = require("Lmaobot.Utils.SourceNav")
local Log = Common.Log

-- Variables to handle asynchronous nav file loading
local isNavGenerationInProgress = false
local navGenerationStartTime = 0
local navCheckInterval = 1  -- seconds
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

local batchIndex = 1
local batchSize = 10

-- Processes nav data and creates nodes, excluding visible nodes for now
function SetupModule.processNavData(navData)
    local navNodes = {}
    for _, area in ipairs(navData.areas) do
        local cX = (area.north_west.x + area.south_east.x) / 2
        local cY = (area.north_west.y + area.south_east.y) / 2
        local cZ = (area.north_west.z + area.south_east.z) / 2

        navNodes[area.id] = {
            pos = Vector3(cX, cY, cZ),
            id = area.id,
            c = area.connections,
            nw = area.north_west,
            se = area.south_east,
            visible_areas = area.visible_areas  -- Store visible areas for later processing
        }
    end
    return navNodes
end

-- Function to process visible node connections in batches
local function processVisibleNodesBatch(nodes)
    local processedCount = 0
    for id, node in pairs(nodes) do
        if node.visible_areas then
            for _, visible in ipairs(node.visible_areas) do
                local visNode = nodes[visible.id]
                if visNode and Common.isWalkable(node.pos, visNode.pos) then
                    node.c = node.c or {}
                    node.c[5] = node.c[5] or { count = 0, connections = {} }
                    table.insert(node.c[5].connections, visNode.id)
                    node.c[5].count = node.c[5].count + 1
                end
                processedCount = processedCount + 1
                if processedCount >= batchSize then
                    return  -- Stop processing after batchSize nodes
                end
            end
            node.visible_areas = nil -- Clear visible_areas once processed
        end
    end
end

-- OnDraw callback to process batches of visible nodes
local function OnDraw()
    if batchIndex <= #G.Navigation.nodes then
        processVisibleNodesBatch(G.Navigation.nodes)
    end
end

-- Register the OnDraw callback to be called each frame

callbacks.Unregister("FireGameEvent", "ProcessVisibleNodesBatch")
callbacks.Register("Draw", "ProcessVisibleNodesBatch", OnDraw)

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
        Log:Info("Parsed %d areas from nav file.", #navNodes)
        G.Navigation.nodes = navNodes
        Log:Info("Nav nodes set and fixed.")
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
        -- Nav file not yet available; will check again next time
        -- Optionally, log a message every few checks
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
    G.Navigation.path = {} -- Clear path after loading nav file
    Log:Info("Path cleared after loading nav file.")
end

-- Function to setup the navigation by loading the navigation file
function SetupModule.SetupNavigation()
    SetupModule.LoadNavFile() -- Reload nodes from navigation file
    Common.Reset("Objective") -- Reset any ongoing objective
    Log:Info("Navigation setup initiated.")
end

--inicial setup
SetupModule.SetupNavigation()


---@param event GameEvent
local function OnGameEvent(event)
    SetupModule.checkNavFileGeneration()
    local eventName = event:GetName()
    if eventName == "game_newmap" then
        Log:Info("New map detected, reloading nav file...")
        SetupModule.SetupNavigation()
    end
end

callbacks.Unregister("FireGameEvent", "LNX.Lmaobot.FireGameEvent")
callbacks.Register("FireGameEvent", "LNX.Lmaobot.FireGameEvent", OnGameEvent)


--cleanup before loading rest of code
collectgarbage("collect")

return SetupModule