---@diagnostic disable: duplicate-set-field, undefined-field
---@class Common
local Common = {}

local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")

Common.Lib = Lib
Common.Utils = Common.Lib.Utils
Common.Notify = Lib.UI.Notify
Common.TF2 = Common.Lib.TF2

Common.Math, Common.Conversion = Common.Utils.Math, Common.Utils.Conversion
Common.WPlayer, Common.PR = Common.TF2.WPlayer, Common.TF2.PlayerResource
Common.Helpers = Common.TF2.Helpers
Common.WalkTo = Common.Helpers.WalkTo

Common.Notify = Lib.UI.Notify
Common.Json = require("Lmaobot.Utils.Json") -- Require Json.lua directly
Common.Log = Common.Utils.Logger.new("Lmaobot")
Common.Log.Level = 0

local G = require("Lmaobot.Utils.Globals")
local IsWalkable = require("Lmaobot.Modules.IsWalkable")

Common.isWalkable = IsWalkable.Path

function Common.horizontal_manhattan_distance(pos1, pos2)
    return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function Common.Normalize(vec)
    local length = vec:Length()
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

function Common.AddCurrentTask(taskKey)
    local task = G.Tasks[taskKey]
    if task and not G.Current_Tasks[taskKey] then
        G.Current_Tasks[taskKey] = task
    end
end

function Common.RemoveCurrentTask(taskKey)
    if G.Current_Tasks[taskKey] then
        G.Current_Tasks[taskKey] = nil
    end
end

function Common.GetHighestPriorityTask()
    local highestPriorityTaskKey = nil
    local highestPriority = math.huge

    for taskKey, priority in pairs(G.Current_Tasks) do
        if priority < highestPriority then
            highestPriority = priority
            highestPriorityTaskKey = taskKey
        end
    end

    return highestPriorityTaskKey
end

-- Reset tasks to the initial objective
function Common.Reset(Default)
    G.Current_Tasks = {}
    local initialObjectiveTaskKey = Default -- Assuming this is defined somewhere in G
    if initialObjectiveTaskKey then
        Common.AddCurrentTask(initialObjectiveTaskKey)
    end
end

--[[ Callbacks ]]
local function OnUnload() -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

callbacks.Unregister("Unload", "CD_Unload")
callbacks.Register("Unload", "CD_Unload", OnUnload)

return Common