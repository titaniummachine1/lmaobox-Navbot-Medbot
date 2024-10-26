
--[[-- Perform a trace hull down from the given position to the ground
---@param position Vector3 The start position of the trace
---@param hullSize table The size of the hull
---@return Vector3 The normal of the ground at that point
local function traceHullDown(position, hullSize)
    local endPos = position - Vector3(0, 0, DROP_HEIGHT)  -- Adjust the distance as needed
    local traceResult = engine.TraceHull(position, endPos, hullSize.min, hullSize.max, MASK_PLAYERSOLID_BRUSHONLY)
    return traceResult.plane  -- Directly using the plane as the normal
end

-- Perform a trace line down from the given position to the ground
---@param position Vector3 The start position of the trace
---@return Vector3 The hit position
local function traceLineDown(position)
    local endPos = position - Vector3(0, 0, DROP_HEIGHT)
    local traceResult = engine.TraceLine(position, endPos, TRACE_MASK)
    return traceResult.endpos
end

-- Calculate the remaining two corners based on the adjusted corners and ground normal
---@param corner1 Vector3 The first adjusted corner
---@param corner2 Vector3 The second adjusted corner
---@param normal Vector3 The ground normal
---@param height number The height of the rectangle
---@return table The remaining two corners
local function calculateRemainingCorners(corner1, corner2, normal, height)
    local widthVector = corner2 - corner1
    local widthLength = widthVector:Length2D()

    local heightVector = Vector3(-widthVector.y, widthVector.x, 0)

    local function rotateAroundNormal(vector, angle)
        local cosTheta = math.cos(angle)
        local sinTheta = math.sin(angle)
        return Vector3(
            (cosTheta + (1 - cosTheta) * normal.x^2) * vector.x + ((1 - cosTheta) * normal.x * normal.y - normal.z * sinTheta) * vector.y + ((1 - cosTheta) * normal.x * normal.z + normal.y * sinTheta) * vector.z,
            ((1 - cosTheta) * normal.x * normal.y + normal.z * sinTheta) * vector.x + (cosTheta + (1 - cosTheta) * normal.y^2) * vector.y + ((1 - cosTheta) * normal.y * normal.z - normal.x * sinTheta) * vector.z,
            ((1 - cosTheta) * normal.x * normal.z - normal.y * sinTheta) * vector.x + ((1 - cosTheta) * normal.y * normal.z + normal.x * sinTheta) * vector.y + (cosTheta + (1 - cosTheta) * normal.z^2) * vector.z
        )
    end

    local rotatedHeightVector = rotateAroundNormal(heightVector, math.pi / 2)

    local corner3 = corner1 + rotatedHeightVector * (height / widthLength)
    local corner4 = corner2 + rotatedHeightVector * (height / widthLength)

    return { corner3, corner4 }
end

-- Fix a node by adjusting its height based on TraceLine results from the corners
---@param nodeId integer The index of the node in the Nodes table
function Navigation.FixNode(nodeId)
    local nodes = G.Navigation.nodes
    local node = nodes[nodeId]
    if not node or not node.pos then
        print("Node with ID " .. tostring(nodeId) .. " is invalid or missing position, exiting function")
        return
    end

    -- Step 1: Raise the corners by a defined height
    local raiseVector = Vector3(0, 0, Jump_Height)
    local raisedNWPos = node.nw + raiseVector
    local raisedSEPos = node.se + raiseVector

    -- Step 2: Calculate the middle position after raising the corners
    local middlePos = (raisedNWPos + raisedSEPos) / 2

    -- Step 3: Perform trace hull down from the middle position to get the ground normal
    local traceHullSize = {
        -- Clamp the size to player hitbox size to avoid staircase issues
        min = Vector3(math.max(-math.abs(raisedNWPos.x - raisedSEPos.x) / 2, HULL_MIN.x), math.max(-math.abs(raisedNWPos.y - raisedSEPos.y) / 2, HULL_MIN.y), 0),
        max = Vector3(math.min(math.abs(raisedNWPos.x - raisedSEPos.x) / 2, HULL_MAX.x), math.min(math.abs(raisedNWPos.y - raisedSEPos.y) / 2, HULL_MAX.y), 45)
    }

   --local groundNormal = traceHullDown(middlePos, traceHullSize)

    -- Step 4: Calculate the remaining corners based on the ground normal
    --local height = math.abs(node.nw.y - node.se.y)
    --local remainingCorners = calculateRemainingCorners(raisedNWPos, raisedSEPos, groundNormal, height)

    -- Step 5: Adjust corners to align with the ground normal
    raisedNWPos = traceLineDown(raisedNWPos)
    raisedSEPos = traceLineDown(raisedSEPos)
    --remainingCorners[1] = traceLineDown(remainingCorners[1])
    --remainingCorners[2] = traceLineDown(remainingCorners[2])

    -- Step 6: Update node with new corners and position
    node.nw = raisedNWPos
    node.se = raisedSEPos
    --node.ne = remainingCorners[1]
    --node.sw = remainingCorners[2]

    -- Step 7: Recalculate the middle position based on the fixed corners
    local finalMiddlePos = (raisedNWPos + raisedSEPos) / 2
    node.pos = finalMiddlePos

    G.Navigation.nodes[nodeId] = node -- Set the fixed node to the global node
end

-- Adjust all nodes by fixing their positions and adding missing corners.
function Navigation.FixAllNodes()
    --local nodes = Navigation.GetNodes()
    --for id in pairs(nodes) do
        Navigation.FixNode(id)
    end
end]]