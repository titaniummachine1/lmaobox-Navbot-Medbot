
--[[           IsWalkable module         ]]--
--[[       Made and optimized by        ]]--
--[[         Titaniummachine1           ]]--
--[[ https://github.com/Titaniummachine1 ]]--

local IsWalkable = {}

--Limits
local MAX_ITERATIONS = 37         -- Maximum number of iterations to prevent infinite loops

-- Constants (initially set to nil or default values)
local pLocal = nil
local PLAYER_HULL, MaxSpeed, gravity, STEP_HEIGHT, STEP_HEIGHT_Vector, MAX_FALL_DISTANCE, MAX_FALL_DISTANCE_Vector, STEP_FRACTION
local MIN_STEP_SIZE = 300 * globals.TickInterval() -- Minimum step size to consider for ground checks

-- Function to initialize constants when pLocal becomes available
local function initializeConstants()
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return end -- Exit if pLocal is still unavailable

    PLAYER_HULL = {Min = Vector3(-24, -24, 0), Max = Vector3(24, 24, 82)} -- Player collision hull
    MaxSpeed = pLocal:GetPropFloat("m_flMaxspeed") or 450 -- Default to 450 if max speed not available
    MIN_STEP_SIZE = MaxSpeed * globals.TickInterval() -- Minimum step size to consider for ground checks
    STEP_HEIGHT = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18 -- Maximum height the player can step up
    STEP_HEIGHT_Vector = Vector3(0, 0, STEP_HEIGHT)
    MAX_FALL_DISTANCE = 250 -- Maximum distance the player can fall without taking fall damage
    MAX_FALL_DISTANCE_Vector = Vector3(0, 0, MAX_FALL_DISTANCE)
    STEP_FRACTION = STEP_HEIGHT / MAX_FALL_DISTANCE
end

-- Callback function ID for easy unregistration
local function checkAndInitialize()
    -- Attempt to initialize constants if not done already
    initializeConstants()
    -- Unregister this callback if pLocal is defined
    if pLocal then
        callbacks.Unregister("CreateMove", "initializeCheckCallback")
    end
end

-- Register the callback to check every tick
callbacks.Register("CreateMove", "initializeCheckCallback", checkAndInitialize)

local UP_VECTOR = Vector3(0, 0, 1)
local MAX_SURFACE_ANGLE = 45       -- Maximum angle for ground surfaces

-- Helper Functions
local function shouldHitEntity(entity)
    return entity ~= pLocal -- Ignore self (the player being simulated)
end

-- Normalize a vector
local function Normalize(vec)
    return vec / vec:Length()
end

-- Calculate horizontal Manhattan distance between two points
local function getHorizontalManhattanDistance(point1, point2)
    return math.abs(point1.x - point2.x) + math.abs(point1.y - point2.y)
end

-- Perform a hull trace to check for obstructions between two points
local function performTraceHull(startPos, endPos)
    return engine.TraceHull(startPos, endPos, PLAYER_HULL.Min, PLAYER_HULL.Max, MASK_PLAYERSOLID, shouldHitEntity)
end

-- Adjust the direction vector to align with the surface normal
local function adjustDirectionToSurface(direction, surfaceNormal)
    direction = Normalize(direction)
    local angle = math.deg(math.acos(surfaceNormal:Dot(UP_VECTOR)))

    -- Check if the surface is within the maximum allowed angle for adjustment
    if angle > MAX_SURFACE_ANGLE then
        return direction
    end

    local dotProduct = direction:Dot(surfaceNormal)

    -- Adjust the z component of the direction in place
    direction.z = direction.z - surfaceNormal.z * dotProduct

    -- Normalize the direction after adjustment
    return Normalize(direction)
end

-- Main function to check walkability
function IsWalkable.Path(startPos, goalPos)
    -- Clear trace tables for debugging
    hullTraces = {}
    local blocked = false

    -- Initialize variables
    local currentPos = startPos

    -- Adjust start position to ground level
    local startGroundTrace = performTraceHull(
        startPos + STEP_HEIGHT_Vector,
        startPos - MAX_FALL_DISTANCE_Vector
    )

    currentPos = startGroundTrace.endpos

    -- Initial direction towards goal, adjusted for ground normal
    local lastPos = currentPos
    local lastDirection = adjustDirectionToSurface(goalPos - currentPos, startGroundTrace.plane)

    local MaxDistance = getHorizontalManhattanDistance(startPos, goalPos)

    -- Main loop to iterate towards the goal
    for iteration = 1, MAX_ITERATIONS do
        -- Calculate distance to goal and update direction
        local distanceToGoal = (currentPos - goalPos):Length()
        local direction = lastDirection

        -- Calculate next position
        local NextPos = lastPos + direction * distanceToGoal

        -- Forward collision check
        local wallTrace = performTraceHull(
            lastPos + STEP_HEIGHT_Vector,
            NextPos + STEP_HEIGHT_Vector
        )
        currentPos = wallTrace.endpos

        if wallTrace.fraction == 0 then
            blocked = true -- Path is blocked by a wall
        end

        -- Ground collision with segmentation
        local totalDistance = (currentPos - lastPos):Length()
        local numSegments = math.max(1, math.floor(totalDistance / MIN_STEP_SIZE))

        for seg = 1, numSegments do
            local t = seg / numSegments
            local segmentPos = lastPos + (currentPos - lastPos) * t
            local segmentTop = segmentPos + STEP_HEIGHT_Vector
            local segmentBottom = segmentPos - MAX_FALL_DISTANCE_Vector

            local groundTrace = performTraceHull(segmentTop, segmentBottom)

            if groundTrace.fraction == 1 then
                return false -- No ground beneath; path is unwalkable
            end

            if groundTrace.fraction > STEP_FRACTION or seg == numSegments then
                -- Adjust position to ground
                direction = adjustDirectionToSurface(direction, groundTrace.plane)
                currentPos = groundTrace.endpos
                blocked = false
                break
            end
        end

        -- Calculate current horizontal distance to goal
        local currentDistance = getHorizontalManhattanDistance(currentPos, goalPos)
        if blocked or currentDistance > MaxDistance then --if target is unreachable
            return false
        elseif currentDistance < 24 then --within range
            local verticalDist = math.abs(goalPos.z - currentPos.z)
            if verticalDist < 24 then  --within vertical range
                return true -- Goal is within reach; path is walkable
            else --unreachable
                return false -- Goal is too far vertically; path is unwalkable
            end
        end

        -- Prepare for the next iteration
        lastPos = currentPos
        lastDirection = direction
    end

    return false -- Max iterations reached without finding a path
end

return IsWalkable