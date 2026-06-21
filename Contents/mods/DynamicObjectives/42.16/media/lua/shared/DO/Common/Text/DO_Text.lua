DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Text = DynamicObjectives.Text or {}

local Text = DynamicObjectives.Text

Text.Tables = Text.Tables or {}
Text.FallbackDomains = Text.FallbackDomains or {
    "DOCommon_UI",
    "DOCommon_Dialogue",
}
Text._missingLogged = Text._missingLogged or {}

local function getLanguageCode()
    if Translator and Translator.getLanguage and Translator.getLanguage() then
        return Translator.getLanguage():toString()
    end
    return "EN"
end

local function getTableName(domain, lang)
    return "DO_Text_" .. tostring(domain) .. "_" .. tostring(lang)
end

local function getRegisteredTable(domain, lang)
    local domainTables = Text.Tables[domain]
    return domainTables and domainTables[lang] or nil
end

local function getRawTable(domain, lang)
    local registered = getRegisteredTable(domain, lang)
    if type(registered) == "table" then
        return registered
    end
    return rawget(_G, getTableName(domain, lang))
end

local function getFallbackValue(key, lang)
    for _, domain in ipairs(Text.FallbackDomains or {}) do
        local tableData = getRawTable(domain, lang)
        local value = tableData and tableData[key]
        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    if lang ~= "EN" then
        for _, domain in ipairs(Text.FallbackDomains or {}) do
            local tableData = getRawTable(domain, "EN")
            local value = tableData and tableData[key]
            if type(value) == "string" and value ~= "" then
                return value
            end
        end
    end

    return nil
end

local function resolveGameText(key)
    if not key or key == "" or type(getText) ~= "function" then
        return nil
    end

    local ok, value = pcall(getText, tostring(key))
    if not ok or type(value) ~= "string" or value == "" or value == tostring(key) then
        return nil
    end

    return value
end

function Text.RegisterDomain(domain)
    local value = tostring(domain or "")
    if value == "" then
        return
    end

    for _, existing in ipairs(Text.FallbackDomains) do
        if existing == value then
            return
        end
    end

    Text.FallbackDomains[#Text.FallbackDomains + 1] = value
end

function Text.RegisterTable(domain, lang, data)
    if not domain or not lang or type(data) ~= "table" then
        return
    end

    Text.Tables[domain] = Text.Tables[domain] or {}
    Text.Tables[domain][lang] = data
    Text.RegisterDomain(domain)
    rawset(_G, getTableName(domain, lang), data)
end

function Text.Format(template, params)
    local text = tostring(template or "")
    if type(params) ~= "table" then
        return text
    end

    return (text:gsub("{([%w_]+)}", function(name)
        local value = params[name]
        if value == nil then
            return "{" .. name .. "}"
        end
        return tostring(value)
    end))
end

function Text.Exists(key)
    local resolved = resolveGameText(key)
    if resolved then
        return true
    end

    return getFallbackValue(tostring(key or ""), getLanguageCode()) ~= nil
end

function Text.LogMissing(key)
    local normalized = tostring(key or "")
    if normalized == "" or Text._missingLogged[normalized] then
        return false
    end

    local enabled = DynamicObjectives and DynamicObjectives.Config and DynamicObjectives.Config.DebugText == true
    if not enabled then
        return false
    end

    Text._missingLogged[normalized] = true
    if DynamicObjectives and DynamicObjectives.LogWarn then
        DynamicObjectives.LogWarn("Text", "Missing translation key: " .. normalized)
    elseif DynamicObjectives and DynamicObjectives.Log then
        DynamicObjectives.Log("Warn", "Text", "Missing translation key: " .. normalized)
    end
    return true
end

function Text.Get(key, params, fallback)
    local normalized = tostring(key or "")
    local resolved = resolveGameText(normalized)
    if not resolved then
        resolved = getFallbackValue(normalized, getLanguageCode())
    end
    if not resolved or resolved == "" then
        resolved = fallback or normalized
        Text.LogMissing(normalized)
    end

    return Text.Format(resolved, params)
end
