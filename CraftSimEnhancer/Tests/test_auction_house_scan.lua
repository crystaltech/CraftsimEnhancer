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
namespace.Config.AuctionHouseScan.GetScanScope = function()
    return "BOTH"
end
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

local function testInputPricingUsesTwentyUnitFill()
    namespace.Config.AuctionHouseScan.GetFillQuantity = function()
        return 20
    end
    local price, quantityUsed, listedQuantity, trimmedUnits = Scanner:CalculateTrimmedFillPrice({
        { unitPrice = 100, quantity = 10 },
        { unitPrice = 200, quantity = 10 },
        { unitPrice = 300, quantity = 10 },
    })

    assertEqual(price, 150, "twenty-unit fill price")
    assertEqual(quantityUsed, 20, "twenty-unit fill quantity")
    assertEqual(listedQuantity, 20, "listings consumed through fill")
    assertEqual(trimmedUnits, 0, "fill outliers trimmed")
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

local function testAuctionHouseTabLayoutOwnership()
    local originalAuctionHouseFrame = AuctionHouseFrame
    local originalPanelTemplatesTabResize = PanelTemplates_TabResize
    local originalPanelTemplatesSetNumTabs = PanelTemplates_SetNumTabs
    local originalButton = Scanner.button
    local originalUsesTabLibrary = Scanner.usesTabLibrary

    local resizeCalls = 0
    PanelTemplates_TabResize = function()
        resizeCalls = resizeCalls + 1
    end

    Scanner.usesTabLibrary = true
    Scanner:ResizeAuctionHouseTab({})
    assertEqual(resizeCalls, 0, "LibAHTab owns its button width")

    local lastBuiltInTab = {}
    local launcher = {
        ClearAllPoints = function(self)
            self.clearedPoints = true
        end,
        SetPoint = function(self, ...)
            self.point = { ... }
        end,
    }
    local tabs = { {}, lastBuiltInTab }
    local setNumTabsCalls = 0
    AuctionHouseFrame = { Tabs = tabs }
    PanelTemplates_SetNumTabs = function()
        setNumTabsCalls = setNumTabsCalls + 1
    end
    Scanner.button = launcher
    Scanner.usesTabLibrary = false

    Scanner:AttachLauncherTabToAuctionHouseTabs()

    assertEqual(#tabs, 2, "fallback launcher stays outside Blizzard tab collection")
    assertEqual(launcher.clearedPoints, true, "fallback launcher clears old anchors")
    assertEqual(launcher.point[1], "LEFT", "fallback launcher anchor point")
    assertEqual(launcher.point[2], lastBuiltInTab, "fallback launcher follows final Blizzard tab")
    assertEqual(setNumTabsCalls, 0, "fallback launcher does not re-anchor Blizzard tabs")

    AuctionHouseFrame = originalAuctionHouseFrame
    PanelTemplates_TabResize = originalPanelTemplatesTabResize
    PanelTemplates_SetNumTabs = originalPanelTemplatesSetNumTabs
    Scanner.button = originalButton
    Scanner.usesTabLibrary = originalUsesTabLibrary
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

    assertEqual(entries[1].kind, "profession", "recipe tree starts with profession")
    assertEqual(entries[2].label, "Shattering", "tree category order")
    assertEqual(entries[3].label, "Dawn Shatter", "tree named recipe row")
    assertEqual(entries[4].label, "Chest Enchants", "tree second category")
    assertEqual(entries[5].label, "Test Chest Enchant", "tree numeric recipe row")
    Scanner.GetConfigProfession = originalGetConfigProfession
    Scanner.GetProfessionDisplayName = originalGetProfessionDisplayName
    Scanner.expandedQuickSetGroups = {}
end

local function testScanScopeUsesStrictItemRoles()
    local product = { kindMap = { output = true } }
    local reagent = { kindMap = { input = true } }

    assertEqual(Scanner:TargetMatchesScanScope(product, "PRODUCTS"), true, "product in product scope")
    assertEqual(Scanner:TargetMatchesScanScope(reagent, "PRODUCTS"), false, "reagent excluded from product scope")
    assertEqual(Scanner:TargetMatchesScanScope(product, "REAGENTS"), false, "product excluded from reagent scope")
    assertEqual(Scanner:TargetMatchesScanScope(reagent, "REAGENTS"), true, "reagent in reagent scope")
    assertEqual(#Scanner:GetTargetsForScanScope({ product, reagent }, "BOTH"), 2, "both scope includes both roles")
    assertEqual(Scanner:GetTargetTypeText(product), "Product", "product user-facing label")
    assertEqual(Scanner:GetTargetTypeText(reagent), "Reagent", "reagent user-facing label")
end

local function testTargetBuildAppliesConfiguredScanScope()
    local config = namespace.Config.AuctionHouseScan
    local originalRecipes = namespace.Data.GeneratedRecipes
    local originalGetSelectedProfessions = Scanner.GetSelectedProfessions
    local originalGetScanScope = config.GetScanScope
    local originalIsTargetSelected = config.IsTargetSelected
    local originalGetSkippedTargets = config.GetSkippedTargets
    local originalPriceResults = Scanner.priceResults
    local originalFixedResultsByKey = Scanner.fixedResultsByKey
    local scope = "BOTH"

    namespace.Data.GeneratedRecipes = {
        {
            profession = "Alchemy",
            stratName = "Test Product",
            recipeID = 9001,
            outputs = {
                { itemRef = "Test Product", itemIDs = { 7001 }, auctionSellable = true },
            },
            reagents = {
                { itemRef = "Test Reagent", itemIDs = { 7002 } },
                {
                    itemRef = "Vendor Reagent",
                    itemIDs = { 7003 },
                    vendorSold = true,
                    vendorItemID = 7003,
                    vendorPriceCopper = 250,
                },
            },
        },
    }
    Scanner.GetSelectedProfessions = function() return { Alchemy = true } end
    config.GetScanScope = function() return scope end
    config.IsTargetSelected = function() return true end
    config.GetSkippedTargets = function() return {} end
    Scanner.priceResults = {}
    Scanner.fixedResultsByKey = {}

    scope = "PRODUCTS"
    local targets = Scanner:BuildScanTargets()
    assertEqual(#targets, 1, "product scope target count")
    assertEqual(Scanner:GetTargetTypeText(targets[1]), "Product", "product scope target type")
    assertEqual(#Scanner.priceResults, 0, "product scope excludes fixed reagent results")

    scope = "REAGENTS"
    targets = Scanner:BuildScanTargets()
    assertEqual(#targets, 1, "reagent scope target count")
    assertEqual(Scanner:GetTargetTypeText(targets[1]), "Reagent", "reagent scope target type")
    assertEqual(#Scanner.priceResults, 1, "reagent scope includes fixed reagent result")

    scope = "BOTH"
    targets = Scanner:BuildScanTargets()
    assertEqual(#targets, 2, "both scope target count")

    namespace.Data.GeneratedRecipes = originalRecipes
    Scanner.GetSelectedProfessions = originalGetSelectedProfessions
    config.GetScanScope = originalGetScanScope
    config.IsTargetSelected = originalIsTargetSelected
    config.GetSkippedTargets = originalGetSkippedTargets
    Scanner.priceResults = originalPriceResults
    Scanner.fixedResultsByKey = originalFixedResultsByKey
end

local function testUnpricedStatusClassification()
    assertEqual(Scanner:GetMissingReasonShort({ itemID = 7001, error = "No posted auctions found." }),
        "No auctions", "no-auction status")
    assertEqual(Scanner:GetMissingReasonShort({ itemID = 7001, error = "Auction House query timed out." }),
        "Scan problem", "timeout status")
    assertEqual(Scanner:GetMissingReasonShort({
        itemID = 7001,
        error = "Posted auctions found, but rank could not be identified.",
    }), "Variant not recognized", "variant status")
end

local function testPartialRecipePreviewIsBoundedAndExplicit()
    local config = namespace.Config.AuctionHouseScan
    local originalIsTargetSelected = config.IsTargetSelected
    local selected = { a = true, c = true, e = true }
    config.IsTargetSelected = function(_, key)
        return selected[key] == true
    end

    local selectedLabels, unselectedLabels, selectedRemaining, unselectedRemaining =
        Scanner:GetTargetSelectionPreview({
            { key = "a", label = "Alpha", itemID = 11 },
            { key = "b", label = "Beta", itemID = 12 },
            { key = "c", label = "Gamma", itemID = 13 },
            { key = "d", label = "Delta", itemID = 14 },
            { key = "e", label = "Epsilon", itemID = 15 },
        }, 2)

    assertEqual(selectedLabels[1], "Alpha (ItemID 11)", "selected preview first label")
    assertEqual(selectedLabels[2], "Epsilon (ItemID 15)", "selected preview sorted label")
    assertEqual(selectedRemaining, 1, "selected preview remaining count")
    assertEqual(unselectedLabels[1], "Beta (ItemID 12)", "unselected preview first label")
    assertEqual(unselectedLabels[2], "Delta (ItemID 14)", "unselected preview sorted label")
    assertEqual(unselectedRemaining, 0, "unselected preview remaining count")

    config.IsTargetSelected = originalIsTargetSelected
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
    assertEqual(Scanner:GetConfigProfession(), "Cooking", "individual items keeps profession filter")
    assertEqual(Scanner:GetProfessionDropdownText("ALL"), "Profession: All Selected",
        "individual items all-professions label")

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

local function testClearingRecipePreservesTargetsClaimedByAnotherRecipe()
    local config = namespace.Config.AuctionHouseScan
    local originalRecipes = namespace.Data.GeneratedRecipes
    local originals = {
        GetTargetSelectionOverrides = config.GetTargetSelectionOverrides,
        IsRecipeSelected = config.IsRecipeSelected,
        SaveRecipeSelected = config.SaveRecipeSelected,
        ReplaceSelectedTargets = config.ReplaceSelectedTargets,
        UpdateButtons = Scanner.UpdateButtons,
        UpdateProgressText = Scanner.UpdateProgressText,
        UpdateConfigList = Scanner.UpdateConfigList,
        SetStatus = Scanner.SetStatus,
        allConfigTargets = Scanner.allConfigTargets,
    }

    namespace.Data.GeneratedRecipes = {
        { profession = "Alchemy", stratName = "Recipe A", recipeID = 101 },
        { profession = "Alchemy", stratName = "Recipe B", recipeID = 102 },
    }
    local targets = {
        { key = "only-a", sourceRecipeMap = { [101] = true }, sourceNamesByProfession = {} },
        { key = "shared", sourceRecipeMap = { [101] = true, [102] = true }, sourceNamesByProfession = {} },
        { key = "only-b", sourceRecipeMap = { [102] = true }, sourceNamesByProfession = {} },
    }
    local selectedRecipes = { ["id:101"] = true, ["id:102"] = true }
    local selectedTargets = {}
    config.GetTargetSelectionOverrides = function() return {} end
    config.IsRecipeSelected = function(_, identity) return selectedRecipes[identity] == true end
    config.SaveRecipeSelected = function(_, identity, selected)
        selectedRecipes[identity] = selected == true or nil
    end
    config.ReplaceSelectedTargets = function(_, values) selectedTargets = values end
    Scanner.UpdateButtons = function() end
    Scanner.UpdateProgressText = function() end
    Scanner.UpdateConfigList = function() end
    Scanner.SetStatus = function() end
    Scanner.allConfigTargets = targets

    Scanner:ToggleTreeEntrySelection({
        kind = "recipe",
        label = "Recipe A",
        recipeIdentities = { ["id:101"] = true },
    })

    assertEqual(selectedRecipes["id:101"], nil, "cleared recipe loses its selection claim")
    assertEqual(selectedTargets["only-a"], nil, "recipe-exclusive target is cleared")
    assertEqual(selectedTargets.shared, true, "shared target remains selected for recipe B")
    assertEqual(selectedTargets["only-b"], true, "other recipe target remains selected")

    namespace.Data.GeneratedRecipes = originalRecipes
    config.GetTargetSelectionOverrides = originals.GetTargetSelectionOverrides
    config.IsRecipeSelected = originals.IsRecipeSelected
    config.SaveRecipeSelected = originals.SaveRecipeSelected
    config.ReplaceSelectedTargets = originals.ReplaceSelectedTargets
    Scanner.UpdateButtons = originals.UpdateButtons
    Scanner.UpdateProgressText = originals.UpdateProgressText
    Scanner.UpdateConfigList = originals.UpdateConfigList
    Scanner.SetStatus = originals.SetStatus
    Scanner.allConfigTargets = originals.allConfigTargets
end

testScannerModuleSurfaceComplete()
testReturnedItemKeyIsUsedForNormalSearch()
testBroadEquipmentSearchReadsAllRanks()
testClearedItemKeyOverridesConstructorNormalization()
testEquipmentStartsBroadSellSearch()
testAlternateEmptyCacheCannotCompleteItemSearch()
testDirectEmptyItemResultGetsConfirmationRetry()
testMissingResultBreakEvenPricing()
testInputPricingUsesTwentyUnitFill()
testMissingLowerRankUsesCheapestRealBetterRank()
testCraftSimCostCompatibilityFallbacks()
testCraftSimTooltipCostCompatibility()
testAuctionHouseDisplayModeClassification()
testAuctionHouseTabLayoutOwnership()
testGeneratedRecipeCategoryLookupAndTargetIndex()
testClearingRecipePreservesTargetsClaimedByAnotherRecipe()
testConfigViewProfessionScopeAndSelectedTargetCount()
testScanScopeUsesStrictItemRoles()
testTargetBuildAppliesConfiguredScanScope()
testUnpricedStatusClassification()
testPartialRecipePreviewIsBoundedAndExplicit()

print("AuctionHouseScan tests passed")
