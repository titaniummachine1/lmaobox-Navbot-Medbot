---@class Benchmark
local Benchmark = {} -- benchmark.lua

-- Runs a function n times and returns the elapsed time in seconds
---@return number
function Benchmark.Run(n, func)
    local startTime = os.clock()
    for _ = 1, n do
        func()
    end
    local endTime = os.clock()
    local elapsedTime = endTime - startTime
    return elapsedTime
end

local startTime, startMemory
local totalTime, totalMemory, iterationCount = 0, 0, 0

-- Function to start the benchmark
function Benchmark.start()
    -- Capture the start time
    startTime = os.clock()
    -- Capture the start memory usage
    startMemory = collectgarbage("count")
end

-- Function to stop the benchmark and update the results
function Benchmark.stop()
    -- Capture the stop time
    local stopTime = os.clock()
    -- Capture the stop memory usage
    local stopMemory = collectgarbage("count")

    -- Calculate the elapsed time
    local elapsedTime = stopTime - startTime
    -- Calculate the memory usage
    local memoryUsed = stopMemory - startMemory

    -- Update the totals and iteration count
    totalTime = totalTime + elapsedTime
    totalMemory = totalMemory + memoryUsed
    iterationCount = iterationCount + 1

    -- Calculate the average time and memory usage
    local averageTime = totalTime / iterationCount
    local averageMemory = totalMemory / iterationCount

    -- Print the results
    print(string.format("Average time elapsed: %.6f seconds", averageTime))
    print(string.format("Average memory used: %.3f KB", averageMemory))
end

-- Function to reset the benchmark
function Benchmark.reset()
    totalTime, totalMemory, iterationCount = 0, 0, 0
end

-- Return the Benchmark table as the module
return Benchmark
