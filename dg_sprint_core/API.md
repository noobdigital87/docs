## API

### 1. ***dg_sprint_core.register_server_step(***`mod_name`, `step_name`, `step_interval`, `step_callback`***)***

When you register a step using this function, it integrates into the global step process, which is the game's continuous update loop. 

Every time the global step runs, it checks all registered steps and executes them at their defined intervals.

So, instead of modifying the global step directly, you use this system to neatly insert your custom logic at controlled time intervals. 

This helps prevent performance issues while ensuring your mod’s functions execute reliably.

#### Example:
```lua

local mod_name = core.get_current_modname()

local api = dg_sprint_core

local STEP_NAME1 = "STEP1" -- MAKE SURE IT IS UNQIUE WHEN ADDING MORE STEPS
local STEP_NAME2 = "STEP2"

local STEP_INTERVAL1 = 1
local STEP_INTERVAL2 = 0.5

local function STEP1(player, player_data, dtime)
    --[[
        player_data:
            This is an empty table for modders to use to store and retrieve player values through multiple steps.
            What you store in player_data will persist during runtime (data gets deleted after server restart)
    ]]
    if not player_data.count then
        player_data.count = 0
    else
        player_data.count = player_data.count + 1
    end
end

local function STEP2(player, player_data, dtime)
    local name = player:get_player_name()

    local counter = tostring(player_data.count)

    core.chat_send_player(name, counter)
end

-- Registering the steps
api.register_server_step(mod_name, STEP_NAME1, STEP_INTERVAL1, STEP1)
api.register_server_step(mod_name, STEP_NAME2, STEP_INTERVAL2, STEP2)

```

### 2. ***dg_sprint_core.sprint_key_detected(***`player`, `sprint_key`, `tap_key`, `tap_interval`***)***
It detects if a sprint key is pressed or double tap have been detected and returns true when it does.

#### Example:

```lua
local mod_name = core.get_current_modname()

local api = dg_sprint_core

local STEP_NAME1 = "STEP1" 
local STEP_NAME2 = "STEP2"

local STEP_INTERVAL1 = 0.1
local STEP_INTERVAL2 = 0.5

local function STEP1(player, player_data, dtime)
    
    --[[
        I use control.aux1 as sprint key and control.up as double tap key,
        but you can set your own button(s) to detect sprint or double tap.
        The tap interval is set to 0.5 and will detect a sprint if you tap the button twice in that time.
    ]]--
    local control = player:get_player_control()

    -- Option 1: sprint_key and tap_key gets detected 
    player_data.detected = api.sprint_key_detected(player, control.aux1, control.up, 0.5)

    -- Option 2: sprint_key works but tap_key is disabled 
    -- player_data.detected = api.sprint_key_detected(player, control.aux1, false, 0.5)
end

local function STEP2(player, player_data, dtime)
    local name = player:get_player_name()
    if player_data.detected then
        core.chat_send_player(name, "Detected")
    else
        core.chat_send_player(name, "Not Detected")
    end
end

-- Registering the steps
api.register_server_step(mod_name, STEP_NAME1, STEP_INTERVAL1, STEP1)
api.register_server_step(mod_name, STEP_NAME2, STEP_INTERVAL2, STEP2)   
```

---

## TOOLS
