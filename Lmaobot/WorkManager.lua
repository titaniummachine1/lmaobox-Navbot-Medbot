local WorkManager = {}
WorkManager.works = {}
WorkManager.sortedIdentifiers = {}
WorkManager.workLimit = 1
WorkManager.executedWorks = 0

local function getCurrentTick()
    return globals.TickCount()
end

--- Adds work to the WorkManager and executes it if possible
--- @param func function The function to be executed
--- @param args table The arguments to pass to the function
--- @param delay number The delay (in ticks) before the function should be executed
--- @param identifier string A unique identifier for the work
function WorkManager.addWork(func, args, delay, identifier)
    local currentTime = getCurrentTick()
    args = args or {}

    -- Check if the work already exists
    if WorkManager.works[identifier] then
        -- Update existing work details (function, delay, args)
        WorkManager.works[identifier].func = func
        WorkManager.works[identifier].delay = delay or 1
        WorkManager.works[identifier].args = args
        WorkManager.works[identifier].wasExecuted = false
    else
        -- Add new work
        WorkManager.works[identifier] = {
            func = func,
            delay = delay,
            args = args,
            lastExecuted = currentTime,
            wasExecuted = false,
            result = nil
        }
        -- Insert identifier and sort works based on their delay, in descending order
        table.insert(WorkManager.sortedIdentifiers, identifier)
        table.sort(WorkManager.sortedIdentifiers, function(a, b)
            return WorkManager.works[a].delay > WorkManager.works[b].delay
        end)
    end

    -- Attempt to execute the work immediately if within the work limit
    if WorkManager.executedWorks < WorkManager.workLimit then
        local entry = WorkManager.works[identifier]
        if not entry.wasExecuted and currentTime - entry.lastExecuted >= entry.delay then
            -- Execute the work
            entry.result = {func(table.unpack(args))}
            entry.wasExecuted = true
            entry.lastExecuted = currentTime
            WorkManager.executedWorks = WorkManager.executedWorks + 1
            return table.unpack(entry.result)
        end
    end

    -- Return cached result if the work cannot be executed immediately
    local entry = WorkManager.works[identifier]
    return table.unpack(entry.result or {})
end

--- Attempts to execute work if conditions are met
--- @param delay number The delay (in ticks) before the function should be executed again
--- @param identifier string A unique identifier for the work
--- @return boolean Whether the work was executed
function WorkManager.attemptWork(delay, identifier)
    local currentTime = getCurrentTick()

    -- Check if the work already exists and was executed recently
    if WorkManager.works[identifier] and currentTime - WorkManager.works[identifier].lastExecuted < delay then
        return false
    end

    -- If the work does not exist or the delay has passed, create/update the work entry
    if not WorkManager.works[identifier] then
        WorkManager.works[identifier] = {
            lastExecuted = currentTime,
            delay = delay
        }
    else
        WorkManager.works[identifier].lastExecuted = currentTime
    end

    return true
end

--- Processes the works based on their priority
function WorkManager.processWorks()
    local currentTime = getCurrentTick()
    WorkManager.executedWorks = 0

    for _, identifier in ipairs(WorkManager.sortedIdentifiers) do
        local work = WorkManager.works[identifier]
        if not work.wasExecuted and currentTime - work.lastExecuted >= work.delay then
            -- Execute the work
            work.result = {work.func(table.unpack(work.args))}
            work.wasExecuted = true
            work.lastExecuted = currentTime
            WorkManager.executedWorks = WorkManager.executedWorks + 1

            -- Stop if the work limit is reached
            if WorkManager.executedWorks >= WorkManager.workLimit then
                break
            end
        end
    end
end

return WorkManager
