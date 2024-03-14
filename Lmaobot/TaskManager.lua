local TaskManager = {}
TaskManager.tasks = {}

function TaskManager.addTask(func, delay, identifier)
    local currentTime = globals.TickCount()

    -- Check if the task already exists
    if TaskManager.tasks[identifier] then
        -- If it does, just reset wasExecuted to false
        TaskManager.tasks[identifier].wasExecuted = false
    else
        -- If it doesn't, schedule the task for execution
        TaskManager.tasks[identifier] = {
            func = func,
            delay = delay,
            lastExecuted = currentTime,
            wasExecuted = false -- Initially marked as not executed
        }
    end
end

local function TickUpdate()
    local currentTime = globals.TickCount()
    for identifier, task in pairs(TaskManager.tasks) do
        if not task.wasExecuted and currentTime - task.lastExecuted >= task.delay then
            -- Task is due for execution
            task.func() -- Execute the task
            task.wasExecuted = true -- Mark as executed
            task.lastExecuted = currentTime -- Update execution time
        end

        -- Remove tasks that were executed and their delay period has passed without being scheduled again
        if task.wasExecuted and currentTime - task.lastExecuted >= task.delay then
            TaskManager.tasks[identifier] = nil
        end
    end
end

-- Simulate attaching to game's tick update or similar
callbacks.Unregister("CreateMove", "LNX.Lmaobot.TaskManager.CreateMove")
callbacks.Register("CreateMove", "LNX.Lmaobot.TaskManager.CreateMove", TickUpdate)

return TaskManager
