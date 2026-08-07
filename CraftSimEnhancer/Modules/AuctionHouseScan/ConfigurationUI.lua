local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before configuration UI")
local Shared = Scanner.Shared
local Config = Shared.Config
local SetButtonEnabled = Shared.SetButtonEnabled
local CreateNativeActionButton = Shared.CreateNativeActionButton
local CreateNativeHeaderBand = Shared.CreateNativeHeaderBand
local CreateNativeListWell = Shared.CreateNativeListWell

local function CreateConfigViewTab(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    return button
end

local function CreateTextAction(parent, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 16)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontDisableSmall")
    return button
end

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
    if self.configView == "recipes" then
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

---@param targets table[]
function Scanner:NormalizeOrphanedRecipeOverrides(targets)
    if not Config:NeedsRecipeOverrideCleanup() then
        return
    end

    local _, recipesByTarget = self:BuildRecipeSelectionCatalog(targets)
    local overrides = Config:GetTargetSelectionOverrides()
    for targetKey, selected in pairs(overrides) do
        if selected == true then
            local claimedBySelectedRecipe = false
            for recipeIdentity in pairs(recipesByTarget[targetKey] or {}) do
                if Config:IsRecipeSelected(recipeIdentity) then
                    claimedBySelectedRecipe = true
                    break
                end
            end
            if not claimedBySelectedRecipe then
                overrides[targetKey] = nil
            end
        end
    end
    Config:CompleteRecipeOverrideCleanup()
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

---@param recipeIdentities table<string, boolean>
function Scanner:ClearTargetOverridesForRecipes(recipeIdentities)
    local targetsByRecipe = self:BuildRecipeSelectionCatalog(self.allConfigTargets or {})
    local clearedTargets = {}
    for recipeIdentity in pairs(recipeIdentities or {}) do
        for targetKey in pairs(targetsByRecipe[recipeIdentity] or {}) do
            if not clearedTargets[targetKey] then
                Config:ClearTargetSelectionOverride(targetKey)
                clearedTargets[targetKey] = true
            end
        end
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
    self:NormalizeOrphanedRecipeOverrides(targets)

    local profession = self:GetConfigProfession()
    return ns.Filter(targets, function(target)
        return self:IsTargetInSelectedProfessions(target)
            and self:IsTargetInConfigProfession(target, profession)
            and self:TargetMatchesScanScope(target)
    end)
end

---@return table counts
function Scanner:GetConfigSelectionSummary()
    local products, reagents = 0, 0
    local scanTargets = self:BuildScanTargets({ skipFixedPrices = true }) or {}
    for _, target in ipairs(scanTargets) do
        if target.kindMap and target.kindMap.output then
            products = products + 1
        elseif target.kindMap and target.kindMap.input then
            reagents = reagents + 1
        end
    end

    local selectedRecipes, totalRecipes = 0, 0
    local selectedProfessions = self:GetSelectedProfessions()
    local scopeTargets = ns.Filter(self.allConfigTargets or {}, function(target)
        return self:IsTargetInSelectedProfessions(target) and self:TargetMatchesScanScope(target)
    end)
    local targetsByRecipe = self:BuildRecipeSelectionCatalog(scopeTargets)
    local recipeProfessions = {}
    for _, recipe in ipairs(self:GetGeneratedRecipes()) do
        recipeProfessions[self:GetRecipeTreeIdentity(recipe)] = recipe.profession
    end
    for recipeIdentity in pairs(targetsByRecipe) do
        local profession = recipeProfessions[recipeIdentity]
        if profession and selectedProfessions[profession] then
            totalRecipes = totalRecipes + 1
            if Config:IsRecipeSelected(recipeIdentity) then
                selectedRecipes = selectedRecipes + 1
            end
        end
    end

    return {
        selectedRecipes = selectedRecipes,
        totalRecipes = totalRecipes,
        products = products,
        reagents = reagents,
        targets = products + reagents,
    }
end

function Scanner:UpdateConfigSummary()
    local panel = self.configPanel
    if not panel or not panel.summaryText then
        return
    end

    local counts = self:GetConfigSelectionSummary()
    panel.summaryCounts = counts
    panel.summaryText:SetText(string.format("%d/%d %s · %d price targets",
        counts.selectedRecipes, counts.totalRecipes, self:Pluralize(counts.totalRecipes, "recipe"), counts.targets))
end

function Scanner:UpdateConfigViewTabs()
    local panel = self.configPanel
    if not panel or not panel.viewButtons then
        return
    end
    for view, button in pairs(panel.viewButtons) do
        local selected = self.configView == view
        if selected then
            PanelTemplates_SelectTab(button)
        else
            PanelTemplates_DeselectTab(button)
        end
    end
end

function Scanner:UpdateConfigBulkActions()
    local panel = self.configPanel
    if not panel or not panel.selectAllButton or not panel.clearAllButton then
        return
    end
    if self.configView == "recipes" then
        panel.selectAllButton:SetWidth(80)
        panel.clearAllButton:SetWidth(72)
        panel.selectAllButton:SetText("Select all")
        panel.clearAllButton:SetText("Clear all")
        return
    end

    local searchText = string.match(tostring(self.itemSearchText or ""), "^%s*(.-)%s*$") or ""
    if searchText ~= "" then
        panel.selectAllButton:SetWidth(92)
        panel.clearAllButton:SetWidth(92)
        panel.selectAllButton:SetText("Select matches")
        panel.clearAllButton:SetText("Clear matches")
    else
        panel.selectAllButton:SetWidth(80)
        panel.clearAllButton:SetWidth(72)
        panel.selectAllButton:SetText("Select all")
        panel.clearAllButton:SetText("Clear all")
    end
end

---@param scope string
function Scanner:SetScanScope(scope)
    Config:SaveScanScope(scope)
    self:InvalidateScanConfiguration()
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
        if button.radio then
            button.radio:SetChecked(active)
        end
        SetButtonEnabled(button, not self.isScanning)
        button:SetAlpha(self.isScanning and 0.5 or 1)
    end
end

---@param selected boolean
function Scanner:SetAllVisibleTargetsSelected(selected)
    if self.configView == "recipes" then
        local changedRecipes = {}
        for _, entry in ipairs(self:GetRecipeListEntries()) do
            for recipeIdentity in pairs(entry.recipeIdentities or {}) do
                if not changedRecipes[recipeIdentity] then
                    changedRecipes[recipeIdentity] = true
                end
            end
        end
        for recipeIdentity in pairs(changedRecipes) do
            Config:SaveRecipeSelected(recipeIdentity, selected)
        end
        self:ClearTargetOverridesForRecipes(changedRecipes)
        self:RebuildSelectedTargetsFromRecipes()
        self:InvalidateScanConfiguration()
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
    self:InvalidateScanConfiguration()
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

---@return boolean hasExpandedGroups
function Scanner:HasExpandedRecipeGroups()
    for _, entry in ipairs(self:GetRecipeListEntries()) do
        if (entry.kind == "profession" or entry.kind == "category") and entry.expanded then
            return true
        end
    end
    return false
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
    panel.treeExpansionButton:SetText(self:HasExpandedRecipeGroups() and "Collapse all" or "Expand all")
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
    row.bg:SetColorTexture(1, 1, 1, 0.02)

    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(22, 22)
    row.checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.checkbox:SetScript("OnClick", function(checkbox)
        local target = row.target
        if target then
            Scanner:SaveIndividualTargetSelection(target.key, checkbox:GetChecked())
            Scanner:UpdateConfigSummary()
            Scanner:InvalidateScanConfiguration()
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
    for _, row in ipairs(self.recipeRows) do
        row:Hide()
    end

    self.configTargets = self:GetConfigTargets()
    self:UpdateScanScopeButtons()

    self:UpdateConfigViewTabs()
    self:UpdateConfigBulkActions()

    if self.configView == "recipes" then
        panel.professionButton:Hide()
        panel.searchBox:Hide()
        panel.searchHint:Hide()
        panel.selectedOnlyCheckbox:Hide()
        panel.treeExpansionButton:Show()
        panel.headerText:Hide()
        panel.listWell:ClearAllPoints()
        panel.listWell:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -128)
        panel.listWell:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
        panel.scrollFrame:ClearAllPoints()
        panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -134)
        panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
        self:UpdateRecipeList()
        self:UpdateTreeExpansionButton()
        self:UpdateConfigSummary()
        return
    end

    panel.professionButton:SetText(self:GetProfessionDropdownText(self:GetConfigProfession()))
    panel.professionButton:Show()
    panel.professionButton:ClearAllPoints()
    panel.professionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -134)
    panel.headerText:ClearAllPoints()
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -166)
    panel.headerText:SetText("Type            Item                                  ItemID     Recipes")
    panel.headerText:Show()
    panel.searchBox:Show()
    panel.searchHint:SetShown((self.itemSearchText or "") == "" and not panel.searchBox:HasFocus())
    panel.selectedOnlyCheckbox:SetChecked(self.showSelectedItemsOnly)
    panel.selectedOnlyCheckbox:Show()
    panel.treeExpansionButton:Hide()
    panel.listWell:ClearAllPoints()
    panel.listWell:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -176)
    panel.listWell:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    panel.scrollFrame:ClearAllPoints()
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -182)
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
function Scanner:GetRecipeListEntries()
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
    local selectedCount = 0
    local totalCount = 0
    for recipeIdentity in pairs(entry.recipeIdentities or {}) do
        totalCount = totalCount + 1
        if Config:IsRecipeSelected(recipeIdentity) then
            selectedCount = selectedCount + 1
        end
    end
    local state = "none"
    if totalCount <= 0 then
        state = "empty"
    elseif selectedCount == totalCount then
        state = "all"
    elseif selectedCount > 0 then
        state = "partial"
    end
    return state, selectedCount, totalCount
end

---@param entry table
function Scanner:ToggleTreeEntrySelection(entry)
    if not entry then
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
    self:ClearTargetOverridesForRecipes(entry.recipeIdentities)
    self:RebuildSelectedTargetsFromRecipes()
    self:InvalidateScanConfiguration()
    self:UpdateButtons()
    self:UpdateProgressText()
    self:UpdateConfigList()
end

---@param entry table
function Scanner:ToggleTreeEntryExpansion(entry)
    if not entry or not entry.key then
        return
    end
    if entry.kind == "profession" then
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
function Scanner:UpdateRecipeRow(row, entry)
    row.entry = entry
    row:SetAlpha(1)
    row.expandButton:Hide()
    row.expandText:Hide()
    row.checkbox:Hide()
    row.mixedTexture:Hide()
    row.labelText:Hide()
    row.countText:Hide()
    row:EnableMouse(false)

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
        row.expandButton:ClearAllPoints()
        row.expandButton:SetPoint("LEFT", row, "LEFT", entry.kind == "profession" and 1 or 21, 0)
        row.expandText:SetText(entry.expanded and "-" or "+")
        row.expandButton:Show()
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
    row.labelText:SetWidth(math.max(180, (entry.kind == "recipe" and 438 or 402) - checkboxX))
    row.labelText:SetText(entry.label)
    if entry.kind == "profession" then
        row.labelText:SetTextColor(1, 0.82, 0)
    elseif entry.kind == "category" then
        row.labelText:SetTextColor(1, 0.82, 0.2)
    else
        row.labelText:SetTextColor(1, 1, 1)
    end
    if entry.kind == "recipe" then
        row.countText:Hide()
    else
        row.countText:SetText(string.format("%d/%d %s", selectedCount, totalCount,
            self:Pluralize(totalCount, "recipe", "recipes")))
        row.countText:Show()
    end
    row.labelText:Show()
    row:EnableMouse(totalCount > 0 or entry.kind == "profession" or entry.kind == "category")
    row:SetAlpha(totalCount > 0 and 1 or 0.45)
end

---@param parent Frame
---@return Frame row
function Scanner:CreateRecipeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(536, 24)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.02)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(1, 0.82, 0, 0.08)

    row.expandButton = CreateFrame("Button", nil, row)
    row.expandButton:SetSize(18, 22)
    row.expandText = row.expandButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.expandText:SetPoint("CENTER", row.expandButton, "CENTER", 0, 0)
    row.expandText:SetWidth(18)
    row.expandText:SetJustifyH("CENTER")
    row.expandButton:SetScript("OnClick", function()
        Scanner:ToggleTreeEntryExpansion(row.entry)
    end)

    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(22, 22)
    row.checkbox:SetScript("OnClick", function()
        Scanner:ToggleTreeEntrySelection(row.entry)
    end)

    row.mixedTexture = row.checkbox:CreateTexture(nil, "OVERLAY")
    row.mixedTexture:SetPoint("CENTER", row.checkbox, "CENTER", 0, 0)
    -- A filled square means some, but not all, recipes in the group are selected.
    row.mixedTexture:SetSize(8, 8)
    row.mixedTexture:SetColorTexture(1, 0.65, 0, 1)
    row.mixedTexture:Hide()

    row.labelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.labelText:SetJustifyH("LEFT")
    row.labelText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.countText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.countText:SetWidth(96)
    row.countText:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(selfRow)
        local entry = selfRow.entry
        if entry and entry.kind == "recipe" then
            Scanner:ToggleTreeEntrySelection(entry)
        end
    end)
    local function showSelectionTooltip(owner)
        local entry = row.entry
        if not entry then
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
            GameTooltip:AddLine(string.format("All %d %s selected.", totalCount,
                    Scanner:Pluralize(totalCount, "recipe")),
                1, 1, 1, true)
        elseif state == "partial" then
            GameTooltip:AddLine(string.format("%d of %d recipes are selected.", selectedCount, totalCount),
                1, 1, 1, true)
            GameTooltip:AddLine("The filled square means this group is partially selected.", 1, 0.82, 0, true)
        elseif state == "none" then
            GameTooltip:AddLine(string.format("None of the %d %s selected.", totalCount,
                    Scanner:Pluralize(totalCount, "recipe")),
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
            GameTooltip:AddLine("Use the + or - control to expand or collapse. Use the checkbox to change selection.",
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
    row.expandButton:SetScript("OnEnter", showSelectionTooltip)
    row.expandButton:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdateRecipeList()
    local panel = self.configPanel
    if not panel then
        return
    end

    local entries = self:GetRecipeListEntries()
    local offset = 0
    for index, entry in ipairs(entries) do
        local row = self.recipeRows[index]
        if not row then
            row = self:CreateRecipeRow(panel.scrollChild)
            self.recipeRows[index] = row
        end
        local rowHeight = entry.kind == "profession" and 28 or entry.kind == "recipe" and 22 or 24
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -offset)
        row.bg:SetShown(entry.kind == "profession" or entry.kind == "category")
        self:UpdateRecipeRow(row, entry)
        row:Show()
        offset = offset + rowHeight
    end
    for index = #entries + 1, #self.recipeRows do
        self.recipeRows[index]:Hide()
    end
    panel.scrollChild:SetHeight(math.max(1, offset))
end

---@param view "items" | "recipes"
function Scanner:SetConfigView(view)
    self.configView = view == "items" and "items" or "recipes"
    if self.configPanel and self.configPanel.scrollFrame then
        self.configPanel.scrollFrame:SetVerticalScroll(0)
    end
    self:UpdateConfigList()
end

function Scanner:CreateConfigPanel()
    if self.configPanel or not self.panel or not self.panel.contentHost then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanConfigPanel", self.panel.contentHost)
    panel:SetAllPoints(self.panel.contentHost)
    panel:SetFrameLevel((self.panel.contentHost:GetFrameLevel() or 1) + 1)
    panel:EnableMouse(true)

    panel.headerBand = CreateNativeHeaderBand(panel, 38)
    panel.headerBand:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    panel.headerBand:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)

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
        GameTooltip:AddLine("First choose Products + reagents, Crafted products, or Required reagents.",
            1, 1, 1, true)
        GameTooltip:AddLine("Recipes selects complete professions, in-game categories, or individual recipes.",
            1, 1, 1, true)
        GameTooltip:AddLine("Individual Items provides exact Auction House target control.", 1, 1, 1, true)
        GameTooltip:AddLine("Use Selected only there to review the exact list before scanning.", 1, 1, 1, true)
        GameTooltip:AddLine("Shared items remain selected while any selected recipe needs them.", 1, 1, 1, true)
        GameTooltip:AddLine("Recipe counts describe tree choices. Price targets describe the products, ranks, and reagents produced by those choices.",
            1, 1, 1, true)
        GameTooltip:AddLine("A filled square means some, but not all, recipes in that group are selected.",
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    panel.helpButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.scopeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.scopeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
    panel.scopeLabel:SetText("Scan scope:")

    panel.scopeButtons = {}
    local scopeDefinitions = {
        { scope = self.SCAN_SCOPES.BOTH, width = 152 },
        { scope = self.SCAN_SCOPES.PRODUCTS, width = 132 },
        { scope = self.SCAN_SCOPES.REAGENTS, width = 140 },
    }
    local previousScopeButton
    for _, definition in ipairs(scopeDefinitions) do
        local scope = definition.scope
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(definition.width, 24)
        if previousScopeButton then
            button:SetPoint("LEFT", previousScopeButton, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", panel.scopeLabel, "RIGHT", 8, 0)
        end
        button.radio = CreateFrame("CheckButton", nil, button, "UIRadioButtonTemplate")
        button.radio:SetSize(20, 20)
        button.radio:SetPoint("LEFT", button, "LEFT", 0, 0)
        button.radio:EnableMouse(false)
        button.labelText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.labelText:SetPoint("LEFT", button.radio, "RIGHT", 2, 0)
        button.labelText:SetText(self:GetScanScopeLabel(scope))
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

    panel.professionButton = CreateNativeActionButton(panel, 190, 24)
    panel.professionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -134)
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

    panel.viewButtons = {}
    panel.viewButtons.recipes = CreateConfigViewTab(panel, "Recipes", 84)
    panel.viewButtons.recipes:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -70)
    panel.viewButtons.recipes:SetScript("OnClick", function()
        Scanner:SetConfigView("recipes")
    end)
    panel.viewButtons.recipes:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Recipes")
        GameTooltip:AddLine("Choose by profession, in-game category, or recipe.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.viewButtons.recipes:SetScript("OnLeave", GameTooltip_Hide)

    panel.viewButtons.items = CreateConfigViewTab(panel, "Individual items", 120)
    panel.viewButtons.items:SetPoint("LEFT", panel.viewButtons.recipes, "RIGHT", 3, 0)
    panel.viewButtons.items:SetScript("OnClick", function()
        Scanner:SetConfigView("items")
    end)
    panel.viewButtons.items:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Individual Items")
        GameTooltip:AddLine("Fine-tune the exact Auction House price targets.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.viewButtons.items:SetScript("OnLeave", GameTooltip_Hide)

    panel.selectAllButton = CreateTextAction(panel, 80)
    panel.selectAllButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 250, -106)
    panel.selectAllButton:SetText("Select all")
    panel.selectAllButton:SetScript("OnClick", function()
        Scanner:SetAllVisibleTargetsSelected(true)
    end)
    panel.selectAllButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if Scanner.configView == "recipes" then
            GameTooltip:AddLine("Select All Recipes")
            GameTooltip:AddLine("Select every recipe in the current profession tree and scan scope.",
                1, 1, 1, true)
        elseif string.match(tostring(Scanner.itemSearchText or ""), "%S") then
            GameTooltip:AddLine("Select Matches")
            GameTooltip:AddLine("Select every item matching the current search and filters.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Select All Items")
            GameTooltip:AddLine("Select every item in the current profession filter and scan scope.",
                1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    panel.selectAllButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.clearAllButton = CreateTextAction(panel, 72)
    panel.clearAllButton:SetPoint("LEFT", panel.selectAllButton, "RIGHT", 6, 0)
    panel.clearAllButton:SetText("Clear all")
    panel.clearAllButton:SetScript("OnClick", function()
        Scanner:SetAllVisibleTargetsSelected(false)
    end)
    panel.clearAllButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if Scanner.configView == "recipes" then
            GameTooltip:AddLine("Clear All Recipes")
            GameTooltip:AddLine("Clear every recipe in the current profession tree and scan scope.",
                1, 1, 1, true)
        elseif string.match(tostring(Scanner.itemSearchText or ""), "%S") then
            GameTooltip:AddLine("Clear Matches")
            GameTooltip:AddLine("Clear every item matching the current search and filters.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Clear All Items")
            GameTooltip:AddLine("Clear every item in the current profession filter and scan scope.",
                1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    panel.clearAllButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.treeExpansionButton = CreateFrame("Button", nil, panel)
    panel.treeExpansionButton:SetSize(76, 16)
    panel.treeExpansionButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -106)
    panel.treeExpansionButton:SetNormalFontObject("GameFontNormalSmall")
    panel.treeExpansionButton:SetHighlightFontObject("GameFontHighlightSmall")
    panel.treeExpansionButton:SetText("Expand all")
    panel.treeExpansionButton:SetScript("OnClick", function()
        Scanner:SetAllRecipeGroupsExpanded(not Scanner:HasExpandedRecipeGroups())
    end)
    panel.treeExpansionButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Recipe Tree")
        GameTooltip:AddLine("Expand or collapse every profession and recipe category in the current tree.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.treeExpansionButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.summaryFrame = CreateFrame("Frame", nil, panel)
    panel.summaryFrame:SetSize(224, 20)
    panel.summaryFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -104)
    panel.summaryFrame:EnableMouse(true)
    panel.summaryText = panel.summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summaryText:SetAllPoints(panel.summaryFrame)
    panel.summaryText:SetJustifyH("LEFT")
    panel.summaryText:SetText("0/0 recipes · 0 price targets")
    panel.summaryFrame:SetScript("OnEnter", function(frame)
        local counts = panel.summaryCounts or {}
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Selection Summary")
        local totalRecipes = tonumber(counts.totalRecipes) or 0
        GameTooltip:AddLine(string.format("%d of %d %s selected.",
            tonumber(counts.selectedRecipes) or 0, totalRecipes, Scanner:Pluralize(totalRecipes, "recipe")),
            1, 1, 1, true)
        GameTooltip:AddLine(string.format("They produce %d unique price targets in the current scope: %d products and %d reagents.",
            tonumber(counts.targets) or 0, tonumber(counts.products) or 0, tonumber(counts.reagents) or 0),
            1, 1, 1, true)
        GameTooltip:AddLine("One recipe can produce several product ranks and require several reagents. Shared targets are counted once.",
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("A price target is not always a separate Auction House request; compatible rank targets can reuse cached results.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    panel.summaryFrame:SetScript("OnLeave", GameTooltip_Hide)

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
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -166)
    panel.headerText:SetText("Type            Item                                  ItemID     Recipes")

    panel.listWell = CreateNativeListWell(panel)
    panel.listWell:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -176)
    panel.listWell:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -182)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(536, 1)
    panel.scrollFrame:SetScrollChild(panel.scrollChild)

    panel:Hide()
    self.configPanel = panel
end

---@param target table
---@param overrideTarget table
