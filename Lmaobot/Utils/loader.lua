local loader = {}
loader.preferred_fps = 30          -- Preferred FPS threshold
loader.initial_batch_size = 10      -- Initial batch size
loader.min_batch_size = 5           -- Minimum batch size
loader.max_batch_size = 500          -- Maximum batch size
loader.batch_size = loader.initial_batch_size  -- Current batch size
loader.co = nil                     -- Coroutine reference
loader.task_done = false            -- Task completion flag

-- Function to create a loader
function loader.create(task_function, task_input)
    loader.batch_size = loader.initial_batch_size  -- Reset batch size
    loader.co = coroutine.create(function() task_function(task_input) end)  -- Create a coroutine for the task
    loader.task_done = false
end

-- Function to update the loader (call in the game loop)
function loader.update()
    if not loader.co or coroutine.status(loader.co) == "dead" then
        loader.task_done = true  -- Mark task as done if coroutine is finished
        return
    end

    local frame_time = globals.FrameTime()  -- Get the time taken for the last frame
    local start_time = os.clock()  -- Start timing the batch

    -- Process the task in the current batch
    for i = 1, loader.batch_size do
        if coroutine.status(loader.co) == "dead" then
            loader.task_done = true
            break
        end
        coroutine.resume(loader.co)
    end

    local time_used = os.clock() - start_time  -- Calculate how much time the batch took
    local fps_drop = time_used / frame_time  -- Estimate the FPS drop due to processing

    -- Adjust batch size based on the FPS drop
    if fps_drop > 0.1 then  -- If processing took too long, reduce batch size
        loader.batch_size = math.max(loader.min_batch_size, math.floor(loader.batch_size * 0.8))
    elseif (1 / frame_time) > loader.preferred_fps then  -- If FPS is above preferred threshold, increase batch size
        loader.batch_size = math.min(loader.max_batch_size, math.ceil(loader.batch_size * 1.2))
    end
end

return loader