-- Define the state machine
---@class StateMachine
local StateMachine = {}

-- Function to traverse and execute the state chain
function StateMachine.executeChain(states, chain)
    local currentState = states
    for _, stateIndex in ipairs(chain) do
        if currentState and currentState[stateIndex] then
            currentState[stateIndex].func()
            currentState = currentState[stateIndex].substates
        else
            print("Invalid state chain")
            return
        end
    end
end

--[[Example usage
local chain = {2, 1, 2}
executeStateChain(stateMachine, chain)
]]

return StateMachine