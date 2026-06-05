DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_MissionViewerShared = DO_MissionViewerShared or {}

local DO = DynamicObjectives

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

function DO_MissionViewerShared.getLocalPlayer()
    if DO.GetLocalPlayer then
        return DO.GetLocalPlayer()
    end
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

function DO_MissionViewerShared.formatRemainingHours(hours)
    local value = tonumber(hours)
    if not value then
        return nil
    end

    local totalMinutes = math.max(0, math.floor((value * 60) + 0.5))
    local wholeHours = math.floor(totalMinutes / 60)
    local minutes = totalMinutes % 60
    if wholeHours <= 0 then
        return T("DOCommon_UI_MissionViewer_MinutesLeft", "{minutes}m left", { minutes = minutes })
    end
    if minutes <= 0 then
        return T("DOCommon_UI_MissionViewer_HoursLeft", "{hours}h left", { hours = wholeHours })
    end
    return T("DOCommon_UI_MissionViewer_HoursMinutesLeft", "{hours}h {minutes}m left", {
        hours = wholeHours,
        minutes = minutes,
    })
end

function DO_MissionViewerShared.getStatusColor(status)
    status = tostring(status or "active")
    if status == "completed" then
        return { r = 0.42, g = 0.88, b = 0.52 }
    end
    if status == "failed" then
        return { r = 0.96, g = 0.46, b = 0.38 }
    end
    if status == "abandoned" then
        return { r = 0.74, g = 0.74, b = 0.74 }
    end
    return { r = 0.96, g = 0.8, b = 0.42 }
end

function DO_MissionViewerShared.getSecondaryText(summary)
    if not summary then
        return ""
    end
    if summary.giverName then
        local issuer = summary.giverTitle and summary.giverTitle ~= ""
            and (tostring(summary.giverName) .. " (" .. tostring(summary.giverTitle) .. ")")
            or tostring(summary.giverName)
        if summary.giverFactionName and summary.giverFactionName ~= "" then
            issuer = issuer .. " - " .. tostring(summary.giverFactionName)
        end
        return issuer
    end
    return tostring(summary.chainSummary or summary.currentObjectiveLabel or summary.targetLabel or "")
end

function DO_MissionViewerShared.getTertiaryText(summary)
    if not summary then
        return ""
    end

    if summary.status ~= "active" then
        return tostring(summary.targetLabel or summary.rewardPreview or "")
    end

    local remaining = DO_MissionViewerShared.formatRemainingHours(summary.timeRemainingHours)
    if remaining then
        return T("DOCommon_UI_MissionViewer_Expires", "Expires: {value}", { value = remaining })
    end
    return tostring(summary.targetLabel or summary.rewardPreview or "")
end

local function appendLine(parts, color, text)
    if not text or text == "" then
        return
    end

    if color then
        parts[#parts + 1] = string.format(" <RGB:%.2f,%.2f,%.2f> %s <LINE> ", color.r, color.g, color.b, tostring(text))
        return
    end

    parts[#parts + 1] = " " .. tostring(text) .. " <LINE> "
end

function DO_MissionViewerShared.buildDetailText(detail)
    if not detail then
        return " <RGB:0.65,0.65,0.65> " .. T("DOCommon_UI_MissionViewer_SelectMission", "Select a mission to inspect its objectives and rewards.") .. " <LINE> "
    end

    local parts = {}
    local statusColor = DO_MissionViewerShared.getStatusColor(detail.status)
    local remaining = DO_MissionViewerShared.formatRemainingHours(detail.timeRemainingHours)

    appendLine(parts, statusColor, T("DOCommon_UI_MissionViewer_Status", "Status: {value}", {
        value = tostring(detail.statusLabel or T("DOCommon_UI_MissionViewer_Active", "Active"))
    }))
    if detail.title and detail.title ~= "" and detail.title ~= detail.name then
        appendLine(parts, { r = 0.98, g = 0.9, b = 0.62 }, T("DOCommon_UI_MissionViewer_Contract", "Contract: {value}", {
            value = tostring(detail.title)
        }))
    end
    if detail.giverName and detail.giverName ~= "" then
        local issuer = detail.giverTitle and detail.giverTitle ~= ""
            and (tostring(detail.giverName) .. " (" .. tostring(detail.giverTitle) .. ")")
            or tostring(detail.giverName)
        if detail.giverFactionName and detail.giverFactionName ~= "" then
            issuer = issuer .. " - " .. tostring(detail.giverFactionName)
        end
        appendLine(parts, { r = 0.76, g = 0.86, b = 0.98 }, T("DOCommon_UI_MissionViewer_Issuer", "Issuer: {value}", {
            value = issuer
        }))
    end
    if detail.chainSummary then
        appendLine(parts, { r = 0.62, g = 0.82, b = 1.0 }, T("DOCommon_UI_MissionViewer_Chain", "Chain: {value}", {
            value = tostring(detail.chainSummary)
        }))
    end
    if detail.themeID and detail.themeID ~= "" then
        appendLine(parts, { r = 0.78, g = 0.88, b = 0.74 }, T("DOCommon_UI_MissionViewer_Theme", "Theme: {value}", {
            value = tostring(detail.themeID)
        }))
    end
    if detail.targetLabel and detail.targetLabel ~= "" then
        appendLine(parts, { r = 0.82, g = 0.84, b = 0.88 }, T("DOCommon_UI_MissionViewer_Target", "Target: {value}", {
            value = tostring(detail.targetLabel)
        }))
    end
    appendLine(
        parts,
        { r = 0.96, g = 0.82, b = 0.62 },
        T("DOCommon_UI_MissionViewer_Threat", "Threat: {label}  x{difficulty}", {
            label = tostring(detail.difficultyLabel or T("DOCommon_UI_ObjectiveHUD_Unknown", "Unknown")),
            difficulty = string.format("%.2f", tonumber(detail.difficulty) or 1.0)
        })
    )
    if remaining then
        appendLine(
            parts,
            detail.expiresSoon and { r = 0.98, g = 0.56, b = 0.42 } or { r = 0.72, g = 0.86, b = 0.98 },
            T("DOCommon_UI_MissionViewer_Expires", "Expires: {value}", { value = remaining })
        )
    end
    if detail.rewardPreview and detail.rewardPreview ~= "" then
        appendLine(parts, { r = 0.7, g = 0.92, b = 0.68 }, T("DOCommon_UI_MissionViewer_Rewards", "Rewards: {value}", {
            value = tostring(detail.rewardPreview)
        }))
    end
    if detail.currentObjectiveLabel and detail.currentObjectiveLabel ~= "" then
        appendLine(parts, { r = 1.0, g = 0.78, b = 0.42 }, T("DOCommon_UI_MissionViewer_Current", "Current: {value}", {
            value = tostring(detail.currentObjectiveLabel)
        }))
    end

    appendLine(parts, nil, "")
    appendLine(parts, { r = 0.92, g = 0.94, b = 0.98 }, T("DOCommon_UI_MissionViewer_Checklist", "Checklist"))
    for _, line in ipairs(detail.lines or {}) do
        local color = line.completed == true and { r = 0.58, g = 0.9, b = 0.66 } or { r = 0.86, g = 0.86, b = 0.88 }
        if line.current == true then
            color = { r = 1.0, g = 0.86, b = 0.62 }
        end
        if line.completed == true then
            appendLine(parts, color, T("DOCommon_UI_MissionViewer_LineDone", "[Done] {label} - {value}", {
                label = tostring(line.label or T("DOCommon_UI_MissionViewer_Objective", "Objective")),
                value = tostring(line.value or "")
            }))
        elseif line.current == true then
            appendLine(parts, color, T("DOCommon_UI_MissionViewer_LineNow", "[Now] {label} - {value}", {
                label = tostring(line.label or T("DOCommon_UI_MissionViewer_Objective", "Objective")),
                value = tostring(line.value or "")
            }))
        else
            appendLine(parts, color, T("DOCommon_UI_MissionViewer_LinePending", "[ ] {label} - {value}", {
                label = tostring(line.label or T("DOCommon_UI_MissionViewer_Objective", "Objective")),
                value = tostring(line.value or "")
            }))
        end
    end

    if detail.status == "completed" and detail.completionReason then
        appendLine(parts, nil, "")
        appendLine(parts, statusColor, T("DOCommon_UI_MissionViewer_CompletedVia", "Completed via: {value}", {
            value = tostring(detail.completionReason)
        }))
    elseif detail.status == "failed" and detail.failureReason then
        appendLine(parts, nil, "")
        appendLine(parts, statusColor, T("DOCommon_UI_MissionViewer_FailedDueTo", "Failed due to: {value}", {
            value = tostring(detail.failureReason)
        }))
    end

    return table.concat(parts)
end
