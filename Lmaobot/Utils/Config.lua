--[[ Imports ]]
local Common = require("Cheater_Detection.Common")
local Config = {}


local Log = Common.Log
local Lib = Common.Lib
local Notify = Lib.UI.Notify
local FS = Common.FS  -- Getting FileSystem directly from lnxLib
local Json = Common.Json
Log.Level = 0

local DataBase = {}

local Menu = {
    Tabs = {
        Main = true,
        Visuals = false,
        playerlist = false,
    },

    Main = {
        StrikeLimit = 5,
        ChokeDetection = {
            Enable = true,
            MaxChoke = 7,
        },
        BhopDetection = {
            Enable = true,
            MaxBhop = 2,
        },
        AimbotDetection = {
            Enable = true,
            MAXfov = 20,
        },
        AntyAimDetection = true,
        DuckSpeedDetection = true,
        debug = false,
    },

    Visuals = {
        AutoMark = true,
        partyCallaut = true,
        Chat_Prefix = true,
        Cheater_Tags = true,
        Debug = false,
    },
}

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

function Config.GetFilePath()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/config.cfg")
end

function Config.CreateCFG(table)
    if not table then
        table = Menu
    end
    local filepath = Config.GetFilePath()
    local file = io.open(filepath, "w")  -- Define the file variable here

    if file then
        local function serializeTable(tbl, level)
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

        local serializedConfig = serializeTable(table)
        file:write(serializedConfig)
        file:close()
        printc( 255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved Config to ".. tostring(Config.GetFilePath()))
    end
end

-- Function to check if all expected keys exist in the loaded config
local function checkAllKeysExist(expectedMenu, loadedMenu)
    for key, value in pairs(expectedMenu) do
        -- If the key from the expected menu does not exist in the loaded menu, return false
        if loadedMenu[key] == nil then
            return false
        end

        -- If the value is a table, check the keys in the nested table
        if type(value) == "table" then
            local result = checkAllKeysExist(value, loadedMenu[key])
            if not result then
                return false
            end
        end
    end
    return true
end

function Config.LoadCFG()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            local loadedMenu = chunk()
            if checkAllKeysExist(Menu, loadedMenu) then
                printc(0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded Config from ".. tostring(filepath))
                return loadedMenu
            else
                print("Config is outdated or invalid. Creating a new config.")
                Config.CreateCFG(Menu) -- Save the config
                return Menu
            end
        else
            print("Error executing configuration file:", err)
            Config.CreateCFG(Menu) -- Save the config
            return Menu
        end
    else
        print("Config file not found. Creating a new config.")
        Config.CreateCFG(Menu) -- Save the config
        return Menu
    end
end

function Config.UpdateDataBase(DataBaseTable)
    DataBase = DataBaseTable or {}
end

function Config.SaveDatabase(DataBaseTable)
    DataBaseTable = DataBaseTable or DataBase or {}
    local filepath = Config.GetFilePath():gsub("config.cfg", "database.json")
    local file = io.open(filepath, "w")

    if file then
        -- Create a new table to store unique records
        local uniqueDataBase = {}

        -- Iterate over the database table
        for steamId, data in pairs(DataBaseTable) do
            -- If the record doesn't exist in the unique database, add it
            if not uniqueDataBase[steamId] then
                uniqueDataBase[steamId] = data
            end
        end

        local serializedDatabase = Json.encode(uniqueDataBase)
        file:write(serializedDatabase)
        file:close()
        printc(255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved Database to ".. tostring(filepath))
    else
        print("Failed to save database. Creating a new database.")
        Config.SaveDatabase()
    end
end

function Config.LoadDatabase()
    local filepath = Config.GetFilePath():gsub("config.cfg", "database.json")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local loadedDatabase, pos, err = Json.decode(content, 1, nil)
        if err then
            print("Error loading database:", err)
        else
            printc(0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded Database from ".. tostring(filepath))
            DataBase = loadedDatabase
        end
    else
        print("Failed to load database. Creating a new database.")
        DataBase = {}
        Config.SaveDatabase()
    end

    return DataBase
end

function Config.IsKnownCheater(steamId)
    local record = DataBase[steamId]
    if record then
        if record.isCheater == true then
            return true
        end
    end
    return false
end

function Config.GetRecord(steamId)
    local record = DataBase[steamId]
    if record then
        return record
    else
        return nil
    end
end

function Config.GetStrikes(steamId)
    local record = DataBase[steamId]
    if record then
        return record.strikes
    else
        return 0
    end
end

function Config.GetCause(steamId)
    local record = DataBase[steamId]
    if record then
        return record.cause
    else
        return nil
    end
end

function Config.GetDate(steamId)
    local record = DataBase[steamId]
    if record then
        return record.date
    else
        return nil
    end
end

function Config.PushSuspect(steamId, data)
    DataBase[steamId] = data
end

function Config.ClearSuspect(steamId)
    if DataBase[steamId] then
        DataBase[steamId] = nil
    end
end

function Config.GetDatabase()
    return DataBase
end

function Config.GetMenu()
    return Menu
end

return Config