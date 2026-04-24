require "DO/UI/Debug/DO_DebugWindow"

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if not isDebugEnabled() then
        return
    end

    context:addOption("[DEBUG] Dynamic Objectives", nil, DO_DebugWindow.OnOpen)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
