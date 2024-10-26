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
