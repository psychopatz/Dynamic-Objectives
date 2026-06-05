DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function T(key, fallback, params)
    if DO and DO.Text and DO.Text.Get then
        return DO.Text.Get(key, params, fallback)
    end
    if type(params) == "table" and fallback then
        return (tostring(fallback):gsub("{([%w_]+)}", function(name)
            local value = params[name]
            return value == nil and ("{" .. name .. "}") or tostring(value)
        end))
    end
    return fallback or key
end

local function getTraderID(context)
    if type(context) ~= "table" then
        return ""
    end
    return tostring(context.traderID or context.id or "")
end

local function isQuestBlockedForNomadFaction(traderContext)
    if type(traderContext) ~= "table" then
        return false
    end

    if traderContext.isNomadic == true then
        return true
    end

    local factionID = traderContext.factionID and tostring(traderContext.factionID) or ""
    local contextFactionType = tostring(traderContext.factionType or "")
    if factionID == "Independent" or contextFactionType == "independent" or contextFactionType == "bandit" then
        return true
    end

    if factionID == "" or not DynamicTrading_Factions or not DynamicTrading_Factions.GetFaction then
        return false
    end

    local ok, faction = pcall(function()
        return DynamicTrading_Factions.GetFaction(factionID)
    end)
    if not ok or type(faction) ~= "table" then
        return false
    end

    local factionType = tostring(faction.factionType or "")
    return faction.isNomadic == true
        or factionType == "independent"
        or factionType == "bandit"
end

local function getOfferFamily(offer)
    if type(offer) ~= "table" then
        return nil
    end

    local family = offer.family
        or (offer.questSpec and offer.questSpec.blueprintFamily)
        or (offer.activeQuest and offer.activeQuest.blueprintFamily)
        or (offer.blueprint and offer.blueprint.family)
        or nil
    return family and tostring(family) or nil
end

local function isQuestRelevantToTrader(quest, traderContext)
    if type(quest) ~= "table" then
        return false
    end

    local traderID = getTraderID(traderContext)
    local sourceTrader = type(quest.sourceTrader) == "table" and quest.sourceTrader or {}
    local sourceTraderID = tostring(sourceTrader.traderID or sourceTrader.id or "")
    if traderID ~= "" and sourceTraderID ~= "" then
        return traderID == sourceTraderID
    end

    return true
end

local function sortOffersForOutput(left, right)
    local leftPriority = tonumber(left and left.outputPriority) or 0
    local rightPriority = tonumber(right and right.outputPriority) or 0
    if leftPriority == rightPriority then
        local leftWeight = tonumber(left and left.weight) or 0
        local rightWeight = tonumber(right and right.weight) or 0
        if leftWeight == rightWeight then
            local leftName = tostring(left and ((left.questSpec and left.questSpec.title) or (left.activeQuest and left.activeQuest.title) or (left.blueprint and left.blueprint.name) or left.blueprintId or ""))
            local rightName = tostring(right and ((right.questSpec and right.questSpec.title) or (right.activeQuest and right.activeQuest.title) or (right.blueprint and right.blueprint.name) or right.blueprintId or ""))
            return leftName < rightName
        end
        return leftWeight > rightWeight
    end
    return leftPriority > rightPriority
end

local function buildResolvedOfferData(player, traderContext, offer)
    if type(offer) ~= "table" then
        return nil
    end

    local blueprint = offer.blueprint
    local tree = offer.dialogueTree or { nodes = {}, choices = {} }
    local context = Runtime.buildTraderDialogueContext(player, traderContext, blueprint, offer.questSpec, offer.activeQuest)
    local resolved = DO.DeepCopy(offer)

    resolved.choiceLabels = {
        accept = tostring(tree.choices and tree.choices.accept or T("DOCommon_Dialogue_Accept", "Accept")),
        details = tostring(tree.choices and tree.choices.details or T("DOCommon_Dialogue_Details", "Tell me more")),
        rewards = tostring(tree.choices and tree.choices.rewards or T("DOCommon_Dialogue_Rewards", "What's the reward?")),
        decline = tostring(tree.choices and tree.choices.decline or T("DOCommon_Dialogue_Decline", "Not now")),
        back = tostring(tree.choices and tree.choices.back or T("DOCommon_Dialogue_Back", "Back")),
    }

    local activeQuest = resolved.activeQuest
    if activeQuest then
        context.rewardPreview = tostring(activeQuest.rewardPreview or context.rewardPreview)
        context["quest.name"] = tostring(activeQuest.name or context["quest.name"])
        if activeQuest.targetLocation and activeQuest.targetLocation.label then
            context["target.label"] = tostring(activeQuest.targetLocation.label)
        end
    end

    local unavailableSuffix = ""
    if tonumber(resolved.cooldownRemainingHours) and tonumber(resolved.cooldownRemainingHours) > 0 then
        unavailableSuffix = T("DOCommon_Dialogue_CooldownSuffix", " Check back in {hours} hours.", {
            hours = string.format("%.1f", tonumber(resolved.cooldownRemainingHours))
        })
    end

    resolved.resolvedDialogue = {
        offer = Runtime.formatDialogueText(tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        details = Runtime.formatDialogueText(tree.nodes and tree.nodes.details and tree.nodes.details.text or tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        rewards = Runtime.formatDialogueText(tree.nodes and tree.nodes.rewards and tree.nodes.rewards.text or "", context),
        accept = Runtime.formatDialogueText(tree.nodes and tree.nodes.accept and tree.nodes.accept.text or T("DOCommon_Dialogue_ObjectiveAccepted", "Objective accepted."), context),
        decline = Runtime.formatDialogueText(tree.nodes and tree.nodes.decline and tree.nodes.decline.text or T("DOCommon_Dialogue_MaybeLater", "Maybe later."), context),
        active = Runtime.formatDialogueText(
            tree.nodes and tree.nodes.active and tree.nodes.active.text or (activeQuest and Quests.BuildSummaryText(activeQuest, player) or T("DOCommon_Dialogue_AlreadyActive", "You already have this objective.")),
            context
        ),
        unavailable = Runtime.formatDialogueText(
            tree.nodes and tree.nodes.unavailable and tree.nodes.unavailable.text or (T("DOCommon_Dialogue_NoWork", "No work from me right now.") .. unavailableSuffix),
            context
        ),
    }

    if activeQuest then
        resolved.progressSummary = Quests.BuildSummaryText(activeQuest, player)
    elseif resolved.questSpec then
        resolved.progressSummary = Quests.BuildSummaryText(resolved.questSpec, player)
    end

    local label = tostring(
        (resolved.questSpec and (resolved.questSpec.title or resolved.questSpec.name))
            or (activeQuest and (activeQuest.title or activeQuest.name))
            or (blueprint and (blueprint.name or blueprint.id))
            or resolved.blueprintId
            or T("DOCommon_Dialogue_Objective", "Objective")
    )

    if resolved.isChainFollowup == true then
        resolved.menuLabel = label .. T("DOCommon_Dialogue_FollowUpSuffix", " (Follow-up)")
        resolved.outputPriority = 300
    elseif activeQuest then
        resolved.menuLabel = label .. T("DOCommon_Dialogue_ActiveSuffix", " (Active)")
        resolved.outputPriority = 250
    else
        resolved.menuLabel = label
        resolved.outputPriority = resolved.outputPriority or 100
    end

    resolved.family = getOfferFamily(resolved)
    return resolved
end

function Quests.GetStore(player, create)
    return Runtime.getStore(player, create)
end

function Quests.BuildObjectiveHookOffer(player, hookID, context)
    local hook = hookID and DO.GetObjectiveHook and DO.GetObjectiveHook(hookID) or nil
    if not hook or not hook.buildOffer then
        return nil
    end
    return hook.buildOffer(player, context)
end

function Quests.GetEligibleTraderOffers(player, traderContext)
    local results = {}
    local store = Runtime.getStore(player, true)
    if not store then
        return results
    end

    local blockNewQuestGeneration = isQuestBlockedForNomadFaction(traderContext)

    local occupiedFamilies = {}
    local bestBlocked = nil
    local pendingOffer = Runtime.buildPendingChainOffer and Runtime.buildPendingChainOffer(store, player, traderContext) or nil
    if pendingOffer then
        pendingOffer.outputPriority = 300
        results[#results + 1] = pendingOffer
        local family = getOfferFamily(pendingOffer)
        if family then
            occupiedFamilies[family] = true
        end
    end

    local activePriority = 250
    for _, blueprint in ipairs(DO.GetQuestBlueprintList and DO.GetQuestBlueprintList() or {}) do
        if blueprint and blueprint.enabled ~= false then
            local activeQuest = Runtime.getActiveQuestForBlueprint and Runtime.getActiveQuestForBlueprint(store, blueprint.id) or nil
            if activeQuest and isQuestRelevantToTrader(activeQuest, traderContext) then
                results[#results + 1] = {
                    blueprintId = tostring(blueprint.id or ""),
                    blueprint = blueprint,
                    activeQuest = activeQuest,
                    cooldownRemainingHours = 0,
                    canStart = false,
                    weight = tonumber(blueprint.weight) or 1,
                    questSpec = nil,
                    dialogueTree = activeQuest.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(activeQuest.dialogueTree)
                        or Runtime.resolveBlueprintDialogueTree(blueprint),
                    outputPriority = activePriority,
                }
                activePriority = activePriority - 1
                local family = getOfferFamily({ blueprint = blueprint, activeQuest = activeQuest })
                if family then
                    occupiedFamilies[family] = true
                end
            elseif not blockNewQuestGeneration
                and Runtime.blueprintMatchesEligibility
                and Runtime.blueprintMatchesEligibility(player, traderContext, blueprint) then
                local cooldownRemainingHours = Runtime.getBlueprintCooldownRemaining and Runtime.getBlueprintCooldownRemaining(store, blueprint) or 0
                if tonumber(cooldownRemainingHours) and tonumber(cooldownRemainingHours) > 0 then
                    if not bestBlocked or tonumber(cooldownRemainingHours) < tonumber(bestBlocked.cooldownRemainingHours) then
                        bestBlocked = {
                            blueprintId = tostring(blueprint.id or ""),
                            blueprint = blueprint,
                            activeQuest = nil,
                            cooldownRemainingHours = cooldownRemainingHours,
                            canStart = false,
                            weight = tonumber(blueprint.weight) or 1,
                            questSpec = nil,
                            dialogueTree = Runtime.resolveBlueprintDialogueTree(blueprint),
                            outputPriority = 10,
                        }
                    end
                end
            end
        end
    end

    local ambientOffers = (not blockNewQuestGeneration)
        and (Runtime.selectAmbientRestingOffers and Runtime.selectAmbientRestingOffers(player, traderContext, store, occupiedFamilies) or {})
        or {}
    local ambientPriority = 100
    for _, ambient in ipairs(ambientOffers) do
        results[#results + 1] = {
            blueprintId = tostring(ambient.blueprintId or ""),
            blueprint = ambient.blueprint,
            activeQuest = nil,
            cooldownRemainingHours = 0,
            canStart = true,
            weight = tonumber(ambient.weight) or tonumber(ambient.blueprint and ambient.blueprint.weight) or 1,
            questSpec = DO.DeepCopy(ambient.questSpec),
            dialogueTree = ambient.questSpec and ambient.questSpec.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(ambient.questSpec.dialogueTree)
                or Runtime.resolveBlueprintDialogueTree(ambient.blueprint),
            outputPriority = ambientPriority,
            family = ambient.family,
            boardDay = ambient.boardDay,
            boardExpiresAtWorldHours = ambient.boardExpiresAtWorldHours,
            generatedAtWorldHours = ambient.generatedAtWorldHours,
        }
        ambientPriority = ambientPriority - 1
    end

    if #results == 0 and bestBlocked and not blockNewQuestGeneration then
        results[#results + 1] = bestBlocked
    end

    table.sort(results, sortOffersForOutput)
    return results
end

function Quests.BuildTraderQuestOffers(player, traderContext)
    local offers = Quests.GetEligibleTraderOffers(player, traderContext)
    local results = {}

    for _, offer in ipairs(offers) do
        local resolved = buildResolvedOfferData(player, traderContext, offer)
        if resolved then
            results[#results + 1] = resolved
        end
    end

    table.sort(results, sortOffersForOutput)
    return results
end

function Quests.BuildTraderQuestOffer(player, traderContext)
    local offers = Quests.BuildTraderQuestOffers(player, traderContext)
    return offers[1]
end

function Quests.StartQuestFromBlueprint(player, traderContext, blueprintID)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if not blueprint then
        return nil
    end

    local store = Runtime.getStore(player, true)
    local pendingOffer = Runtime.buildPendingChainOffer and Runtime.buildPendingChainOffer(store, player, traderContext) or nil
    if pendingOffer and tostring(pendingOffer.blueprintId or "") == tostring(blueprint.id or "") then
        return Quests.StartQuest(player, DO.DeepCopy(pendingOffer.questSpec))
    end

    if Runtime.getActiveQuestForBlueprint(store, blueprint.id) then
        return nil
    end
    if Runtime.getBlueprintCooldownRemaining(store, blueprint) > 0 then
        return nil
    end

    local spec = Runtime.buildEntryChainSpec and Runtime.buildEntryChainSpec(player, traderContext, blueprint, store)
        or Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
    if not spec then
        return nil
    end

    return Quests.StartQuest(player, spec)
end

function Quests.StartQuestFromResolvedOffer(player, offer)
    if not player or type(offer) ~= "table" or type(offer.questSpec) ~= "table" then
        return nil
    end

    local blueprintID = offer.blueprintId or (offer.questSpec and offer.questSpec.blueprintId) or nil
    local blueprint = blueprintID and DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    local store = Runtime.getStore(player, true)
    local bypassCooldown = offer.isChainFollowup == true or (offer.questSpec and offer.questSpec.bypassBlueprintCooldown == true)
    if blueprint and (Runtime.getActiveQuestForBlueprint(store, blueprint.id) or (not bypassCooldown and Runtime.getBlueprintCooldownRemaining(store, blueprint) > 0)) then
        return nil
    end

    return Quests.StartQuest(player, DO.DeepCopy(offer.questSpec))
end
