local _, ns = ...
local Scanner = assert(ns.Modules.AuctionHouseScan)
local Config = Scanner.Shared.Config
local Catalog = assert(ns.Catalog)

function Scanner:GetConfigRecipes(ignoreFlatProfession)
    local recipes = {}
    local selected = self:GetSelectedProfessions()
    local profession = ignoreFlatProfession and "ALL" or self:GetConfigProfession()
    local expansion = Config:GetConfigExpansion()
    local availabilityFilter = Config:GetAvailabilityFilter()
    local character = ns.RecipeAvailability and ns.RecipeAvailability:GetCharacter()
    for _, info in ipairs(self.PROFESSIONS) do
        if selected[info.name] and (profession == "ALL" or profession == info.name) then
            for _, recipe in ipairs(Catalog:GetRecipes(info.name, expansion)) do
                if not ns.RecipeAvailability or ns.RecipeAvailability:Matches(recipe, availabilityFilter, character) then
                    recipes[#recipes + 1] = recipe
                end
            end
        end
    end
    return recipes
end

function Scanner:GetCatalogConfigTargets()
    self:EnsureProfessionSelectionForCurrentCrafter()
    if not self:HasSelectedProfession() then return {} end
    local index = Catalog:GetIndex()
    if self.catalogDataIndex ~= index then
        if self.catalogPreparation and self.catalogPreparation.job then self.catalogPreparation.job.cancelled = true end
        self.catalogDataIndex, self.catalogTargetCaches, self.catalogPreparation = index, {}, nil
        self.catalogCacheOrder = {}
    end
    local professions = {}
    for name, selected in pairs(self:GetSelectedProfessions()) do if selected then professions[#professions + 1] = name end end
    table.sort(professions)
    local migrating = not Config:IsRecipeSelectionExplicit() or Config:GetData().targetSelectionMode == "legacy-exclude"
    local key = migrating and "migration" or table.concat(professions, ":") .. ":" .. tostring(Config:GetConfigExpansion())
    if not migrating then
        local filter = Config:GetAvailabilityFilter()
        key = key .. ":" .. filter
        if filter ~= "ALL" and ns.RecipeAvailability then
            key = key .. ":" .. ns.Compat.WoW:GetCrafterUID() .. ":" .. ns.RecipeAvailability.revision
        end
    end
    self.catalogRequestedKey = key
    local cached = self.catalogTargetCaches[key]
    if not cached then
        if self.catalogPreparation and self.catalogPreparation.key == key then return {} end
        if self.catalogPreparation and self.catalogPreparation.job then self.catalogPreparation.job.cancelled = true end
        local marker = { key = key }
        self.catalogPreparation = marker
        local recipes = migrating and (ns.Data.GeneratedRecipes or {}) or self:GetConfigRecipes(true)
        marker.job = Catalog:RunJob(function(checkpoint)
            Catalog:GetItemSources(checkpoint)
            local targets, byKey = {}, {}
            for _, recipe in ipairs(recipes) do
                self:AddRecipeTargets(recipe, byKey, targets, { ignoreScanScope = true, skipFixedPrices = true })
                checkpoint()
            end
            Catalog:SortTargets(targets, checkpoint)
            self:BuildRecipeSelectionCatalog(targets, checkpoint)
            marker.byKey = byKey
            return targets
        end, function(targets, job)
            if self.catalogPreparation ~= marker then return end
            self.catalogPreparation = nil
            self.catalogTargetCaches[key] = { targets = targets, byKey = marker.byKey }
            self.catalogCacheOrder = self.catalogCacheOrder or {}
            self.catalogCacheOrder[#self.catalogCacheOrder + 1] = key
            if #self.catalogCacheOrder > 4 then self.catalogTargetCaches[table.remove(self.catalogCacheOrder, 1)] = nil end
            Catalog.perf.configRecipes, Catalog.perf.configTargets = #recipes, #targets
            Catalog.perf.maxConfigSliceMs = job.maxSliceMs
            self.selectedTargetCache = nil
            if self.configPanel and self.configPanel:IsShown() then self:UpdateConfigList(); self:UpdateButtons() end
        end, function(message)
            if self.catalogPreparation ~= marker then return end
            self.catalogPreparation = nil
            self.catalogTargetCaches[key] = { targets = {}, error = message }
            ns:WarnOnce("catalog-targets-" .. key, "Could not prepare recipe targets: " .. message)
        end)
        return {}
    end
    Catalog.perf.configCacheHits = (Catalog.perf.configCacheHits or 0) + 1
    if self.allConfigTargets ~= cached.targets or self.catalogBoundConfigData ~= Config:GetData() then
        self.catalogBoundConfigData = Config:GetData()
        self.allConfigTargets = cached.targets
        self.allConfigTargetsByKey = cached.byKey or {}
        Config:EnsureExplicitTargetSelection(cached.targets)
        self:EnsureRecipeSelectionModel(cached.targets)
        self:NormalizeOrphanedRecipeOverrides(cached.targets)
        self:RebuildSelectedTargetsFromRecipes(cached.targets)
        self.selectedTargetCache = nil
        if migrating then return self:GetCatalogConfigTargets() end
    end
    local profession = self:GetConfigProfession()
    local scope = Config:GetScanScope()
    if profession == "ALL" and scope == self.SCAN_SCOPES.BOTH then return cached.targets end
    cached.views = cached.views or {}
    local viewKey = profession .. ":" .. scope
    if cached.views[viewKey] then return cached.views[viewKey] end
    cached.views[viewKey] = ns.Filter(cached.targets, function(target)
        return self:IsTargetInConfigProfession(target, profession) and self:TargetMatchesScanScope(target)
    end)
    return cached.views[viewKey]
end

function Scanner:GetSelectedTargetsCached()
    local signature = tostring(self.configurationRevision or 0) .. ":" .. Config:GetScanScope()
    local selectedProfessions = self:GetSelectedProfessions()
    for _, info in ipairs(self.PROFESSIONS) do
        if selectedProfessions[info.name] then signature = signature .. ":" .. info.name end
    end
    local configData = Config:GetData()
    if self.selectedTargetCache and self.selectedTargetCache.signature == signature and self.selectedTargetCache.data == configData then return self.selectedTargetCache.targets end
    if self.selectedPreparation and self.selectedPreparation.signature == signature and self.selectedPreparation.data == configData then return {} end
    if self.selectedPreparation and self.selectedPreparation.job then self.selectedPreparation.job.cancelled = true end
    local selectedCount = 0
    for _, selected in pairs(Config:GetSelectedRecipes()) do if selected then selectedCount = selectedCount + 1 end end
    local hasOverrides = next(Config:GetTargetSelectionOverrides()) ~= nil
    if selectedCount > 200 or hasOverrides or not Config:IsRecipeSelectionExplicit() then
        local marker = { signature = signature, data = configData }
        self.selectedPreparation = marker
        marker.job = Catalog:RunJob(function(checkpoint)
            return self:BuildScanTargets({ skipFixedPrices = true, checkpoint = checkpoint }) or {}
        end, function(targets, job)
            if self.selectedPreparation ~= marker then return end
            self.selectedPreparation = nil
            self.selectedTargetCache = { signature = signature, targets = targets, data = configData }
            Catalog.perf.maxSelectionSliceMs = job.maxSliceMs
            self:UpdateConfigSummary(); self:UpdateButtons()
        end, function(message)
            if self.selectedPreparation ~= marker then return end
            self.selectedPreparation = nil
            self.selectedTargetCache = { signature = signature, targets = {}, data = configData }
            ns:WarnOnce("selected-targets-" .. signature, "Could not prepare selected targets: " .. message)
        end)
        return {}
    end
    self.selectedPreparation = nil
    local start = Catalog:Now()
    local targets = self:BuildScanTargets({ skipFixedPrices = true }) or {}
    self.selectedTargetCache = { signature = signature, targets = targets, data = configData }
    Catalog.perf.selectedTargetsMs = Catalog:Now() - start
    return targets
end

function Scanner:GetCatalogSelectionSummary()
    local counts = { selectedRecipes = 0, totalRecipes = 0, products = 0, reagents = 0, targets = 0 }
    for _, target in ipairs(self:GetSelectedTargetsCached()) do
        if target.pricingMode == "output" then counts.products = counts.products + 1
        else counts.reagents = counts.reagents + 1 end
    end
    counts.targets = counts.products + counts.reagents
    if not self.catalogVisibleSummary or self.catalogVisibleSummary.targets ~= self.configTargets then
        local byRecipe = self:BuildRecipeSelectionCatalog(self.configTargets or {})
        local visible, total = {}, 0
        for _, recipe in ipairs(self:GetConfigRecipes()) do
            local identity = self:GetRecipeTreeIdentity(recipe)
            if byRecipe[identity] and not recipe.catalogOnlyReason then visible[identity] = true; total = total + 1 end
        end
        self.catalogVisibleSummary = { targets = self.configTargets, visible = visible, total = total }
    end
    counts.totalRecipes = self.catalogVisibleSummary.total
    for identity, selected in pairs(Config:GetSelectedRecipes()) do
        if selected and self.catalogVisibleSummary.visible[identity] then counts.selectedRecipes = counts.selectedRecipes + 1 end
    end
    return counts
end

function Scanner:SetAvailabilityFilter(filter)
    Config:SaveAvailabilityFilter(filter)
    self.recipeTreeCache, self.catalogVisibleSummary = nil, nil
    if self.configPanel then self.configPanel.scrollFrame:SetVerticalScroll(0) end
    self:UpdateConfigList()
    self:UpdateButtons()
end

function Scanner:SetScanLearnedOnly(enabled)
    Config:SaveScanLearnedOnly(enabled)
    self:InvalidateScanConfiguration()
    self:UpdateConfigList()
    self:UpdateButtons()
    self:UpdateProgressText()
end

function Scanner:SetConfigExpansion(expansion)
    Config:SaveConfigExpansion(expansion)
    self.recipeTreeCache = nil
    if self.configPanel then self.configPanel.scrollFrame:SetVerticalScroll(0) end
    self:UpdateConfigList() -- This changes the view, never saved scan selections or completed scan results.
end

function Scanner:GetCatalogRecipeEntries()
    if self.catalogPreparation then return {} end
    if self.recipeTreeCache then return self.recipeTreeCache end
    local targets, recipes = self.configTargets or {}, self:GetConfigRecipes()
    local revision = self.treeExpansionRevision or 0
    if self.treePreparation and self.treePreparation.targets == targets and self.treePreparation.revision == revision then return {} end
    if self.treePreparation and self.treePreparation.job then self.treePreparation.job.cancelled = true end
    local function BuildEntries(checkpoint)
        self.expandedExpansionGroups = self.expandedExpansionGroups or {}
        local byRecipe = self:BuildRecipeSelectionCatalog(targets, checkpoint)
        local index, groups, entries = Catalog:GetIndex(), {}, {}
        local character = ns.RecipeAvailability and ns.RecipeAvailability:GetCharacter()
        for _, recipe in ipairs(recipes) do
            local identity = self:GetRecipeTreeIdentity(recipe)
            local targetMap = byRecipe[identity]
            if targetMap or recipe.catalogOnlyReason then
                local categoryID, info = self:GetRecipeCategoryInfo(recipe)
                info = info or { name = "Other", order = 999 }
                local expansionID = index.expansionByIdentity[identity]
                local profession = recipe.profession
                groups[profession] = groups[profession] or {}
                local expansions = groups[profession]
                expansions[expansionID] = expansions[expansionID] or { categories = {}, identities = {}, expansionID = expansionID }
                local expansion = expansions[expansionID]
                local categoryKey = categoryID or 0
                expansion.categories[categoryKey] = expansion.categories[categoryKey] or
                    { id = categoryKey, info = info, recipes = {}, identities = {} }
                local category = expansion.categories[categoryKey]
                local selectable = not recipe.catalogOnlyReason and targetMap and next(targetMap)
                local identities = selectable and { [identity] = true } or {}
                category.recipes[#category.recipes + 1] = { kind = "recipe", recipe = recipe, profession = profession,
                    label = recipe.stratName .. (recipe.catalogOnlyReason and " (catalog only)" or ""),
                    recipeIdentities = identities, catalogOnlyReason = recipe.catalogOnlyReason,
                    availability = ns.RecipeAvailability and ns.RecipeAvailability:GetState(recipe, character) or "UNCHECKED",
                    targets = self:TargetMapToList(targetMap or {}) }
                if selectable then category.identities[identity] = true; expansion.identities[identity] = true end
            end
            checkpoint()
        end
        local function Append(kind, key, label, profession, identities, defaultExpanded)
            local states = kind == "profession" and self.expandedProfessionGroups or
                kind == "expansion" and self.expandedExpansionGroups or self.expandedCategoryGroups
            local expanded = self:GetTreeExpanded(states, key, defaultExpanded)
            entries[#entries + 1] = { kind = kind, key = key, label = label, profession = profession,
                recipeIdentities = identities, expanded = expanded }
            return expanded
        end
        local firstProfession = true
        for _, professionInfo in ipairs(self.PROFESSIONS) do
            local profession = professionInfo.name
            if groups[profession] then
                local expansions, identities = {}, {}
                for _, group in pairs(groups[profession]) do
                    expansions[#expansions + 1] = group
                    for id in pairs(group.identities) do identities[id] = true end
                end
                table.sort(expansions, function(a, b) return a.expansionID > b.expansionID end)
                local opened = Append("profession", "profession:" .. profession, self:GetProfessionDisplayName(professionInfo),
                    profession, identities, firstProfession)
                firstProfession = false
                if opened then
                    for expansionIndex, expansion in ipairs(expansions) do
                        if Append("expansion", "expansion:" .. profession .. ":" .. expansion.expansionID,
                            index.expansions[expansion.expansionID], profession, expansion.identities, expansionIndex == 1) then
                            local categories = {}
                            for _, category in pairs(expansion.categories) do categories[#categories + 1] = category end
                            table.sort(categories, function(a, b)
                                if a.info.order ~= b.info.order then return (a.info.order or 999) < (b.info.order or 999) end
                                return a.info.name < b.info.name
                            end)
                            for _, category in ipairs(categories) do
                                if Append("category", "category:" .. profession .. ":" .. category.id, category.info.name,
                                    profession, category.identities, false) then
                                    table.sort(category.recipes, function(a, b) return a.label < b.label end)
                                    for _, recipe in ipairs(category.recipes) do entries[#entries + 1] = recipe; checkpoint() end
                                end
                            end
                        end
                    end
                end
            end
        end
        return entries
    end
    if #recipes <= 200 then
        local started = Catalog:Now()
        self.recipeTreeCache = BuildEntries(function() end)
        Catalog.perf.treeBuildMs, Catalog.perf.treeRows = Catalog:Now() - started, #self.recipeTreeCache
        return self.recipeTreeCache
    end
    local marker = { targets = targets, revision = revision }
    self.treePreparation = marker
    marker.job = Catalog:RunJob(BuildEntries, function(entries, job)
        if self.treePreparation ~= marker then return end
        self.treePreparation, self.recipeTreeCache = nil, entries
        Catalog.perf.treeBuildMs, Catalog.perf.treeRows, Catalog.perf.maxTreeSliceMs = job.workMs, #entries, job.maxSliceMs
        if self.configPanel and self.configPanel:IsShown() then self:UpdateConfigList(); self:UpdateButtons() end
    end, function(message)
        if self.treePreparation ~= marker then return end
        self.treePreparation, self.recipeTreeCache = nil, {}
        ns:WarnOnce("recipe-tree", "Could not prepare recipe tree: " .. message)
    end)
    return {}
end

function Scanner:SetCatalogGroupsExpanded(expanded)
    self.treeExpansionRevision = (self.treeExpansionRevision or 0) + 1
    self.recipeTreeCache = nil
    self.expandedExpansionGroups = self.expandedExpansionGroups or {}
    for _, recipe in ipairs(self:GetConfigRecipes()) do
        local categoryID = self:GetRecipeCategoryInfo(recipe)
        local expansionID = Catalog:GetIndex().expansionByIdentity[self:GetRecipeTreeIdentity(recipe)]
        self.expandedProfessionGroups["profession:" .. recipe.profession] = expanded
        self.expandedExpansionGroups["expansion:" .. recipe.profession .. ":" .. expansionID] = expanded
        self.expandedCategoryGroups["category:" .. recipe.profession .. ":" .. tostring(categoryID or 0)] = expanded
    end
    self:UpdateConfigList()
end

function Scanner:RenderCatalogRows(kind, entries)
    if self.renderingCatalogRows then return end
    self.renderingCatalogRows = true
    local panel = self.configPanel
    self.catalogDisplayedKind, self.catalogDisplayedEntries = kind, entries
    local rowHeight = 24
    local first = math.floor((panel.scrollFrame:GetVerticalScroll() or 0) / rowHeight) + 1
    local visible = math.ceil((panel.scrollFrame:GetHeight() or 360) / rowHeight) + 2
    local pool = kind == "recipes" and self.recipeRows or self.configRows
    for slot = 1, visible do
        local index, entry = first + slot - 1, entries[first + slot - 1]
        if entry then
            local row = pool[slot]
            if not row then
                row = kind == "recipes" and self:CreateRecipeRow(panel.scrollChild) or self:CreateConfigRow(panel.scrollChild)
                pool[slot] = row
            end
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -(index - 1) * rowHeight)
            row.bg:SetShown(kind == "recipes" and entry.kind ~= "recipe" or index % 2 == 0)
            if kind == "recipes" then self:UpdateRecipeRow(row, entry) else self:UpdateConfigRow(row, entry) end
            row:Show()
        elseif pool[slot] then pool[slot]:Hide() end
    end
    for slot = visible + 1, #pool do pool[slot]:Hide() end
    local height = math.max(1, #entries * rowHeight)
    if self.catalogContentHeight ~= height then panel.scrollChild:SetHeight(height); self.catalogContentHeight = height end
    Catalog.perf.allocatedRecipeRows, Catalog.perf.allocatedItemRows = #self.recipeRows, #self.configRows
    self.renderingCatalogRows = false
end
