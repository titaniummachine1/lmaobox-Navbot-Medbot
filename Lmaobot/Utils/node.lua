local Node = {}

local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")

-- Function to process a single node and calculate its position
function Node.createNode(area)
    local cX = (area.north_west.x + area.south_east.x) / 2
    local cY = (area.north_west.y + area.south_east.y) / 2
    local cZ = (area.north_west.z + area.south_east.z) / 2

    return {
        pos = Vector3(cX, cY, cZ),
        id = area.id,
        c = area.connections or {},  -- Ensure connections exist
        nw = area.north_west,
        se = area.south_east,
        visible_areas = area.visible_areas or {}  -- Handle missing visible areas
    }
end

-- Function to reindex nodes sequentially
function Node.reindexNodesSequentially(nodes)
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

-- Function to process connections for a node
function Node.processConnections(node, nodes)
    if node.visible_areas then
        for _, visible in ipairs(node.visible_areas) do
            local visNode = nodes[visible.id]
            if visNode and Common.isWalkable(node.pos, visNode.pos) then
                node.c = node.c or {}
                node.c[5] = node.c[5] or { count = 0, connections = {} }
                table.insert(node.c[5].connections, visNode.id)
                node.c[5].count = node.c[5].count + 1
            end
        end
        node.visible_areas = nil  -- Clear visible_areas once processed
    end
end

-- Function to remove a connection between two nodes
function Node.removeConnection(nodeA, nodeB, nodes)
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

    -- Remove the reverse connection from nodeB to nodeA
    for dir = 1, 4 do
        local conDir = nodeBGlobal.c[dir]
        if conDir then
            for i, con in ipairs(conDir.connections) do
                if con == nodeA.id then
                    table.remove(conDir.connections, i)
                    conDir.count = conDir.count - 1
                    break
                end
            end
        end
    end
end

-- Fix node by adjusting its height
function Node.fixNode(nodeId, nodes, traceFunctions)
    local node = nodes[nodeId]
    if not node or not node.pos then return end

    -- Adjust corners based on trace line results
    local raiseVector = Vector3(0, 0, traceFunctions.Jump_Height)
    node.nw = traceFunctions.traceLineDown(node.nw + raiseVector)
    node.se = traceFunctions.traceLineDown(node.se + raiseVector)

    node.pos = (node.nw + node.se) / 2  -- Update node position to the midpoint
end

-- Fix all nodes by adjusting their positions
function Node.fixAllNodes(nodes, traceFunctions)
    for id in pairs(nodes) do
        Node.fixNode(id, nodes, traceFunctions)
    end
end

-- Get the closest node to a given position
function Node.getClosestNode(pos, nodes)
    local closestNode = nil
    local closestDist = math.huge

    for _, node in pairs(nodes) do
        if node and node.pos then
            local dist = (node.pos - pos):Length()
            if dist < closestDist then
                closestNode = node
                closestDist = dist
            end
        end
    end

    return closestNode
end

-- Clear all nodes
function Node.clearNodes()
    G.Navigation.nodes = {}
    G.Navigation.nodesCount = 0
end

-- Set new nodes into the global state
function Node.setNodes(nodes)
    G.Navigation.nodes = nodes
end

-- Get all nodes from the global state
function Node.getNodes()
    return G.Navigation.nodes
end

-- Get a node by its ID
function Node.getNodeByID(id)
    return G.Navigation.nodes[id]
end

-- Remove the current node from the path
function Node.removeCurrentNode(path)
    table.remove(path[#path])
end

-- Set the current path globally
function Node.setCurrentPath(path)
    G.Navigation.path = path
end

-- Get the current path
function Node.getCurrentPath()
    return G.Navigation.path
end

return Node
