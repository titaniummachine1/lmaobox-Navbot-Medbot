---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local G = require("Lmaobot.Utils.Globals")

local Math = lnxLib.Utils.Math
local Prediction = lnxLib.TF2.Prediction
local WPlayer = lnxLib.TF2.WPlayer

-- Globals
local lastAngle = nil            ---@type number
local pLocal = entities.GetLocalPlayer()
local onGround = true
local isDucking = false
local predictedPosition = Vector3(0, 0, 0)
local jumpPeakPosition = Vector3(0, 0, 0)
local shouldJump = false

-- Constants
local HITBOX_MIN = Vector3(-23.99, -23.99, 0)
local HITBOX_MAX = Vector3(23.99, 23.99, 82)
local MAX_JUMP_HEIGHT = Vector3(0, 0, 72)   -- Maximum jump height vector
local STEP_HEIGHT = Vector3(0, 0, 18)   -- Maximum jump height vector
local MAX_WALKABLE_ANGLE = 45               -- Maximum angle considered walkable
local GRAVITY = 800                         -- Gravity per second squared
local JUMP_FORCE = 277                      -- Initial vertical boost for a duck jump

-- State Definitions
local STATE_AWAITING_JUMP = "STATE_AWAITING_JUMP"
local STATE_CTAP = "STATE_CTAP"
local STATE_JUMP = "STATE_JUMP"
local STATE_ASCENDING = "STATE_ASCENDING"
local STATE_DESCENDING = "STATE_DESCENDING"

-- Initial state
local jumpState = STATE_AWAITING_JUMP

-- Function to rotate a vector by yaw angle
local function RotateVectorByYaw(vector, yaw)
    local rad = math.rad(yaw)
    local cosYaw, sinYaw = math.cos(rad), math.sin(rad)
    return Vector3(
        cosYaw * vector.x - sinYaw * vector.y,
        sinYaw * vector.x + cosYaw * vector.y,
        vector.z
    )
end

-- Function to normalize a vector
local function Normalize(vec)
    return vec / vec:Length()
end

-- Function to check if the surface is walkable based on its normal
local function IsSurfaceWalkable(normal)
    local upVector = Vector3(0, 0, 1)
    local angle = math.deg(math.acos(normal:Dot(upVector)))
    return angle < MAX_WALKABLE_ANGLE
end

-- Helper function to check if the player is on the ground
local function IsPlayerOnGround(player)
    local flags = player:GetPropInt("m_fFlags")
    return (flags & FL_ONGROUND) == FL_ONGROUND
end

-- Helper function to check if the player is ducking
local function IsPlayerDucking(player)
    local flags = player:GetPropInt("m_fFlags")
    return (flags & FL_DUCKING) == FL_DUCKING
end

local function isSmaller(player)
    return player:GetPropVector("m_vecViewOffset[0]").z < 65
end

-- Function to calculate the strafe angle delta
---@param player WPlayer?
local function CalcStrafe(player)
    if not player then return 0 end
    local velocityAngle = player:EstimateAbsVelocity():Angles()
    local delta = 0
    if lastAngle then
        delta = Math.NormalizeAngle(velocityAngle.y - lastAngle)
    end
    lastAngle = velocityAngle.y
    return delta
end

-- Function to calculate the jump peak position and direction
local function GetJumpPeak(horizontalVelocity, startPos)
    -- Calculate the time to reach the jump peak
    local timeToPeak = JUMP_FORCE / GRAVITY

    -- Calculate horizontal velocity length
    local horizontalSpeed = horizontalVelocity:Length()

    -- Calculate distance traveled horizontally during time to peak
    local distanceTravelled = horizontalSpeed * timeToPeak

    -- Calculate peak position vector
    local peakPosition = startPos + Normalize(horizontalVelocity) * distanceTravelled

    -- Calculate direction to peak position
    local directionToPeak = Normalize(peakPosition - startPos)

    return peakPosition, directionToPeak
end

-- Function to adjust player's velocity towards the movement input direction
local function AdjustVelocity(cmd)
    if not pLocal then return Vector3(0, 0, 0) end

    -- Get movement input
    local moveInput = Vector3(cmd.forwardmove, -cmd.sidemove, 0)
    if moveInput:Length() == 0 then
        return pLocal:EstimateAbsVelocity()
    end

    -- Get view angles
    local viewAngles = engine.GetViewAngles()
    -- Rotate movement input by yaw
    local rotatedMoveDir = RotateVectorByYaw(moveInput, viewAngles.yaw)
    local normalizedMoveDir = Normalize(rotatedMoveDir)

    -- Get current velocity
    local velocity = pLocal:EstimateAbsVelocity()
    local intendedSpeed = math.max(10, velocity:Length())

    -- Adjust velocity to match intended direction and speed
    if onGround then
        velocity = normalizedMoveDir * intendedSpeed
    end

    return velocity
end

-- Smart jump logic
local function SmartJump(cmd)
    if not pLocal then return end
    if not G.Menu.Movement.Smart_Jump then return end
    shouldJump = false

    if onGround then
        local adjustedVelocity = AdjustVelocity(cmd)
        local playerPos = pLocal:GetAbsOrigin()

        -- Calculate jump peak position and direction
        local jumpPeakPos, jumpDirection = GetJumpPeak(adjustedVelocity, playerPos)

       -- Move up
       local startTracePos = playerPos + STEP_HEIGHT
       jumpPeakPos = jumpPeakPos + STEP_HEIGHT

       -- Trace from player position to forward direction
       local trace = engine.TraceHull(startTracePos, jumpPeakPos, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
       local ForwardPos = trace.endpos

        -- Trace down to snap to ground
        local downTrace = engine.TraceHull(ForwardPos , ForwardPos - MAX_JUMP_HEIGHT, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
        ForwardPos = downTrace.endpos

        if trace.fraction < 1 then
            -- Move forward slightly
            local JumpPos = ForwardPos + jumpDirection * 1

            -- Trace down to check for landing
            local downTrace = engine.TraceHull(JumpPos + MAX_JUMP_HEIGHT, JumpPos, HITBOX_MIN, HITBOX_MAX, MASK_PLAYERSOLID_BRUSHONLY)
            JumpPos = downTrace.endpos

            if downTrace.fraction > 0 and downTrace.fraction < 0.75 then
                local normal = downTrace.plane
                if IsSurfaceWalkable(normal) then
                    shouldJump = true
                end
            end
        end
    elseif (cmd.buttons & IN_JUMP) == 1 then
        shouldJump = true
    end
end

-- OnCreateMove callback
local function OnCreateMove(cmd)
    -- Get local player
    pLocal = entities.GetLocalPlayer()
    local wLocal = WPlayer.GetLocal()
    predictedPosition = nil --remveo visuals when not needed

    if not pLocal or not pLocal:IsAlive() or not wLocal then
        jumpState = STATE_AWAITING_JUMP -- Previously STATE_IDLE
        return
    end

    -- Update player states
    onGround = IsPlayerOnGround(pLocal)
    isDucking = IsPlayerDucking(pLocal)

    -- Adjust hitbox based on ducking state
    if isDucking then
        HITBOX_MAX.z = 62
    else
        HITBOX_MAX.z = 82
    end

    -- Calculate strafe angle delta
    local strafeDelta = CalcStrafe(wLocal)

    -- Handle edge case when player is on ground and ducking.
    if onGround and isDucking or onGround and isSmaller(pLocal) then
        jumpState = STATE_AWAITING_JUMP --jump if youre duckign already means we could have gotten stuck ducking
    end

    -- State machine for jump logic
    if jumpState == STATE_AWAITING_JUMP then
        -- Waiting for jump
        SmartJump(cmd)
        if shouldJump then
            jumpState = STATE_CTAP -- Previously STATE_PREPARE_JUMP
        end
    elseif jumpState == STATE_CTAP then
        -- Start crouching
        cmd:SetButtons(cmd.buttons | IN_DUCK)
        cmd:SetButtons(cmd.buttons & (~IN_JUMP))
        jumpState = STATE_JUMP -- Previously STATE_CTAP
        return
    elseif jumpState == STATE_JUMP then
        -- Uncrouch and jump
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))
        cmd:SetButtons(cmd.buttons | IN_JUMP)
        jumpState = STATE_ASCENDING
        return
    elseif jumpState == STATE_ASCENDING then
        -- Ascending after jump
        cmd:SetButtons(cmd.buttons | IN_DUCK)
        if pLocal:EstimateAbsVelocity().z <= 0 then
            jumpState = STATE_DESCENDING
        elseif onGround then
            jumpState = STATE_AWAITING_JUMP --we landed prematurely
        end
        return
    elseif jumpState == STATE_DESCENDING then
        -- Descending
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))

        local predData = Prediction.Player(wLocal, 1, strafeDelta, nil)
        if not predData then return end

        predictedPosition = predData.pos[1]
        print("XD")

        if not predData.onGround[1] or not onGround then
            SmartJump(cmd)
            if shouldJump then
                cmd:SetButtons(cmd.buttons & (~IN_DUCK))
                cmd:SetButtons(cmd.buttons | IN_JUMP)
                jumpState = STATE_CTAP -- Previously STATE_PREPARE_JUMP
            end
        else
            cmd:SetButtons(cmd.buttons | IN_DUCK)
            jumpState = STATE_AWAITING_JUMP -- Previously STATE_IDLE
        end
    end
end

-- OnDraw callback for visual debugging
local function OnDraw()
    pLocal = entities.GetLocalPlayer()
    if not pLocal or not predictedPosition then return end

    -- Draw predicted position
    local screenPredPos = client.WorldToScreen(predictedPosition)
    if not predictedPosition then return end
    if screenPredPos then
        draw.Color(255, 0, 0, 255)  -- Red color
        draw.FilledRect(screenPredPos[1] - 5, screenPredPos[2] - 5, screenPredPos[1] + 5, screenPredPos[2] + 5)
    end

    -- Draw jump peak position
    local screenJumpPeakPos = client.WorldToScreen(jumpPeakPosition)
    if screenJumpPeakPos then
        draw.Color(0, 255, 0, 255)  -- Green color
        draw.FilledRect(screenJumpPeakPos[1] - 5, screenJumpPeakPos[2] - 5, screenJumpPeakPos[1] + 5, screenJumpPeakPos[2] + 5)
    end

    -- Draw bounding box at jump peak position
    local minPoint = HITBOX_MIN + jumpPeakPosition
    local maxPoint = HITBOX_MAX + jumpPeakPosition

    -- Define the vertices of the bounding box
    local vertices = {
        Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
        Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
        Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
        Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
        Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
    }

    -- Convert 3D coordinates to 2D screen coordinates
    for i, vertex in ipairs(vertices) do
        vertices[i] = client.WorldToScreen(vertex)
    end

    -- Draw lines between vertices to visualize the bounding box
    if vertices[1] and vertices[2] and vertices[3] and vertices[4] and
       vertices[5] and vertices[6] and vertices[7] and vertices[8] then
        draw.Color(255, 255, 255, 255)  -- White color
        -- Draw bottom face
        draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
        draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
        draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
        draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])
        -- Draw top face
        draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
        draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
        draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
        draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])
        -- Draw sides
        draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
        draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
        draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
        draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
    end
end

-- Register callbacks
callbacks.Unregister("CreateMove", "SmartJumpNavbot_CreateMove")
callbacks.Register("CreateMove", "SmartJumpNavbot_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "SmartJumpNavbot_Draw")
callbacks.Register("Draw", "SmartJumpNavbot_Draw", OnDraw)
