DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local REWARD_TABLE_VERSION = 3

local REWARD_PROFILES = {
    courier_default = {
        cashMin = 80,
        cashMax = 150,
        itemRollsMin = 2,
        itemRollsMax = 3,
        premium = false,
        preferredTags = { "Food.NonPerishable", "Food.Drink.Water", "Medical", "Container.Bag", "Weapon.Melee" },
    },
    killzone_default = {
        cashMin = 60,
        cashMax = 140,
        itemRollsMin = 2,
        itemRollsMax = 4,
        premium = true,
        preferredTags = { "Medical.General", "Weapon.Ranged", "Weapon.Ranged.Ammo", "Weapon.Melee", "Theme.Combat" },
    },
    huntdrop_default = {
        cashMin = 70,
        cashMax = 150,
        itemRollsMin = 2,
        itemRollsMax = 4,
        premium = true,
        preferredTags = { "Medical", "Food.NonPerishable", "Weapon.Melee", "Weapon.Ranged.Ammo", "Container.Bag" },
    },
    escort_default = {
        cashMin = 90,
        cashMax = 180,
        itemRollsMin = 2,
        itemRollsMax = 3,
        premium = false,
        preferredTags = { "Medical", "Food.NonPerishable", "Weapon.Melee", "Container.Bag" },
    },
}

local QUEST_REWARD_ITEMS = {
    Weapons = {
        { item = "Base.Crowbar", chance = 70, tags = { "Weapon.Melee", "Weapon.Melee.Blunt" } },
        { item = "Base.BaseballBat", chance = 64, tags = { "Weapon.Melee", "Weapon.Melee.Blunt" } },
        { item = "Base.BaseballBat_Nails", chance = 54, tags = { "Weapon.Melee", "Weapon.Melee.Blunt" } },
        { item = "Base.Axe", chance = 48, tags = { "Weapon.Melee", "Weapon.Melee.Axe" } },
        { item = "Base.Machete", chance = 42, tags = { "Weapon.Melee", "Weapon.Melee.Blade" } },
        { item = "Base.Katana", chance = 12, tags = { "Weapon.Melee", "Weapon.Melee.Blade", "Quality.Premium" }, premium = true },
        { item = "Base.Pistol", chance = 26, tags = { "Weapon.Ranged", "Weapon.Ranged.Firearm", "Theme.Combat" }, premium = true },
        { item = "Base.Revolver", chance = 24, tags = { "Weapon.Ranged", "Weapon.Ranged.Firearm", "Theme.Combat" }, premium = true },
        { item = "Base.Shotgun", chance = 18, tags = { "Weapon.Ranged", "Weapon.Ranged.Firearm", "Theme.Combat" }, premium = true },
        { item = "Base.HuntingRifle", chance = 12, tags = { "Weapon.Ranged", "Weapon.Ranged.Firearm", "Theme.Combat" }, premium = true },
        { item = "Base.Bullets9mmBox", chance = 58, tags = { "Weapon.Ranged.Ammo", "Theme.Combat" } },
        { item = "Base.Bullets38Box", chance = 52, tags = { "Weapon.Ranged.Ammo", "Theme.Combat" } },
        { item = "Base.ShotgunShellsBox", chance = 46, tags = { "Weapon.Ranged.Ammo", "Theme.Combat" } },
    },
    Medicine = {
        { item = "Base.BandageBox", chance = 78, tags = { "Medical", "Medical.Healthcare" } },
        { item = "Base.AdhesiveBandageBox", chance = 70, tags = { "Medical", "Medical.Healthcare" } },
        { item = "Base.AlcoholBandage", chance = 60, count = 2, tags = { "Medical", "Medical.Healthcare" } },
        { item = "Base.Antibiotics", chance = 44, tags = { "Medical", "Medical.Consumable" } },
        { item = "Base.PillsVitamins", chance = 54, tags = { "Medical", "Medical.Consumable" } },
        { item = "Base.Pills", chance = 36, tags = { "Medical", "Medical.Consumable" } },
        { item = "Base.PillsBeta", chance = 32, tags = { "Medical", "Medical.Consumable" } },
        { item = "Base.SutureNeedle", chance = 46, count = 2, tags = { "Medical", "Tool.Medical" } },
        { item = "Base.SutureNeedleHolder", chance = 36, tags = { "Medical", "Tool.Medical" } },
    },
    Foods = {
        { item = "Base.Cereal", chance = 72, tags = { "Food.NonPerishable", "Food.HighNutrition" } },
        { item = "Base.PeanutButter", chance = 66, tags = { "Food.NonPerishable", "Food.HighNutrition" } },
        { item = "Base.CannedCornedBeef", chance = 70, tags = { "Food.NonPerishable", "Food.MediumNutrition" } },
        { item = "Base.CannedChili", chance = 64, tags = { "Food.NonPerishable" } },
        { item = "Base.CannedMilk", chance = 58, tags = { "Food.NonPerishable", "Food.MediumNutrition" } },
        { item = "Base.TunaTin", chance = 58, tags = { "Food.NonPerishable" } },
        { item = "Base.GranolaBar", chance = 62, count = 2, tags = { "Food.NonPerishable" } },
    },
    Bags = {
        { item = "Base.Bag_Schoolbag", chance = 68, tags = { "Container.Bag", "Container.Bag.Backpack" } },
        { item = "Base.Bag_NormalHikingBag", chance = 46, tags = { "Container.Bag", "Container.Bag.Backpack", "Theme.Survival" } },
        { item = "Base.Bag_BigHikingBag", chance = 34, tags = { "Container.Bag", "Container.Bag.Backpack", "Theme.Survival" }, premium = true },
        { item = "Base.Bag_Military", chance = 30, tags = { "Container.Bag", "Container.Bag.Backpack", "Theme.Combat" }, premium = true },
        { item = "Base.Bag_ALICEpack", chance = 22, tags = { "Container.Bag", "Container.Bag.Backpack", "Theme.Survival" }, premium = true },
        { item = "Base.Bag_SurvivorBag", chance = 14, tags = { "Container.Bag", "Container.Bag.Backpack", "Theme.Survival" }, premium = true },
    },
}

local function deepCopy(value)
    if DO.DeepCopy then
        return DO.DeepCopy(value)
    end
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function normalizeText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function itemMatchesTag(itemTags, targetTag)
    local probe = normalizeText(targetTag)
    if probe == "" then
        return false
    end

    for _, rawTag in ipairs(type(itemTags) == "table" and itemTags or {}) do
        local itemTag = normalizeText(rawTag)
        if itemTag == probe or itemTag:find("^" .. probe:gsub("%.", "%%.") .. "%.") then
            return true
        end
        if probe:find("^" .. itemTag:gsub("%.", "%%.") .. "%.") then
            return true
        end
    end

    return false
end

local function countTagMatches(itemTags, wantedTags)
    local matches = 0
    for _, tag in ipairs(type(wantedTags) == "table" and wantedTags or {}) do
        if itemMatchesTag(itemTags, tag) then
            matches = matches + 1
        end
    end
    return matches
end

local function buildTagSet(tags)
    local set = {}
    for _, tag in ipairs(type(tags) == "table" and tags or {}) do
        local key = normalizeText(tag)
        if key ~= "" then
            set[key] = true
        end
    end
    return set
end

local function sandboxBool(name, fallback)
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    local value = sandbox and sandbox[name]
    if value == nil then
        return fallback == true
    end
    return value == true
end

local function getRewardCategorySettings()
    return {
        Weapons = sandboxBool("QuestRewardPoolWeapons", true),
        Medicine = sandboxBool("QuestRewardPoolMedicine", true),
        Foods = sandboxBool("QuestRewardPoolFoods", true),
        Bags = sandboxBool("QuestRewardPoolBags", true),
    }
end

local function getMinimumMoneyReward()
    if Runtime.getConfiguredQuestRewardMinimumMoney then
        return Runtime.getConfiguredQuestRewardMinimumMoney()
    end
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return math.max(0, math.floor(tonumber(sandbox and sandbox.QuestRewardMinimumMoney) or 75))
end

local function getRewardCategoryWeights(themeID)
    local weights = { Weapons = 1.2, Medicine = 1.2, Foods = 1.2, Bags = 0.8 }
    themeID = tostring(themeID or "")
    if themeID == "combat" then
        weights.Weapons = weights.Weapons + 2.2
        weights.Medicine = weights.Medicine + 0.8
    elseif themeID == "medical" then
        weights.Medicine = weights.Medicine + 2.4
        weights.Bags = weights.Bags + 0.5
    elseif themeID == "food" then
        weights.Foods = weights.Foods + 2.4
    elseif themeID == "survival" or themeID == "scavenge" then
        weights.Bags = weights.Bags + 1.6
        weights.Foods = weights.Foods + 0.8
        weights.Weapons = weights.Weapons + 0.6
    end
    return weights
end

local function randomRatio(minValue, maxValue)
    local low = tonumber(minValue) or 0
    local high = tonumber(maxValue) or low
    if high < low then
        low, high = high, low
    end
    if math.abs(high - low) <= 0.0001 then
        return low
    end
    return low + ((ZombRand(0, 10001) / 10000) * (high - low))
end

local function pickWeightedEntry(entries)
    local total = 0
    for _, entry in ipairs(entries or {}) do
        total = total + math.max(0, tonumber(entry.weight) or 0)
    end
    if total <= 0 then
        return nil
    end

    local roll = ZombRand(0, math.max(1, math.floor(total * 1000))) / 1000
    local cursor = 0
    for _, entry in ipairs(entries) do
        cursor = cursor + math.max(0, tonumber(entry.weight) or 0)
        if roll <= cursor then
            return entry
        end
    end
    return entries[#entries]
end

local function getEffectiveItemPrice(itemKey, itemData)
    if not itemData then
        return 0
    end
    if DynamicTrading and DynamicTrading.PriceConfig and DynamicTrading.PriceConfig.GetEffectiveBasePrice then
        return math.max(0, math.floor(tonumber(DynamicTrading.PriceConfig.GetEffectiveBasePrice(itemKey, itemData)) or 0))
    end
    return math.max(0, math.floor(tonumber(itemData.basePrice) or 0))
end

local function getRewardItemDisplayName(itemType)
    itemType = tostring(itemType or "")
    if itemType == "" then
        return "Item"
    end

    local masterList = DynamicTrading and DynamicTrading.Config and DynamicTrading.Config.MasterList or nil
    if type(masterList) == "table" then
        local itemData = type(masterList[itemType]) == "table" and masterList[itemType] or nil
        if not itemData then
            for _, data in pairs(masterList) do
                if type(data) == "table" and tostring(data.item or "") == itemType then
                    itemData = data
                    break
                end
            end
        end
        if itemData and itemData.displayName and tostring(itemData.displayName) ~= "" then
            return tostring(itemData.displayName)
        end
        if itemData and itemData.name and tostring(itemData.name) ~= "" then
            return tostring(itemData.name)
        end
    end

    local manager = getScriptManager and getScriptManager() or ScriptManager and ScriptManager.instance or nil
    if manager and manager.getItem then
        local ok, scriptItem = pcall(function()
            return manager:getItem(itemType)
        end)
        if ok and scriptItem and scriptItem.getDisplayName then
            local okName, name = pcall(function()
                return scriptItem:getDisplayName()
            end)
            if okName and name and tostring(name) ~= "" then
                return tostring(name)
            end
        end
    end
    return tostring(itemType:match("([^%.]+)$") or itemType)
end

local function buildRewardPreviewText(rewards)
    local parts = {}
    for _, reward in ipairs(rewards or {}) do
        if type(reward) == "table" then
            local kind = tostring(reward.kind or reward.type or ""):lower()
            if kind == "item" then
                parts[#parts + 1] = string.format("%dx %s", math.max(1, math.floor(tonumber(reward.count) or 1)), getRewardItemDisplayName(reward.itemType or reward.item))
            elseif kind == "money" and tonumber(reward.amount) and tonumber(reward.amount) > 0 then
                parts[#parts + 1] = "$" .. tostring(math.floor(tonumber(reward.amount) or 0))
            elseif kind == "reputation" and tonumber(reward.amount) and tonumber(reward.amount) ~= 0 then
                local amount = math.floor(tonumber(reward.amount) or 0)
                parts[#parts + 1] = (amount > 0 and "+" or "") .. tostring(amount) .. " rep"
            end
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

local function resolveRewardItemData(itemType)
    local masterList = DynamicTrading and DynamicTrading.Config and DynamicTrading.Config.MasterList or nil
    if type(masterList) ~= "table" then
        return nil, nil
    end

    itemType = tostring(itemType or "")
    if itemType == "" then
        return nil, nil
    end

    if type(masterList[itemType]) == "table" then
        return itemType, masterList[itemType]
    end

    for itemKey, itemData in pairs(masterList) do
        if type(itemData) == "table" and tostring(itemData.item or itemKey or "") == itemType then
            return itemKey, itemData
        end
    end
    return nil, nil
end

local function itemAllowedForArchetype(itemData, archetype)
    local tags = itemData and itemData.tags or nil
    if itemData == nil or type(tags) ~= "table" or #tags == 0 then
        return false
    end
    if itemMatchesTag(tags, "Quality.Waste") then
        return false
    end
    for _, forbid in ipairs(archetype and archetype.forbid or {}) do
        if itemMatchesTag(tags, forbid) then
            return false
        end
    end
    return true
end

local function mergeRewardTags(itemData, entry)
    local tags = deepCopy(itemData and itemData.tags or {})
    local seen = buildTagSet(tags)
    for _, tag in ipairs(entry and entry.tags or {}) do
        local key = normalizeText(tag)
        if key ~= "" and not seen[key] then
            tags[#tags + 1] = tostring(tag)
            seen[key] = true
        end
    end
    return tags
end

local function buildCandidateList(archetype, theme, profile)
    local allowedCategories = getRewardCategorySettings()
    local categoryWeights = getRewardCategoryWeights(theme and theme.id)
    local candidates = {}
    local looseCandidates = {}

    for category, entries in pairs(QUEST_REWARD_ITEMS) do
        if allowedCategories[category] == true then
            for _, entry in ipairs(entries or {}) do
                local itemKey, itemData = resolveRewardItemData(entry.item)
                local itemType = itemData and tostring(itemData.item or itemKey or "") or tostring(entry.item or "")
                if itemKey and itemType ~= "" and itemAllowedForArchetype(itemData, archetype) then
                    local count = math.max(1, math.floor(tonumber(entry.count) or 1))
                    local unitPrice = getEffectiveItemPrice(itemKey, itemData)
                    local price = math.max(1, unitPrice * count)
                    local chance = math.max(0, math.min(100, tonumber(entry.chance) or 0))
                    if chance > 0 then
                        local tags = mergeRewardTags(itemData, entry)
                        local themeMatches = countTagMatches(tags, theme.preferredTags)
                        local profileMatches = countTagMatches(tags, profile.preferredTags)
                        local expertMatches = countTagMatches(tags, archetype and archetype.expertTags or nil)
                        local allocationMatches = 0
                        for _, allocation in ipairs(archetype and archetype.allocations or {}) do
                            allocationMatches = allocationMatches + countTagMatches(tags, allocation.tags)
                        end

                        local score = chance
                            + ((themeMatches * 18) + (profileMatches * 14) + (expertMatches * 10) + (allocationMatches * 8))
                            + ((tonumber(categoryWeights and categoryWeights[category]) or 0) * 10)
                            + math.min(18, math.sqrt(price))
                        if entry.premium == true and profile and profile.premium == true then
                            score = score + 22
                        elseif entry.premium == true then
                            score = score * 0.6
                        end

                        local candidate = {
                            itemType = itemType,
                            itemKey = itemKey,
                            itemData = itemData,
                            tags = tags,
                            price = price,
                            unitPrice = unitPrice,
                            count = count,
                            chance = chance,
                            weight = math.max(0.1, score),
                            rewardCategory = category,
                        }

                        looseCandidates[#looseCandidates + 1] = candidate
                        if chance >= 100 or ZombRand(0, 100) < chance then
                            candidates[#candidates + 1] = candidate
                        end
                    end
                elseif Runtime.questLog then
                    Runtime.questLog("Quest", "Procedural", "Quest reward item missing from DT registry: " .. tostring(entry.item))
                end
            end
        end
    end
    return #candidates > 0 and candidates or looseCandidates
end

local function pickRewardItems(candidates, profile, difficulty)
    local selected = {}
    local picked = {}
    local minRolls = math.max(1, math.floor(tonumber(profile.itemRollsMin) or 1))
    local maxRolls = math.max(minRolls, math.floor(tonumber(profile.itemRollsMax) or minRolls))
    local targetCount = ZombRand(minRolls, maxRolls + 1)
    if tonumber(difficulty) and tonumber(difficulty) >= 1.75 then
        targetCount = targetCount + 1
    end

    local totalValue = 0
    for _ = 1, math.min(6, targetCount) do
        local pool = {}
        for _, candidate in ipairs(candidates or {}) do
            if not picked[candidate.itemType] then
                pool[#pool + 1] = candidate
            end
        end
        if #pool == 0 then
            break
        end

        local chosen = pickWeightedEntry(pool)
        if not chosen then
            break
        end

        selected[#selected + 1] = {
            kind = "item",
            itemType = chosen.itemType,
            count = math.max(1, math.floor(tonumber(chosen.count) or 1)),
            dynamicPrice = chosen.unitPrice,
            rewardValue = chosen.price,
            rewardChance = chosen.chance,
            rewardCategory = chosen.rewardCategory,
        }
        picked[chosen.itemType] = true
        totalValue = totalValue + chosen.price
    end
    return selected, totalValue
end

local function buildRewardTags(themeID, itemRewards, candidatesByType)
    local tags = {}
    local seen = {}
    if themeID and themeID ~= "" then
        tags[#tags + 1] = tostring(themeID)
        seen[tostring(themeID)] = true
    end
    for _, reward in ipairs(itemRewards or {}) do
        local candidate = candidatesByType and candidatesByType[tostring(reward.itemType)] or nil
        local tag = candidate and candidate.tags and candidate.tags[1] or nil
        if tag and not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tostring(tag)
        end
    end
    return tags
end

local function buildHistorySignature(family, themeID, rewardTags)
    local primaryTag = type(rewardTags) == "table" and rewardTags[2] or nil
    return table.concat({ tostring(family or "Quest"), tostring(themeID or "mixed"), tostring(primaryTag or "cash") }, "|")
end

function Runtime.getProceduralRewardTableVersion()
    return REWARD_TABLE_VERSION
end

function Runtime.getProceduralRewardProfile(profileID)
    return REWARD_PROFILES[tostring(profileID or "")] or REWARD_PROFILES.courier_default
end

function Runtime.buildProceduralRewardData(request)
    request = type(request) == "table" and request or {}
    local profile = Runtime.getProceduralRewardProfile(request.profileID)
    local difficulty = Runtime.normalizeDifficulty and Runtime.normalizeDifficulty(request.difficulty or 1.0) or (tonumber(request.difficulty) or 1.0)
    local themeID = tostring(request.themeID or "mixed")
    local theme = type(request.theme) == "table" and request.theme or { id = themeID, preferredTags = {} }
    theme.id = theme.id or themeID
    local archetype = type(request.archetype) == "table" and request.archetype or {}

    local candidates = buildCandidateList(archetype, theme, profile)
    local itemRewards, itemValue = pickRewardItems(candidates, profile, difficulty)

    local candidateByType = {}
    for _, candidate in ipairs(candidates) do
        candidateByType[tostring(candidate.itemType)] = candidate
    end

    local rewards = {}
    for _, reward in ipairs(itemRewards) do
        rewards[#rewards + 1] = reward
    end

    local cashAmount = 0
    if request.allowCash ~= false then
        cashAmount = math.max(
            getMinimumMoneyReward(),
            math.max(0, math.floor(randomRatio(profile.cashMin, profile.cashMax) * difficulty + 0.5))
        )
        if cashAmount > 0 then
            rewards[#rewards + 1] = { kind = "money", amount = cashAmount }
        end
    end

    local giver = request.giver
    if request.allowReputation == true and giver and giver.giverFactionID then
        rewards[#rewards + 1] = {
            kind = "reputation",
            amount = math.max(2, math.floor((difficulty * 2.2) + 2.5)),
            factionID = giver.giverFactionID,
            factionName = giver.giverFactionName,
        }
    end

    local rewardTags = buildRewardTags(themeID, itemRewards, candidateByType)
    local totalValue = itemValue + cashAmount
    return {
        targetValue = totalValue,
        actualValue = totalValue,
        targetBudget = totalValue,
        rewards = rewards,
        previewText = buildRewardPreviewText(rewards),
        rewardTags = rewardTags,
        signature = buildHistorySignature(request.family, themeID, rewardTags),
    }
end
