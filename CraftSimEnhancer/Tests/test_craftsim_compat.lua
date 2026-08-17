local soulboundItems = {}
local namespace = {
    Compat = {
        WoW = {
            IsItemSoulbound = function(_, itemID)
                return soulboundItems[itemID] == true
            end,
            GetAddonVersion = function()
                return "27.0.0"
            end,
        },
    },
}

local hookedModule
local hookedMethod
local hookedCallback
hooksecurefunc = function(module, methodName, callback)
    hookedModule = module
    hookedMethod = methodName
    hookedCallback = callback
end

assert(loadfile("CraftSimEnhancer/Compat/CraftSim.lua"))("CraftSimEnhancer", namespace)
local Compat = namespace.Compat.CraftSim

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function testVersionSupport()
    assertEqual(Compat:IsVersionTested("26.1.10"), true, "CraftSim 26 support")
    assertEqual(Compat:IsVersionTested("27.0.0"), true, "CraftSim 27 support")
    assertEqual(Compat:IsVersionTested("27.0.1"), false, "unknown CraftSim version warning")
end

local function testCraftSim26Adapters()
    local resetCalls = 0
    local updateCalls = 0
    local queueModule = {
        GetNonSoulboundAlternativeItemID = function(_, itemID)
            return itemID + 1
        end,
        GetItemCountFromCraftQueueCache = function()
            return 4
        end,
        ResetQuickBuyCache = function()
            resetCalls = resetCalls + 1
        end,
        CreateAuctionatorShoppingList = function() end,
    }
    Compat.craftSim = {
        CRAFTQ = queueModule,
        MODULES = {
            UpdateUI = function()
                updateCalls = updateCalls + 1
            end,
        },
    }

    assertEqual(Compat:GetNonSoulboundAlternativeItemID(100), 101, "CraftSim 26 reagent helper")
    assertEqual(Compat:ResetQuickBuyCache(), true, "CraftSim 26 quick-buy reset available")
    assertEqual(resetCalls, 1, "CraftSim 26 quick-buy reset called")
    assertEqual(Compat:UpdateCraftSimUI(), true, "CraftSim 26 UI refresh available")
    assertEqual(updateCalls, 1, "CraftSim 26 UI refresh called")
    assertEqual(Compat:ValidateVendorBuy(), true, "CraftSim 26 vendor validation")
    assertEqual(Compat:ValidateShoppingListHook(), true, "CraftSim 26 shopping hook validation")

    local callback = function() end
    assertEqual(Compat:HookShoppingListCreated(callback), true, "CraftSim 26 shopping hook")
    assertEqual(hookedModule, queueModule, "CraftSim 26 shopping hook module")
    assertEqual(hookedMethod, "CreateAuctionatorShoppingList", "CraftSim 26 shopping hook method")
    assertEqual(hookedCallback, callback, "CraftSim 26 shopping hook callback")
end

local function testCraftSim27Adapters()
    local resetCalls = 0
    local triggeredEvent
    local queueModule = {
        GetItemCountFromCraftQueueCache = function()
            return 7
        end,
    }
    local shoppingModule = {
        ResetQuickBuyCache = function()
            resetCalls = resetCalls + 1
        end,
        CreateShoppingListFromCraftQueue = function() end,
    }
    soulboundItems = {
        [200] = true,
        [201] = false,
        [300] = false,
        [400] = true,
    }
    Compat.craftSim = {
        CRAFTQ = queueModule,
        SHOPPING = shoppingModule,
        CONST = {
            REAGENT_ID_EXCEPTION_MAPPING = {
                [200] = 201,
            },
        },
        GUTIL = {
            isItemSoulbound = function(_, itemID)
                return soulboundItems[itemID] == true
            end,
            TriggerCustomEvent = function(_, eventName)
                triggeredEvent = eventName
            end,
        },
    }

    assertEqual(Compat:GetNonSoulboundAlternativeItemID(300), 300, "CraftSim 27 tradable reagent")
    assertEqual(Compat:GetNonSoulboundAlternativeItemID(200), 201, "CraftSim 27 mapped reagent")
    assertEqual(Compat:GetNonSoulboundAlternativeItemID(400), nil, "CraftSim 27 unmapped soulbound reagent")
    assertEqual(Compat:ResetQuickBuyCache(), true, "CraftSim 27 quick-buy reset available")
    assertEqual(resetCalls, 1, "CraftSim 27 quick-buy reset called")
    assertEqual(Compat:UpdateCraftSimUI(), true, "CraftSim 27 event refresh available")
    assertEqual(triggeredEvent, "CRAFTSIM_RECIPE_DATA_MODIFIED", "CraftSim 27 refresh event")
    assertEqual(Compat:ValidateVendorBuy(), true, "CraftSim 27 vendor validation")
    assertEqual(Compat:ValidateShoppingListHook(), true, "CraftSim 27 shopping hook validation")

    local callback = function() end
    assertEqual(Compat:HookShoppingListCreated(callback), true, "CraftSim 27 shopping hook")
    assertEqual(hookedModule, shoppingModule, "CraftSim 27 shopping hook module")
    assertEqual(hookedMethod, "CreateShoppingListFromCraftQueue", "CraftSim 27 shopping hook method")
    assertEqual(hookedCallback, callback, "CraftSim 27 shopping hook callback")
end

testVersionSupport()
testCraftSim26Adapters()
testCraftSim27Adapters()

print("CraftSim compatibility tests passed")
