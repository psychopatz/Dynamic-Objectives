DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

local DO = DynamicObjectives
local UI = DO.UI

local MAX_EVENT_HISTORY = 32

local function getStore(player, create)
    return DO.Quests
        and DO.Quests.Runtime
        and DO.Quests.Runtime.getStore
        and DO.Quests.Runtime.getStore(player, create)
        or nil
end

local function normalizeEventKind(kind)
    local value = tostring(kind or "")
    if value == "completed" or value == "failed" or value == "progress" then
        return value
    end
    return nil
end

local function normalizeStore(store)
    if not store then
        return nil
    end

    store.uiEventSeq = math.max(0, math.floor(tonumber(store.uiEventSeq) or 0))
    store.uiEvents = type(store.uiEvents) == "table" and store.uiEvents or {}

    while #store.uiEvents > MAX_EVENT_HISTORY do
        table.remove(store.uiEvents, 1)
    end

    return store
end

local function findObjectiveSnapshot(quest, objectiveID)
    if type(quest) ~= "table" or type(quest.objectives) ~= "table" then
        return nil
    end

    local probe = tostring(objectiveID or "")
    if probe == "" then
        return nil
    end

    for _, objective in ipairs(quest.objectives) do
        if tostring(objective and objective.id or "") == probe then
            return objective
        end
    end

    return nil
end

function UI.QueueMissionEvent(player, eventData)
    if not player or type(eventData) ~= "table" then
        return nil
    end

    local store = normalizeStore(getStore(player, true))
    local kind = normalizeEventKind(eventData.kind)
    if not store or not kind then
        return nil
    end

    store.uiEventSeq = store.uiEventSeq + 1

    local quest = type(eventData.quest) == "table" and DO.DeepCopy(eventData.quest) or nil
    local objective = type(eventData.objective) == "table" and DO.DeepCopy(eventData.objective) or nil
    local objectiveID = eventData.objectiveID or (objective and objective.id) or nil
    if not objective and quest and objectiveID then
        objective = DO.DeepCopy(findObjectiveSnapshot(quest, objectiveID))
    end

    local event = {
        seq = store.uiEventSeq,
        kind = kind,
        source = eventData.source and tostring(eventData.source) or nil,
        status = eventData.status and tostring(eventData.status) or nil,
        reason = eventData.reason and tostring(eventData.reason) or nil,
        questID = eventData.questID and tostring(eventData.questID) or (quest and tostring(quest.id or "") ~= "" and tostring(quest.id) or nil),
        objectiveID = objectiveID and tostring(objectiveID) or nil,
        occurredAt = math.max(0, math.floor(tonumber(eventData.occurredAt) or (DO.NowMs and DO.NowMs() or 0))),
        quest = quest,
        objective = objective,
    }

    store.uiEvents[#store.uiEvents + 1] = event
    normalizeStore(store)
    return event
end

function UI.GetMissionEvents(player)
    local store = normalizeStore(getStore(player, false))
    if not store then
        return {}
    end

    return store.uiEvents
end

function UI.GetLatestMissionEventSeq(player)
    local store = normalizeStore(getStore(player, false))
    if not store then
        return 0
    end

    return math.max(0, math.floor(tonumber(store.uiEventSeq) or 0))
end
