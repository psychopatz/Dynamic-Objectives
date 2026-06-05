require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "DO/UI/MissionViewer/DO_MissionViewerShared"

DO_MissionViewerListPanel = ISPanel:derive("DO_MissionViewerListPanel")

local DO = DynamicObjectives

local function T(key, fallback, params)
    if DO and DO.Text and DO.Text.Get then
        return DO.Text.Get(key, params, fallback)
    end
    return fallback or key
end

function DO_MissionViewerListPanel:initialise()
    ISPanel.initialise(self)
end

function DO_MissionViewerListPanel:createChildren()
    ISPanel.createChildren(self)

    self.list = ISScrollingListBox:new(0, 0, self.width, self.height)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 54
    self.list.parentPanel = self
    self.list.doDrawItem = self.list.drawItem
    self.list.drawItem = function(list, y, item, alt)
        return self:drawMissionItem(list, y, item, alt)
    end
    self.list.onMouseDown = function(list, x, y)
        local result = ISScrollingListBox.onMouseDown(list, x, y)
        if list.parentPanel then
            local selected = list:getItem()
            list.parentPanel:onListSelectionChanged(selected and selected.item or nil)
        end
        return result
    end
    self.list:setAnchorLeft(true)
    self.list:setAnchorRight(true)
    self.list:setAnchorTop(true)
    self.list:setAnchorBottom(true)
    self:addChild(self.list)
end

function DO_MissionViewerListPanel:drawMissionItem(list, y, item, alt)
    local summary = item.item or {}
    local width = list:getWidth() - 2
    local statusColor = DO_MissionViewerShared.getStatusColor(summary.status)
    local secondary = DO_MissionViewerShared.getSecondaryText(summary)
    local tertiary = DO_MissionViewerShared.getTertiaryText(summary)
    local badges = {}

    if summary.tracked == true then
        badges[#badges + 1] = T("DOCommon_UI_MissionViewer_BadgeTracked", "TRACKED")
    end
    if summary.located == true then
        badges[#badges + 1] = T("DOCommon_UI_MissionViewer_BadgeLocated", "LOCATED")
    end
    if summary.status ~= "active" then
        badges[#badges + 1] = string.upper(tostring(summary.statusLabel or summary.status))
    end

    list:drawRect(0, y, width, item.height - 2, 0.86, 0.1, 0.1, 0.1)
    if list.selected == item.index then
        list:drawRectBorder(0, y, width, item.height - 2, 0.9, 0.96, 0.8, 0.34)
        list:drawRect(0, y, 4, item.height - 2, 0.9, statusColor.r, statusColor.g, statusColor.b)
    else
        list:drawRectBorder(0, y, width, item.height - 2, 0.35, 0.42, 0.42, 0.42)
    end

    list:drawText(tostring(summary.title or summary.name or item.text or T("DOCommon_UI_MissionViewer_Mission", "Mission")), 12, y + 6, 0.98, 0.98, 0.98, 0.98, UIFont.Small)
    if #badges > 0 then
        list:drawTextRight(table.concat(badges, " | "), width - 10, y + 6, statusColor.r, statusColor.g, statusColor.b, 0.98, UIFont.Small)
    end
    if secondary ~= "" then
        list:drawText(secondary, 12, y + 22, 0.84, 0.86, 0.9, 0.92, UIFont.Small)
    end
    if tertiary ~= "" then
        list:drawText(tertiary, 12, y + 36, 0.72, 0.76, 0.8, 0.88, UIFont.Small)
    end

    return y + item.height
end

function DO_MissionViewerListPanel:onListSelectionChanged(summary)
    self.selectedQuestID = summary and summary.questID or nil
    if self.ownerWindow and self.ownerWindow.onMissionSelected then
        self.ownerWindow:onMissionSelected(summary, self.mode)
    end
end

function DO_MissionViewerListPanel:refreshMissions(preferredQuestID)
    if not self.list then
        return
    end

    local player = DO_MissionViewerShared.getLocalPlayer()
    local provider = self.mode == "done"
        and (DO.Quests and DO.Quests.GetCompletedQuestSummary)
        or (DO.Quests and DO.Quests.GetActiveQuestSummary)
    local entries = provider and provider(player) or {}
    local targetQuestID = preferredQuestID or self.selectedQuestID

    self.list:clear()
    for _, summary in ipairs(entries) do
        self.list:addItem(summary.title or summary.name or summary.questID, summary)
    end

    self:selectQuest(targetQuestID)
    if not self.list:getItem() and #self.list.items > 0 then
        self.list.selected = 1
        self:onListSelectionChanged(self.list.items[1].item)
    end
end

function DO_MissionViewerListPanel:selectQuest(questID)
    self.selectedQuestID = questID
    self.list.selected = -1

    if not questID then
        return false
    end

    for index, entry in ipairs(self.list.items or {}) do
        local summary = entry.item or nil
        if summary and tostring(summary.questID) == tostring(questID) then
            self.list.selected = index
            return true
        end
    end

    return false
end

function DO_MissionViewerListPanel:getSelectedSummary()
    local item = self.list and self.list:getItem() or nil
    return item and item.item or nil
end

function DO_MissionViewerListPanel:update()
    ISPanel.update(self)
    self.refreshTick = (tonumber(self.refreshTick) or 0) + 1
    if self.refreshTick >= 60 then
        self.refreshTick = 0
        self:refreshMissions(self.selectedQuestID)
    end
end

function DO_MissionViewerListPanel:new(x, y, width, height, mode, ownerWindow)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.noBackground = true
    o.mode = mode or "active"
    o.ownerWindow = ownerWindow
    o.refreshTick = 0
    o.selectedQuestID = nil
    return o
end
