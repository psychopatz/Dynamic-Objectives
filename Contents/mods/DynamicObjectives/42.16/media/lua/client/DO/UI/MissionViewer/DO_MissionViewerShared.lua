DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_MissionViewerShared = DO_MissionViewerShared or {}

local DO = DynamicObjectives

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
        return string.format("%dm left", minutes)
    end
    if minutes <= 0 then
        return string.format("%dh left", wholeHours)
    end
    return string.format("%dh %dm left", wholeHours, minutes)
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
        return "Expires: " .. remaining
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
        return " <RGB:0.65,0.65,0.65> Select a mission to inspect its objectives and rewards. <LINE> "
    end

    local parts = {}
    local statusColor = DO_MissionViewerShared.getStatusColor(detail.status)
    local remaining = DO_MissionViewerShared.formatRemainingHours(detail.timeRemainingHours)

    appendLine(parts, statusColor, "Status: " .. tostring(detail.statusLabel or "Active"))
    if detail.chainSummary then
        appendLine(parts, { r = 0.62, g = 0.82, b = 1.0 }, "Chain: " .. tostring(detail.chainSummary))
    end
    if detail.targetLabel and detail.targetLabel ~= "" then
        appendLine(parts, { r = 0.82, g = 0.84, b = 0.88 }, "Target: " .. tostring(detail.targetLabel))
    end
    appendLine(
        parts,
        { r = 0.96, g = 0.82, b = 0.62 },
        string.format(
            "Threat: %s  x%.2f",
            tostring(detail.difficultyLabel or "Unknown"),
            tonumber(detail.difficulty) or 1.0
        )
    )
    if remaining then
        appendLine(
            parts,
            detail.expiresSoon and { r = 0.98, g = 0.56, b = 0.42 } or { r = 0.72, g = 0.86, b = 0.98 },
            "Expires: " .. remaining
        )
    end
    if detail.rewardPreview and detail.rewardPreview ~= "" then
        appendLine(parts, { r = 0.7, g = 0.92, b = 0.68 }, "Rewards: " .. tostring(detail.rewardPreview))
    end
    if detail.currentObjectiveLabel and detail.currentObjectiveLabel ~= "" then
        appendLine(parts, { r = 1.0, g = 0.78, b = 0.42 }, "Current: " .. tostring(detail.currentObjectiveLabel))
    end

    appendLine(parts, nil, "")
    appendLine(parts, { r = 0.92, g = 0.94, b = 0.98 }, "Checklist")
    for _, line in ipairs(detail.lines or {}) do
        local prefix = line.completed == true and "[Done] " or (line.current == true and "[Now] " or "[ ] ")
        local color = line.completed == true and { r = 0.58, g = 0.9, b = 0.66 } or { r = 0.86, g = 0.86, b = 0.88 }
        if line.current == true then
            color = { r = 1.0, g = 0.86, b = 0.62 }
        end
        appendLine(parts, color, prefix .. tostring(line.label or "Objective") .. " - " .. tostring(line.value or ""))
    end

    if detail.status == "completed" and detail.completionReason then
        appendLine(parts, nil, "")
        appendLine(parts, statusColor, "Completed via: " .. tostring(detail.completionReason))
    elseif detail.status == "failed" and detail.failureReason then
        appendLine(parts, nil, "")
        appendLine(parts, statusColor, "Failed due to: " .. tostring(detail.failureReason))
    end

    return table.concat(parts)
end
