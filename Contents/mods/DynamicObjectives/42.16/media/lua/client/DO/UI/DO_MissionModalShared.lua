DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_MissionModalShared = DO_MissionModalShared or {}

local DO = DynamicObjectives
local UI = DO.UI
local Shared = DO_MissionModalShared

Shared.tracker = Shared.tracker or {
    lastSeq = 0,
    sessionStartedAt = DO.NowMs and DO.NowMs() or 0,
}

function Shared.Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function Shared.EaseOutCubic(value)
    local t = Shared.Clamp(tonumber(value) or 0, 0, 1)
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

function Shared.TrimText(value, limit, minLimit)
    local text = tostring(value or "")
    local floorLimit = math.max(4, math.floor(tonumber(minLimit) or 4))
    local maxLength = math.max(floorLimit, math.floor(tonumber(limit) or 40))
    if #text <= maxLength then
        return text
    end
    return text:sub(1, maxLength - 3) .. "..."
end

function Shared.GetGrowAnimation(openedAt, options)
    options = type(options) == "table" and options or {}
    local duration = math.max(1, math.floor(tonumber(options.durationMs) or 260))
    local startScale = tonumber(options.startScale) or 0.9
    local endScale = tonumber(options.endScale) or 1.0
    local travelY = tonumber(options.travelY) or 18
    local startAlpha = tonumber(options.startAlpha) or 0.2
    local startAt = math.max(0, tonumber(openedAt) or 0)
    local now = Shared.GetNowMs()

    if startAt <= 0 or now <= startAt then
        return startAlpha, startScale, travelY
    end

    local eased = Shared.EaseOutCubic((now - startAt) / duration)
    local alpha = startAlpha + ((1 - startAlpha) * eased)
    local scale = startScale + ((endScale - startScale) * eased)
    local offsetY = (1 - eased) * travelY
    return alpha, scale, offsetY
end

function Shared.GetEntryAnimation(openedAt, index, options)
    options = type(options) == "table" and options or {}
    local staggerMs = math.max(0, math.floor(tonumber(options.staggerMs) or 90))
    local delayMs = math.max(0, math.floor(tonumber(options.delayMs) or 0))
    local durationMs = math.max(1, math.floor(tonumber(options.durationMs) or 280))
    local startScale = tonumber(options.startScale) or 0.92
    local endScale = tonumber(options.endScale) or 1.0
    local travelY = tonumber(options.travelY) or 14
    local startAlpha = tonumber(options.startAlpha) or 0.18
    local startAt = math.max(0, tonumber(openedAt) or 0) + delayMs + (math.max(0, tonumber(index) or 0) * staggerMs)
    local now = Shared.GetNowMs()

    if startAt <= 0 or now <= startAt then
        return startAlpha, travelY, startScale
    end

    local eased = Shared.EaseOutCubic((now - startAt) / durationMs)
    local alpha = startAlpha + ((1 - startAlpha) * eased)
    local scale = startScale + ((endScale - startScale) * eased)
    local offsetY = (1 - eased) * travelY
    return alpha, offsetY, scale
end

function Shared.GetNowMs()
    return DO.NowMs and DO.NowMs() or 0
end

function Shared.GetLocalPlayer()
    if DO.GetLocalPlayer then
        return DO.GetLocalPlayer()
    end
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

function Shared.PlayUISound(soundName, player)
    local cue = tostring(soundName or "")
    if cue == "" then
        return
    end

    if DT_AudioManager and DT_AudioManager.PlayUISound then
        DT_AudioManager.PlayUISound(cue, 1.0)
        return
    end

    local emitter = player and player.getEmitter and player:getEmitter() or nil
    if emitter and emitter.playSound then
        emitter:playSound(cue)
        return
    end

    local soundManager = getSoundManager and getSoundManager() or nil
    if soundManager and soundManager.PlaySound then
        soundManager:PlaySound(cue, false, 1.0)
    end
end

function Shared.HideModal(modalClass)
    if not modalClass or not modalClass.instance then
        return
    end

    local instance = modalClass.instance
    if instance.setVisible then
        instance:setVisible(false)
    end
    if instance.removeFromUIManager then
        instance:removeFromUIManager()
    end
    instance.addedToUIManager = false
end

function Shared.CenterModal(instance)
    local core = getCore and getCore() or nil
    if not core or not instance then
        return
    end

    instance:setX(math.floor((core:getScreenWidth() - instance.width) / 2))
    instance:setY(math.floor((core:getScreenHeight() - instance.height) / 2))
end

function Shared.ResetTracker()
    Shared.tracker = Shared.tracker or {}
    Shared.tracker.lastSeq = 0
    Shared.tracker.sessionStartedAt = Shared.GetNowMs()
end

local function dispatchMissionEvent(event)
    local kind = tostring(event and event.kind or "")
    if kind == "completed" then
        return DO_CompletionModal and DO_CompletionModal.OpenFromEvent and DO_CompletionModal.OpenFromEvent(event) or nil
    end
    if kind == "failed" then
        return DO_FailureModal and DO_FailureModal.OpenFromEvent and DO_FailureModal.OpenFromEvent(event) or nil
    end
    if kind == "progress" then
        return DO_ProgressModal and DO_ProgressModal.OpenFromEvent and DO_ProgressModal.OpenFromEvent(event) or nil
    end
    return nil
end

function Shared.ProcessMissionEvents(player)
    player = player or Shared.GetLocalPlayer()
    if not player or not UI or not UI.GetMissionEvents then
        return false
    end

    Shared.tracker = Shared.tracker or { lastSeq = 0, sessionStartedAt = Shared.GetNowMs() }
    if (tonumber(Shared.tracker.sessionStartedAt) or 0) <= 0 then
        Shared.tracker.sessionStartedAt = Shared.GetNowMs()
    end

    local handled = false
    local lastSeq = math.max(0, math.floor(tonumber(Shared.tracker.lastSeq) or 0))
    for _, event in ipairs(UI.GetMissionEvents(player) or {}) do
        local seq = math.max(0, math.floor(tonumber(event and event.seq) or 0))
        if seq > lastSeq then
            local occurredAt = math.max(0, math.floor(tonumber(event and event.occurredAt) or 0))
            lastSeq = seq
            if occurredAt >= math.max(0, tonumber(Shared.tracker.sessionStartedAt) or 0) then
                handled = dispatchMissionEvent(event) and true or handled
            end
        end
    end

    Shared.tracker.lastSeq = lastSeq
    return handled
end

local function onTick()
    Shared.ProcessMissionEvents(Shared.GetLocalPlayer())
end

local function onGameStart()
    Shared.HideModal(DO_CompletionModal)
    Shared.HideModal(DO_FailureModal)
    Shared.HideModal(DO_ProgressModal)
    Shared.ResetTracker()
end

if Events then
    if Events.OnTick then
        Events.OnTick.Add(onTick)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(onGameStart)
    end
end
