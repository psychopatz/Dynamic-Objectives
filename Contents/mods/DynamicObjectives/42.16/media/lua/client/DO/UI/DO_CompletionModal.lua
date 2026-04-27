require "ISUI/ISPanel"
require "ISUI/ISButton"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_CompletionModal = ISPanel:derive("DO_CompletionModal")
DO_CompletionModal.instance = DO_CompletionModal.instance or nil
DO_CompletionModal.lastCompletedQuestID = DO_CompletionModal.lastCompletedQuestID or nil
DO_CompletionModal.lastCompletedAt = DO_CompletionModal.lastCompletedAt or 0
DO_CompletionModal.initializedCompletionBaseline = DO_CompletionModal.initializedCompletionBaseline or false
DO_CompletionModal.sessionStartedAt = DO_CompletionModal.sessionStartedAt or 0

local DO = DynamicObjectives
local COMPLETION_SOUND = "DO_ObjectiveComplete"
local ITEM_TEXTURE_CACHE = {}
local AUTO_CLOSE_MS = 8000
local ENTRY_STAGGER_MS = 110
local ENTRY_ANIM_MS = 320

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function easeOutCubic(value)
    local t = clamp(tonumber(value) or 0, 0, 1)
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function trimText(value, limit)
    local text = tostring(value or "")
    limit = math.max(4, math.floor(tonumber(limit) or 40))
    if #text <= limit then
        return text
    end
    return text:sub(1, limit - 3) .. "..."
end

local function getItemDisplayName(itemType)
    local value = tostring(itemType or "")
    if value == "" then
        return "Loot"
    end

    local manager = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
    if manager and manager.getItem then
        local scriptItem = manager:getItem(value)
        if scriptItem and scriptItem.getDisplayName then
            return tostring(scriptItem:getDisplayName() or value)
        end
    end

    return tostring(value:match("([^%.]+)$") or value)
end

local function isValidTexture(texture)
    return texture ~= nil and texture ~= false
end

local function tryTexture(textureName)
    if not textureName or textureName == "" or not getTexture then
        return nil
    end

    local texture = getTexture(textureName)
    return isValidTexture(texture) and texture or nil
end

local function getItemBasePrice(itemType)
    local registry = DynamicTrading and DynamicTrading.Config and DynamicTrading.Config.MasterList or nil
    local data = registry and registry[tostring(itemType or "")] or nil
    return math.max(0, math.floor(tonumber(data and data.basePrice) or 0))
end

local function getItemTexture(itemType)
    local key = tostring(itemType or "")
    if key == "" then
        return nil
    end

    local cached = ITEM_TEXTURE_CACHE[key]
    if cached ~= nil then
        return cached or nil
    end

    local manager = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
    local scriptItem = manager and manager.getItem and manager:getItem(key) or nil
    local texture = nil

    if scriptItem and scriptItem.getIcon then
        local iconName = tostring(scriptItem:getIcon() or "")
        if iconName ~= "" then
            texture = tryTexture("Item_" .. iconName)
                or tryTexture(iconName)
                or tryTexture("media/textures/Item_" .. iconName .. ".png")
        end
    end

    if not isValidTexture(texture) then
        local shortType = key:match("([^%.]+)$")
        if shortType and shortType ~= "" then
            texture = tryTexture("Item_" .. shortType)
                or tryTexture("media/textures/Item_" .. shortType .. ".png")
        end
    end

    if not isValidTexture(texture) and InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, item = pcall(InventoryItemFactory.CreateItem, key)
        if ok and item and item.getTex then
            texture = item:getTex()
        end
    end

    ITEM_TEXTURE_CACHE[key] = isValidTexture(texture) and texture or false
    return isValidTexture(texture) and texture or nil
end

local function resolveFactionDisplayName(factionID, fallbackName)
    local fallback = tostring(fallbackName or "")
    if fallback ~= "" then
        return fallback
    end

    if DT_Reputation and DT_Reputation.Internal and DT_Reputation.Internal.GetFactionDisplayName then
        local ok, resolved = pcall(DT_Reputation.Internal.GetFactionDisplayName, factionID)
        if ok and resolved and tostring(resolved) ~= "" then
            return tostring(resolved)
        end
    end

    if DynamicTrading_Factions and DynamicTrading_Factions.GetFaction and factionID then
        local faction = DynamicTrading_Factions.GetFaction(factionID)
        if faction and faction.name and tostring(faction.name) ~= "" then
            return tostring(faction.name)
        end
    end

    local factionData = ModData and ModData.get and ModData.get("DynamicTrading_Factions") or nil
    local faction = factionData and factionData[factionID] or nil
    if faction and faction.name and tostring(faction.name) ~= "" then
        return tostring(faction.name)
    end

    if factionID and tostring(factionID) ~= "" then
        return tostring(factionID)
    end

    return "Faction Recipient"
end

local function buildRecipientSummary(names)
    if type(names) ~= "table" or #names == 0 then
        return "Faction Recipient"
    end
    if #names == 1 then
        return names[1]
    end
    if #names == 2 then
        return names[1] .. " and " .. names[2]
    end
    return names[1] .. " +" .. tostring(#names - 1) .. " more"
end

local function buildRewardSummary(quest)
    local summary = {
        money = 0,
        reputation = 0,
        lootCount = 0,
        lootEntries = {},
        primaryLoot = nil,
        repRecipients = {},
        repRecipientLabel = "Faction Recipient",
    }
    local recipientLookup = {}
    local rewardContext = type(quest and quest.rewardContext) == "table" and quest.rewardContext or {}
    local fallbackRecipient = resolveFactionDisplayName(
        rewardContext.factionID or (quest and quest.giverFactionID) or nil,
        rewardContext.factionName or (quest and quest.giverFactionName) or nil
    )

    for _, reward in ipairs(quest and quest.rewards or {}) do
        if type(reward) == "table" then
            if reward.kind == "money" then
                summary.money = summary.money + math.max(0, math.floor(tonumber(reward.amount) or 0))
            elseif reward.kind == "reputation" then
                local amount = math.floor(tonumber(reward.amount) or 0)
                summary.reputation = summary.reputation + amount
                local recipientName = resolveFactionDisplayName(reward.factionID or rewardContext.factionID, reward.factionName or rewardContext.factionName)
                if recipientName ~= "" and not recipientLookup[recipientName] then
                    recipientLookup[recipientName] = true
                    summary.repRecipients[#summary.repRecipients + 1] = recipientName
                end
            elseif reward.kind == "item" then
                local count = math.max(1, math.floor(tonumber(reward.count) or 1))
                local itemType = tostring(reward.itemType or "")
                local displayName = getItemDisplayName(itemType)
                local unitPrice = getItemBasePrice(itemType)
                summary.lootCount = summary.lootCount + count
                summary.lootEntries[#summary.lootEntries + 1] = {
                    count = count,
                    itemType = itemType,
                    displayName = displayName,
                    texture = getItemTexture(itemType),
                    unitPrice = unitPrice,
                    totalValue = unitPrice * count,
                }
            end
        end
    end

    if #summary.repRecipients == 0 and fallbackRecipient ~= "" then
        summary.repRecipients[1] = fallbackRecipient
    end

    table.sort(summary.lootEntries, function(left, right)
        local leftUnit = tonumber(left and left.unitPrice) or 0
        local rightUnit = tonumber(right and right.unitPrice) or 0
        if leftUnit ~= rightUnit then
            return leftUnit > rightUnit
        end

        local leftTotal = tonumber(left and left.totalValue) or 0
        local rightTotal = tonumber(right and right.totalValue) or 0
        if leftTotal ~= rightTotal then
            return leftTotal > rightTotal
        end

        return tostring(left and left.displayName or "") < tostring(right and right.displayName or "")
    end)

    summary.primaryLoot = summary.lootEntries[1]
    summary.repRecipientLabel = buildRecipientSummary(summary.repRecipients)

    return summary
end

local function getLocalPlayer()
    if DO.GetLocalPlayer then
        return DO.GetLocalPlayer()
    end
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

local function playCompletionSound(player)
    if DT_AudioManager and DT_AudioManager.PlayUISound then
        DT_AudioManager.PlayUISound(COMPLETION_SOUND, 1.0)
        return
    end

    local emitter = player and player.getEmitter and player:getEmitter() or nil
    if emitter and emitter.playSound then
        emitter:playSound(COMPLETION_SOUND)
        return
    end

    local soundManager = getSoundManager and getSoundManager() or nil
    if soundManager and soundManager.PlaySound then
        soundManager:PlaySound(COMPLETION_SOUND, false, 1.0)
    end
end

function DO_CompletionModal:initialise()
    ISPanel.initialise(self)
end

function DO_CompletionModal:createChildren()
    ISPanel.createChildren(self)

    local buttonW = 96
    local buttonH = 26
    self.closeButton = ISButton:new((self.width - buttonW) / 2, self.height - buttonH - 18, buttonW, buttonH, "Close", self, self.onCloseButton)
    self.closeButton:initialise()
    self.closeButton.backgroundColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.85 }
    self.closeButton.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self:addChild(self.closeButton)
end

function DO_CompletionModal:onCloseButton()
    self:setVisible(false)
    self:removeFromUIManager()
    self.addedToUIManager = false
    self.autoCloseAt = 0
end

function DO_CompletionModal:prerender()
    local alpha = self.modalAlpha or 1
    self:drawRect(0, 0, self.width, self.height, 0.9 * alpha, 0.035, 0.04, 0.045)
    self:drawRect(0, 0, self.width, 4, 0.95 * alpha, 0.45, 0.82, 0.42)
    self:drawRectBorder(0, 0, self.width, self.height, 0.72 * alpha, 0.82, 0.92, 0.78)
end

function DO_CompletionModal:getNowMs()
    return DO.NowMs and DO.NowMs() or 0
end

function DO_CompletionModal:getEntryAnimation(index)
    local openedAt = tonumber(self.openedAt) or 0
    if openedAt <= 0 then
        return 1, 0, 1
    end

    local startAt = openedAt + (math.max(0, tonumber(index) or 0) * ENTRY_STAGGER_MS)
    local elapsed = self:getNowMs() - startAt
    local progress = easeOutCubic(elapsed / ENTRY_ANIM_MS)
    local alpha = 0.2 + (0.8 * progress)
    local offsetY = (1 - progress) * 16
    local scale = 0.9 + (0.1 * progress)
    return alpha, offsetY, scale
end

function DO_CompletionModal:drawRewardCard(x, y, w, h, title, value, detail, color, texture, animIndex)
    color = color or { r = 0.75, g = 0.85, b = 1.0 }
    local alpha, offsetY = self:getEntryAnimation(animIndex or 0)
    y = y + offsetY

    self:drawRect(x, y, w, h, 0.54 * alpha, 0.08, 0.1, 0.1)
    self:drawRect(x, y, w, 3, 0.9 * alpha, color.r, color.g, color.b)
    self:drawRectBorder(x, y, w, h, 0.38 * alpha, color.r, color.g, color.b)

    local iconX = x + 10
    local iconY = y + 12
    local iconSize = 34
    if texture then
        self:drawTextureScaled(texture, iconX, iconY, iconSize, iconSize, 0.96 * alpha, 1, 1, 1)
    else
        self:drawRect(iconX, iconY, iconSize, iconSize, 0.28 * alpha, color.r, color.g, color.b)
        self:drawRectBorder(iconX, iconY, iconSize, iconSize, 0.5 * alpha, color.r, color.g, color.b)
        self:drawTextCentre(tostring(title or "?"):sub(1, 1), iconX + (iconSize / 2), iconY + 9, 1, 1, 1, alpha, UIFont.Small)
    end

    self:drawText(tostring(title or ""), x + 52, y + 9, color.r, color.g, color.b, alpha, UIFont.Small)
    self:drawText(tostring(value or ""), x + 52, y + 27, 0.98, 0.98, 0.92, alpha, UIFont.Medium)
    if detail and tostring(detail) ~= "" then
        self:drawText(trimText(tostring(detail), 30), x + 52, y + 52, 0.72, 0.8, 0.74, alpha, UIFont.Small)
    end
end

function DO_CompletionModal:drawLootTile(entry, x, y, w, h, featured, animIndex)
    if not entry then
        return
    end

    local alpha, offsetY, scale = self:getEntryAnimation(animIndex or 0)
    y = y + offsetY
    local drawW = w * scale
    local drawH = h * scale
    local drawX = x + ((w - drawW) / 2)
    local drawY = y + ((h - drawH) / 2)
    local borderColor = featured and { r = 0.72, g = 0.9, b = 0.46 } or { r = 0.56, g = 0.78, b = 0.46 }
    local textureSize = featured and math.min(drawH - 36, 92) or math.min(drawW - 16, drawH - 26)
    local textureX = drawX + (featured and 14 or ((drawW - textureSize) / 2))
    local textureY = drawY + (featured and ((drawH - textureSize) / 2) or 10)

    self:drawRect(drawX, drawY, drawW, drawH, 0.48 * alpha, 0.09, 0.1, 0.09)
    self:drawRect(drawX, drawY, drawW, 3, 0.92 * alpha, borderColor.r, borderColor.g, borderColor.b)
    self:drawRectBorder(drawX, drawY, drawW, drawH, 0.44 * alpha, borderColor.r, borderColor.g, borderColor.b)

    if entry.texture then
        self:drawTextureScaled(entry.texture, textureX, textureY, textureSize, textureSize, 0.98 * alpha, 1, 1, 1)
    else
        self:drawRect(textureX, textureY, textureSize, textureSize, 0.2 * alpha, borderColor.r, borderColor.g, borderColor.b)
        self:drawRectBorder(textureX, textureY, textureSize, textureSize, 0.45 * alpha, borderColor.r, borderColor.g, borderColor.b)
    end

    if featured then
        local textX = textureX + textureSize + 14
        self:drawText("TOP REWARD", textX, drawY + 14, 0.74, 0.94, 0.56, alpha, UIFont.Small)
        self:drawText(trimText(entry.displayName, 24), textX, drawY + 34, 0.98, 0.98, 0.92, alpha, UIFont.Large)
        self:drawText("x" .. tostring(entry.count), textX, drawY + 58, 0.9, 0.94, 0.88, alpha, UIFont.Medium)
        if tonumber(entry.totalValue) and tonumber(entry.totalValue) > 0 then
            self:drawTextRight("$" .. tostring(math.floor(entry.totalValue)) .. " value", drawX + drawW - 14, drawY + drawH - 22, 0.72, 0.82, 0.72, alpha, UIFont.Small)
        end
    else
        self:drawTextCentre("x" .. tostring(entry.count), drawX + (drawW / 2), drawY + drawH - 20, 0.94, 0.96, 0.9, alpha, UIFont.Small)
    end
end

function DO_CompletionModal:drawLootPanel(x, y, w, h, summary)
    local panelAlpha, panelOffset = self:getEntryAnimation(1)
    y = y + panelOffset
    self:drawRect(x, y, w, h, 0.46 * panelAlpha, 0.06, 0.09, 0.06)
    self:drawRect(x, y, w, 3, 0.88 * panelAlpha, 0.64, 0.88, 0.38)
    self:drawRectBorder(x, y, w, h, 0.4 * panelAlpha, 0.62, 0.84, 0.36)
    self:drawText("LOOT", x + 14, y + 11, 0.78, 0.98, 0.56, panelAlpha, UIFont.Small)
    self:drawTextRight(tostring(summary.lootCount or 0) .. " items", x + w - 14, y + 11, 0.94, 0.96, 0.9, panelAlpha, UIFont.Small)

    local primary = summary.primaryLoot
    if not primary then
        self:drawTextCentre("No item rewards", x + (w / 2), y + 72, 0.72, 0.78, 0.72, panelAlpha, UIFont.Medium)
        return
    end

    local innerX = x + 12
    local innerY = y + 30
    local innerW = w - 24
    local innerH = h - 42
    local primaryW = math.floor(innerW * 0.62)
    local secondaryX = innerX + primaryW + 10
    local secondaryW = innerW - primaryW - 10
    local secondaryEntries = summary.lootEntries or {}

    self:drawLootTile(primary, innerX, innerY, primaryW, innerH, true, 2)

    local columns = 2
    local tileGap = 8
    local tileW = math.floor((secondaryW - tileGap) / columns)
    local tileH = math.floor((innerH - tileGap) / 2)
    local drawCount = math.min(4, math.max(0, #secondaryEntries - 1))

    for index = 1, drawCount do
        local entry = secondaryEntries[index + 1]
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local tileX = secondaryX + (column * (tileW + tileGap))
        local tileY = innerY + (row * (tileH + tileGap))
        self:drawLootTile(entry, tileX, tileY, tileW, tileH, false, 2 + index)
    end

    if (#secondaryEntries - 1) > drawCount then
        local remaining = (#secondaryEntries - 1) - drawCount
        self:drawTextRight("+" .. tostring(remaining) .. " more", x + w - 14, y + h - 24, 0.74, 0.82, 0.72, panelAlpha, UIFont.Small)
    end
end

function DO_CompletionModal:render()
    local headerAlpha, headerOffset = self:getEntryAnimation(0)
    local y = 18 + headerOffset
    local countdownRatio = self.autoCloseAt and self.autoCloseAt > 0 and clamp((self.autoCloseAt - self:getNowMs()) / AUTO_CLOSE_MS, 0, 1) or 0

    self:drawTextCentre("Objective Complete", self.width / 2, y, 0.98, 0.98, 0.92, headerAlpha, UIFont.Medium)
    self:drawTextCentre(trimText(self.questName or "Completed", 52), self.width / 2, y + 28, 0.68, 0.9, 1.0, headerAlpha, UIFont.Small)
    self:drawRect(22, 72, self.width - 44, 4, 0.3, 0.18, 0.2, 0.18)
    self:drawRect(22, 72, (self.width - 44) * countdownRatio, 4, 0.82, 0.64, 0.88, 0.38)

    local summary = self.rewardSummary or {}
    local moneyValue = "$" .. tostring(math.max(0, tonumber(summary.money) or 0))
    local repAmount = math.floor(tonumber(summary.reputation) or 0)
    local repValue = repAmount >= 0 and ("+" .. tostring(repAmount)) or tostring(repAmount)
    local repDetail = "Recipient: " .. tostring(summary.repRecipientLabel or "Faction Recipient")

    self:drawLootPanel(18, 88, self.width - 36, 176, summary)
    local metricY = 278
    local metricW = math.floor((self.width - 46) / 2)
    self:drawRewardCard(18, metricY, metricW, 70, "CASH", moneyValue, "Immediate payout", { r = 0.95, g = 0.86, b = 0.34 }, self.moneyTexture, 7)
    self:drawRewardCard(28 + metricW, metricY, metricW, 70, "REP", repValue, repDetail, { r = 0.44, g = 0.76, b = 1.0 }, nil, 8)
    ISPanel.render(self)
end

function DO_CompletionModal:applyQuest(quest)
    self.questID = quest and quest.id or nil
    self.questName = quest and quest.name or "Completed"
    self.rewardSummary = buildRewardSummary(quest)
    self.moneyTexture = getTexture and getTexture("Item_Money") or nil
    self.openedAt = self:getNowMs()
    self.autoCloseAt = self.openedAt + AUTO_CLOSE_MS
    self.modalAlpha = 1
    self.remainingSeconds = math.ceil(AUTO_CLOSE_MS / 1000)
    if self.closeButton and self.closeButton.setTitle then
        self.closeButton:setTitle("Close (" .. tostring(self.remainingSeconds) .. ")")
    end

    local core = getCore and getCore() or nil
    if core then
        self:setX((core:getScreenWidth() - self.width) / 2)
        self:setY((core:getScreenHeight() - self.height) / 2)
    end
    if self.closeButton then
        local buttonW = self.closeButton.width or 96
        local buttonH = self.closeButton.height or 26
        self.closeButton:setX((self.width - buttonW) / 2)
        self.closeButton:setY(self.height - buttonH - 18)
    end
end

function DO_CompletionModal:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.noBackground = true
    o.questID = nil
    o.questName = nil
    o.rewardSummary = {}
    o.moneyTexture = nil
    o.addedToUIManager = false
    o.openedAt = 0
    o.autoCloseAt = 0
    o.remainingSeconds = 0
    o.modalAlpha = 1
    return o
end

function DO_CompletionModal.Open(quest)
    local modal = DO_CompletionModal.instance
    if not modal then
        modal = DO_CompletionModal:new(0, 0, 500, 420)
        modal:initialise()
        modal:instantiate()
        DO_CompletionModal.instance = modal
    end
    modal:setWidth(500)
    modal:setHeight(420)

    modal:applyQuest(quest)
    if modal.addedToUIManager ~= true then
        modal:addToUIManager()
        modal.addedToUIManager = true
    end
    modal:setVisible(true)
    modal:bringToTop()
    playCompletionSound(getLocalPlayer())
    return modal
end

function DO_CompletionModal:update()
    ISPanel.update(self)

    if not self:getIsVisible() then
        return
    end

    local now = self:getNowMs()
    if self.autoCloseAt and self.autoCloseAt > 0 then
        local remainingMs = self.autoCloseAt - now
        if remainingMs <= 0 then
            self:onCloseButton()
            return
        end

        local remainingSeconds = math.max(1, math.ceil(remainingMs / 1000))
        if remainingSeconds ~= self.remainingSeconds then
            self.remainingSeconds = remainingSeconds
            if self.closeButton and self.closeButton.setTitle then
                self.closeButton:setTitle("Close (" .. tostring(remainingSeconds) .. ")")
            end
        end
    end
end

local function processLatestCompletedQuest(player)
    if not player or not DO.Quests or not DO.Quests.GetLatestCompletedQuest then
        return nil
    end

    local quest = DO.Quests.GetLatestCompletedQuest(player)
    if not quest or tonumber(quest.completedAt) == nil then
        if DO_CompletionModal.initializedCompletionBaseline ~= true then
            DO_CompletionModal.initializedCompletionBaseline = true
        end
        return nil
    end

    local completedAt = tonumber(quest.completedAt) or 0
    if DO_CompletionModal.sessionStartedAt <= 0 and DO.NowMs then
        DO_CompletionModal.sessionStartedAt = tonumber(DO.NowMs()) or 0
    end

    if DO_CompletionModal.initializedCompletionBaseline ~= true then
        DO_CompletionModal.initializedCompletionBaseline = true
        if DO_CompletionModal.sessionStartedAt > 0 and completedAt < DO_CompletionModal.sessionStartedAt then
            DO_CompletionModal.lastCompletedQuestID = quest.id
            DO_CompletionModal.lastCompletedAt = completedAt
            return nil
        end
    end

    if DO_CompletionModal.sessionStartedAt > 0 and completedAt < DO_CompletionModal.sessionStartedAt then
        DO_CompletionModal.lastCompletedQuestID = quest.id
        DO_CompletionModal.lastCompletedAt = math.max(completedAt, tonumber(DO_CompletionModal.lastCompletedAt) or 0)
        return nil
    end

    if DO_CompletionModal.lastCompletedQuestID == quest.id and completedAt <= (DO_CompletionModal.lastCompletedAt or 0) then
        return nil
    end

    DO_CompletionModal.lastCompletedQuestID = quest.id
    DO_CompletionModal.lastCompletedAt = completedAt
    return DO_CompletionModal.Open(quest)
end

function DO_CompletionModal.ProcessLatestCompletedQuest(player)
    return processLatestCompletedQuest(player or getLocalPlayer())
end

local function onTick()
    DO_CompletionModal.ProcessLatestCompletedQuest(getLocalPlayer())
end

local function onGameStart()
    if DO_CompletionModal.instance and DO_CompletionModal.instance.addedToUIManager == true then
        DO_CompletionModal.instance:setVisible(false)
        DO_CompletionModal.instance:removeFromUIManager()
        DO_CompletionModal.instance.addedToUIManager = false
    end
    DO_CompletionModal.sessionStartedAt = 0
    DO_CompletionModal.initializedCompletionBaseline = false
    DO_CompletionModal.lastCompletedQuestID = nil
    DO_CompletionModal.lastCompletedAt = 0
end

if Events then
    if Events.OnTick then
        Events.OnTick.Add(onTick)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(onGameStart)
    end
end
