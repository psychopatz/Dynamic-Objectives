DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.ObjectiveHooks = DO.ObjectiveHooks or {
    Registry = {},
    Order = {},
}

local Hooks = DO.ObjectiveHooks

local function containsValue(list, value)
    for _, existing in ipairs(list or {}) do
        if existing == value then
            return true
        end
    end
    return false
end

local function addOrderValue(value)
    if not containsValue(Hooks.Order, value) then
        Hooks.Order[#Hooks.Order + 1] = value
    end
end

function DO.RegisterObjectiveHook(id, handler)
    if not id or type(handler) ~= "table" then
        return nil
    end

    local key = tostring(id)
    handler.id = key
    Hooks.Registry[key] = handler
    addOrderValue(key)
    return handler
end

function DO.GetObjectiveHook(id)
    return id and Hooks.Registry[tostring(id)] or nil
end

function DO.GetObjectiveHookList()
    local results = {}
    for _, id in ipairs(Hooks.Order or {}) do
        local entry = Hooks.Registry[id]
        if entry then
            results[#results + 1] = entry
        end
    end
    return results
end
