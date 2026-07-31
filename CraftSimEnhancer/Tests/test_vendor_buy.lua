local currentShoppingList = {}
local createShoppingListCalls = 0
local failNextCreateShoppingList = false
local resetQuickBuyCalls = 0
local timers = {}
local bagCounts = {}
local buyCalls = {}
local messages = {}

local function copyList(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

Auctionator = {
    API = {
        v1 = {
            ConvertFromSearchString = function(_, searchString)
                return { searchString = searchString }
            end,
            GetShoppingListItems = function()
                return copyList(currentShoppingList)
            end,
            CreateShoppingList = function(_, _, searchStrings)
                createShoppingListCalls = createShoppingListCalls + 1
                if failNextCreateShoppingList then
                    failNextCreateShoppingList = false
                    error("simulated Auctionator replacement failure")
                end
                currentShoppingList = copyList(searchStrings)
            end,
        },
    },
}

C_Item = {
    GetItemNameByID = function(itemID)
        return ({ [101] = "Vendor Butter", [102] = "Vendor Spice" })[itemID]
    end,
}

C_Timer = {
    After = function(_, callback)
        table.insert(timers, callback)
    end,
}

GetMoney = function()
    return 1000000
end

local planData = {
    items = {},
    window = { hidden = false },
}

local VendorPlan = {}
function VendorPlan:GetItems()
    return planData.items
end
function VendorPlan:Replace(items, sourceListName)
    planData.items = items
    planData.sourceListName = sourceListName
end
function VendorPlan:Clear()
    planData.items = {}
    planData.sourceListName = ""
    planData.window.hidden = true
end
function VendorPlan:GetWindow()
    return planData.window
end

local compat = {
    GetAuctionatorShoppingListName = function()
        return "CraftSim Shopping List"
    end,
    GetPlayerCrafterUID = function()
        return "Tester-Realm"
    end,
    ResetQuickBuyCache = function()
        resetQuickBuyCalls = resetQuickBuyCalls + 1
    end,
}

local wow = {
    GetBagItemCount = function(_, itemID)
        return bagCounts[itemID] or 0
    end,
    BuyMerchantItem = function(_, index, quantity)
        table.insert(buyCalls, { index = index, quantity = quantity })
        return true
    end,
    FormatMoney = function(_, copper)
        return tostring(copper) .. "c"
    end,
}

local registeredVendorBuy
local namespace = {
    Compat = { CraftSim = compat, WoW = wow },
    Config = { VendorPlan = VendorPlan },
    Data = { ItemMetadata = {} },
    Debug = { Log = function() end },
    Modules = {},
}
function namespace:RegisterModule(_, module)
    registeredVendorBuy = module
end
function namespace:Print(message)
    table.insert(messages, tostring(message))
end
function namespace:WarnOnce(_, message)
    table.insert(messages, tostring(message))
end
function namespace.Map(source, transform)
    local result = {}
    for key, value in pairs(source or {}) do
        local mapped = transform(value, key)
        if mapped ~= nil then
            table.insert(result, mapped)
        end
    end
    return result
end
function namespace.ContinueOnAllItemsLoaded(_, callback)
    callback()
end

assert(loadfile("CraftSimEnhancer/Modules/VendorBuy.lua"))("CraftSimEnhancer", namespace)
local VendorBuy = assert(registeredVendorBuy)

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function resetState()
    currentShoppingList = {}
    createShoppingListCalls = 0
    failNextCreateShoppingList = false
    resetQuickBuyCalls = 0
    timers = {}
    bagCounts = {}
    buyCalls = {}
    messages = {}
    planData.items = {}
    planData.sourceListName = ""
    planData.window.hidden = false
    VendorBuy.pendingPurchases = nil
    VendorBuy.purchaseConfirmToken = 0
    VendorBuy.button = nil
    VendorBuy.planFrame = nil
    VendorBuy.UpdateButton = function() end
    VendorBuy.UpdatePlanWindow = function() end
    VendorBuy.ShowPlanWindow = function() return true end
end


local function testFailedShoppingListReplacementRestoresOriginal()
    resetState()
    currentShoppingList = { "Auction Ore", "Vendor Butter" }
    local originalList = copyList(currentShoppingList)
    failNextCreateShoppingList = true

    local removed, _, unmatched, separationError = VendorBuy:RemovePlannedItemsFromAuctionator({
        [101] = { itemName = "Vendor Butter", quantity = 10 },
    })

    assertEqual(next(removed), nil, "failed replacement removed nothing")
    assertEqual(unmatched[101] ~= nil, true, "failed replacement reports planned entry")
    assertEqual(type(separationError), "string", "failed replacement error")
    assertEqual(createShoppingListCalls, 2, "failed replacement attempts restore")
    assertEqual(currentShoppingList[1], originalList[1], "restore retains first entry")
    assertEqual(currentShoppingList[2], originalList[2], "restore retains vendor entry")
end

local function testCompleteShoppingListSeparationIsAtomic()
    resetState()
    currentShoppingList = { "Auction Ore", "Vendor Butter", "Vendor Spice" }
    local plannedItems = {
        [101] = { itemName = "Vendor Butter", quantity = 10 },
        [102] = { itemName = "Vendor Spice", quantity = 5 },
    }

    local removed, listName, unmatched, separationError =
        VendorBuy:RemovePlannedItemsFromAuctionator(plannedItems)

    assertEqual(listName, "CraftSim Shopping List", "resolved shopping-list name")
    assertEqual(separationError, nil, "complete split error")
    assertEqual(removed[101], plannedItems[101], "butter removed")
    assertEqual(removed[102], plannedItems[102], "spice removed")
    assertEqual(next(unmatched), nil, "complete split unmatched")
    assertEqual(createShoppingListCalls, 1, "single atomic list replacement")
    assertEqual(#currentShoppingList, 1, "remaining AH entry count")
    assertEqual(currentShoppingList[1], "Auction Ore", "remaining AH entry")
    assertEqual(resetQuickBuyCalls, 1, "quick-buy cache reset")
end

local function testIncompleteShoppingListSeparationChangesNothing()
    resetState()
    currentShoppingList = { "Auction Ore", "Vendor Butter" }
    local originalList = copyList(currentShoppingList)
    local plannedItems = {
        [101] = { itemName = "Vendor Butter", quantity = 10 },
        [102] = { itemName = "Vendor Spice", quantity = 5 },
    }

    local removed, _, unmatched, separationError = VendorBuy:RemovePlannedItemsFromAuctionator(plannedItems)

    assertEqual(next(removed), nil, "incomplete split removed nothing")
    assertEqual(unmatched[102], plannedItems[102], "incomplete split reports unmatched entry")
    assertEqual(type(separationError), "string", "incomplete split error")
    assertEqual(createShoppingListCalls, 0, "incomplete split does not replace list")
    assertEqual(currentShoppingList[1], originalList[1], "first original entry retained")
    assertEqual(currentShoppingList[2], originalList[2], "second original entry retained")
end

local function configurePurchase(quantity)
    planData.items = {
        [101] = { itemName = "Vendor Butter", quantity = quantity, unitPrice = 10 },
    }
    VendorBuy.GetPurchasableItems = function()
        return {
            [101] = {
                index = 3,
                name = "Vendor Butter",
                quantity = 10,
                neededQuantity = quantity,
                purchaseQuantity = 2,
                price = 50,
                stackCount = 5,
            },
        }, quantity, 100
    end
end

local function testPlanWaitsForBagConfirmation()
    resetState()
    configurePurchase(10)
    bagCounts[101] = 2

    VendorBuy:BuyQueuedVendorItems()

    assertEqual(planData.items[101].quantity, 10, "plan unchanged before confirmation")
    assertEqual(#buyCalls, 1, "merchant purchase requested")
    assertEqual(VendorBuy.pendingPurchases ~= nil, true, "purchase pending")

    bagCounts[101] = 12
    local confirmed, confirmedQuantity, unconfirmedQuantity = VendorBuy:ReconcilePendingPurchases()

    assertEqual(confirmed, true, "purchase confirmed")
    assertEqual(confirmedQuantity, 10, "confirmed quantity")
    assertEqual(unconfirmedQuantity, 0, "fully confirmed quantity")
    assertEqual(next(planData.items), nil, "confirmed purchase clears plan")
    assertEqual(VendorBuy.pendingPurchases, nil, "pending purchase cleared")
end

local function testUnreceivedPurchaseRemainsPlanned()
    resetState()
    configurePurchase(10)
    bagCounts[101] = 2

    VendorBuy:BuyQueuedVendorItems()
    local confirmed, confirmedQuantity, unconfirmedQuantity = VendorBuy:ReconcilePendingPurchases()

    assertEqual(confirmed, false, "failed purchase not confirmed")
    assertEqual(confirmedQuantity, 0, "failed purchase confirmed quantity")
    assertEqual(unconfirmedQuantity, 10, "failed purchase unconfirmed quantity")
    assertEqual(planData.items[101].quantity, 10, "failed purchase remains planned")
end

local function testPartiallyReceivedPurchaseConsumesOnlyBagIncrease()
    resetState()
    configurePurchase(10)
    bagCounts[101] = 2

    VendorBuy:BuyQueuedVendorItems()
    bagCounts[101] = 7
    local confirmed, confirmedQuantity, unconfirmedQuantity = VendorBuy:ReconcilePendingPurchases()

    assertEqual(confirmed, true, "partial purchase confirmed")
    assertEqual(confirmedQuantity, 5, "partial confirmed quantity")
    assertEqual(unconfirmedQuantity, 5, "partial unconfirmed quantity")
    assertEqual(planData.items[101].quantity, 5, "partial purchase leaves remainder planned")
end

testCompleteShoppingListSeparationIsAtomic()
testIncompleteShoppingListSeparationChangesNothing()
testFailedShoppingListReplacementRestoresOriginal()
testPlanWaitsForBagConfirmation()
testUnreceivedPurchaseRemainsPlanned()
testPartiallyReceivedPurchaseConsumesOnlyBagIncrease()

print("VendorBuy tests passed")
