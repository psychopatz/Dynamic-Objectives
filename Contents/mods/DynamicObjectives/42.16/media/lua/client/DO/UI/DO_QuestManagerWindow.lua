DynamicObjectives = DynamicObjectives or {}

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISLabel"
require "ISUI/ISPanel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "DO/UI/DO_QuestPresetIO"

DO_QuestManagerWindow = ISCollapsableWindow:derive("DO_QuestManagerWindow")
DO_QuestManagerWindow.instance = nil

local DO = DynamicObjectives

local function trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function splitList(text, delimiterPattern)
    local results = {}
    local source = tostring(text or "")
    delimiterPattern = delimiterPattern or "[^,]+"
    for token in string.gmatch(source, delimiterPattern) do
        local cleaned = trim(token)
        if cleaned ~= "" then
            results[#results + 1] = cleaned
        end
    end
    return results
end

local function joinList(items, separator)
    return table.concat(items or {}, separator or ", ")
end

local function getLocalPlayer()
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

local function parseWeightedItemPool(text)
    local entries = {}
    local errors = {}

    for _, token in ipairs(splitList(text, "[^,]+")) do
        local itemType, weightText = string.match(token, "^([^@|]+)[@|]([%d%.]+)$")
        if not itemType then
            errors[#errors + 1] = "Invalid pool entry: " .. token
        else
            entries[#entries + 1] = {
                itemType = trim(itemType),
                weight = tonumber(weightText) or 1,
            }
        end
    end

    return entries, errors
end

local function formatWeightedItemPool(poolID)
    local pool = poolID and DO.GetQuestLootPool and DO.GetQuestLootPool(poolID) or nil
    if not pool then
        return ""
    end

    local parts = {}
    for _, entry in ipairs(pool.entries or {}) do
        if entry.itemType then
            parts[#parts + 1] = tostring(entry.itemType) .. "@" .. tostring(entry.weight or 1)
        end
    end
    return table.concat(parts, ", ")
end

local function parseRewardPool(text)
    local entries = {}
    local errors = {}

    for _, bundleToken in ipairs(splitList(text, "[^;]+")) do
        local payload, weightText = string.match(bundleToken, "^(.-)@([%d%.]+)$")
        payload = trim(payload)
        if payload == "" then
            errors[#errors + 1] = "Invalid reward bundle: " .. bundleToken
        else
            local rewards = {}
            for _, rewardToken in ipairs(splitList(payload, "[^+]+")) do
                local key, value = string.match(rewardToken, "^([^:]+):(.+)$")
                key = trim(key)
                value = trim(value)
                if key == "money" then
                    rewards[#rewards + 1] = { kind = "money", amount = tonumber(value) or 0 }
                elseif key == "rep" then
                    rewards[#rewards + 1] = { kind = "reputation", amount = tonumber(value) or 0 }
                elseif key == "item" then
                    local itemType, countText = string.match(value, "^([^*]+)%*(%d+)$")
                    rewards[#rewards + 1] = {
                        kind = "item",
                        itemType = trim(itemType or value),
                        count = tonumber(countText) or 1,
                    }
                elseif key == "recruit" then
                    local parts = splitList(value, "[^|]+")
                    rewards[#rewards + 1] = {
                        kind = "recruit",
                        count = 1,
                        template = {
                            profession = parts[1],
                            jobType = parts[2],
                            name = parts[3],
                        },
                    }
                else
                    errors[#errors + 1] = "Unknown reward token: " .. rewardToken
                end
            end

            entries[#entries + 1] = {
                weight = tonumber(weightText) or 1,
                rewards = rewards,
            }
        end
    end

    return entries, errors
end

local function formatRewardPool(poolID)
    local pool = poolID and DO.GetQuestLootPool and DO.GetQuestLootPool(poolID) or nil
    if not pool then
        return ""
    end

    local bundles = {}
    for _, entry in ipairs(pool.entries or {}) do
        local rewardParts = {}
        for _, reward in ipairs(entry.rewards or {}) do
            if reward.kind == "money" then
                rewardParts[#rewardParts + 1] = "money:" .. tostring(reward.amount or 0)
            elseif reward.kind == "reputation" then
                rewardParts[#rewardParts + 1] = "rep:" .. tostring(reward.amount or 0)
            elseif reward.kind == "item" then
                rewardParts[#rewardParts + 1] = "item:" .. tostring(reward.itemType or "") .. "*" .. tostring(reward.count or 1)
            elseif reward.kind == "recruit" then
                local template = reward.template or {}
                rewardParts[#rewardParts + 1] = "recruit:" .. table.concat({
                    tostring(template.profession or ""),
                    tostring(template.jobType or ""),
                    tostring(template.name or ""),
                }, "|")
            end
        end
        if #rewardParts > 0 then
            bundles[#bundles + 1] = table.concat(rewardParts, "+") .. "@" .. tostring(entry.weight or 1)
        end
    end

    return table.concat(bundles, "; ")
end

local function ensurePoolID(baseID, suffix, explicitID)
    local value = trim(explicitID)
    if value ~= "" then
        return value
    end
    return tostring(baseID) .. "_" .. tostring(suffix)
end

function DO_QuestManagerWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function DO_QuestManagerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 10
    local th = self:titleBarHeight()
    local leftW = 280
    local rightX = leftW + (pad * 2)
    local rightW = self.width - rightX - pad
    local y = th + pad

    self.searchEntry = ISTextEntryBox:new("", pad, y, 170, 22)
    self.searchEntry:initialise()
    self:addChild(self.searchEntry)

    self.familyFilter = ISComboBox:new(pad + 176, y, 94, 22)
    self.familyFilter:initialise()
    self.familyFilter:addOption("All")
    self.familyFilter:addOption("Courier")
    self.familyFilter:addOption("KillZone")
    self.familyFilter:addOption("HuntDrop")
    self.familyFilter.selected = 1
    self:addChild(self.familyFilter)
    y = y + 28

    self.blueprintList = ISScrollingListBox:new(pad, y, leftW - pad, self.height - y - 160)
    self.blueprintList:initialise()
    self.blueprintList.doDrawItem = self.blueprintList.drawItem
    self.blueprintList.drawItem = function(list, yPos, item, alt)
        list:drawRect(0, yPos, list:getWidth() - 2, item.height - 2, 0.9, 0.12, 0.12, 0.12)
        if list.selected == item.index then
            list:drawRectBorder(0, yPos, list:getWidth() - 2, item.height - 2, 0.9, 0.7, 0.5, 0.2)
        else
            list:drawRectBorder(0, yPos, list:getWidth() - 2, item.height - 2, 0.5, 0.3, 0.3, 0.3)
        end
        list:drawText(item.text, 8, yPos + 6, 0.95, 0.95, 0.95, 1, UIFont.Small)
        return yPos + item.height
    end
    self:addChild(self.blueprintList)

    local btnY = self.blueprintList:getY() + self.blueprintList:getHeight() + 6
    self.btnRefresh = ISButton:new(pad, btnY, 84, 24, "Refresh", self, self.onRefreshList)
    self.btnRefresh:initialise()
    self:addChild(self.btnRefresh)

    self.btnCreate = ISButton:new(pad + 88, btnY, 84, 24, "Create", self, self.onCreatePreset)
    self.btnCreate:initialise()
    self:addChild(self.btnCreate)

    self.btnClone = ISButton:new(pad + 176, btnY, 84, 24, "Clone", self, self.onClonePreset)
    self.btnClone:initialise()
    self:addChild(self.btnClone)

    btnY = btnY + 28
    self.btnDelete = ISButton:new(pad, btnY, 84, 24, "Delete", self, self.onDeletePreset)
    self.btnDelete:initialise()
    self.btnDelete.backgroundColor = { r = 0.4, g = 0.1, b = 0.1, a = 1.0 }
    self:addChild(self.btnDelete)

    self.btnToggle = ISButton:new(pad + 88, btnY, 84, 24, "Enable/Off", self, self.onTogglePreset)
    self.btnToggle:initialise()
    self:addChild(self.btnToggle)

    self.fileEntry = ISTextEntryBox:new("custom", pad + 176, btnY, 84, 24)
    self.fileEntry:initialise()
    self:addChild(self.fileEntry)
    btnY = btnY + 28

    self.btnImport = ISButton:new(pad, btnY, 124, 24, "Import File", self, self.onImportPreset)
    self.btnImport:initialise()
    self:addChild(self.btnImport)

    self.btnExport = ISButton:new(pad + 128, btnY, 132, 24, "Export File", self, self.onExportPreset)
    self.btnExport:initialise()
    self:addChild(self.btnExport)

    local sectionY = th + pad
    local labelW = 110
    local inputW = 170
    local gap = 6

    local function addLabel(text, x, rowY)
        local label = ISLabel:new(x, rowY + 4, 18, text, 1, 1, 1, 1, UIFont.Small, true)
        label:initialise()
        self:addChild(label)
        return label
    end

    local function addEntry(defaultText, x, rowY, width)
        local entry = ISTextEntryBox:new(defaultText or "", x, rowY, width, 22)
        entry:initialise()
        self:addChild(entry)
        return entry
    end

    addLabel("Preset ID", rightX, sectionY)
    self.idEntry = addEntry("", rightX + labelW, sectionY, inputW)
    addLabel("Name", rightX + labelW + inputW + gap, sectionY)
    self.nameEntry = addEntry("", rightX + labelW + inputW + gap + 42, sectionY, 180)
    sectionY = sectionY + 28

    addLabel("Family", rightX, sectionY)
    self.familyEntry = ISComboBox:new(rightX + labelW, sectionY, inputW, 22)
    self.familyEntry:initialise()
    self.familyEntry:addOption("Courier")
    self.familyEntry:addOption("KillZone")
    self.familyEntry:addOption("HuntDrop")
    self.familyEntry.selected = 1
    self:addChild(self.familyEntry)
    addLabel("Weight", rightX + labelW + inputW + gap, sectionY)
    self.weightEntry = addEntry("1", rightX + labelW + inputW + gap + 42, sectionY, 60)
    addLabel("Difficulty", rightX + labelW + inputW + gap + 108, sectionY)
    self.difficultyEntry = addEntry("1.0", rightX + labelW + inputW + gap + 168, sectionY, 54)
    addLabel("Timer", rightX + labelW + inputW + gap + 228, sectionY)
    self.timerEntry = addEntry("0", rightX + labelW + inputW + gap + 266, sectionY, 44)
    addLabel("Cooldown", rightX + labelW + inputW + gap + 316, sectionY)
    self.cooldownEntry = addEntry("24", rightX + labelW + inputW + gap + 376, sectionY, 44)
    sectionY = sectionY + 28

    addLabel("States", rightX, sectionY)
    self.statesEntry = addEntry("Resting", rightX + labelW, sectionY, 150)
    addLabel("Archetypes", rightX + labelW + 156, sectionY)
    self.archetypeEntry = addEntry("", rightX + labelW + 228, sectionY, 150)
    addLabel("Factions", rightX + labelW + 384, sectionY)
    self.factionEntry = addEntry("", rightX + labelW + 442, sectionY, 140)
    sectionY = sectionY + 28

    addLabel("Target Label", rightX, sectionY)
    self.targetLabelEntry = addEntry("", rightX + labelW, sectionY, 190)
    addLabel("Purpose", rightX + labelW + 196, sectionY)
    self.targetPurposeEntry = addEntry("Objective Site", rightX + labelW + 250, sectionY, 190)
    addLabel("Radius", rightX + labelW + 446, sectionY)
    self.targetRadiusEntry = addEntry("20", rightX + labelW + 490, sectionY, 44)
    sectionY = sectionY + 28

    addLabel("Grant Pool ID", rightX, sectionY)
    self.grantPoolIDEntry = addEntry("", rightX + labelW, sectionY, 180)
    addLabel("Grant Items", rightX + labelW + 186, sectionY)
    self.grantPoolTextEntry = addEntry("", rightX + labelW + 248, sectionY, 286)
    sectionY = sectionY + 28

    addLabel("Drop Pool ID", rightX, sectionY)
    self.dropPoolIDEntry = addEntry("", rightX + labelW, sectionY, 180)
    addLabel("Drop Items", rightX + labelW + 186, sectionY)
    self.dropPoolTextEntry = addEntry("", rightX + labelW + 248, sectionY, 286)
    sectionY = sectionY + 28

    addLabel("Reward Pool ID", rightX, sectionY)
    self.rewardPoolIDEntry = addEntry("", rightX + labelW, sectionY, 180)
    addLabel("Reward Bundles", rightX + labelW + 186, sectionY)
    self.rewardPoolTextEntry = addEntry("", rightX + labelW + 286, sectionY, 248)
    sectionY = sectionY + 28

    addLabel("Dialogue ID", rightX, sectionY)
    self.dialogueIDEntry = addEntry("", rightX + labelW, sectionY, 180)
    addLabel("Encounter Count", rightX + labelW + 186, sectionY)
    self.encounterCountEntry = addEntry("8", rightX + labelW + 286, sectionY, 50)
    addLabel("Spawn Radius", rightX + labelW + 342, sectionY)
    self.spawnRadiusEntry = addEntry("18", rightX + labelW + 424, sectionY, 44)
    addLabel("Clear Radius", rightX + labelW + 474, sectionY)
    self.clearRadiusEntry = addEntry("28", rightX + labelW + 550, sectionY, 44)
    sectionY = sectionY + 28

    addLabel("Kill Label", rightX, sectionY)
    self.killLabelEntry = addEntry("", rightX + labelW, sectionY, 180)
    addLabel("Drop Label", rightX + labelW + 186, sectionY)
    self.dropLabelEntry = addEntry("", rightX + labelW + 248, sectionY, 170)
    addLabel("Spawn After", rightX + labelW + 424, sectionY)
    self.spawnAfterEntry = addEntry("4", rightX + labelW + 494, sectionY, 40)
    addLabel("Deliver Label", rightX + labelW + 540, sectionY)
    self.deliverLabelEntry = addEntry("", rightX + labelW + 616, sectionY, 160)
    sectionY = sectionY + 28

    addLabel("Offer Text", rightX, sectionY)
    self.offerTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Details", rightX, sectionY)
    self.detailsTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Rewards", rightX, sectionY)
    self.rewardsTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Accept", rightX, sectionY)
    self.acceptTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Decline", rightX, sectionY)
    self.declineTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Active", rightX, sectionY)
    self.activeTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 28
    addLabel("Unavailable", rightX, sectionY)
    self.unavailableTextEntry = addEntry("", rightX + labelW, sectionY, rightW - labelW - 20)
    sectionY = sectionY + 32

    self.btnValidate = ISButton:new(rightX, sectionY, 100, 24, "Validate", self, self.onValidatePreset)
    self.btnValidate:initialise()
    self:addChild(self.btnValidate)
    self.btnSave = ISButton:new(rightX + 104, sectionY, 100, 24, "Save", self, self.onSavePreset)
    self.btnSave:initialise()
    self:addChild(self.btnSave)
    self.btnTest = ISButton:new(rightX + 208, sectionY, 120, 24, "Start Test Quest", self, self.onTestPreset)
    self.btnTest:initialise()
    self:addChild(self.btnTest)
    sectionY = sectionY + 30

    self.previewPanel = ISRichTextPanel:new(rightX, sectionY, rightW, 120)
    self.previewPanel:initialise()
    self.previewPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
    self.previewPanel.text = "Quest preview will appear here."
    self.previewPanel.autosetheight = false
    self.previewPanel.clip = true
    self.previewPanel.marginLeft = 8
    self.previewPanel.marginTop = 8
    self.previewPanel.marginBottom = 8
    self:addChild(self.previewPanel)
    sectionY = sectionY + 126

    self.activeLabel = ISLabel:new(rightX, sectionY, 18, "Active Quests", 1, 1, 1, 1, UIFont.Small, true)
    self.activeLabel:initialise()
    self:addChild(self.activeLabel)
    sectionY = sectionY + 20

    self.activeQuestList = ISScrollingListBox:new(rightX, sectionY, rightW, 110)
    self.activeQuestList:initialise()
    self:addChild(self.activeQuestList)

    self.refreshCounter = 0
    self:refreshBlueprintList()
    self:refreshActiveQuestMonitor()
    self:onCreatePreset()
end

function DO_QuestManagerWindow:getSelectedBlueprintID()
    local item = self.blueprintList and self.blueprintList:getItem() or nil
    return item and item.item or nil
end

function DO_QuestManagerWindow:getFilteredBlueprints()
    local results = {}
    local search = lower(self.searchEntry and self.searchEntry:getText() or "")
    local familyFilter = self.familyFilter and self.familyFilter:getOptionText(self.familyFilter.selected) or "All"

    for _, blueprint in ipairs(DO.GetQuestBlueprintList and DO.GetQuestBlueprintList() or {}) do
        local matchesSearch = search == ""
            or string.find(lower(blueprint.id), search, 1, true)
            or string.find(lower(blueprint.name), search, 1, true)
        local matchesFamily = familyFilter == "All" or tostring(blueprint.family or "") == familyFilter
        if matchesSearch and matchesFamily then
            results[#results + 1] = blueprint
        end
    end

    table.sort(results, function(left, right)
        return lower(left.name or left.id) < lower(right.name or right.id)
    end)

    return results
end

function DO_QuestManagerWindow:refreshBlueprintList(preferredID)
    preferredID = preferredID or self:getSelectedBlueprintID()
    self.blueprintList:clear()

    for _, blueprint in ipairs(self:getFilteredBlueprints()) do
        local suffix = blueprint.enabled == false and " [Disabled]" or ""
        local line = string.format("%s (%s)%s", tostring(blueprint.name or blueprint.id), tostring(blueprint.family or "?"), suffix)
        self.blueprintList:addItem(line, blueprint.id)
    end

    if preferredID then
        for index, item in ipairs(self.blueprintList.items or {}) do
            if item and item.item == preferredID then
                self.blueprintList.selected = index
                break
            end
        end
    end
end

function DO_QuestManagerWindow:buildPackageFromEditor()
    local blueprintID = trim(self.idEntry:getText())
    if blueprintID == "" then
        return nil, { "Preset ID is required." }
    end

    local family = self.familyEntry:getOptionText(self.familyEntry.selected)
    local grantPoolID = ensurePoolID(blueprintID, "grant_pool", self.grantPoolIDEntry:getText())
    local dropPoolID = ensurePoolID(blueprintID, "drop_pool", self.dropPoolIDEntry:getText())
    local rewardPoolID = ensurePoolID(blueprintID, "reward_pool", self.rewardPoolIDEntry:getText())
    local dialogueID = ensurePoolID(blueprintID, "dialogue", self.dialogueIDEntry:getText())

    local grantEntries, grantErrors = parseWeightedItemPool(self.grantPoolTextEntry:getText())
    local dropEntries, dropErrors = parseWeightedItemPool(self.dropPoolTextEntry:getText())
    local rewardEntries, rewardErrors = parseRewardPool(self.rewardPoolTextEntry:getText())

    local errors = {}
    for _, list in ipairs({ grantErrors, dropErrors, rewardErrors }) do
        for _, message in ipairs(list) do
            errors[#errors + 1] = message
        end
    end

    local blueprint = DO.DeepCopy(self.loadedBlueprint or {})
    blueprint.id = blueprintID
    blueprint.name = trim(self.nameEntry:getText()) ~= "" and trim(self.nameEntry:getText()) or blueprintID
    blueprint.family = family
    blueprint.enabled = true
    blueprint.weight = tonumber(self.weightEntry:getText()) or 1
    blueprint.difficulty = tonumber(self.difficultyEntry:getText()) or 1.0
    blueprint.timeLimitHours = tonumber(self.timerEntry:getText()) or 0
    blueprint.cooldown = tonumber(self.cooldownEntry:getText()) or 0
    blueprint.eligibility = {
        traderStates = splitList(self.statesEntry:getText()),
        archetypes = splitList(self.archetypeEntry:getText()),
        factionIDs = splitList(self.factionEntry:getText()),
    }
    blueprint.target = {
        label = trim(self.targetLabelEntry:getText()),
        purpose = trim(self.targetPurposeEntry:getText()),
        radius = tonumber(self.targetRadiusEntry:getText()) or 20,
    }
    blueprint.rewardPools = { rewardPoolID }
    blueprint.dialogueTree = dialogueID
    blueprint.objective = {
        label = trim(self.killLabelEntry:getText()),
        killLabel = trim(self.killLabelEntry:getText()),
        dropLabel = trim(self.dropLabelEntry:getText()),
        deliverLabel = trim(self.deliverLabelEntry:getText()),
        spawnAfterKills = tonumber(self.spawnAfterEntry:getText()) or 4,
        consumeOnComplete = true,
        completeRemainingObjectives = true,
        completeQuestOnComplete = true,
    }

    if family == "Courier" then
        blueprint.grantItemPool = grantPoolID
    elseif family == "HuntDrop" then
        blueprint.dropItemPool = dropPoolID
    end

    if family == "KillZone" or family == "HuntDrop" then
        blueprint.encounter = {
            id = blueprintID .. "_encounter",
            kind = family == "KillZone" and "kill_zone" or "hunt_drop",
            baseCount = tonumber(self.encounterCountEntry:getText()) or 8,
            spawnRadius = tonumber(self.spawnRadiusEntry:getText()) or 18,
            clearRadius = tonumber(self.clearRadiusEntry:getText()) or 28,
            spawnMode = "building",
            requireAreaClear = true,
            requirePlayerPresence = true,
        }
    end

    if blueprint.objective.label == "" then
        blueprint.objective.label = family == "Courier" and "Deliver the package" or "Eliminate the infestation"
    end
    if blueprint.objective.killLabel == "" then
        blueprint.objective.killLabel = family == "HuntDrop" and "Purge the marked cluster" or blueprint.objective.label
    end
    if blueprint.objective.dropLabel == "" then
        blueprint.objective.dropLabel = "Recover the objective"
    end
    if blueprint.objective.deliverLabel == "" then
        blueprint.objective.deliverLabel = "Deliver the package"
    end

    local package = {
        id = blueprintID,
        blueprint = blueprint,
        lootPools = {
            [rewardPoolID] = { id = rewardPoolID, entries = rewardEntries },
        },
        dialogueTrees = {
            [dialogueID] = {
                id = dialogueID,
                choices = {
                    accept = "Accept",
                    details = "Tell me more",
                    rewards = "What's the reward?",
                    decline = "Not now",
                    back = "Back",
                },
                nodes = {
                    offer = { text = self.offerTextEntry:getText() },
                    details = { text = self.detailsTextEntry:getText() },
                    rewards = { text = self.rewardsTextEntry:getText() },
                    accept = { text = self.acceptTextEntry:getText() },
                    decline = { text = self.declineTextEntry:getText() },
                    active = { text = self.activeTextEntry:getText() },
                    unavailable = { text = self.unavailableTextEntry:getText() },
                },
            },
        },
    }

    if family == "Courier" then
        package.lootPools[grantPoolID] = { id = grantPoolID, entries = grantEntries }
    elseif family == "HuntDrop" then
        package.lootPools[dropPoolID] = { id = dropPoolID, entries = dropEntries }
    end

    if #errors > 0 then
        return package, errors
    end

    return package, {}
end

function DO_QuestManagerWindow:loadBlueprintIntoEditor(blueprintID)
    local blueprint = blueprintID and DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if not blueprint then
        return
    end

    self.loadedBlueprint = DO.DeepCopy(blueprint)

    self.idEntry:setText(tostring(blueprint.id or ""))
    self.nameEntry:setText(tostring(blueprint.name or blueprint.id or ""))
    self.familyEntry.selected = ({ Courier = 1, KillZone = 2, HuntDrop = 3 })[tostring(blueprint.family or "Courier")] or 1
    self.weightEntry:setText(tostring(blueprint.weight or 1))
    self.difficultyEntry:setText(tostring(blueprint.difficulty or blueprint.baseDifficulty or 1.0))
    self.timerEntry:setText(tostring(blueprint.timeLimitHours or 0))
    self.cooldownEntry:setText(tostring(blueprint.cooldown or 0))
    self.statesEntry:setText(joinList(blueprint.eligibility and blueprint.eligibility.traderStates or {}, ", "))
    self.archetypeEntry:setText(joinList(blueprint.eligibility and blueprint.eligibility.archetypes or {}, ", "))
    self.factionEntry:setText(joinList(blueprint.eligibility and blueprint.eligibility.factionIDs or {}, ", "))
    self.targetLabelEntry:setText(tostring(blueprint.target and blueprint.target.label or ""))
    self.targetPurposeEntry:setText(tostring(blueprint.target and blueprint.target.purpose or "Objective Site"))
    self.targetRadiusEntry:setText(tostring(blueprint.target and blueprint.target.radius or 20))
    self.grantPoolIDEntry:setText(tostring(blueprint.grantItemPool or ""))
    self.grantPoolTextEntry:setText(formatWeightedItemPool(blueprint.grantItemPool))
    self.dropPoolIDEntry:setText(tostring(blueprint.dropItemPool or ""))
    self.dropPoolTextEntry:setText(formatWeightedItemPool(blueprint.dropItemPool))
    self.rewardPoolIDEntry:setText(tostring((blueprint.rewardPools and blueprint.rewardPools[1]) or ""))
    self.rewardPoolTextEntry:setText(formatRewardPool(blueprint.rewardPools and blueprint.rewardPools[1]))
    self.dialogueIDEntry:setText(tostring(blueprint.dialogueTree or ""))
    self.encounterCountEntry:setText(tostring(blueprint.encounter and (blueprint.encounter.baseCount or blueprint.encounter.count) or 8))
    self.spawnRadiusEntry:setText(tostring(blueprint.encounter and blueprint.encounter.spawnRadius or 18))
    self.clearRadiusEntry:setText(tostring(blueprint.encounter and blueprint.encounter.clearRadius or 28))
    self.killLabelEntry:setText(tostring(blueprint.objective and (blueprint.objective.killLabel or blueprint.objective.label) or ""))
    self.dropLabelEntry:setText(tostring(blueprint.objective and blueprint.objective.dropLabel or ""))
    self.spawnAfterEntry:setText(tostring(blueprint.objective and blueprint.objective.spawnAfterKills or 4))
    self.deliverLabelEntry:setText(tostring(blueprint.objective and (blueprint.objective.deliverLabel or blueprint.objective.label) or ""))

    local tree = blueprint.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(blueprint.dialogueTree) or nil
    local nodes = tree and tree.nodes or {}
    self.offerTextEntry:setText(tostring(nodes.offer and nodes.offer.text or ""))
    self.detailsTextEntry:setText(tostring(nodes.details and nodes.details.text or ""))
    self.rewardsTextEntry:setText(tostring(nodes.rewards and nodes.rewards.text or ""))
    self.acceptTextEntry:setText(tostring(nodes.accept and nodes.accept.text or ""))
    self.declineTextEntry:setText(tostring(nodes.decline and nodes.decline.text or ""))
    self.activeTextEntry:setText(tostring(nodes.active and nodes.active.text or ""))
    self.unavailableTextEntry:setText(tostring(nodes.unavailable and nodes.unavailable.text or ""))

    self:updatePreviewText("Loaded preset: " .. tostring(blueprint.name or blueprint.id))
end

function DO_QuestManagerWindow:updatePreviewText(text)
    self.previewPanel.text = tostring(text or "")
    self.previewPanel:paginate()
end

function DO_QuestManagerWindow:refreshActiveQuestMonitor()
    self.activeQuestList:clear()
    local player = getLocalPlayer()
    for _, summary in ipairs(DO.Quests and DO.Quests.GetActiveQuestSummary and DO.Quests.GetActiveQuestSummary(player) or {}) do
        self.activeQuestList:addItem(summary.display, summary.questID)
    end
end

function DO_QuestManagerWindow:onRefreshList()
    self:refreshBlueprintList()
    self:refreshActiveQuestMonitor()
end

function DO_QuestManagerWindow:onCreatePreset()
    self.loadedBlueprint = nil
    local seed = tostring(math.floor(ZombRand(1000, 9999)))
    self.idEntry:setText("custom_quest_" .. seed)
    self.nameEntry:setText("Custom Quest " .. seed)
    self.familyEntry.selected = 1
    self.weightEntry:setText("1")
    self.difficultyEntry:setText("1.0")
    self.timerEntry:setText("12")
    self.cooldownEntry:setText("24")
    self.statesEntry:setText("Resting")
    self.archetypeEntry:setText("")
    self.factionEntry:setText("")
    self.targetLabelEntry:setText("Objective Site")
    self.targetPurposeEntry:setText("Objective Site")
    self.targetRadiusEntry:setText("20")
    self.grantPoolIDEntry:setText("")
    self.grantPoolTextEntry:setText("DTQuest.PackageMedicalQuest@5, DTQuest.PackageSmallQuest@3")
    self.dropPoolIDEntry:setText("")
    self.dropPoolTextEntry:setText("DTQuest.InfectedSampleQuest@5, DTQuest.ProofOfKillQuest@2")
    self.rewardPoolIDEntry:setText("")
    self.rewardPoolTextEntry:setText("money:300+rep:3+item:Base.CannedSoup*2@5; money:200+item:Base.Bandage*4@3")
    self.dialogueIDEntry:setText("")
    self.encounterCountEntry:setText("8")
    self.spawnRadiusEntry:setText("18")
    self.clearRadiusEntry:setText("28")
    self.killLabelEntry:setText("Eliminate the infestation")
    self.dropLabelEntry:setText("Recover the objective")
    self.spawnAfterEntry:setText("4")
    self.deliverLabelEntry:setText("Deliver the package")
    self.offerTextEntry:setText("I have a job for you near {target.label}.")
    self.detailsTextEntry:setText("Handle the marked objective and finish the work clean.")
    self.rewardsTextEntry:setText("Complete it and I will pay {rewardPreview}.")
    self.acceptTextEntry:setText("Good. I am marking it now.")
    self.declineTextEntry:setText("Then maybe later.")
    self.activeTextEntry:setText("You already have this job. Finish it first.")
    self.unavailableTextEntry:setText("No work from me right now.")
    self:updatePreviewText("Created a new editable preset shell.")
end

function DO_QuestManagerWindow:onClonePreset()
    local blueprintID = self:getSelectedBlueprintID()
    if not blueprintID then
        self:updatePreviewText("Select a preset to clone.")
        return
    end

    self:loadBlueprintIntoEditor(blueprintID)
    self.idEntry:setText(tostring(blueprintID) .. "_copy")
    self.nameEntry:setText(tostring(self.nameEntry:getText()) .. " Copy")
    self:updatePreviewText("Cloned preset into the editor. Save it to register the copy.")
end

function DO_QuestManagerWindow:onDeletePreset()
    local blueprintID = self:getSelectedBlueprintID()
    if not blueprintID then
        self:updatePreviewText("Select a preset to delete.")
        return
    end

    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if blueprint and blueprint.dialogueTree then
        DO.RemoveQuestDialogueTree(blueprint.dialogueTree)
    end
    if blueprint and blueprint.grantItemPool then
        DO.RemoveQuestLootPool(blueprint.grantItemPool)
    end
    if blueprint and blueprint.dropItemPool then
        DO.RemoveQuestLootPool(blueprint.dropItemPool)
    end
    for _, poolID in ipairs(blueprint and blueprint.rewardPools or {}) do
        DO.RemoveQuestLootPool(poolID)
    end
    DO.RemoveQuestBlueprint(blueprintID)
    self:refreshBlueprintList()
    self:refreshActiveQuestMonitor()
    self:updatePreviewText("Deleted preset: " .. tostring(blueprintID))
end

function DO_QuestManagerWindow:onTogglePreset()
    local blueprintID = self:getSelectedBlueprintID()
    local blueprint = blueprintID and DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if not blueprint then
        self:updatePreviewText("Select a preset to toggle.")
        return
    end

    blueprint.enabled = blueprint.enabled == false
    DO.RegisterQuestBlueprint(blueprintID, blueprint)
    self:refreshBlueprintList(blueprintID)
    self:updatePreviewText(string.format("%s is now %s.", tostring(blueprintID), blueprint.enabled == false and "disabled" or "enabled"))
end

function DO_QuestManagerWindow:onImportPreset()
    local presetName = self.fileEntry:getText()
    local ok, result, warnings = DO_QuestPresetIO.importPreset(presetName)
    if not ok then
        self:updatePreviewText(tostring(result))
        return
    end

    self:refreshBlueprintList(result and result.blueprint and result.blueprint.id or nil)
    if result and result.blueprint and result.blueprint.id then
        self:loadBlueprintIntoEditor(result.blueprint.id)
    end
    self:updatePreviewText("Imported preset from " .. DO_QuestPresetIO.getExportPathHint(presetName) .. (#(warnings or {}) > 0 and ("\nWarnings: " .. table.concat(warnings, "; ")) or ""))
end

function DO_QuestManagerWindow:onExportPreset()
    local package, parseErrors = self:buildPackageFromEditor()
    if #parseErrors > 0 then
        self:updatePreviewText("Cannot export until parse errors are fixed:\n- " .. table.concat(parseErrors, "\n- "))
        return
    end

    local ok, result = DO_QuestPresetIO.exportPreset(self.fileEntry:getText(), package.blueprint.id, package)
    if not ok then
        self:updatePreviewText(tostring(result))
        return
    end

    self:updatePreviewText("Exported preset to " .. tostring(DO_QuestPresetIO.getExportPathHint(self.fileEntry:getText())))
end

function DO_QuestManagerWindow:onValidatePreset()
    local package, parseErrors = self:buildPackageFromEditor()
    local validator = DO.QuestBlueprintValidator
    local valid, errors, warnings = true, {}, {}
    if validator and validator.ValidatePackage then
        valid, errors, warnings = validator.ValidatePackage(package)
    end

    local issues = {}
    for _, message in ipairs(parseErrors or {}) do
        issues[#issues + 1] = message
    end
    if type(errors) == "table" then
        for _, message in ipairs(errors) do
            issues[#issues + 1] = message
        end
    end

    if #issues > 0 or valid ~= true then
        self:updatePreviewText("Validation failed:\n- " .. table.concat(issues, "\n- "))
        return
    end

    local warningText = type(warnings) == "table" and #warnings > 0 and ("\nWarnings: " .. table.concat(warnings, "; ")) or ""
    self:updatePreviewText("Validation passed for " .. tostring(package.blueprint.id) .. warningText)
end

function DO_QuestManagerWindow:onSavePreset()
    local package, parseErrors = self:buildPackageFromEditor()
    if #parseErrors > 0 then
        self:updatePreviewText("Save blocked:\n- " .. table.concat(parseErrors, "\n- "))
        return
    end

    local validator = DO.QuestBlueprintValidator
    local valid, errors = true, {}
    if validator and validator.ValidatePackage then
        valid, errors = validator.ValidatePackage(package)
    end
    if valid ~= true then
        self:updatePreviewText("Save blocked:\n- " .. table.concat(errors or {}, "\n- "))
        return
    end

    DO_QuestPresetIO.registerPackage(package)
    self:refreshBlueprintList(package.blueprint.id)
    self:loadBlueprintIntoEditor(package.blueprint.id)
    self:updatePreviewText("Saved preset " .. tostring(package.blueprint.id) .. " into the live registry.")
end

function DO_QuestManagerWindow:onTestPreset()
    local package, parseErrors = self:buildPackageFromEditor()
    if #parseErrors > 0 then
        self:updatePreviewText("Test blocked:\n- " .. table.concat(parseErrors, "\n- "))
        return
    end

    local validator = DO.QuestBlueprintValidator
    local valid, errors = true, {}
    if validator and validator.ValidatePackage then
        valid, errors = validator.ValidatePackage(package)
    end
    if valid ~= true then
        self:updatePreviewText("Test blocked:\n- " .. table.concat(errors or {}, "\n- "))
        return
    end

    DO_QuestPresetIO.registerPackage(package)
    local player = getLocalPlayer()
    local quest = DO.Quests and DO.Quests.StartQuestFromBlueprint and DO.Quests.StartQuestFromBlueprint(player, {
        traderID = "quest_manager",
        displayName = "Quest Manager",
        currentState = "Resting",
        archetype = "General",
    }, package.blueprint.id) or nil

    self:refreshBlueprintList(package.blueprint.id)
    self:refreshActiveQuestMonitor()
    if quest then
        self:updatePreviewText("Started test quest: " .. tostring(quest.name))
    else
        self:updatePreviewText("Test quest could not be started.")
    end
end

function DO_QuestManagerWindow:update()
    ISCollapsableWindow.update(self)

    self.refreshCounter = (tonumber(self.refreshCounter) or 0) + 1
    if self.refreshCounter >= 90 then
        self.refreshCounter = 0
        self:refreshActiveQuestMonitor()
    end

    if self.blueprintList and self.blueprintList:getItem() and self.lastSelectedBlueprintID ~= self:getSelectedBlueprintID() then
        self.lastSelectedBlueprintID = self:getSelectedBlueprintID()
        self:loadBlueprintIntoEditor(self.lastSelectedBlueprintID)
    end
end

function DO_QuestManagerWindow.OnOpen()
    if DO_QuestManagerWindow.instance then
        DO_QuestManagerWindow.instance:setVisible(true)
        DO_QuestManagerWindow.instance:bringToTop()
        DO_QuestManagerWindow.instance:refreshBlueprintList()
        DO_QuestManagerWindow.instance:refreshActiveQuestMonitor()
        return
    end

    local window = DO_QuestManagerWindow:new(40, 40, 1180, 820)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    DO_QuestManagerWindow.instance = window
end

function DO_QuestManagerWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Dynamic Objectives Quest Manager"
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.92 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.45 }
    o:setResizable(true)
    return o
end

return DO_QuestManagerWindow
