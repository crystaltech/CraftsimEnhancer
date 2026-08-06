local _, ns = ...

local Config = ns.Config
local CURRENT_SCHEMA_VERSION = 2
local CURRENT_MIGRATION_VERSION = 2
local DEFAULT_FILL_QUANTITY = 20

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
            selectedProfessionsByCrafter = {},
            professionSelectionInitializedByCrafter = {},
            migratedGlobalSelectedProfessions = true,
            skippedTargets = {},
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
    if type(CraftSimEnhancerDB) ~= "table" then
        CraftSimEnhancerDB = {}
    end
    CopyDefaults(DEFAULTS, CraftSimEnhancerDB)
    CraftSimEnhancerDB.schemaVersion = CURRENT_SCHEMA_VERSION
    self.db = CraftSimEnhancerDB
    self:RunMigrations()
end

function Config:RunMigrations()
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

function Config.AuctionHouseScan:IsTargetSelected(targetKey)
    return self:GetSkippedTargets()[targetKey] ~= true
end

function Config.AuctionHouseScan:SaveTargetSelected(targetKey, selected)
    local skippedTargets = self:GetSkippedTargets()
    if selected then
        skippedTargets[targetKey] = nil
    else
        skippedTargets[targetKey] = true
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
