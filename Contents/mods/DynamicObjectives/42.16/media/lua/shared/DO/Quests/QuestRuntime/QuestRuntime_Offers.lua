DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

function Quests.GetStore(player, create)
    return Runtime.getStore(player, create)
end

function Quests.GetEligibleTraderOffers(player, traderContext)
    local results = {}
    local store = Runtime.getStore(player, true)
    if not store or not DO.GetQuestBlueprintList then
        return results
    end

    local pendingOffer = Runtime.buildPendingChainOffer and Runtime.buildPendingChainOffer(store, player, traderContext) or nil
    if pendingOffer then
        results[1] = pendingOffer
        return results
    end

    for _, blueprint in ipairs(DO.GetQuestBlueprintList()) do
        if blueprint and blueprint.enabled ~= false and Runtime.blueprintMatchesEligibility(player, traderContext, blueprint) then
            local activeQuest = Runtime.getActiveQuestForBlueprint(store, blueprint.id)
            local cooldownRemaining = Runtime.getBlueprintCooldownRemaining(store, blueprint)
            local questSpec = nil
            if not activeQuest and cooldownRemaining <= 0 then
                questSpec = Runtime.buildEntryChainSpec and Runtime.buildEntryChainSpec(player, traderContext, blueprint, store)
                    or Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
            end

            results[#results + 1] = {
                blueprintId = blueprint.id,
                blueprint = blueprint,
                activeQuest = activeQuest,
                cooldownRemainingHours = cooldownRemaining,
                canStart = activeQuest == nil and cooldownRemaining <= 0 and questSpec ~= nil,
                weight = tonumber(questSpec and questSpec.offerWeight) or tonumber(blueprint.weight) or 1,
                questSpec = questSpec,
                dialogueTree = questSpec and questSpec.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(questSpec.dialogueTree)
                    or Runtime.resolveBlueprintDialogueTree(blueprint),
            }
        end
    end

    return results
end

function Quests.BuildTraderQuestOffer(player, traderContext)
    local offers = Quests.GetEligibleTraderOffers(player, traderContext)
    if #offers == 0 then
        return nil
    end

    local startable = {}
    local active = {}
    local blocked = {}

    for _, offer in ipairs(offers) do
        if offer.canStart == true then
            startable[#startable + 1] = offer
        elseif offer.activeQuest then
            active[#active + 1] = offer
        else
            blocked[#blocked + 1] = offer
        end
    end

    local selected = Runtime.pickWeightedOffer(#startable > 0 and startable or (#active > 0 and active or blocked))
    if not selected then
        return nil
    end

    local blueprint = selected.blueprint
    local tree = selected.dialogueTree or { nodes = {}, choices = {} }
    local context = Runtime.buildTraderDialogueContext(player, traderContext, blueprint, selected.questSpec, selected.activeQuest)

    selected.choiceLabels = {
        accept = tostring(tree.choices and tree.choices.accept or "Accept"),
        details = tostring(tree.choices and tree.choices.details or "Tell me more"),
        rewards = tostring(tree.choices and tree.choices.rewards or "What's the reward?"),
        decline = tostring(tree.choices and tree.choices.decline or "Not now"),
        back = tostring(tree.choices and tree.choices.back or "Back"),
    }

    local activeQuest = selected.activeQuest
    if activeQuest then
        context["rewardPreview"] = tostring(activeQuest.rewardPreview or context["rewardPreview"])
        context["quest.name"] = tostring(activeQuest.name or context["quest.name"])
        if activeQuest.targetLocation and activeQuest.targetLocation.label then
            context["target.label"] = tostring(activeQuest.targetLocation.label)
        end
    end

    local unavailableSuffix = ""
    if tonumber(selected.cooldownRemainingHours) and tonumber(selected.cooldownRemainingHours) > 0 then
        unavailableSuffix = string.format(" Check back in %.1f hours.", tonumber(selected.cooldownRemainingHours))
    end

    selected.resolvedDialogue = {
        offer = Runtime.formatDialogueText(tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        details = Runtime.formatDialogueText(tree.nodes and tree.nodes.details and tree.nodes.details.text or tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        rewards = Runtime.formatDialogueText(tree.nodes and tree.nodes.rewards and tree.nodes.rewards.text or "", context),
        accept = Runtime.formatDialogueText(tree.nodes and tree.nodes.accept and tree.nodes.accept.text or "Objective accepted.", context),
        decline = Runtime.formatDialogueText(tree.nodes and tree.nodes.decline and tree.nodes.decline.text or "Maybe later.", context),
        active = Runtime.formatDialogueText(
            tree.nodes and tree.nodes.active and tree.nodes.active.text or (activeQuest and Quests.BuildSummaryText(activeQuest, player) or "You already have this objective."),
            context
        ),
        unavailable = Runtime.formatDialogueText(
            tree.nodes and tree.nodes.unavailable and tree.nodes.unavailable.text or ("No work from me right now." .. unavailableSuffix),
            context
        ),
    }

    if activeQuest then
        selected.progressSummary = Quests.BuildSummaryText(activeQuest, player)
    elseif selected.questSpec then
        selected.progressSummary = Quests.BuildSummaryText(selected.questSpec, player)
    end

    return selected
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
