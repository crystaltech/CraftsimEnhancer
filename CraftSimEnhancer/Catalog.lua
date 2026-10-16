local _, ns = ...
local Catalog = { perf = {} }
ns.Catalog = Catalog

function Catalog:Now()
    return type(debugprofilestop) == "function" and debugprofilestop() or 0
end

function Catalog:Identity(recipe)
    return recipe.recipeID and "id:" .. tostring(recipe.recipeID) or
        "name:" .. tostring(recipe.profession or "") .. ":" .. tostring(recipe.stratName or "")
end

function Catalog:GetIndex()
    local data = ns.Data
    if self.index and self.base == data.GeneratedRecipes and self.imported == data.ImportedRecipes and
        self.categories == data.RecipeCategories then return self.index end
    local started = self:Now()
    local index = { recipes = {}, byIdentity = {}, byID = {}, byProfession = {}, byExpansion = {},
        expansionByIdentity = {}, expansions = {}, catalogOnly = 0 }
    local categories = data.RecipeCategories or {}
    for _, source in ipairs({ data.GeneratedRecipes or {}, data.ImportedRecipes or {} }) do
        for _, recipe in ipairs(source) do
            local identity = self:Identity(recipe)
            if not index.byIdentity[identity] then
                local categoryID = recipe.recipeID and categories.recipeIDs and categories.recipeIDs[recipe.recipeID] or
                    categories.recipeNames and categories.recipeNames[tostring(recipe.profession) .. ":" .. tostring(recipe.stratName)]
                local info = categoryID and categories.categories and categories.categories[categoryID]
                local expansion = info and info.expansionID
                -- Original generated records with no explicit expansion metadata are Midnight.
                if expansion == nil then expansion = recipe.catalogOnlyReason and -1 or 11 end
                index.recipes[#index.recipes + 1] = recipe
                index.byIdentity[identity] = recipe
                if recipe.recipeID then index.byID[recipe.recipeID] = recipe end
                local profession = recipe.profession
                index.byProfession[profession] = index.byProfession[profession] or {}
                table.insert(index.byProfession[profession], recipe)
                index.byExpansion[profession] = index.byExpansion[profession] or {}
                index.byExpansion[profession][expansion] = index.byExpansion[profession][expansion] or {}
                table.insert(index.byExpansion[profession][expansion], recipe)
                index.expansionByIdentity[identity] = expansion
                index.expansions[expansion] = info and info.expansionName or (expansion == 11 and "Midnight" or "Unknown")
                if recipe.catalogOnlyReason then index.catalogOnly = index.catalogOnly + 1 end
            end
        end
    end
    self.base, self.imported, self.categories = data.GeneratedRecipes, data.ImportedRecipes, data.RecipeCategories
    self.index = index
    self.perf.indexBuildMs = self:Now() - started
    self.perf.recipes = #index.recipes
    return index
end

function Catalog:GetRecipes(profession, expansion)
    local index = self:GetIndex()
    if expansion ~= nil and expansion ~= "ALL" then
        return index.byExpansion[profession] and index.byExpansion[profession][tonumber(expansion)] or {}
    end
    return index.byProfession[profession] or {}
end

function Catalog:GetItemSources(checkpoint)
    local index = self:GetIndex()
    if index.itemSources then return index.itemSources end
    -- Concurrent view/count jobs share progress; cancellation never makes
    -- another job rebuild the entire ownership index.
    index.itemSourcesWork = index.itemSourcesWork or { sources = { input = {}, output = {} }, next = 1 }
    local work = index.itemSourcesWork
    local sources = work.sources
    while work.next <= #index.recipes do
        local recipe = index.recipes[work.next]
        work.next = work.next + 1
        if not recipe.catalogOnlyReason then
            for _, group in ipairs({ { "reagents", "input" }, { "outputs", "output" } }) do
                local role = sources[group[2]]
                for _, entry in ipairs(recipe[group[1]] or {}) do
                    for _, itemID in ipairs(entry.itemIDs or {}) do
                        role[itemID] = role[itemID] or {}
                        role[itemID][self:Identity(recipe)] = recipe
                    end
                end
            end
        end
        if checkpoint then checkpoint() end
    end
    index.itemSources = sources
    index.itemSourcesWork = nil
    return sources
end

function Catalog:GetTargetRecipes(target)
    local sources = self:GetItemSources()
    local roles = target.kindMap or { [target.pricingMode == "output" and "output" or "input"] = true }
    if not (roles.input and roles.output) then
        return sources[roles.output and "output" or "input"][target.itemID] or {}
    end
    local result = {}
    for role in pairs(roles) do
        for identity, recipe in pairs(sources[role] and sources[role][target.itemID] or {}) do result[identity] = recipe end
    end
    return result
end

function Catalog:GetSelectedRecipes(config, professions, checkpoint)
    local index = self:GetIndex()
    local result, seen = {}, {}
    local function Add(recipe)
        if recipe and not recipe.catalogOnlyReason and professions[recipe.profession] then
            local identity = self:Identity(recipe)
            if not seen[identity] then result[#result + 1] = recipe; seen[identity] = true end
        end
    end
    for identity, selected in pairs(config:GetSelectedRecipes()) do
        if selected then Add(index.byIdentity[identity]) end
        if checkpoint then checkpoint() end
    end
    local overrides = config:GetTargetSelectionOverrides()
    if next(overrides) == nil then return result end
    local sources = self:GetItemSources(checkpoint)
    for key, selected in pairs(overrides) do
        if selected then
            local itemID, role = key:match("^(%d+):[^:]+:(%a+)$")
            itemID = tonumber(itemID)
            role = role == "output" and "output" or "input"
            for _, recipe in pairs(sources[role][itemID] or {}) do
                Add(recipe)
                if checkpoint then checkpoint() end
            end
        end
        if checkpoint then checkpoint() end
    end
    return result
end

-- Time-sliced work runs only when explicitly requested. No idle OnUpdate loop.
function Catalog:RunJob(work, complete, failed)
    local job = { cancelled = false, maxSliceMs = 0, workMs = 0 }
    local sliceStart, operations = 0, 0
    local thread = coroutine.create(function()
        return work(function()
            operations = operations + 1
            if (type(debugprofilestop) == "function" and self:Now() - sliceStart >= 2) or
                (type(debugprofilestop) ~= "function" and operations >= 32) then
                coroutine.yield()
                operations = 0
            end
        end)
    end)
    local function Resume()
        if job.cancelled then return end
        sliceStart = self:Now()
        local ok, result = coroutine.resume(thread)
        local elapsed = self:Now() - sliceStart
        job.maxSliceMs = math.max(job.maxSliceMs, elapsed)
        job.workMs = job.workMs + elapsed
        if not ok then if failed then failed(tostring(result)) end; return end
        if coroutine.status(thread) == "dead" then complete(result, job)
        elseif C_Timer and C_Timer.After then C_Timer.After(0, Resume)
        else Resume() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Resume) else Resume() end
    return job
end

function Catalog:SortTargets(values, checkpoint)
    local width, count = 1, #values
    local scratch = {}
    while width < count do
        for first = 1, count, width * 2 do
            local left, right, middle, last = first, first + width, math.min(first + width - 1, count),
                math.min(first + width * 2 - 1, count)
            for output = first, last do
                if left <= middle and (right > last or tostring(values[left].label or values[left].itemID) <=
                    tostring(values[right].label or values[right].itemID)) then
                    scratch[output] = values[left]; left = left + 1
                else scratch[output] = values[right]; right = right + 1 end
                checkpoint()
            end
        end
        for index = 1, count do values[index] = scratch[index]; checkpoint() end
        width = width * 2
    end
    return values
end
