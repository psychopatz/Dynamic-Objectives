DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Rewards = DynamicObjectives.Rewards or {}

local DO = DynamicObjectives
local Rewards = DO.Rewards

local function rewardLog(category, topic, message)
    DO.Log(category, topic, message)
end

local function ensureQuestRewardState(quest)
    if not quest then
        return {
            granted = false,
            grantedAt = nil,
            entries = {},
        }
    end

    quest.rewardState = type(quest.rewardState) == "table" and quest.rewardState or {}
    quest.rewardState.granted = quest.rewardState.granted == true
    quest.rewardState.grantedAt = tonumber(quest.rewardState.grantedAt) or nil
    quest.rewardState.entries = type(quest.rewardState.entries) == "table" and quest.rewardState.entries or {}
    return quest.rewardState
end

local function getItemDisplayName(itemType)
    local value = tostring(itemType or "")
    if value == "" then
        return "Item"
    end

    local manager = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
    if manager and manager.getItem then
        local scriptItem = manager:getItem(value)
        if scriptItem and scriptItem.getDisplayName then
            return tostring(scriptItem:getDisplayName() or value)
        end
    end

    local display = value:match("([^%.]+)$")
    return tostring(display or value)
end

local function normalizePositiveWhole(value, fallback)
    local number = math.floor(tonumber(value) or tonumber(fallback) or 0)
    return math.max(0, number)
end

local function getMinimumMoneyReward()
    local runtime = DO.Quests and DO.Quests.Runtime or nil
    if runtime and runtime.getConfiguredQuestRewardMinimumMoney then
        return runtime.getConfiguredQuestRewardMinimumMoney()
    end
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return math.max(0, math.floor(tonumber(sandbox and sandbox.QuestRewardMinimumMoney) or 75))
end

local function normalizeRewardContext(context)
    if type(context) ~= "table" then
        return {}
    end

    local factionID = context.factionID and tostring(context.factionID) or nil
    local factionName = context.factionName and tostring(context.factionName) or nil
    return {
        factionID = factionID ~= "" and factionID or nil,
        factionName = factionName ~= "" and factionName or nil,
    }
end

local function copyRewardTemplate(template)
    if type(template) ~= "table" then
        return {}
    end
    return DO.DeepCopy(template)
end

local function normalizeRewardEntry(index, reward, context)
    if type(reward) ~= "table" then
        return nil
    end

    local kind = tostring(reward.kind or reward.type or ""):lower()
    local id = tostring(reward.id or ("reward_" .. tostring(index)))
    if kind == "item" then
        local itemType = reward.itemType or reward.item or reward.fullType
        if not itemType then
            return nil
        end

        local count = normalizePositiveWhole(reward.count, 1)
        if count <= 0 then
            return nil
        end

        return {
            id = id,
            kind = "item",
            itemType = tostring(itemType),
            count = count,
            previewText = string.format("%dx %s", count, getItemDisplayName(itemType)),
        }
    elseif kind == "money" then
        local amount = normalizePositiveWhole(reward.amount, reward.count)
        if amount <= 0 then
            return nil
        end
        amount = math.max(amount, getMinimumMoneyReward())

        return {
            id = id,
            kind = "money",
            amount = amount,
            previewText = "$" .. tostring(amount),
        }
    elseif kind == "reputation" then
        local amount = math.floor(tonumber(reward.amount) or 0)
        if amount == 0 then
            return nil
        end

        local factionID = reward.factionID and tostring(reward.factionID) or context.factionID
        local factionName = reward.factionName and tostring(reward.factionName) or context.factionName
        local amountLabel = amount > 0 and ("+" .. tostring(amount)) or tostring(amount)
        return {
            id = id,
            kind = "reputation",
            amount = amount,
            factionID = factionID ~= "" and factionID or nil,
            factionName = factionName ~= "" and factionName or nil,
            previewText = amountLabel .. " rep",
        }
    elseif kind == "recruit" then
        local count = normalizePositiveWhole(reward.count, 1)
        if count <= 0 then
            return nil
        end

        local template = copyRewardTemplate(reward.template)
        if reward.profession and template.profession == nil then
            template.profession = reward.profession
        end
        if reward.jobType and template.jobType == nil then
            template.jobType = reward.jobType
        end
        if reward.archetypeID and template.archetypeID == nil then
            template.archetypeID = reward.archetypeID
        end
        if reward.name and template.name == nil then
            template.name = reward.name
        end

        return {
            id = id,
            kind = "recruit",
            count = count,
            template = template,
            previewText = string.format("%d recruit%s", count, count == 1 and "" or "s"),
        }
    end

    return nil
end

local function addItemsToContainer(container, itemType, count)
    if not container or not itemType then
        return 0
    end

    local qty = math.max(1, math.floor(tonumber(count) or 1))
    if container.AddItems then
        local items = container:AddItems(itemType, qty)
        local added = items and items.size and items:size() or qty
        if items and sendAddItemToContainer then
            for i = 0, items:size() - 1 do
                sendAddItemToContainer(container, items:get(i))
            end
        end
        return added
    end

    local added = 0
    if container.AddItem then
        for _ = 1, qty do
            local item = container:AddItem(itemType)
            if item then
                added = added + 1
                if sendAddItemToContainer then
                    sendAddItemToContainer(container, item)
                end
            end
        end
    end
    return added
end

local function getRewardLedger(player, create)
    if not player then
        return nil
    end

    local modData = player:getModData()
    local ledger = modData.DynamicObjectivesRewardLedger
    if not ledger and create then
        ledger = {}
        modData.DynamicObjectivesRewardLedger = ledger
    end
    return ledger
end

local function resolveRewardUsername(player)
    local username = player and player.getUsername and player:getUsername() or nil
    if username and username ~= "" then
        return tostring(username)
    end

    if DC_Colony and DC_Colony.Config and DC_Colony.Config.GetOwnerUsername then
        return tostring(DC_Colony.Config.GetOwnerUsername(player))
    end

    return tostring(DO.GetPlayerKey and DO.GetPlayerKey(player) or "local")
end

local function grantItemReward(player, reward)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then
        return "failed", "Player inventory was not available."
    end

    local added = addItemsToContainer(inventory, reward.itemType, reward.count)
    if added <= 0 then
        return "failed", "Could not add " .. tostring(reward.itemType) .. "."
    end

    return "granted", string.format("Added %d x %s.", added, getItemDisplayName(reward.itemType))
end

local function grantMoneyReward(player, reward)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then
        return "failed", "Player inventory was not available."
    end

    local amount = math.max(0, math.floor(tonumber(reward.amount) or 0))
    if amount <= 0 then
        return "failed", "Money reward amount was invalid."
    end

    local bundles = math.floor(amount / 100)
    local loose = amount % 100
    local added = 0
    if bundles > 0 then
        added = added + (addItemsToContainer(inventory, "Base.MoneyBundle", bundles) * 100)
    end
    if loose > 0 then
        added = added + addItemsToContainer(inventory, "Base.Money", loose)
    end

    if added <= 0 then
        return "failed", "Could not add money reward."
    end

    return "granted", "Added $" .. tostring(amount) .. "."
end

local function grantReputationReward(player, reward, context)
    if not (DynamicTrading and DynamicTrading.ServerHelpers and DynamicTrading.ServerHelpers.SendReputationSync) then
        return "skipped_missing_integration", "Dynamic Trading factions were not available."
    end

    local factionID = reward.factionID or (context and context.factionID) or nil
    if not factionID or tostring(factionID) == "" then
        return "skipped_missing_context", "No faction context was available for reputation."
    end

    local ok = DynamicTrading.ServerHelpers.SendReputationSync(player, {
        action = "factionBiasDelta",
        factionID = tostring(factionID),
        amount = tonumber(reward.amount) or 0,
        reason = "quest_reward"
    })
    if not ok then
        return "failed", "Could not modify faction reputation."
    end

    return "granted", string.format("Applied %d reputation to %s.", tonumber(reward.amount) or 0, tostring(factionID))
end

local function grantRecruitReward(player, reward)
    if not (DC_Colony and DC_Colony.Registry and DC_Colony.Registry.CreateWorker) then
        return "skipped_missing_integration", "Dynamic Colonies worker registry was not available."
    end

    local count = math.max(1, math.floor(tonumber(reward.count) or 1))
    local ownerUsername = resolveRewardUsername(player)
    local created = 0
    for index = 1, count do
        local template = copyRewardTemplate(reward.template)
        if count > 1 and template.name and template.name ~= "" then
            template.name = tostring(template.name) .. " " .. tostring(index)
        end

        local worker = DC_Colony.Registry.CreateWorker(ownerUsername, template)
        if worker then
            created = created + 1
            if DynamicTrading_Factions and DynamicTrading_Factions.OnColonyWorkerCreated then
                pcall(DynamicTrading_Factions.OnColonyWorkerCreated, ownerUsername, worker)
            end
        end
    end

    if created <= 0 then
        return "failed", "Could not create recruit rewards."
    end

    return "granted", string.format("Created %d recruit%s.", created, created == 1 and "" or "s")
end

function Rewards.BuildRewardPreview(quest)
    local rewards = quest and quest.rewards or nil
    if type(rewards) ~= "table" or #rewards == 0 then
        return nil
    end

    local parts = {}
    for _, reward in ipairs(rewards) do
        if reward and reward.previewText and reward.previewText ~= "" then
            parts[#parts + 1] = tostring(reward.previewText)
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, ", ")
end

function Rewards.NormalizeRewards(quest, rewards)
    if type(quest) ~= "table" then
        quest = {}
    end

    quest.rewardContext = normalizeRewardContext(quest.rewardContext)
    local normalized = {}
    for index, reward in ipairs(type(rewards) == "table" and rewards or {}) do
        local entry = normalizeRewardEntry(index, reward, quest.rewardContext)
        if entry then
            normalized[#normalized + 1] = entry
        end
    end

    local state = ensureQuestRewardState(quest)
    local previousEntries = state.entries
    state.entries = {}
    for index, reward in ipairs(normalized) do
        local previous = type(previousEntries[index]) == "table" and previousEntries[index] or {}
        state.entries[index] = {
            id = reward.id,
            kind = reward.kind,
            status = tostring(previous.status or "pending"),
            message = previous.message and tostring(previous.message) or nil,
        }
    end

    quest.rewards = normalized
    quest.rewardPreview = Rewards.BuildRewardPreview(quest)
    return normalized
end

function Rewards.GrantQuestRewards(player, quest)
    if not player or type(quest) ~= "table" then
        return false
    end

    local state = ensureQuestRewardState(quest)
    if state.granted == true then
        return false
    end

    local rewards = Rewards.NormalizeRewards(quest, quest.rewards)
    if #rewards == 0 then
        state.granted = true
        state.grantedAt = DO.NowMs()
        return true
    end

    if isClient() and not isServer() then
        if sendClientCommand then
            sendClientCommand(player, "DynamicObjectives", "GrantQuestRewards", {
                questID = quest.id,
                questName = quest.name,
                rewards = DO.DeepCopy(rewards),
                rewardContext = DO.DeepCopy(quest.rewardContext),
            })
        end

        for index, reward in ipairs(rewards) do
            state.entries[index] = state.entries[index] or { id = reward.id, kind = reward.kind }
            state.entries[index].status = "requested"
            state.entries[index].message = "Reward grant requested from server."
        end
        state.granted = true
        state.grantedAt = DO.NowMs()
        return true
    end

    local context = normalizeRewardContext(quest.rewardContext)
    for index, reward in ipairs(rewards) do
        local status = "failed"
        local message = "Reward kind was not recognized."
        if reward.kind == "item" then
            status, message = grantItemReward(player, reward)
        elseif reward.kind == "money" then
            status, message = grantMoneyReward(player, reward)
        elseif reward.kind == "reputation" then
            status, message = grantReputationReward(player, reward, context)
        elseif reward.kind == "recruit" then
            status, message = grantRecruitReward(player, reward)
        end

        state.entries[index] = state.entries[index] or { id = reward.id, kind = reward.kind }
        state.entries[index].status = tostring(status or "failed")
        state.entries[index].message = message and tostring(message) or nil
        rewardLog("Quest", "Rewards", string.format("%s [%s] %s", tostring(quest.id or "unknown"), tostring(reward.kind), tostring(message or status)))
    end

    state.granted = true
    state.grantedAt = DO.NowMs()
    quest.rewardPreview = Rewards.BuildRewardPreview(quest)
    return true
end

function Rewards.GrantQuestRewardsFromPayload(player, args)
    if not player or type(args) ~= "table" then
        return false
    end

    local questID = tostring(args.questID or "")
    if questID == "" then
        return false
    end

    local ledger = getRewardLedger(player, true)
    if ledger and ledger[questID] then
        return false
    end

    local quest = {
        id = questID,
        name = tostring(args.questName or questID),
        rewards = DO.DeepCopy(args.rewards or {}),
        rewardContext = DO.DeepCopy(args.rewardContext or {}),
    }

    Rewards.NormalizeRewards(quest, quest.rewards)
    local granted = Rewards.GrantQuestRewards(player, quest)
    if not granted then
        return false
    end

    if ledger then
        ledger[questID] = {
            grantedAt = DO.NowMs(),
            entries = DO.DeepCopy(quest.rewardState and quest.rewardState.entries or {}),
        }
    end

    if DO.Quests and DO.Quests.GetQuest then
        local liveQuest = DO.Quests.GetQuest(player, questID)
        if liveQuest then
            liveQuest.rewardState = DO.DeepCopy(quest.rewardState)
            liveQuest.rewards = DO.DeepCopy(quest.rewards)
            liveQuest.rewardContext = DO.DeepCopy(quest.rewardContext)
            liveQuest.rewardPreview = quest.rewardPreview
        end
    end

    return true
end
