local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before configuration UI")
local Shared = Scanner.Shared
local Config = Shared.Config
local SetButtonEnabled = Shared.SetButtonEnabled

function Scanner:ToggleConfigPanel()
    if not self:HasSelectedProfession() then
        self:SetStatus("Choose at least one profession first.")
        return
    end
    self:ShowPanelView("config")
end

---@return string profession
function Scanner:GetConfigProfession()
    -- The recipe tree already groups every profession selected in the left
    -- column. Keep the saved profession filter for the flat Individual Items view,
    -- but never let that hidden filter narrow the hierarchy.
    if self.configView == "presets" then
        return "ALL"
    end

    local profession = Config:GetConfigProfession()
    local selectedProfessions = self:GetSelectedProfessions()
    if profession ~= "ALL" and (not self:GetProfessionInfoByName(profession) or not selectedProfessions[profession]) then
        profession = "ALL"
        Config:SaveConfigProfession(profession)
    end
    return profession
end

---@param target table
---@param profession string
---@return boolean
function Scanner:IsTargetInConfigProfession(target, profession)
    return profession == "ALL" or (target.professionMap and target.professionMap[profession] == true)
end

---@param targets table[]
---@return table<string, table<string, table>> targetsByRecipe
---@return table<string, table<string, boolean>> recipesByTarget
function Scanner:BuildRecipeSelectionCatalog(targets)
    local targetsByRecipe = {}
    local recipesByTarget = {}
    local knownRecipes = {}
    for _, recipe in ipairs(self:GetGeneratedRecipes()) do
        knownRecipes[self:GetRecipeTreeIdentity(recipe)] = true
    end

    local function add(recipeIdentity, target)
        if not knownRecipes[recipeIdentity] then
            return
        end
        targetsByRecipe[recipeIdentity] = targetsByRecipe[recipeIdentity] or {}
        targetsByRecipe[recipeIdentity][target.key] = target
        recipesByTarget[target.key] = recipesByTarget[target.key] or {}
        recipesByTarget[target.key][recipeIdentity] = true
    end

    for _, target in ipairs(targets or {}) do
        for recipeID in pairs(target.sourceRecipeMap or {}) do
            add("id:" .. tostring(recipeID), target)
        end
        for profession, sourceNames in pairs(target.sourceNamesByProfession or {}) do
            for sourceName in pairs(sourceNames) do
                add("name:" .. tostring(profession) .. ":" .. tostring(sourceName), target)
            end
        end
    end
    return targetsByRecipe, recipesByTarget
end

---@param targets table[]
function Scanner:RebuildSelectedTargetsFromRecipes(targets)
    targets = targets or self.allConfigTargets
    if not targets then
        return
    end
    local _, recipesByTarget = self:BuildRecipeSelectionCatalog(targets)
    local overrides = Config:GetTargetSelectionOverrides()
    local selectedTargets = {}
    for _, target in ipairs(targets) do
        local selected = false
        for recipeIdentity in pairs(recipesByTarget[target.key] or {}) do
            if Config:IsRecipeSelected(recipeIdentity) then
                selected = true
                break
            end
        end
        if overrides[target.key] ~= nil then
            selected = overrides[target.key] == true
        end
        if selected then
            selectedTargets[target.key] = true
        end
    end
    Config:ReplaceSelectedTargets(selectedTargets)
end

---@param targets table[]
function Scanner:EnsureRecipeSelectionModel(targets)
    if Config:IsRecipeSelectionExplicit() then
        return
    end

    local targetsByRecipe = self:BuildRecipeSelectionCatalog(targets)
    local selectedRecipes = {}
    local selectedByRecipe = {}
    for recipeIdentity, targetMap in pairs(targetsByRecipe) do
        local hasTargets = false
        local allSelected = true
        for _, target in pairs(targetMap) do
            hasTargets = true
            if not Config:IsTargetSelected(target.key) then
                allSelected = false
                break
            end
        end
        if hasTargets and allSelected then
            selectedRecipes[recipeIdentity] = true
            for targetKey in pairs(targetMap) do
                selectedByRecipe[targetKey] = true
            end
        end
    end

    local overrides = {}
    local savedOverrides = Config:GetTargetSelectionOverrides()
    for _, target in ipairs(targets or {}) do
        local wasSelected = Config:IsTargetSelected(target.key)
        local selectedFromRecipe = selectedByRecipe[target.key] == true
        if savedOverrides[target.key] ~= nil then
            overrides[target.key] = savedOverrides[target.key] == true
        elseif wasSelected ~= selectedFromRecipe then
            overrides[target.key] = wasSelected
        end
    end
    Config:InitializeRecipeSelection(selectedRecipes, overrides)
    self:RebuildSelectedTargetsFromRecipes(targets)
end

---@param targetKey string
---@param selected boolean
function Scanner:SaveIndividualTargetSelection(targetKey, selected)
    Config:SaveTargetSelectionOverride(targetKey, selected)
    if self.allConfigTargets then
        self:RebuildSelectedTargetsFromRecipes()
    else
        -- Configuration may not have been opened yet, so the complete recipe
        -- catalog is unavailable. Preserve the immediate effective choice;
        -- the saved override will be applied when the catalog is initialized.
        Config:SaveTargetSelected(targetKey, selected)
    end
end

---@return table[] targets
function Scanner:GetConfigTargets()
    self:EnsureProfessionSelectionForCurrentCrafter()
    if not self:HasSelectedProfession() then
        return {}
    end

    local targets = self:BuildScanTargets({
        includeAllProfessions = true,
        ignoreSavedFilter = true,
        ignoreScanScope = true,
        skipFixedPrices = true,
    }) or {}

    Config:EnsureExplicitTargetSelection(targets)
    self.allConfigTargets = targets
    self:EnsureRecipeSelectionModel(targets)

    local profession = self:GetConfigProfession()
    return ns.Filter(targets, function(target)
        return self:IsTargetInSelectedProfessions(target)
            and self:IsTargetInConfigProfession(target, profession)
            and self:TargetMatchesScanScope(target)
    end)
end

function Scanner:UpdateConfigSummary()
    local panel = self.configPanel
    if not panel or not panel.summaryText then
        return
    end

    local products, reagents = 0, 0
    local scanTargets = self:BuildScanTargets({ skipFixedPrices = true }) or {}
    for _, target in ipairs(scanTargets) do
        if target.kindMap and target.kindMap.output then
            products = products + 1
        elseif target.kindMap and target.kindMap.input then
            reagents = reagents + 1
        end
    end
    local total = products + reagents
    panel.summaryText:SetText(string.format("%d products + %d reagents = %d AH searches", products, reagents, total))
end

---@param scope string
function Scanner:SetScanScope(scope)
    Config:SaveScanScope(scope)
    self.scanComplete = false
    self.overridesPushed = false
    self:SetStatus("Scanning " .. string.lower(self:GetScanScopeLabel(scope)) .. ".")
    self:UpdateConfigList()
    self:UpdateButtons()
    self:UpdateProgressText()
end

function Scanner:UpdateScanScopeButtons()
    local panel = self.configPanel
    if not panel or not panel.scopeButtons then
        return
    end
    local activeScope = Config:GetScanScope()
    for scope, button in pairs(panel.scopeButtons) do
        local active = scope == activeScope
        button:SetText((active and "• " or "") .. self:GetScanScopeLabel(scope))
        SetButtonEnabled(button, not self.isScanning and not active)
    end
end

---@param selected boolean
function Scanner:SetAllVisibleTargetsSelected(selected)
    if self.configView == "presets" then
        local changedRecipes = {}
        local changedCount = 0
        for _, entry in ipairs(self:GetPresetListEntries()) do
            for recipeIdentity in pairs(entry.recipeIdentities or {}) do
                if not changedRecipes[recipeIdentity] then
                    changedRecipes[recipeIdentity] = true
                    changedCount = changedCount + 1
                end
            end
        end
        for recipeIdentity in pairs(changedRecipes) do
            Config:SaveRecipeSelected(recipeIdentity, selected)
        end
        self:RebuildSelectedTargetsFromRecipes()
        self.scanComplete = false
        self.overridesPushed = false
        self:SetStatus(string.format("%s %d visible recipes.", selected and "Selected" or "Cleared", changedCount))
        self:UpdateConfigList()
        self:UpdateButtons()
        self:UpdateProgressText()
        return
    end

    local targets = self.configTargets or {}
    targets = ns.Filter(targets, function(target)
        return self:TargetMatchesItemSearch(target)
    end)
    for _, target in ipairs(targets) do
        Config:SaveTargetSelectionOverride(target.key, selected)
    end
    self:RebuildSelectedTargetsFromRecipes()
    self.scanComplete = false
    self.overridesPushed = false
    self:SetStatus(string.format("%s %d visible scan items.", selected and "Selected" or "Cleared", #targets))
    self:UpdateConfigList()
    self:UpdateButtons()
    self:UpdateProgressText()
end

---@param target table
---@return boolean
function Scanner:TargetMatchesItemSearch(target)
    if self.showSelectedItemsOnly and not Config:IsTargetSelected(target.key) then
        return false
    end
    local searchText = string.lower(tostring(self.itemSearchText or ""))
    searchText = string.match(searchText, "^%s*(.-)%s*$") or ""
    if searchText == "" then
        return true
    end
    local haystack = {
        tostring(target.label or ""),
        tostring(target.itemID or ""),
        self:GetTargetTypeText(target),
    }
    for sourceName in pairs(target.sourceNames or {}) do
        table.insert(haystack, tostring(sourceName))
    end
    return string.find(string.lower(table.concat(haystack, " ")), searchText, 1, true) ~= nil
end

---@param targets table[]?
---@param limit number?
---@return string[] selectedLabels
---@return string[] unselectedLabels
---@return number selectedRemaining
---@return number unselectedRemaining
function Scanner:GetTargetSelectionPreview(targets, limit)
    limit = math.max(1, tonumber(limit) or 5)
    local selectedTargets = {}
    local unselectedTargets = {}
    for _, target in ipairs(targets or {}) do
        local destination = Config:IsTargetSelected(target.key) and selectedTargets or unselectedTargets
        table.insert(destination, target)
    end

    local function sortTargets(left, right)
        local leftLabel = tostring(left.label or left.itemID or "")
        local rightLabel = tostring(right.label or right.itemID or "")
        if leftLabel ~= rightLabel then
            return leftLabel < rightLabel
        end
        return (tonumber(left.itemID) or 0) < (tonumber(right.itemID) or 0)
    end
    table.sort(selectedTargets, sortTargets)
    table.sort(unselectedTargets, sortTargets)

    local function formatTargets(values)
        local labels = {}
        for index = 1, math.min(limit, #values) do
            local target = values[index]
            local label = tostring(target.label or ("Item " .. tostring(target.itemID)))
            table.insert(labels, string.format("%s (ItemID %s)", label, tostring(target.itemID or "?")))
        end
        return labels, math.max(0, #values - #labels)
    end

    local selectedLabels, selectedRemaining = formatTargets(selectedTargets)
    local unselectedLabels, unselectedRemaining = formatTargets(unselectedTargets)
    return selectedLabels, unselectedLabels, selectedRemaining, unselectedRemaining
end

---@return boolean allExpanded
function Scanner:AreAllRecipeGroupsExpanded()
    local foundGroup = false
    for _, entry in ipairs(self:GetPresetListEntries()) do
        if entry.kind == "profession" or entry.kind == "category" then
            foundGroup = true
            if not entry.expanded then
                return false
            end
        end
    end
    return foundGroup
end

---@param expanded boolean
function Scanner:SetAllRecipeGroupsExpanded(expanded)
    local selectedProfessions = self:GetSelectedProfessions()
    for _, professionInfo in ipairs(self.PROFESSIONS) do
        if selectedProfessions[professionInfo.name] then
            self.expandedProfessionGroups["profession:" .. professionInfo.name] = expanded
        end
    end
    for _, recipe in ipairs(self:GetGeneratedRecipes()) do
        if recipe.profession and selectedProfessions[recipe.profession] then
            local categoryID = self:GetRecipeCategoryInfo(recipe)
            self.expandedCategoryGroups["category:" .. recipe.profession .. ":" .. tostring(categoryID or 0)] = expanded
        end
    end
    self:UpdateConfigList()
end

function Scanner:UpdateTreeExpansionButton()
    local panel = self.configPanel
    if not panel or not panel.treeExpansionButton then
        return
    end
    panel.treeExpansionButton:SetText(self:AreAllRecipeGroupsExpanded() and "Collapse all" or "Expand all")
end

---@param target table
---@return string
function Scanner:GetConfigRowTooltip(target)
    local lines = {
        tostring(target.label or ("Item " .. tostring(target.itemID))),
        "ItemID: " .. tostring(target.itemID),
        "Type: " .. self:GetTargetTypeText(target),
    }

    local sourceNames = {}
    local profession = self:GetConfigProfession()
    local sourceMap = target.sourceNames or {}
    if profession ~= "ALL" and target.sourceNamesByProfession then
        sourceMap = target.sourceNamesByProfession[profession] or sourceMap
    elseif profession == "ALL" and target.sourceNamesByProfession then
        sourceMap = {}
        for selectedProfession, selected in pairs(self:GetSelectedProfessions()) do
            if selected then
                for sourceName in pairs(target.sourceNamesByProfession[selectedProfession] or {}) do
                    sourceMap[sourceName] = true
                end
            end
        end
    end
    for sourceName in pairs(sourceMap) do
        table.insert(sourceNames, sourceName)
    end
    table.sort(sourceNames)

    if #sourceNames > 0 then
        table.insert(lines, "Recipes:")
        for index, sourceName in ipairs(sourceNames) do
            if index > 8 then
                table.insert(lines, "...")
                break
            end
            table.insert(lines, "- " .. tostring(sourceName))
        end
    end

    return table.concat(lines, "\n")
end

---@param row Frame
---@param target table
function Scanner:UpdateConfigRow(row, target)
    row.target = target
    row.checkbox:SetChecked(Config:IsTargetSelected(target.key))
    row.typeText:SetText(self:GetTargetTypeText(target))
    row.nameText:SetText(tostring(target.label or ("Item " .. tostring(target.itemID))))
    row.itemIDText:SetText(tostring(target.itemID))
    row.sourceCountText:SetText(tostring(target.sourceCount or 0))
    row.tooltipText = self:GetConfigRowTooltip(target)
end

---@param parent Frame
---@return Frame row
function Scanner:CreateConfigRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(536, 24)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.03)

    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(22, 22)
    row.checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.checkbox:SetScript("OnClick", function(checkbox)
        local target = row.target
        if target then
            Scanner:SaveIndividualTargetSelection(target.key, checkbox:GetChecked())
            Scanner:UpdateConfigSummary()
            Scanner.scanComplete = false
            Scanner:UpdateButtons()
            Scanner:UpdateProgressText()
            if Scanner.showSelectedItemsOnly then
                Scanner:UpdateConfigList()
            end
        end
    end)

    row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.typeText:SetPoint("LEFT", row.checkbox, "RIGHT", 2, 0)
    row.typeText:SetWidth(58)
    row.typeText:SetJustifyH("LEFT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.typeText, "RIGHT", 8, 0)
    row.nameText:SetWidth(279)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.itemIDText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.itemIDText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)
    row.itemIDText:SetWidth(58)
    row.itemIDText:SetJustifyH("LEFT")

    row.sourceCountText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sourceCountText:SetPoint("LEFT", row.itemIDText, "RIGHT", 8, 0)
    row.sourceCountText:SetWidth(32)
    row.sourceCountText:SetJustifyH("LEFT")

    row:SetScript("OnEnter", function(selfRow)
        if not selfRow.tooltipText then
            return
        end
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CraftSim Scan Item")
        GameTooltip:AddLine(selfRow.tooltipText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdateConfigList()
    self:CreateConfigPanel()
    local panel = self.configPanel
    if not panel then
        return
    end

    for _, row in ipairs(self.configRows) do
        row:Hide()
    end
    for _, row in ipairs(self.presetRows) do
        row:Hide()
    end

    self.configTargets = self:GetConfigTargets()
    self:UpdateScanScopeButtons()

    if self.configView == "presets" then
        panel.professionButton:Hide()
        panel.searchBox:Hide()
        panel.searchHint:Hide()
        panel.selectedOnlyCheckbox:Hide()
        panel.treeExpansionButton:Show()
        panel.presetButton:ClearAllPoints()
        panel.presetButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
        panel.presetButton:SetText("Individual Items")
        panel.headerText:Hide()
        panel.scrollFrame:ClearAllPoints()
        panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -128)
        panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
        self:UpdatePresetList()
        self:UpdateTreeExpansionButton()
        self:UpdateConfigSummary()
        return
    end

    panel.professionButton:SetText(self:GetProfessionDropdownText(self:GetConfigProfession()))
    panel.professionButton:Show()
    panel.professionButton:ClearAllPoints()
    panel.professionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -108)
    panel.presetButton:ClearAllPoints()
    panel.presetButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
    panel.headerText:ClearAllPoints()
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -140)
    panel.headerText:SetText("Type            Item                                  ItemID     Recipes")
    panel.headerText:Show()
    panel.presetButton:SetText("Recipes")
    panel.searchBox:Show()
    panel.searchHint:SetShown((self.itemSearchText or "") == "" and not panel.searchBox:HasFocus())
    panel.selectedOnlyCheckbox:SetChecked(self.showSelectedItemsOnly)
    panel.selectedOnlyCheckbox:Show()
    panel.treeExpansionButton:Hide()
    panel.scrollFrame:ClearAllPoints()
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -156)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

    local displayTargets = ns.Filter(self.configTargets, function(target)
        return self:TargetMatchesItemSearch(target)
    end)
    local rowHeight = 24
    for index, target in ipairs(displayTargets) do
        local row = self.configRows[index]
        if not row then
            row = self:CreateConfigRow(panel.scrollChild)
            self.configRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight))
        if index % 2 == 0 then
            row.bg:Show()
        else
            row.bg:Hide()
        end
        self:UpdateConfigRow(row, target)
        row:Show()
    end

    panel.scrollChild:SetHeight(math.max(1, #displayTargets * rowHeight))
    self:UpdateConfigSummary()
end

---@param recipe table
---@return string
function Scanner:GetRecipeTreeIdentity(recipe)
    local recipeID = tonumber(recipe and recipe.recipeID)
    if recipeID then
        return "id:" .. tostring(recipeID)
    end
    return "name:" .. tostring(recipe and recipe.profession or "") .. ":" ..
        tostring(recipe and recipe.stratName or "")
end

---@param recipe table
---@return number?
---@return table?
function Scanner:GetRecipeCategoryInfo(recipe)
    local data = ns.Data.RecipeCategories or {}
    local categoryID
    if recipe.recipeID then
        categoryID = data.recipeIDs and data.recipeIDs[tonumber(recipe.recipeID)]
    else
        local nameKey = tostring(recipe.profession or "") .. ":" .. tostring(recipe.stratName or "")
        categoryID = data.recipeNames and data.recipeNames[nameKey]
    end
    return categoryID, categoryID and data.categories and data.categories[categoryID]
end

---@param targetMap table<string, table>
---@return table[] targets
function Scanner:TargetMapToList(targetMap)
    local targets = {}
    for _, target in pairs(targetMap or {}) do
        table.insert(targets, target)
    end
    table.sort(targets, function(left, right)
        return tostring(left.label or left.itemID) < tostring(right.label or right.itemID)
    end)
    return targets
end

---@return table<string, table<string, table>> targetsByRecipe
function Scanner:BuildTargetsByRecipeIdentity()
    local targetsByRecipe = {}
    local function add(identity, target)
        targetsByRecipe[identity] = targetsByRecipe[identity] or {}
        targetsByRecipe[identity][target.key] = target
    end

    for _, target in ipairs(self.configTargets or {}) do
        for recipeID in pairs(target.sourceRecipeMap or {}) do
            add("id:" .. tostring(recipeID), target)
        end
        for profession, sourceNames in pairs(target.sourceNamesByProfession or {}) do
            for sourceName in pairs(sourceNames) do
                add("name:" .. tostring(profession) .. ":" .. tostring(sourceName), target)
            end
        end
    end
    return targetsByRecipe
end

---@param stateMap table<string, boolean>
---@param key string
---@param defaultValue boolean
---@return boolean
function Scanner:GetTreeExpanded(stateMap, key, defaultValue)
    if stateMap[key] == nil then
        stateMap[key] = defaultValue
    end
    return stateMap[key] == true
end

---@return table[] entries
function Scanner:GetPresetListEntries()
    local entries = {}

    local configProfession = self:GetConfigProfession()
    local professions
    if configProfession == "ALL" then
        professions = self:GetSelectedProfessionInfos()
    else
        professions = ns.Filter(self.PROFESSIONS, function(professionInfo)
            return professionInfo.name == configProfession
        end)
    end

    local targetsByRecipe = self:BuildTargetsByRecipeIdentity()
    local firstVisibleProfession = true
    for _, professionInfo in ipairs(professions) do
        local profession = professionInfo.name
        local categoriesByID = {}
        for _, recipe in ipairs(self:GetGeneratedRecipes()) do
            if recipe.profession == profession then
                local recipeTargets = targetsByRecipe[self:GetRecipeTreeIdentity(recipe)]
                if recipeTargets and next(recipeTargets) then
                    local categoryID, categoryInfo = self:GetRecipeCategoryInfo(recipe)
                    categoryID = categoryID or 0
                    categoryInfo = categoryInfo or {
                        name = "Other",
                        order = 999,
                        parentName = "Uncategorized",
                        parentOrder = 999,
                    }
                    local category = categoriesByID[categoryID]
                    if not category then
                        category = {
                            id = categoryID,
                            info = categoryInfo,
                            recipes = {},
                            targetMap = {},
                            recipeIdentities = {},
                        }
                        categoriesByID[categoryID] = category
                    end
                    local recipeTargetList = self:TargetMapToList(recipeTargets)
                    local recipeIdentity = self:GetRecipeTreeIdentity(recipe)
                    table.insert(category.recipes, {
                        recipe = recipe,
                        recipeIdentity = recipeIdentity,
                        targets = recipeTargetList,
                    })
                    category.recipeIdentities[recipeIdentity] = true
                    for _, target in ipairs(recipeTargetList) do
                        category.targetMap[target.key] = target
                    end
                end
            end
        end

        local categories = {}
        local professionTargetMap = {}
        local professionRecipeIdentities = {}
        for _, category in pairs(categoriesByID) do
            category.targets = self:TargetMapToList(category.targetMap)
            table.sort(category.recipes, function(left, right)
                return tostring(left.recipe.stratName or "") < tostring(right.recipe.stratName or "")
            end)
            table.insert(categories, category)
            for _, target in ipairs(category.targets) do
                professionTargetMap[target.key] = target
            end
            for recipeIdentity in pairs(category.recipeIdentities) do
                professionRecipeIdentities[recipeIdentity] = true
            end
        end
        table.sort(categories, function(left, right)
            local leftOrder = tonumber(left.info.order) or 999
            local rightOrder = tonumber(right.info.order) or 999
            if leftOrder ~= rightOrder then
                return leftOrder < rightOrder
            end
            return tostring(left.info.name or "") < tostring(right.info.name or "")
        end)

        if #categories > 0 then
            local professionKey = "profession:" .. profession
            local defaultExpanded = configProfession ~= "ALL" or firstVisibleProfession
            local professionExpanded = self:GetTreeExpanded(
                self.expandedProfessionGroups, professionKey, defaultExpanded)
            local parentName = categories[1].info.parentName or "Profession Recipes"
            table.insert(entries, {
                kind = "profession",
                key = professionKey,
                label = self:GetProfessionDisplayName(professionInfo) .. " — " .. tostring(parentName),
                profession = profession,
                expanded = professionExpanded,
                targets = self:TargetMapToList(professionTargetMap),
                recipeIdentities = professionRecipeIdentities,
            })
            firstVisibleProfession = false

            if professionExpanded then
                for _, category in ipairs(categories) do
                    local categoryKey = "category:" .. profession .. ":" .. tostring(category.id)
                    local categoryExpanded = self:GetTreeExpanded(
                        self.expandedCategoryGroups, categoryKey, true)
                    table.insert(entries, {
                        kind = "category",
                        key = categoryKey,
                        label = tostring(category.info.name or "Other"),
                        profession = profession,
                        expanded = categoryExpanded,
                        targets = category.targets,
                        recipeIdentities = category.recipeIdentities,
                    })
                    if categoryExpanded then
                        for _, recipeEntry in ipairs(category.recipes) do
                            table.insert(entries, {
                                kind = "recipe",
                                label = tostring(recipeEntry.recipe.stratName or "Unnamed Recipe"),
                                profession = profession,
                                recipe = recipeEntry.recipe,
                                targets = recipeEntry.targets,
                                recipeIdentities = { [recipeEntry.recipeIdentity] = true },
                            })
                        end
                    end
                end
            end
        end
    end

    return entries
end

---@param entry table
---@return string state
---@return number selectedCount
---@return number totalCount
function Scanner:GetTreeEntrySelectionState(entry)
    if entry.kind == "preset" then
        return self:GetPresetSelectionState(entry.id, entry.contextProfession)
    end
    local selectedCount = 0
    local totalCount = 0
    for recipeIdentity in pairs(entry.recipeIdentities or {}) do
        totalCount = totalCount + 1
        if Config:IsRecipeSelected(recipeIdentity) then
            selectedCount = selectedCount + 1
        end
    end
    return self:GetPresetSelectionStateFromCounts("TREE", selectedCount, totalCount), selectedCount, totalCount
end

---@param entry table
function Scanner:ToggleTreeEntrySelection(entry)
    if not entry or entry.kind == "quicksets" then
        return
    end
    local selectedCount = 0
    local totalCount = 0
    for recipeIdentity in pairs(entry.recipeIdentities or {}) do
        totalCount = totalCount + 1
        if Config:IsRecipeSelected(recipeIdentity) then
            selectedCount = selectedCount + 1
        end
    end
    local selected = selectedCount ~= totalCount
    if totalCount == 0 then
        return
    end
    for recipeIdentity in pairs(entry.recipeIdentities or {}) do
        Config:SaveRecipeSelected(recipeIdentity, selected)
    end
    self:RebuildSelectedTargetsFromRecipes()
    self.scanComplete = false
    self.overridesPushed = false
    local sharedItemNote = selected and "" or " Shared items needed elsewhere were kept."
    self:SetStatus(string.format("%s %d recipe(s) for %s.%s",
        selected and "Selected" or "Cleared", totalCount, tostring(entry.label or "this group"), sharedItemNote))
    self:UpdateButtons()
    self:UpdateProgressText()
    self:UpdateConfigList()
end

---@param entry table
function Scanner:ToggleTreeEntryExpansion(entry)
    if not entry or not entry.key then
        return
    end
    if entry.kind == "quicksets" then
        self.expandedQuickSetGroups[entry.key] = not entry.expanded
    elseif entry.kind == "profession" then
        self.expandedProfessionGroups[entry.key] = not entry.expanded
    elseif entry.kind == "category" then
        self.expandedCategoryGroups[entry.key] = not entry.expanded
    else
        return
    end
    self:UpdateConfigList()
end

---@param row Frame
---@param entry table
function Scanner:UpdatePresetRow(row, entry)
    row.entry = entry
    row:SetAlpha(1)
    row.headerText:Hide()
    row.expandText:Hide()
    row.checkbox:Hide()
    row.mixedTexture:Hide()
    row.labelText:Hide()
    row.countText:Hide()
    row:EnableMouse(false)

    if entry.kind == "quicksets" then
        row.expandText:ClearAllPoints()
        row.expandText:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.expandText:SetText(entry.expanded and "−" or "+")
        row.expandText:Show()
        row.headerText:ClearAllPoints()
        row.headerText:SetPoint("LEFT", row, "LEFT", 22, 0)
        row.headerText:SetText(entry.label)
        row.headerText:SetTextColor(1, 0.82, 0)
        row.headerText:Show()
        row:EnableMouse(true)
        return
    end

    local state, selectedCount, totalCount = self:GetTreeEntrySelectionState(entry)
    local checkboxX = 16
    if entry.kind == "profession" then
        checkboxX = 20
    elseif entry.kind == "category" then
        checkboxX = 40
    elseif entry.kind == "recipe" then
        checkboxX = 58
    end

    if entry.kind == "profession" or entry.kind == "category" then
        row.expandText:ClearAllPoints()
        row.expandText:SetPoint("LEFT", row, "LEFT", entry.kind == "profession" and 3 or 23, 0)
        row.expandText:SetText(entry.expanded and "−" or "+")
        row.expandText:Show()
    end

    row.checkbox:ClearAllPoints()
    row.checkbox:SetPoint("LEFT", row, "LEFT", checkboxX, 0)
    row.checkbox:SetChecked(state == "all")
    row.mixedTexture:SetShown(state == "partial")
    row.checkbox:Show()
    SetButtonEnabled(row.checkbox, totalCount > 0)

    row.labelText:ClearAllPoints()
    row.labelText:SetPoint("LEFT", row.checkbox, "RIGHT", 3, 0)
    row.labelText:SetWidth(math.max(180, 438 - checkboxX))
    row.labelText:SetText(entry.label)
    if entry.kind == "profession" then
        row.labelText:SetTextColor(1, 0.82, 0)
    elseif entry.kind == "category" then
        row.labelText:SetTextColor(1, 0.82, 0.2)
    else
        row.labelText:SetTextColor(1, 1, 1)
    end
    row.countText:SetText(string.format("%d/%d", selectedCount, totalCount))
    row.labelText:Show()
    row.countText:Show()
    row:EnableMouse(totalCount > 0 or entry.kind == "profession" or entry.kind == "category")
    row:SetAlpha(totalCount > 0 and 1 or 0.45)
end

---@param parent Frame
---@return Frame row
function Scanner:CreatePresetRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(536, 24)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.04)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(1, 0.82, 0, 0.08)

    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.headerText:SetWidth(506)
    row.headerText:SetJustifyH("LEFT")

    row.expandText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.expandText:SetWidth(14)
    row.expandText:SetJustifyH("CENTER")

    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(22, 22)
    row.checkbox:SetScript("OnClick", function()
        Scanner:ToggleTreeEntrySelection(row.entry)
    end)

    row.mixedTexture = row.checkbox:CreateTexture(nil, "OVERLAY")
    row.mixedTexture:SetPoint("CENTER", row.checkbox, "CENTER", 0, 0)
    -- A filled square is visually distinct from the horizontal collapse
    -- marker beside category rows. It means some, but not all, recipes in the
    -- group are selected.
    row.mixedTexture:SetSize(8, 8)
    row.mixedTexture:SetColorTexture(1, 0.65, 0, 1)
    row.mixedTexture:Hide()

    row.labelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.labelText:SetJustifyH("LEFT")
    row.labelText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.countText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.countText:SetWidth(62)
    row.countText:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(selfRow)
        local entry = selfRow.entry
        if entry and (entry.kind == "quicksets" or entry.kind == "profession" or entry.kind == "category") then
            Scanner:ToggleTreeEntryExpansion(entry)
        else
            Scanner:ToggleTreeEntrySelection(entry)
        end
    end)
    local function showSelectionTooltip(owner)
        local entry = row.entry
        if not entry then
            return
        end
        if entry.kind == "quicksets" then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:AddLine(entry.label)
            GameTooltip:AddLine("Click to expand or collapse the common scan selections.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
            return
        end
        local state, selectedCount, totalCount = Scanner:GetTreeEntrySelectionState(entry)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.label)
        GameTooltip:AddLine("Current scope: " .. Scanner:GetScanScopeLabel() .. ".", 0.8, 0.8, 0.8, true)
        if entry.kind == "recipe" and state == "all" then
            GameTooltip:AddLine("This recipe is selected.", 1, 1, 1, true)
        elseif entry.kind == "recipe" and state == "none" then
            GameTooltip:AddLine("This recipe is not selected.", 1, 1, 1, true)
        elseif state == "all" then
            GameTooltip:AddLine(string.format("All %d recipes are selected.", totalCount),
                1, 1, 1, true)
        elseif state == "partial" then
            GameTooltip:AddLine(string.format("%d of %d recipes are selected.", selectedCount, totalCount),
                1, 1, 1, true)
            GameTooltip:AddLine("The filled square means this group is partially selected.", 1, 0.82, 0, true)
        elseif state == "none" then
            GameTooltip:AddLine(string.format("None of the %d recipes are selected.", totalCount),
                1, 1, 1, true)
        else
            GameTooltip:AddLine("This group has no recipes with Auction House items in the current scope.",
                0.8, 0.8, 0.8, true)
        end
        if entry.kind == "recipe" then
            GameTooltip:AddLine(string.format("This recipe contributes %d Auction House item(s) in this scope.",
                #(entry.targets or {})), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Shared items stay selected while another selected recipe still needs them.",
                0.8, 0.8, 0.8, true)
        end
        if entry.kind == "profession" or entry.kind == "category" then
            GameTooltip:AddLine("Click the row to expand or collapse. Click the checkbox to change selection.",
                0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Click to select or clear this recipe.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end
    row:SetScript("OnEnter", showSelectionTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row.checkbox:SetScript("OnEnter", showSelectionTooltip)
    row.checkbox:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdatePresetList()
    local panel = self.configPanel
    if not panel then
        return
    end

    self.presetMenuTargetCache = {
        ["__CURRENT__"] = self.configTargets,
    }
    local entries = self:GetPresetListEntries()
    local offset = 0
    for index, entry in ipairs(entries) do
        local row = self.presetRows[index]
        if not row then
            row = self:CreatePresetRow(panel.scrollChild)
            self.presetRows[index] = row
        end
        local rowHeight = entry.kind == "quicksets" and 28 or entry.kind == "profession" and 28 or
            entry.kind == "recipe" and 22 or 24
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -offset)
        row.bg:SetShown(entry.kind ~= "quicksets" and index % 2 == 0)
        self:UpdatePresetRow(row, entry)
        row:Show()
        offset = offset + rowHeight
    end
    for index = #entries + 1, #self.presetRows do
        self.presetRows[index]:Hide()
    end
    self.presetMenuTargetCache = nil
    panel.scrollChild:SetHeight(math.max(1, offset))
end

---@param view "items" | "presets"
function Scanner:SetConfigView(view)
    self.configView = view == "items" and "items" or "presets"
    if self.configPanel and self.configPanel.scrollFrame then
        self.configPanel.scrollFrame:SetVerticalScroll(0)
    end
    self:UpdateConfigList()
end

---@param presetID string
---@param contextProfession string?
function Scanner:ApplyConfigPreset(presetID, contextProfession)
    local configProfession = self:GetConfigProfession()
    local profession = contextProfession or configProfession
    local targets = self:GetPresetScopeTargets(contextProfession)
    local scopeText = contextProfession and (" for " .. tostring(contextProfession)) or ""

    if presetID == self.PRESET_IDS.ALL or presetID == self.PRESET_IDS.NONE then
        local selected = presetID == self.PRESET_IDS.ALL
        for _, target in ipairs(targets) do
            Config:SaveTargetSelectionOverride(target.key, selected)
        end
        self:RebuildSelectedTargetsFromRecipes()
        if contextProfession then
            self:ClearActivePresetMap(contextProfession)
        elseif configProfession == "ALL" then
            self:ClearActivePresetMap()
        else
            self:ClearActivePresetMap(configProfession)
        end
        self.scanComplete = false
        self:SetStatus(selected and ("Selected all scan items" .. scopeText .. ".") or
            ("Cleared all scan items" .. scopeText .. "."))
        self:UpdateButtons()
        self:UpdateProgressText()
        self:UpdateConfigList()
        return
    end

    local matchedTargets = self:GetPresetMatchedTargets(presetID, contextProfession, targets)

    if #matchedTargets == 0 then
        self:SetStatus("Preset matched 0 scan items" .. scopeText .. ".")
        self:UpdateConfigList()
        return
    end

    local activePresets = self:GetActivePresetMap(profession)
    local selectedCount = self:GetSelectedTargetCount(matchedTargets)
    local presetState = self:GetPresetSelectionStateFromCounts(presetID, selectedCount, #matchedTargets)
    local selected = presetState ~= "all"
    local changedCount = 0
    for _, target in ipairs(matchedTargets) do
        if Config:IsTargetSelected(target.key) ~= selected then
            changedCount = changedCount + 1
        end
        Config:SaveTargetSelectionOverride(target.key, selected)
    end
    self:RebuildSelectedTargetsFromRecipes()

    activePresets[presetID] = selected or nil
    self.scanComplete = false
    self:SetStatus(string.format("%s %d item(s) from preset%s. %d changed.",
        selected and "Added" or "Removed", #matchedTargets, scopeText, changedCount))
    self:UpdateButtons()
    self:UpdateProgressText()
    self:UpdateConfigList()
end

---@param menu any
---@param label string
---@param presetID string
---@param contextProfession string?
function Scanner:AddPresetMenuButton(menu, label, presetID, contextProfession)
    menu:CreateButton(self:GetPresetMenuLabel(label, presetID, contextProfession), function()
        Scanner:ApplyConfigPreset(presetID, contextProfession)
        return MenuResponse.Close
    end)
end

---@param menu any
---@param profession string
---@param contextProfession string?
function Scanner:AddProfessionPresetSections(menu, profession, contextProfession)
    local presetIDs = self.PRESET_IDS
    self:AddPresetMenuButton(menu, "Select This Profession", presetIDs.ALL, contextProfession)
    self:AddPresetMenuButton(menu, "Clear This Profession", presetIDs.NONE, contextProfession)
    menu:CreateDivider()

    local definitions = self.PROFESSION_PRESET_MENUS[profession] or {}
    for sectionIndex, section in ipairs(definitions) do
        if sectionIndex > 1 then
            menu:CreateDivider()
        end
        local sectionMenu = menu:CreateButton(self:GetPresetGroupMenuLabel(section.label, section.presets, contextProfession))
        for _, preset in ipairs(section.presets or {}) do
            self:AddPresetMenuButton(sectionMenu, preset.label, preset.id, contextProfession)
        end
    end
end

---@param rootDescription any
function Scanner:BuildPresetMenu(rootDescription)
    local presetIDs = self.PRESET_IDS
    local profession = self:GetConfigProfession()
    local selectedProfessionInfos = self:GetSelectedProfessionInfos()
    local quickSetPresets = {
        { label = "Inputs", id = presetIDs.INPUTS },
        { label = "Outputs", id = presetIDs.OUTPUTS },
        { label = "Commodities", id = presetIDs.COMMODITIES },
        { label = "Equipment", id = presetIDs.EQUIPMENT },
        { label = "Materials", id = presetIDs.MATERIALS },
    }

    self.presetMenuTargetCache = {}
    self:AddPresetMenuButton(rootDescription, "Select All", presetIDs.ALL)
    self:AddPresetMenuButton(rootDescription, "Clear All", presetIDs.NONE)
    rootDescription:CreateDivider()
    local quickSets = rootDescription:CreateButton(self:GetPresetGroupMenuLabel("Quick Sets", quickSetPresets))
    for _, preset in ipairs(quickSetPresets) do
        self:AddPresetMenuButton(quickSets, preset.label, preset.id)
    end

    if profession ~= "ALL" then
        rootDescription:CreateDivider()
        self:AddProfessionPresetSections(rootDescription, profession, profession)
        self.presetMenuTargetCache = nil
        return
    end

    rootDescription:CreateDivider()
    for _, professionInfo in ipairs(selectedProfessionInfos) do
        local professionMenu = rootDescription:CreateButton(
            self:GetPresetMenuLabel(self:GetProfessionLabel(professionInfo), presetIDs.ALL, professionInfo.name))
        self:AddProfessionPresetSections(professionMenu, professionInfo.name, professionInfo.name)
    end
    self.presetMenuTargetCache = nil
end

function Scanner:CreateConfigPanel()
    if self.configPanel or not self.panel or not self.panel.contentHost then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanConfigPanel", self.panel.contentHost)
    panel:SetAllPoints(self.panel.contentHost)
    panel:SetFrameLevel((self.panel.contentHost:GetFrameLevel() or 1) + 1)
    panel:EnableMouse(true)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    panel.title:SetText("Configure Scan")

    panel.helpButton = CreateFrame("Button", nil, panel)
    panel.helpButton:SetSize(22, 22)
    panel.helpButton:SetPoint("LEFT", panel.title, "RIGHT", 4, 0)
    panel.helpButton:SetNormalTexture("Interface\\common\\help-i")
    panel.helpButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    panel.helpButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Scan Configuration")
        GameTooltip:AddLine("First choose whether to scan crafted products, required reagents, or both.",
            1, 1, 1, true)
        GameTooltip:AddLine("Recipes selects complete professions, in-game categories, or individual recipes.",
            1, 1, 1, true)
        GameTooltip:AddLine("Individual Items provides exact Auction House target control.", 1, 1, 1, true)
        GameTooltip:AddLine("Use Selected only there to review the exact list before scanning.", 1, 1, 1, true)
        GameTooltip:AddLine("Shared items remain selected while any selected recipe needs them.", 1, 1, 1, true)
        GameTooltip:AddLine("A filled square means some, but not all, recipes in that group are selected.",
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    panel.helpButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.scopeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.scopeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
    panel.scopeLabel:SetText("Prices to scan:")

    panel.scopeButtons = {}
    local scopeDefinitions = {
        { scope = self.SCAN_SCOPES.PRODUCTS, width = 132 },
        { scope = self.SCAN_SCOPES.REAGENTS, width = 140 },
        { scope = self.SCAN_SCOPES.BOTH, width = 152 },
    }
    local previousScopeButton
    for _, definition in ipairs(scopeDefinitions) do
        local scope = definition.scope
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(definition.width, 24)
        if previousScopeButton then
            button:SetPoint("LEFT", previousScopeButton, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", panel.scopeLabel, "RIGHT", 8, 0)
        end
        button:SetScript("OnClick", function()
            Scanner:SetScanScope(scope)
        end)
        button:SetScript("OnEnter", function(selfButton)
            GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Scanner:GetScanScopeLabel(scope))
            if scope == Scanner.SCAN_SCOPES.PRODUCTS then
                GameTooltip:AddLine("Only Auction House items produced by the selected recipes.", 1, 1, 1, true)
            elseif scope == Scanner.SCAN_SCOPES.REAGENTS then
                GameTooltip:AddLine("Only Auction House materials consumed by the selected recipes.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Both crafted products and their required Auction House reagents.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        panel.scopeButtons[scope] = button
        previousScopeButton = button
    end

    panel.professionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.professionButton:SetSize(190, 24)
    panel.professionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -108)
    panel.professionButton:SetText(self:GetProfessionDropdownText(self:GetConfigProfession()))
    panel.professionButton:SetScript("OnClick", function(button)
        ns.Compat.WoW:OpenContextMenu(button, function(_, rootDescription)
            rootDescription:CreateRadio("All Selected Professions", function()
                return Config:GetConfigProfession() == "ALL"
            end, function()
                Config:SaveConfigProfession("ALL")
                Scanner:UpdateConfigList()
                return MenuResponse.Close
            end)
            rootDescription:CreateDivider()
            for _, professionInfo in ipairs(Scanner:GetSelectedProfessionInfos()) do
                local profession = professionInfo.name
                rootDescription:CreateRadio(Scanner:GetProfessionLabel(professionInfo), function()
                    return Config:GetConfigProfession() == profession
                end, function()
                    Config:SaveConfigProfession(profession)
                    Scanner:UpdateConfigList()
                    return MenuResponse.Close
                end)
            end
        end)
    end)
    panel.professionButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Individual Items Profession")
        GameTooltip:AddLine("Limit the flat item list to one selected profession. This does not change which professions will be scanned.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.professionButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.presetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.presetButton:SetSize(120, 24)
    panel.presetButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
    panel.presetButton:SetText("Individual Items")
    panel.presetButton:SetScript("OnClick", function()
        Scanner:SetConfigView(Scanner.configView == "presets" and "items" or "presets")
    end)
    panel.presetButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if Scanner.configView == "presets" then
            GameTooltip:AddLine("Individual Items")
            GameTooltip:AddLine("Fine tune individual Auction House scan targets.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Recipes")
            GameTooltip:AddLine("Choose targets by profession, in-game category, or recipe.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    panel.presetButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.selectAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.selectAllButton:SetSize(82, 24)
    panel.selectAllButton:SetPoint("LEFT", panel.presetButton, "RIGHT", 8, 0)
    panel.selectAllButton:SetText("Select all")
    panel.selectAllButton:SetScript("OnClick", function()
        Scanner:SetAllVisibleTargetsSelected(true)
    end)

    panel.clearAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clearAllButton:SetSize(82, 24)
    panel.clearAllButton:SetPoint("LEFT", panel.selectAllButton, "RIGHT", 6, 0)
    panel.clearAllButton:SetText("Clear all")
    panel.clearAllButton:SetScript("OnClick", function()
        Scanner:SetAllVisibleTargetsSelected(false)
    end)

    panel.treeExpansionButton = CreateFrame("Button", nil, panel)
    panel.treeExpansionButton:SetSize(76, 16)
    panel.treeExpansionButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -108)
    panel.treeExpansionButton:SetNormalFontObject("GameFontNormalSmall")
    panel.treeExpansionButton:SetHighlightFontObject("GameFontHighlightSmall")
    panel.treeExpansionButton:SetText("Expand all")
    panel.treeExpansionButton:SetScript("OnClick", function()
        Scanner:SetAllRecipeGroupsExpanded(not Scanner:AreAllRecipeGroupsExpanded())
    end)
    panel.treeExpansionButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Recipe Tree")
        GameTooltip:AddLine("Expand or collapse every profession and recipe category in the current tree.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.treeExpansionButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.summaryText:SetPoint("LEFT", panel.clearAllButton, "RIGHT", 10, 0)
    panel.summaryText:SetWidth(270)
    panel.summaryText:SetJustifyH("LEFT")

    panel.searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.searchBox:SetSize(210, 22)
    panel.searchBox:SetPoint("LEFT", panel.professionButton, "RIGHT", 12, 0)
    panel.searchBox:SetAutoFocus(false)
    panel.searchBox:SetText(self.itemSearchText or "")
    panel.searchHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.searchHint:SetPoint("LEFT", panel.searchBox, "LEFT", 6, 0)
    panel.searchHint:SetText("Search name or ItemID")
    panel.searchHint:SetShown((self.itemSearchText or "") == "")
    panel.searchBox:SetScript("OnTextChanged", function(editBox)
        Scanner.itemSearchText = editBox:GetText() or ""
        panel.searchHint:SetShown(Scanner.itemSearchText == "" and not editBox:HasFocus())
        Scanner:UpdateConfigList()
    end)
    panel.searchBox:SetScript("OnEditFocusGained", function()
        panel.searchHint:Hide()
    end)
    panel.searchBox:SetScript("OnEditFocusLost", function(editBox)
        panel.searchHint:SetShown((editBox:GetText() or "") == "")
    end)
    panel.searchBox:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)

    panel.selectedOnlyCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.selectedOnlyCheckbox:SetSize(22, 22)
    panel.selectedOnlyCheckbox:SetPoint("LEFT", panel.searchBox, "RIGHT", 10, 0)
    panel.selectedOnlyCheckbox.text = panel.selectedOnlyCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.selectedOnlyCheckbox.text:SetPoint("LEFT", panel.selectedOnlyCheckbox, "RIGHT", 2, 0)
    panel.selectedOnlyCheckbox.text:SetText("Selected only")
    panel.selectedOnlyCheckbox:SetScript("OnClick", function(checkbox)
        Scanner.showSelectedItemsOnly = checkbox:GetChecked() == true
        Scanner:UpdateConfigList()
    end)

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -140)
    panel.headerText:SetText("Type            Item                                  ItemID     Recipes")

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -156)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(536, 1)
    panel.scrollFrame:SetScrollChild(panel.scrollChild)

    panel:Hide()
    self.configPanel = panel
end

---@param target table
---@param overrideTarget table
