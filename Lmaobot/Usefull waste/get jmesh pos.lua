---@param node NavNode
---@param pos Vector3
---@return Vector3
function Navigation.GetMeshPos(node, pos)
    -- Calculate the closest point on the node's 3D plane to the given position
    return Vector3(
        math.max(node.nw.pos.x, math.min(node.se.pos.x, pos.x)),
        math.max(node.nw.pos.y, math.min(node.se.pos.y, pos.y)),
        math.max(node.nw.pos.z, math.min(node.se.pos.z, pos.z))
    )
end