local addonName, ns = ...

ns.name = addonName
ns.displayName = "CraftSim Enhancer"
ns.version = "1.4"
ns.Config = ns.Config or {}
ns.Compat = ns.Compat or {}
ns.Modules = ns.Modules or {}
ns.ModuleOrder = ns.ModuleOrder or {}
ns.ModuleStatus = ns.ModuleStatus or {}
ns.Debug = ns.Debug or {}
ns.Data = ns.Data or {}
ns.Data.GeneratedRecipes = ns.Data.GeneratedRecipes or {}
ns.Data.ItemMetadata = ns.Data.ItemMetadata or {}
ns.warnings = ns.warnings or {}
ns.warned = ns.warned or {}

local PREFIX = "|cff33ff99[CraftSim Enhancer]|r "

function ns:Print(message)
    print(PREFIX .. tostring(message or ""))
end

function ns:WarnOnce(key, message)
    if self.warned[key] then
        return
    end
    self.warned[key] = true
    self.warnings[key] = tostring(message)
    self:Print("|cffffcc00Warning:|r " .. tostring(message))
end

function ns:RegisterModule(name, module)
    if self.Modules[name] then
        error("duplicate module registration: " .. tostring(name))
    end
    module.name = name
    self.Modules[name] = module
    table.insert(self.ModuleOrder, name)
    self.ModuleStatus[name] = {
        enabled = true,
        initialized = false,
    }
end

function ns:CreateEventDispatcher(owner, events)
    local frame = CreateFrame("Frame")
    for _, event in ipairs(events or {}) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local handler = owner[event]
        if handler then
            handler(owner, ...)
        end
    end)
    return frame
end

function ns.Filter(source, predicate)
    local result = {}
    for key, value in pairs(source or {}) do
        if predicate(value, key) then
            table.insert(result, value)
        end
    end
    return result
end

function ns.Map(source, transform)
    local result = {}
    for key, value in pairs(source or {}) do
        local mapped = transform(value, key)
        if mapped ~= nil then
            table.insert(result, mapped)
        end
    end
    return result
end

function ns.Find(source, predicate)
    for key, value in pairs(source or {}) do
        if predicate(value, key) then
            return value, key
        end
    end
end

function ns.Fold(source, initialValue, reducer)
    local result = initialValue
    for key, value in pairs(source or {}) do
        result = reducer(result, value, key)
    end
    return result
end

function ns.ToSet(source)
    local result = {}
    local seen = {}
    for _, value in pairs(source or {}) do
        if not seen[value] then
            table.insert(result, value)
            seen[value] = true
        end
    end
    return result
end

function ns.StringStartsWith(value, prefix)
    return string.sub(value, 1, #prefix) == prefix
end

function ns.GetReagentQuality(itemInfo)
    if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
        return C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemInfo)
    end
end

function ns.ContinueOnAllItemsLoaded(items, callback)
    local remaining = #items
    if remaining == 0 then
        callback()
        return
    end

    local finished = false
    local function itemLoaded()
        if finished then
            return
        end
        remaining = remaining - 1
        if remaining <= 0 then
            finished = true
            callback()
        end
    end

    for _, item in ipairs(items) do
        item:ContinueOnItemLoad(itemLoaded)
    end
end
