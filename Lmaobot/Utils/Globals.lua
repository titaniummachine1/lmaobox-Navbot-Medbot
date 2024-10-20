-- Define the G module
local G = {}

G.Menu = {
    Tabs = {
        Main = true,
        Settings = false,
        Visuals = false,
        Movement = false,
    },

    Main = {
        Loading = 0,
        Walking = true,
        Skip_Nodes = true, -- skips nodes if it can go directly to ones closer to target.
        Optymise_Path = true,-- straighten the nodes into segments so you would go in straight line
        shouldfindhealth = true, -- Path to health
        SelfHealTreshold = 45, -- Health percentage to start looking for healthPacks
        smoothFactor = 0.05
    },
    Visuals = {
        EnableVisuals = true,
        memoryUsage = true,
        drawNodes = true, -- Draws all nodes on the map
        drawPath = true, -- Draws the path to the current goal
        drawCurrentNode = false, -- Draws the current node
    },
    Movement = {
        lookatpath = false, -- Look at where we are walking
        smoothLookAtPath = true, -- Set this to true to enable smooth look at path
        Smart_Jump = true, -- jumps perfectly before obstacle to be at peek of jump height when at collision point
    }
}

G.Default = {
    flags = 1,
    vHitbox = {Min = Vector3(-24, -24, 0), Max = Vector3(24, 24, 82)},
}

G.pLocal = G.Default

G.World_Default = {
    healthPacks = {},  -- Stores positions of health packs
    spawns = {},       -- Stores positions of spawn points
    payloads = {},     -- Stores payload entities in payload maps
    flags = {},        -- Stores flag entities in CTF maps (implicitly included in the logic)
}

G.World = G.World_Default

G.Gui = {
    IsVisible = false,
}

G.Misc = {
    NodeTouchDistance = 10,
    NodeTouchHeight = 82,
}

G.Navigation = {
    path = nil,
    nodes = nil,
    currentNode = nil,
    currentNodePos = nil,
    currentNodeinPath = 1000,
    currentNodeTicks = 0,
    nodesCount = 0,
}

G.Tasks = {
    None = 0,
    Objective = 1,
    Follow = 2,
    Health = 3,
    Medic = 4,
    Goto = 5,
}

G.Current_Tasks = {}
G.Current_Task = G.Tasks.Objective

G.Benchmark = {
    MemUsage = 0
}

G.StateDefinition = {
    Pathfinding = 1,
    PathWalking = 2,
    Walking = 3,
    Parkour = 4,
    ManualBypass = 5,
}

G.State = nil

function G.ReloadNodes()
    G.Navigation.nodes = G.Navigation.rawNodes
end

return G