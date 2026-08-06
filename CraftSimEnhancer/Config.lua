local _, ns = ...

local Config = ns.Config
local CURRENT_SCHEMA_VERSION = 4
local CURRENT_MIGRATION_VERSION = 4
local DEFAULT_FILL_QUANTITY = 20
local DEFAULT_SCAN_SCOPE = "BOTH"

local DEFAULTS = {
    schemaVersion = CURRENT_SCHEMA_VERSION,
    migrationVersion = 0,
    global = {
        debug = false,
        modules = {
            AuctionHouseScan = true,
            BreakEvenTooltip = true,
            VendorBuy = true,
            VendorShoppingListNotice = true,
        },
        auctionHouseScan = {
            fillQuantity = DEFAULT_FILL_QUANTITY,
            scanScope = DEFAULT_SCAN_SCOPE,
            selectedProfessionsByCrafter = {},
            professionSelectionInitializedByCrafter = {},
            migratedGlobalSelectedProfessions = true,
            skippedTargets = {},
            selectedTargets = {},
            targetSelectionMode = "explicit",
            selectedRecipes = {},
            targetSelectionOverrides = {},
            recipeSelectionMode = "explicit",
            configProfession = "ALL",
        },
        vendorPlan = {
            createdAt = 0,
            sourceListName = "",
            items = {},
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
                width = 410,
                height = 0,
                userSized = false,
                collapsed = false,
                hidden = true,
            },
        },
    },
    profile = {},
}

local function CopyDefaults(defaults, destination)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            CopyDefaults(value, destination[key])
        elseif destination[key] == nil or type(destination[key]) ~= type(value) then
            destination[key] = value
        end
    end
end

local function CopyBooleanMap(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        if type(key) == "string" then
            copy[key] = value == true
        end
    end
    return copy
end

local function CopyNestedBooleanMaps(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        if type(key) == "string" and type(value) == "table" then
            copy[key] = CopyBooleanMap(value)
        end
    end
    return copy
end

function Config:Initialize()
    local isNewInstall = type(CraftSimEnhancerDB) ~= "table"
    if isNewInstall then
        CraftSimEnhancerDB = {}
    end
    CopyDefaults(DEFAULTS, CraftSimEnhancerDB)
    CraftSimEnhancerDB.schemaVersion = CURRENT_SCHEMA_VERSION
    self.db = CraftSimEnhancerDB
    self:RunMigrations(isNewInstall)
end

---@param isNewInstall boolean?
function Config:RunMigrations(isNewInstall)
    local migrationVersion = tonumber(self.db.migrationVersion) or 0
    if migrationVersion >= CURRENT_MIGRATION_VERSION then
        self.migrationStatus = self.db.migrationStatus or "complete"
        return
    end

    if migrationVersion < 1 then
        local legacy = type(CraftSimDB) == "table" and CraftSimDB.auctionHouseScanDB
        legacy = type(legacy) == "table" and legacy.data or nil
        if type(legacy) == "table" then
            local target = self.db.global.auctionHouseScan
            target.selectedProfessionsByCrafter = CopyNestedBooleanMaps(legacy.selectedProfessionsByCrafter)
            target.professionSelectionInitializedByCrafter = CopyBooleanMap(
                legacy.professionSelectionInitializedByCrafter)
            target.skippedTargets = CopyBooleanMap(legacy.skippedTargets)
            target.configProfession = type(legacy.configProfession) == "string" and legacy.configProfession or "ALL"
            target.migratedGlobalSelectedProfessions = legacy.migratedGlobalSelectedProfessions == true

            -- Older builds stored one global profession map. Preserve it for the current character.
            if next(target.selectedProfessionsByCrafter) == nil and type(legacy.selectedProfessions) == "table" then
                local crafterUID = ns.Compat.WoW:GetCrafterUID()
                target.selectedProfessionsByCrafter[crafterUID] = CopyBooleanMap(legacy.selectedProfessions)
                target.professionSelectionInitializedByCrafter[crafterUID] = true
                target.migratedGlobalSelectedProfessions = true
            end
            self.migrationStatus = "legacy settings copied"
        else
            self.migrationStatus = "no legacy settings found"
        end
    end

    if migrationVersion < 2 then
        -- Fill quantity is no longer user-configurable. Keep existing installs
        -- aligned with the fixed small-batch pricing quantity.
        self.db.global.auctionHouseScan.fillQuantity = DEFAULT_FILL_QUANTITY
        self.migrationStatus = "input fill quantity updated"
    end

    if migrationVersion < 3 then
        local target = self.db.global.auctionHouseScan
        target.scanScope = DEFAULT_SCAN_SCOPE
        target.selectedTargets = {}
        if isNewInstall then
            -- A new user starts with an honest empty selection. Existing
            -- installs are converted lazily once the complete generated item
            -- catalog is available to the scanner.
            target.targetSelectionMode = "explicit"
            self.migrationStatus = "new explicit scan selection initialized"
        else
            target.targetSelectionMode = "legacy-exclude"
            self.migrationStatus = "scan selection awaiting catalog migration"
        end
    end

    if migrationVersion < 4 then
        local target = self.db.global.auctionHouseScan
        target.selectedRecipes = {}
        target.targetSelectionOverrides = {}
        if isNewInstall then
            target.recipeSelectionMode = "explicit"
        else
            -- The scanner converts the old item-only allowlist after the full
            -- recipe catalog is available. That lets it preserve the exact
            -- effective selection while restoring recipe ownership.
            target.recipeSelectionMode = "target-allowlist"
            self.migrationStatus = "recipe selection awaiting catalog migration"
        end
    end

    self.db.migrationVersion = CURRENT_MIGRATION_VERSION
    self.db.migrationStatus = self.migrationStatus
end

function Config:IsModuleEnabled(name)
    return self.db.global.modules[name] ~= false
end

function Config:SetModuleEnabled(name, enabled)
    self.db.global.modules[name] = enabled == true
end

function Config:IsDebugEnabled()
    return self.db.global.debug == true
end

function Config:SetDebugEnabled(enabled)
    self.db.global.debug = enabled == true
end

function Config:GetMigrationStatus()
    return self.migrationStatus or self.db.migrationStatus or "not run"
end

function Config:Reset()
    CraftSimEnhancerDB = {
        migrationVersion = CURRENT_MIGRATION_VERSION,
        migrationStatus = "reset; legacy settings not re-imported",
    }
    self.db = nil
    self.migrationStatus = nil
    self:Initialize()
end

Config.AuctionHouseScan = {}

function Config.AuctionHouseScan:GetData()
    return Config.db.global.auctionHouseScan
end

function Config.AuctionHouseScan:GetFillQuantity()
    return tonumber(self:GetData().fillQuantity) or DEFAULT_FILL_QUANTITY
end

function Config.AuctionHouseScan:SaveFillQuantity(fillQuantity)
    fillQuantity = tonumber(fillQuantity) or DEFAULT_FILL_QUANTITY
    self:GetData().fillQuantity = math.max(5, math.min(1000, math.floor(fillQuantity)))
end

function Config.AuctionHouseScan:EnsureSelectedProfessions(defaultSelectedProfessions)
    local data = self:GetData()
    local crafterUID = ns.Compat.WoW:GetCrafterUID()
    if not data.professionSelectionInitializedByCrafter[crafterUID] then
        data.selectedProfessionsByCrafter[crafterUID] = CopyBooleanMap(defaultSelectedProfessions)
        data.professionSelectionInitializedByCrafter[crafterUID] = true
    end
    data.selectedProfessionsByCrafter[crafterUID] = data.selectedProfessionsByCrafter[crafterUID] or {}
    return data.selectedProfessionsByCrafter[crafterUID]
end

function Config.AuctionHouseScan:GetSelectedProfessions()
    return self:EnsureSelectedProfessions()
end

function Config.AuctionHouseScan:IsProfessionSelected(profession)
    return self:GetSelectedProfessions()[profession] == true
end

function Config.AuctionHouseScan:SaveProfessionSelected(profession, selected)
    local data = self:GetData()
    local crafterUID = ns.Compat.WoW:GetCrafterUID()
    data.professionSelectionInitializedByCrafter[crafterUID] = true
    self:GetSelectedProfessions()[profession] = selected == true
end

function Config.AuctionHouseScan:GetSkippedTargets()
    local data = self:GetData()
    data.skippedTargets = data.skippedTargets or {}
    return data.skippedTargets
end

function Config.AuctionHouseScan:GetSelectedTargets()
    local data = self:GetData()
    data.selectedTargets = data.selectedTargets or {}
    return data.selectedTargets
end

function Config.AuctionHouseScan:GetSelectedRecipes()
    local data = self:GetData()
    data.selectedRecipes = data.selectedRecipes or {}
    return data.selectedRecipes
end

function Config.AuctionHouseScan:IsRecipeSelected(recipeIdentity)
    return self:GetSelectedRecipes()[recipeIdentity] == true
end

function Config.AuctionHouseScan:SaveRecipeSelected(recipeIdentity, selected)
    local selectedRecipes = self:GetSelectedRecipes()
    if selected == true then
        selectedRecipes[recipeIdentity] = true
    else
        selectedRecipes[recipeIdentity] = nil
    end
end

function Config.AuctionHouseScan:GetTargetSelectionOverrides()
    local data = self:GetData()
    data.targetSelectionOverrides = data.targetSelectionOverrides or {}
    return data.targetSelectionOverrides
end

function Config.AuctionHouseScan:GetTargetSelectionOverride(targetKey)
    return self:GetTargetSelectionOverrides()[targetKey]
end

function Config.AuctionHouseScan:SaveTargetSelectionOverride(targetKey, selected)
    self:GetTargetSelectionOverrides()[targetKey] = selected == true
end

function Config.AuctionHouseScan:IsRecipeSelectionExplicit()
    return self:GetData().recipeSelectionMode == "explicit"
end

---@param selectedRecipes table<string, boolean>
---@param targetSelectionOverrides table<string, boolean>
function Config.AuctionHouseScan:InitializeRecipeSelection(selectedRecipes, targetSelectionOverrides)
    local data = self:GetData()
    data.selectedRecipes = selectedRecipes or {}
    data.targetSelectionOverrides = targetSelectionOverrides or {}
    data.recipeSelectionMode = "explicit"
    Config.migrationStatus = "recipe-aware scan selection migrated"
    Config.db.migrationStatus = Config.migrationStatus
    data.selectionMigrationStatus = Config.migrationStatus
end

---@param selectedTargets table<string, boolean>
function Config.AuctionHouseScan:ReplaceSelectedTargets(selectedTargets)
    local data = self:GetData()
    data.selectedTargets = selectedTargets or {}
    data.skippedTargets = {}
    data.targetSelectionMode = "explicit"
end

---@return "PRODUCTS" | "REAGENTS" | "BOTH"
function Config.AuctionHouseScan:GetScanScope()
    local scope = tostring(self:GetData().scanScope or DEFAULT_SCAN_SCOPE)
    if scope ~= "PRODUCTS" and scope ~= "REAGENTS" and scope ~= "BOTH" then
        scope = DEFAULT_SCAN_SCOPE
    end
    return scope
end

---@param scope string?
function Config.AuctionHouseScan:SaveScanScope(scope)
    scope = tostring(scope or DEFAULT_SCAN_SCOPE)
    if scope ~= "PRODUCTS" and scope ~= "REAGENTS" and scope ~= "BOTH" then
        scope = DEFAULT_SCAN_SCOPE
    end
    self:GetData().scanScope = scope
end

---@param targets table[]
---@return boolean migrated
function Config.AuctionHouseScan:EnsureExplicitTargetSelection(targets)
    local data = self:GetData()
    if data.targetSelectionMode ~= "legacy-exclude" then
        return false
    end

    local skippedTargets = self:GetSkippedTargets()
    local selectedTargets = {}
    for _, target in ipairs(targets or {}) do
        if target.key and skippedTargets[target.key] ~= true then
            selectedTargets[target.key] = true
        end
    end

    data.selectedTargets = selectedTargets
    data.skippedTargets = {}
    data.targetSelectionMode = "explicit"
    Config.migrationStatus = "legacy scan selection migrated"
    Config.db.migrationStatus = Config.migrationStatus
    data.selectionMigrationStatus = Config.migrationStatus
    return true
end

function Config.AuctionHouseScan:IsTargetSelected(targetKey)
    local data = self:GetData()
    if data.targetSelectionMode == "legacy-exclude" then
        return self:GetSkippedTargets()[targetKey] ~= true
    end
    return self:GetSelectedTargets()[targetKey] == true
end

function Config.AuctionHouseScan:SaveTargetSelected(targetKey, selected)
    local data = self:GetData()
    if data.targetSelectionMode == "legacy-exclude" then
        local skippedTargets = self:GetSkippedTargets()
        if selected then
            skippedTargets[targetKey] = nil
        else
            skippedTargets[targetKey] = true
        end
        return
    end

    local selectedTargets = self:GetSelectedTargets()
    if selected == true then
        selectedTargets[targetKey] = true
    else
        selectedTargets[targetKey] = nil
    end
end

function Config.AuctionHouseScan:GetConfigProfession()
    return self:GetData().configProfession or "ALL"
end

function Config.AuctionHouseScan:SaveConfigProfession(profession)
    self:GetData().configProfession = profession or "ALL"
end

Config.VendorPlan = {}

function Config.VendorPlan:GetData()
    return Config.db.global.vendorPlan
end

function Config.VendorPlan:GetItems()
    local data = self:GetData()
    data.items = data.items or {}
    return data.items
end

function Config.VendorPlan:Replace(items, sourceListName)
    local data = self:GetData()
    data.items = type(items) == "table" and items or {}
    data.createdAt = time and time() or 0
    data.sourceListName = tostring(sourceListName or "")
    data.window.hidden = false
end

function Config.VendorPlan:Clear()
    local data = self:GetData()
    data.items = {}
    data.createdAt = 0
    data.sourceListName = ""
    data.window.hidden = true
end

function Config.VendorPlan:GetWindow()
    return self:GetData().window
end
