--[[ Imports ]]
local Common = require("Lmaobot.Common")
local G = require("Lmaobot.Utils.Globals")
local Visuals = {}

local Log = Common.Log
local Lib = Common.Lib
local Notify = Lib.UI.Notify
local Fonts = Lib.UI.Fonts
local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)


--[[ Functions ]]

local function Draw3DBox(size, pos)
    local halfSize = size / 2
    if not corners then
        corners1 = {
            Vector3(-halfSize, -halfSize, -halfSize),
            Vector3(halfSize, -halfSize, -halfSize),
            Vector3(halfSize, halfSize, -halfSize),
            Vector3(-halfSize, halfSize, -halfSize),
            Vector3(-halfSize, -halfSize, halfSize),
            Vector3(halfSize, -halfSize, halfSize),
            Vector3(halfSize, halfSize, halfSize),
            Vector3(-halfSize, halfSize, halfSize)
        }
    end

    local linesToDraw = {
        {1, 2}, {2, 3}, {3, 4}, {4, 1},
        {5, 6}, {6, 7}, {7, 8}, {8, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
    }

    local screenPositions = {}
    for _, cornerPos in ipairs(corners1) do
        local worldPos = pos + cornerPos
        local screenPos = client.WorldToScreen(worldPos)
        if screenPos then
            table.insert(screenPositions, { x = screenPos[1], y = screenPos[2] })
        end
    end

    for _, line in ipairs(linesToDraw) do
        local p1, p2 = screenPositions[line[1]], screenPositions[line[2]]
        if p1 and p2 then
            draw.Line(p1.x, p1.y, p2.x, p2.y)
        end
    end
end

local function ArrowLine(start_pos, end_pos, arrowhead_length, arrowhead_width, invert)
    if not (start_pos and end_pos) then return end

    -- If invert is true, swap start_pos and end_pos
    if invert then
        start_pos, end_pos = end_pos, start_pos
    end

    -- Calculate direction from start to end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then return end

    -- Normalize the direction vector
    local normalized_direction = Common.Normalize(direction)

    -- Calculate the arrow base position by moving back from end_pos in the direction of start_pos
    local arrow_base = end_pos - normalized_direction * arrowhead_length

    -- Calculate the perpendicular vector for the arrow width
    local perpendicular = Vector3(-normalized_direction.y, normalized_direction.x, 0) * (arrowhead_width / 2)

    -- Convert world positions to screen positions
    local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
    local w2s_arrow_base = client.WorldToScreen(arrow_base)
    local w2s_perp1 = client.WorldToScreen(arrow_base + perpendicular)
    local w2s_perp2 = client.WorldToScreen(arrow_base - perpendicular)

    if not (w2s_start and w2s_end and w2s_arrow_base and w2s_perp1 and w2s_perp2) then return end

    -- Draw the line from start to the base of the arrow (not all the way to the end)
    draw.Line(w2s_start[1], w2s_start[2], w2s_arrow_base[1], w2s_arrow_base[2])

    -- Draw the sides of the arrowhead
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp1[1], w2s_perp1[2])
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp2[1], w2s_perp2[2])

    -- Optionally, draw the base of the arrowhead to close it
    draw.Line(w2s_perp1[1], w2s_perp1[2], w2s_perp2[1], w2s_perp2[2])
end


local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 0, 0, 255)
    local me = entities.GetLocalPlayer()
    if not me then return end

    local myPos = me:GetAbsOrigin()
    local currentY = 120
    G.Navigation.currentNodeinPath = G.Navigation.currentNodeinPath or 1 -- Initialize currentNodeIndex if it's nil
    if G.Navigation.currentNodeinPath == nil then return end

    -- Memory usage
    if G.Menu.Visuals.memoryUsage then
        draw.Text(20, currentY, string.format("Memory usage: %.2f MB", G.Benchmark.MemUsage / 1024))
        currentY = currentY + 20
    end

    -- Auto path informaton
    if G.Menu.Main.Enable then
        draw.Text(20, currentY, string.format("Current Node: %d", G.Navigation.currentNodeinPath))
        currentY = currentY + 20
    end

    -- Draw all nodes
    if G.Menu.Visuals.drawNodes then
        draw.Color(0, 255, 0, 255)

        local navNodes = G.Navigation.nodes

        if navNodes then
            for id, node in pairs(navNodes) do
                local nodePos = node.pos
                local dist = (myPos - nodePos):Length()
                if dist > 700 then goto continue end

                local screenPos = client.WorldToScreen(nodePos)
                if not screenPos then goto continue end

                local x, y = screenPos[1], screenPos[2]
                draw.FilledRect(x - 4, y - 4, x + 4, y + 4)  -- Draw a small square centered at (x, y)

                -- Node IDs
                draw.Text(screenPos[1], screenPos[2] + 10, tostring(id))

                ::continue::
            end
        else
            print("errror printing nodes")
        end
    end

    -- Draw current path
    if G.Menu.Visuals.drawPath and G.State == G.StateDefinition.PathWalking and G.Navigation.path then
        draw.Color(255, 255, 255, 255)

        for i = 1, #G.Navigation.path - 1 do
            local node1 = G.Navigation.path[i]
            local node2 = G.Navigation.path[i + 1]

            local node1Pos = node1.pos
            local node2Pos = node2.pos

            local screenPos1 = client.WorldToScreen(node1Pos)
            local screenPos2 = client.WorldToScreen(node2Pos)
            if not screenPos1 or not screenPos2 then goto continue end

            if node1Pos and node2Pos then
                ArrowLine(node1Pos, node2Pos, 22, 15, true)  -- Adjust the size for the perpendicular segment as needed
            end
            ::continue::
        end

        -- Draw a line from the player to the second node from the end
        local node1 = G.Navigation.path[#G.Navigation.path]
        if node1 then
            node1 = node1.pos
            ArrowLine(myPos, node1, 22, 15, false)
        end
    end

    -- Draw current node
    if G.Menu.Visuals.drawCurrentNode and G.Navigation.path then
        draw.Color(255, 0, 0, 255)

        local currentNode = G.Navigation.path[G.Navigation.currentNodeinPath]
        local currentNodePos = currentNode.pos

        local screenPos = client.WorldToScreen(currentNodePos)
        if screenPos then
            Draw3DBox(20, currentNodePos)
            draw.Text(screenPos[1], screenPos[2] + 40, tostring(G.Navigation.currentNodeinPath))
        end
    end
end

--[[ Callbacks ]]
callbacks.Unregister("Draw", "MCT_Draw") -- unregister the "Draw" callback
callbacks.Register("Draw", "MCT_Draw", OnDraw) -- Register the "Draw" callback 

return Visuals