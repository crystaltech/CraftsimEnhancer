local function enumTable()
    return setmetatable({}, {
        __index = function(tableValue, key)
            local value = enumTable()
            rawset(tableValue, key, value)
            return value
        end,
    })
end

Enum = enumTable()
Enum.Profession.Alchemy = 1
Enum.Profession.Blacksmithing = 2
Enum.Profession.Cooking = 3
Enum.Profession.Enchanting = 4
Enum.Profession.Engineering = 5
Enum.Profession.Inscription = 6
Enum.Profession.Jewelcrafting = 7
Enum.Profession.Leatherworking = 8
Enum.Profession.Tailoring = 9
Enum.AuctionHouseSortOrder.Price = 1

local registeredScanner
local namespace = {
    Config = { AuctionHouseScan = {} },
    Debug = { Log = function() end },
    Compat = { CraftSim = {} },
    Modules = {},
}
function namespace:RegisterModule(name, module)
    self.Modules[name] = module
    registeredScanner = module
end
function namespace.Filter(values, predicate)
    local result = {}
    for _, value in ipairs(values) do
        if predicate(value) then
            result[#result + 1] = value
        end
    end
    return result
end

C_AuctionHouse = {}
function C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID)
    return {
        itemID = itemID,
        itemLevel = itemLevel,
        itemSuffix = itemSuffix,
        battlePetSpeciesID = battlePetSpeciesID,
    }
end

assert(loadfile("CraftSimEnhancer/Compat/CraftSim.lua"))("CraftSimEnhancer", namespace)
assert(loadfile("CraftSimEnhancer/Modules/AuctionHouseScan.lua"))("CraftSimEnhancer", namespace)
for _, path in ipairs({
    "CraftSimEnhancer/Modules/AuctionHouseScan/UI.lua",
    "CraftSimEnhancer/Modules/AuctionHouseScan/ConfigurationUI.lua",
    "CraftSimEnhancer/Modules/AuctionHouseScan/Targets.lua",
    "CraftSimEnhancer/Modules/AuctionHouseScan/Query.lua",
    "CraftSimEnhancer/Modules/AuctionHouseScan/Pricing.lua",
    "CraftSimEnhancer/Modules/AuctionHouseScan/Lifecycle.lua",
}) do
    assert(loadfile(path))("CraftSimEnhancer", namespace)
end
local Scanner = assert(registeredScanner)

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function testScannerModuleSurfaceComplete()
    for _, functionName in ipairs({
        "CreatePanel",
        "CreateConfigPanel",
        "BuildScanTargets",
        "StartScan",
        "PushOverrides",
        "Initialize",
    }) do
        assertEqual(type(Scanner[functionName]), "function", functionName .. " loaded from scanner module set")
    end
end

local function testReturnedItemKeyIsUsedForNormalSearch()
    local queriedLevel
    C_AuctionHouse.GetNumItemSearchResults = function(itemKey)
        queriedLevel = itemKey.itemLevel
        return itemKey.itemLevel == 197 and 1 or 0
    end
    C_AuctionHouse.GetItemSearchResultInfo = function(itemKey)
        return {
            auctionID = 10,
            buyoutAmount = 7490000,
            quantity = 1,
            itemKey = itemKey,
        }
    end

    local target = {
        itemID = 239673,
        itemLevel = 0,
        itemSearchKey = Scanner:MakeItemKey(239673, 0),
        usesBroadItemSearch = false,
    }
    Scanner:CaptureItemResultKey(target, Scanner:MakeItemKey(239673, 197))
    local rows = Scanner:GetItemRows(Scanner:GetTargetItemResultKey(target), target)

    assertEqual(queriedLevel, 197, "normal search read level")
    assertEqual(#rows, 1, "normal search row count")
end

local function testClearedItemKeyOverridesConstructorNormalization()
    local originalMakeItemKey = C_AuctionHouse.MakeItemKey
    C_AuctionHouse.MakeItemKey = function(itemID)
        return {
            itemID = itemID,
            itemLevel = 44,
            itemSuffix = 123,
            battlePetSpeciesID = 0,
        }
    end

    local itemKey = Scanner:MakeClearedItemKey(239673)
    C_AuctionHouse.MakeItemKey = originalMakeItemKey

    assertEqual(itemKey.itemLevel, 0, "cleared item level")
    assertEqual(itemKey.itemSuffix, 0, "cleared item suffix")
end

local function testBroadEquipmentSearchReadsAllRanks()
    local searchKey = Scanner:MakeItemKey(239673, 0)
    local sourceRows = {
        {
            auctionID = 11,
            buyoutAmount = 30000000,
            quantity = 1,
            itemKey = Scanner:MakeItemKey(239673, 165),
        },
        {
            auctionID = 12,
            buyoutAmount = 7499600,
            quantity = 1,
            itemKey = Scanner:MakeItemKey(239673, 178),
        },
    }
    C_AuctionHouse.GetNumItemSearchResults = function(itemKey)
        assertEqual(itemKey.itemLevel, 0, "broad search read level")
        return #sourceRows
    end
    C_AuctionHouse.GetItemSearchResultInfo = function(_, index)
        return sourceRows[index]
    end

    local target = {
        itemID = 239673,
        itemLevel = 44,
        outputQualityID = 1,
        requiredBonusIDs = { 90001 },
        rankItemLevelDeltas = { [1] = 0, [2] = 3, [3] = 6, [4] = 9, [5] = 13 },
        rankBonusIDsByQuality = {},
        itemSearchKey = searchKey,
        usesBroadItemSearch = true,
    }
    Scanner:CaptureItemResultKey(target, Scanner:MakeItemKey(239673, 0))
    local rows = Scanner:GetItemRows(Scanner:GetTargetItemResultKey(target), target)

    assertEqual(#target.currentRawItemRows, 2, "broad raw row count")
    assertEqual(target.itemLevel, 165, "inferred rank one level")
    assertEqual(#rows, 1, "rank one row count")
    assertEqual(rows[1].auctionID, 11, "rank one auction")
end

local function testEquipmentStartsBroadSellSearch()
    local sellCalls = 0
    local normalCalls = 0
    C_AuctionHouse.GetItemKeyInfo = function()
        return { isEquipment = true }
    end
    C_AuctionHouse.SendSellSearchQuery = function(itemKey)
        sellCalls = sellCalls + 1
        itemKey.itemLevel = 197 -- Simulate the API normalizing the caller's table.
    end
    C_AuctionHouse.SendSearchQuery = function()
        normalCalls = normalCalls + 1
    end

    AuctionHouseFrame = { IsShown = function() return true end }
    GetTime = function() return 100 end
    local target = {
        itemID = 239673,
        itemLevel = 44,
        queryItemLevel = 0,
        itemKey = Scanner:MakeItemKey(239673, 0),
        resultType = "item",
        pricingMode = "output",
        requiredBonusIDs = { 90001 },
        label = "Courtly Slippers",
    }
    local originalIsAuctionThrottleReady = Scanner.IsAuctionThrottleReady
    local originalSetStatus = Scanner.SetStatus
    local originalUpdateProgressText = Scanner.UpdateProgressText
    local originalSchedulePendingTimeout = Scanner.SchedulePendingTimeout
    local originalSchedulePendingPoll = Scanner.SchedulePendingPoll
    Scanner.isScanning = true
    Scanner.pendingQuery = nil
    Scanner.scanIndex = 0
    Scanner.totalTargets = 1
    Scanner.scanTargets = { target }
    Scanner.nextQueryTime = 0
    Scanner.outputItemRowsCache = {}
    Scanner.IsAuctionThrottleReady = function() return true end
    Scanner.SetStatus = function() end
    Scanner.UpdateProgressText = function() end
    Scanner.SchedulePendingTimeout = function() end
    Scanner.SchedulePendingPoll = function() end
    Scanner:TrySendNextQuery()

    assertEqual(sellCalls, 1, "sell-search calls")
    assertEqual(normalCalls, 0, "normal-search calls")
    assertEqual(target.itemSearchKey.itemLevel, 0, "stable broad result key")
    assertEqual(Scanner:GetTargetItemResultKey(target).itemLevel, 0, "broad result read key")

    Scanner.IsAuctionThrottleReady = originalIsAuctionThrottleReady
    Scanner.SetStatus = originalSetStatus
    Scanner.UpdateProgressText = originalUpdateProgressText
    Scanner.SchedulePendingTimeout = originalSchedulePendingTimeout
    Scanner.SchedulePendingPoll = originalSchedulePendingPoll
end

local function testAlternateEmptyCacheCannotCompleteItemSearch()
    local processed = false
    local scheduled = false
    local originalGetRows = Scanner.GetRowsForResultType
    local originalHasFull = Scanner.HasFullResults
    local originalFallbacks = Scanner.TryFallbacksBeforeMissing
    local originalSchedule = Scanner.SchedulePendingPoll
    local originalProcess = Scanner.ProcessPendingResults

    Scanner.GetRowsForResultType = function() return {} end
    Scanner.HasFullResults = function(_, resultType) return resultType == "commodity" end
    Scanner.TryFallbacksBeforeMissing = function() return false end
    Scanner.SchedulePendingPoll = function() scheduled = true end
    Scanner.ProcessPendingResults = function() processed = true end
    Scanner.isScanning = true
    Scanner.pendingQuery = {
        itemID = 239673,
        resultType = "item",
        resultsReceived = true,
    }
    Scanner:PollPendingResults()

    Scanner.GetRowsForResultType = originalGetRows
    Scanner.HasFullResults = originalHasFull
    Scanner.TryFallbacksBeforeMissing = originalFallbacks
    Scanner.SchedulePendingPoll = originalSchedule
    Scanner.ProcessPendingResults = originalProcess

    assertEqual(processed, false, "alternate empty result processing")
    assertEqual(scheduled, true, "incomplete primary result polling")
end

local function testDirectEmptyItemResultGetsConfirmationRetry()
    local retryCalled = false
    local finishCalled = false
    local originalGetRows = Scanner.GetRowsForResultType
    local originalFallbacks = Scanner.TryFallbacksBeforeMissing
    local originalHasFull = Scanner.HasFullResults
    local originalRetry = Scanner.RetryEmptySearch
    local originalFinish = Scanner.FinishPendingTarget

    Scanner.GetRowsForResultType = function() return {} end
    Scanner.TryFallbacksBeforeMissing = function() return false end
    Scanner.HasFullResults = function() return true end
    Scanner.RetryEmptySearch = function()
        retryCalled = true
        return true
    end
    Scanner.FinishPendingTarget = function() finishCalled = true end
    Scanner.isScanning = true
    Scanner.pendingQuery = {
        itemID = 239673,
        resultType = "item",
        resultsReceived = true,
    }
    Scanner:ProcessPendingResults("item")

    Scanner.GetRowsForResultType = originalGetRows
    Scanner.TryFallbacksBeforeMissing = originalFallbacks
    Scanner.HasFullResults = originalHasFull
    Scanner.RetryEmptySearch = originalRetry
    Scanner.FinishPendingTarget = originalFinish

    assertEqual(retryCalled, true, "direct empty result confirmation retry")
    assertEqual(finishCalled, false, "direct empty result premature completion")
end

local function testMissingResultBreakEvenPricing()
    local price, capped = Scanner:CalculateMissingResultPrice(10000)
    assertEqual(price, 10526, "break-even price after AH cut")
    assertEqual(capped, false, "uncapped break-even price")

    price, capped = Scanner:CalculateMissingResultPrice(10000, 9000)
    assertEqual(price, 8999, "better-rank cap")
    assertEqual(capped, true, "better-rank cap flag")

    price, capped = Scanner:CalculateMissingResultPrice(nil, 9000)
    assertEqual(price, nil, "missing crafting cost price")
    assertEqual(capped, false, "missing crafting cost cap flag")
end

local function testMissingLowerRankUsesCheapestRealBetterRank()
    Scanner.priceResults = {
        {
            price = 15000,
            overrideTargets = { { kind = "result", recipeID = 100, qualityID = 3 } },
        },
        {
            price = 12000,
            overrideTargets = { { kind = "result", recipeID = 100, qualityID = 5 } },
        },
        {
            price = 8000,
            overrideTargets = { { kind = "result", recipeID = 100, qualityID = 1 } },
        },
    }

    local normalized, cappedCount, pricesByRecipe = Scanner:GetNormalizedResultOverridePrices()
    assertEqual(normalized["100:3"], 12000, "real lower-rank normalization")
    assertEqual(cappedCount, 1, "real lower-rank cap count")
    assertEqual(Scanner:GetCheapestRealBetterRankPrice(pricesByRecipe, 100, 2), 12000,
        "missing lower-rank ceiling")
    assertEqual(Scanner:GetCheapestRealBetterRankPrice(pricesByRecipe, 100, 5), nil,
        "highest rank has no better-rank ceiling")
end

local function testCraftSimCostCompatibilityFallbacks()
    local qualityCosts = {
        [3] = { "Crafter-Realm", 15000, 1000 },
        [5] = { "Crafter-Realm", 12000, 2000 },
    }
    local repository = {
        GetCheapestByItemIDAndQuality = function(_, _, qualityID)
            local entry = qualityCosts[qualityID]
            if entry then
                return entry[1], entry[2], entry[3]
            end
        end,
        GetCheapestByItemID = function() return nil end,
    }
    namespace.Compat.CraftSim.craftSim = { DB = { LAST_CRAFTING_COST = repository } }

    local cost, timestamp, crafterUID, costQualityID =
        namespace.Compat.CraftSim:GetLastCraftingCost(239673, 3)
    assertEqual(cost, 15000, "exact quality cost")
    assertEqual(timestamp, 1000, "exact quality timestamp")
    assertEqual(crafterUID, "Crafter-Realm", "exact quality crafter")
    assertEqual(costQualityID, 3, "exact cost quality")

    cost, timestamp, crafterUID, costQualityID = namespace.Compat.CraftSim:GetLastCraftingCost(239673, 2)
    assertEqual(cost, 12000, "cheapest alternate quality cost")
    assertEqual(timestamp, 2000, "alternate quality timestamp")
    assertEqual(crafterUID, "Crafter-Realm", "alternate quality crafter")
    assertEqual(costQualityID, 5, "alternate cost quality")
end

local function testCraftSimTooltipCostCompatibility()
    local receivedLink
    local repository = {
        GetCheapestByItemLink = function(_, itemLink)
            receivedLink = itemLink
            return "TooltipCrafter-Realm", 21000, 3000
        end,
        GetCheapestByItemID = function()
            return "FallbackCrafter-Realm", 22000, 4000
        end,
    }
    namespace.Compat.CraftSim.craftSim = { DB = { LAST_CRAFTING_COST = repository } }

    local cost, timestamp, crafterUID = namespace.Compat.CraftSim:GetLastCraftingCostForTooltip(
        "item:239673::::::::::Quality-Tier4", 239673)
    assertEqual(cost, 21000, "tooltip link cost")
    assertEqual(timestamp, 3000, "tooltip link timestamp")
    assertEqual(crafterUID, "TooltipCrafter-Realm", "tooltip link crafter")
    assertEqual(receivedLink, "item:239673::::::::::Quality-Tier4", "tooltip exact-rank link")

    cost, timestamp, crafterUID = namespace.Compat.CraftSim:GetLastCraftingCostForTooltip(nil, 240160)
    assertEqual(cost, 22000, "tooltip item ID fallback cost")
    assertEqual(timestamp, 4000, "tooltip item ID fallback timestamp")
    assertEqual(crafterUID, "FallbackCrafter-Realm", "tooltip item ID fallback crafter")
    assertEqual(namespace.Compat.CraftSim:ValidateBreakEvenTooltip(), true, "tooltip repository validation")
end

local function testAuctionHouseDisplayModeClassification()
    assertEqual(Scanner:IsBuiltInAuctionHouseDisplayMode(nil), false, "nil display mode")
    assertEqual(Scanner:IsBuiltInAuctionHouseDisplayMode({}), false, "custom empty display mode")
    assertEqual(Scanner:IsBuiltInAuctionHouseDisplayMode({ "BrowseResultsFrame" }), true,
        "built-in table display mode")
    assertEqual(Scanner:IsBuiltInAuctionHouseDisplayMode(1), true, "non-table display mode")
end

local function testGeneratedRecipeCategoryLookupAndTargetIndex()
    namespace.Data = {
        RecipeCategories = {
            categories = {
                [2275] = { name = "Chest Enchants", order = 35 },
                [2265] = { name = "Shattering", order = 10 },
            },
            recipeIDs = { [123] = 2275 },
            recipeNames = { ["Enchanting:Dawn Shatter"] = 2265 },
        },
    }
    local categoryID, category = Scanner:GetRecipeCategoryInfo({
        profession = "Enchanting",
        stratName = "Test Chest Enchant",
        recipeID = 123,
    })
    assertEqual(categoryID, 2275, "numeric recipe category ID")
    assertEqual(category.name, "Chest Enchants", "numeric recipe category name")

    categoryID, category = Scanner:GetRecipeCategoryInfo({
        profession = "Enchanting",
        stratName = "Dawn Shatter",
    })
    assertEqual(categoryID, 2265, "named recipe category ID")
    assertEqual(category.name, "Shattering", "named recipe category name")

    local numericTarget = {
        key = "numeric",
        sourceRecipeMap = { [123] = true },
        sourceNamesByProfession = {},
    }
    local namedTarget = {
        key = "named",
        sourceRecipeMap = {},
        sourceNamesByProfession = { Enchanting = { ["Dawn Shatter"] = true } },
    }
    Scanner.configTargets = { numericTarget, namedTarget }
    local targetsByRecipe = Scanner:BuildTargetsByRecipeIdentity()
    assertEqual(targetsByRecipe["id:123"].numeric, numericTarget, "numeric recipe target index")
    assertEqual(targetsByRecipe["name:Enchanting:Dawn Shatter"].named, namedTarget,
        "named recipe target index")

    namespace.Data.GeneratedRecipes = {
        { profession = "Enchanting", stratName = "Test Chest Enchant", recipeID = 123 },
        { profession = "Enchanting", stratName = "Dawn Shatter" },
    }
    local originalGetConfigProfession = Scanner.GetConfigProfession
    local originalGetProfessionDisplayName = Scanner.GetProfessionDisplayName
    Scanner.GetConfigProfession = function() return "Enchanting" end
    Scanner.GetProfessionDisplayName = function(_, info) return info.name end
    Scanner.expandedQuickSetGroups = {}
    Scanner.expandedProfessionGroups = {}
    Scanner.expandedCategoryGroups = {}
    local entries = Scanner:GetPresetListEntries()

    assertEqual(entries[1].kind, "quicksets", "quick sets group row")
    assertEqual(entries[1].expanded, true, "quick sets default expansion")
    assertEqual(entries[8].kind, "profession", "tree profession row")
    assertEqual(entries[9].label, "Shattering", "tree category order")
    assertEqual(entries[10].label, "Dawn Shatter", "tree named recipe row")
    assertEqual(entries[11].label, "Chest Enchants", "tree second category")
    assertEqual(entries[12].label, "Test Chest Enchant", "tree numeric recipe row")

    Scanner.expandedQuickSetGroups["quick-sets"] = false
    local collapsedEntries = Scanner:GetPresetListEntries()
    assertEqual(collapsedEntries[1].expanded, false, "quick sets collapsed state")
    assertEqual(collapsedEntries[2].kind, "profession", "collapsed quick sets hides preset rows")
    Scanner.GetConfigProfession = originalGetConfigProfession
    Scanner.GetProfessionDisplayName = originalGetProfessionDisplayName
    Scanner.expandedQuickSetGroups = {}
end

local function testConfigViewProfessionScopeAndSelectedTargetCount()
    local config = namespace.Config.AuctionHouseScan
    local originalGetConfigProfession = config.GetConfigProfession
    local originalSaveConfigProfession = config.SaveConfigProfession
    local originalGetSelectedProfessions = Scanner.GetSelectedProfessions
    local originalHasSelectedProfession = Scanner.HasSelectedProfession
    local originalBuildScanTargets = Scanner.BuildScanTargets
    local originalConfigView = Scanner.configView

    config.GetConfigProfession = function() return "Cooking" end
    config.SaveConfigProfession = function() end
    Scanner.GetSelectedProfessions = function() return { Cooking = true } end

    Scanner.configView = "presets"
    assertEqual(Scanner:GetConfigProfession(), "ALL", "recipe tree ignores hidden profession filter")

    Scanner.configView = "items"
    assertEqual(Scanner:GetConfigProfession(), "Cooking", "item details keeps profession filter")
    assertEqual(Scanner:GetProfessionDropdownText("ALL"), "Profession: All Selected",
        "item details all-professions label")

    Scanner.HasSelectedProfession = function() return false end
    Scanner.BuildScanTargets = function() error("target build should not run without a profession") end
    assertEqual(Scanner:GetSelectedScanTargetCount(), 0, "no-profession target count")

    Scanner.HasSelectedProfession = function() return true end
    Scanner.BuildScanTargets = function(_, options)
        assertEqual(options.skipFixedPrices, true, "selected target count excludes fixed prices")
        return { {}, {} }
    end
    assertEqual(Scanner:GetSelectedScanTargetCount(), 2, "selected scan target count")

    config.GetConfigProfession = originalGetConfigProfession
    config.SaveConfigProfession = originalSaveConfigProfession
    Scanner.GetSelectedProfessions = originalGetSelectedProfessions
    Scanner.HasSelectedProfession = originalHasSelectedProfession
    Scanner.BuildScanTargets = originalBuildScanTargets
    Scanner.configView = originalConfigView
end

testScannerModuleSurfaceComplete()
testReturnedItemKeyIsUsedForNormalSearch()
testBroadEquipmentSearchReadsAllRanks()
testClearedItemKeyOverridesConstructorNormalization()
testEquipmentStartsBroadSellSearch()
testAlternateEmptyCacheCannotCompleteItemSearch()
testDirectEmptyItemResultGetsConfirmationRetry()
testMissingResultBreakEvenPricing()
testMissingLowerRankUsesCheapestRealBetterRank()
testCraftSimCostCompatibilityFallbacks()
testCraftSimTooltipCostCompatibility()
testAuctionHouseDisplayModeClassification()
testGeneratedRecipeCategoryLookupAndTargetIndex()
testConfigViewProfessionScopeAndSelectedTargetCount()

print("AuctionHouseScan tests passed")
