-- TaskManager.lua

--[[ TaskManager Module ]]
local TaskManager = {}

--[[ Dependencies ]]
local G = require("Lmaobot.Utils.Globals") -- Adjust the path as necessary
local Log = require("Lmaobot.Common").Log   -- Assuming Log is in Common module

--[[ TaskManager Functions ]]

--- Adds a task to the current tasks if it doesn't already exist.
---@param taskKey string The key of the task to add.
function TaskManager.AddTask(taskKey)
    local taskPriority = G.Tasks[taskKey]
    if taskPriority then
        if not G.Current_Tasks[taskKey] then
            G.Current_Tasks[taskKey] = taskPriority
            Log:Info("Added task: %s with priority %d", taskKey, taskPriority)
        else
            Log:Info("Task %s is already in the current tasks.", taskKey)
        end
    else
        Log:Warn("Task '%s' does not exist in G.Tasks.", taskKey)
    end
end

--- Removes a task from the current tasks.
---@param taskKey string The key of the task to remove.
function TaskManager.RemoveTask(taskKey)
    if G.Current_Tasks[taskKey] then
        G.Current_Tasks[taskKey] = nil
        Log:Info("Removed task: %s", taskKey)
    else
        Log:Info("Task %s is not in the current tasks.", taskKey)
    end
end

--- Retrieves the task with the highest priority.
---@return string|nil The key of the highest priority task, or nil if no tasks are active.
function TaskManager.GetCurrentTask()
    local highestPriorityTaskKey = nil
    local highestPriority = -math.huge  -- Start with negative infinity

    for taskKey, priority in pairs(G.Current_Tasks) do
        if priority > highestPriority then  -- Higher numerical value means higher priority
            highestPriority = priority
            highestPriorityTaskKey = taskKey
        end
    end

    if highestPriorityTaskKey then
        G.Current_Task = G.Tasks[highestPriorityTaskKey]
    else
        G.Current_Task = G.Tasks.None
    end

    return highestPriorityTaskKey
end

--- Resets the current tasks to only include the default task.
---@param defaultTaskKey string The key of the default task to reset to.
function TaskManager.Reset(defaultTaskKey)
    G.Current_Tasks = {}
    if defaultTaskKey and G.Tasks[defaultTaskKey] then
        TaskManager.AddTask(defaultTaskKey)
        Log:Info("Tasks reset to default task: %s", defaultTaskKey)
    else
        Log:Warn("Default task key '%s' is invalid.", tostring(defaultTaskKey))
    end
end

--- Checks if a task is currently active.
---@param taskKey string The key of the task to check.
---@return boolean True if the task is active, false otherwise.
function TaskManager.IsTaskActive(taskKey)
    return G.Current_Tasks[taskKey] ~= nil
end

return TaskManager
