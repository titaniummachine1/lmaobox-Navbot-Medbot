local Node = {}

local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")


-- Clear all nodes
function Node.clearNodes()
    G.Navigation.nodes = {}
    G.Navigation.nodesCount = 0
end

-- Set new nodes into the global state
function Node.SetNodes(nodes)
    G.Navigation.nodes = nodes
end

-- Get all nodes from the global state
function Node.GetNodes()
    return G.Navigation.nodes
end

-- Get a node by its ID
function Node.GetNodeByID(id)
    return G.Navigation.nodes[id]
end

function Node.currentNodePos()
    return G.Navigation.currentNodePos
end

-- Function to process a single node and calculate its position
function Node.create(area)
    local cX = (area.north_west.x + area.south_east.x) / 2
    local cY = (area.north_west.y + area.south_east.y) / 2
    local cZ = (area.north_west.z + area.south_east.z) / 2

    return {
        pos = Vector3(cX, cY, cZ),
        id = area.id,
        c = area.connections or {},  -- Ensure connections exist
        corners = {
            nw = area.north_west,
            se = area.south_east,
        },
    }
end

-- Function to process connections for a node, checking against all nodes
function Node.processConnections(node)
    node.c = node.c or {}  -- Initialize connections table
    local nodes = Node.GetNodes()
    for _, targetNode in pairs(nodes) do
        if targetNode.id ~= node.id and Common.isWalkable(node.pos, targetNode.pos) then
            -- Use a specific direction (e.g., 5) for adding connections
            node.c[5] = node.c[5] or { count = 0, connections = {} }
            table.insert(node.c[5].connections, targetNode.id)
            node.c[5].count = node.c[5].count + 1
        end
    end
end

-- Function to remove a connection between two nodes
function Node.RemoveConnection(nodeA, nodeB)
    local nodes = Node.GetNodes()
    if not nodes or not nodes[nodeA.id] or not nodes[nodeB.id] then return end
    local nodeAGlobal = nodes[nodeA.id]
    local nodeBGlobal = nodes[nodeB.id]

    if not nodeAGlobal or not nodeBGlobal then return end

    -- Remove the connection from nodeA to nodeB
    for dir = 1, 4 do
        local conDir = nodeAGlobal.c[dir]
        if conDir then
            for i, con in ipairs(conDir.connections) do
                if con == nodeBGlobal.id then
                    table.remove(conDir.connections, i)
                    conDir.count = conDir.count - 1
                    break
                end
            end
        end
    end
end

---@param pos Vector3|{ x:number, y:number, z:number }
---@return Node
function Node.GetClosest(pos)
    local closestDist = math.huge
    local nodes = Node.GetNodes()
    local closestNode = {}

    for _, node in pairs(nodes) do
        if node and node.pos then
            local dist = (node.pos - pos):Length()
            if dist < closestDist and Common.isWalkable(pos, node.pos)  then
                closestNode = node
                closestDist = dist
            end
        else
            error("GetClosestNode: Node or node.pos is nil")
        end
    end

    return closestNode
end

-- Function to reindex nodes sequentially
function Node.reindexNodesSequentially()
    local nodes = Node.GetNodes()
    local newNodes = {}
    local idMap = {}  -- Map old IDs to new sequential IDs
    local index = 1   -- Start with the first sequential ID

    -- First pass: assign new sequential IDs while keeping original connections
    for oldID, node in pairs(nodes) do
        idMap[oldID] = index  -- Map old ID to new sequential ID
        node.id = index       -- Assign the new ID
        newNodes[index] = node  -- Store the node in the new table
        index = index + 1
    end

    -- Second pass: update all connections to use the new sequential IDs
    for _, node in pairs(newNodes) do
        if node.c then
            for _, connData in pairs(node.c) do
                if connData.connections then
                    for i, connID in ipairs(connData.connections) do
                        connData.connections[i] = idMap[connID]  -- Update to new ID
                    end
                end
            end
        end
    end

    return newNodes  -- Return the new table with sequential IDs
end

return Node
