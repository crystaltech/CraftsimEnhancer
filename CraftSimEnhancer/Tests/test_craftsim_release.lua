-- Run from repository root with CRAFTSIM_SOURCE_DIR pointing at an extracted release.
local sourceDir = os.getenv("CRAFTSIM_SOURCE_DIR")
if not sourceDir then
    print("CraftSim release integration skipped (set CRAFTSIM_SOURCE_DIR)")
    return
end
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function noop() end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
tinsert = table.insert
local ns = {}
assert(loadfile("CraftSimEnhancer/Core.lua"))("CraftSimEnhancer", ns)
local pendingLoad
local published = {}
local gutil = {
    GetFormatter = function() return setmetatable({}, { __index = function() return tostring end }) end,
    CreateRegistreeForEvents = function() return {} end,
    RegisterCustomEvents = noop,
    ContinueOnAllItemsLoaded = function(_, _, callback) pendingLoad = callback end,
    isItemSoulbound = function() return false end,
    GetQualityIDFromLink = function() return 2 end,
}
for _, name in ipairs({ "Map", "ToSet", "Fold" }) do
    gutil[name] = function(_, ...) return ns[name](...) end
end
local craftSim = {
    GUTIL = gutil, GGUI = {},
    LOCAL = { GetLocalizer = function() return tostring end },
    DEBUG = setmetatable({ RegisterLogger = function() return setmetatable({}, { __index = function() return noop end }) end },
        { __index = function() return noop end }),
    CONST = { AUCTIONATOR_SHOPPING_LIST_QUEUE_NAME = "CraftSim Queue", SUPPORTED_PRICE_API_ADDONS = { "TSM", "Auctionator" } },
    DB = { RegisterRepository = function() return { MIGRATION = {} } end,
        CRAFTER = { GetCrafterUIDs = function() return {} end } },
    ITEM_COUNT = { Get = function() return 2 end },
}
C_AddOns = { IsAddOnLoaded = function() return true end }
C_Item = { GetItemNameByID = function() return "Vendor Butter" end,
    GetItemInfoInstant = function() return 101 end }
C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return nil end }
Item = { CreateFromItemID = function() return {} end }
Auctionator = { API = { v1 = {
    ConvertToSearchString = function(_, terms) return terms.searchString end,
    CreateShoppingList = function(_, name, items) published[name] = items end,
} }, Shopping = { ListManager = {
    GetIndexForName = function(_, name) return published[name] and 1 end,
    Delete = function(_, name) published[name] = nil end,
} } }
hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        original(...)
        callback(...)
    end
end
local function upstream(path) assert(loadfile(sourceDir .. "/" .. path))("CraftSim", craftSim) end
upstream("Modules/Modules.lua")
upstream("Modules/CraftQueue/CraftQueue.lua")
upstream("Modules/Shopping/Shopping.lua")
upstream("DB/priceOverrideDB.lua")
upstream("DB/lastCraftingCostDB.lua")
upstream("Util/API.lua")
CraftSimDB = {}
craftSim.DB.PRICE_OVERRIDE:Init()
craftSim.DB.LAST_CRAFTING_COST:Init()
ns.Compat.WoW = { IsAddonLoaded = function() return true end, GetAddonVersion = function() return "release under test" end }
assert(loadfile("CraftSimEnhancer/Compat/CraftSim.lua"))("CraftSimEnhancer", ns)
local compat = ns.Compat.CraftSim
assert(compat:Initialize())
assert(compat:ValidateAuctionScanner())
assert(compat:ValidateBreakEvenTooltip())
assert(compat:ValidateVendorBuy())
assert(compat:ValidateShoppingListHook())
assert(compat:SaveGlobalOverride({ itemID = 101, price = 123 }))
eq(CraftSimDB.priceOverrideDB.data.globalOverrides[101].price, 123, "global override")
assert(compat:SaveResultOverride({ recipeID = 42, qualityID = 2, price = 456, source = "CSE" }))
eq(craftSim.DB.PRICE_OVERRIDE:GetResultOverride(42, 2).price, 456, "result override")
assert(compat:ClearEstimatedResultOverride(42, 2, "CSE"))
CraftSimDB.lastCraftingCostDB.data["101:2"] = { Crafter = { cost = 950, timestamp = 100 } }
eq(compat:GetLastCraftingCost(101, 2), 950, "ranked saved cost")
eq(compat:GetLastCraftingCostForTooltip("item:101", 101), 950, "tooltip saved cost")
local updated = {}
craftSim.MODULES.GetRecipeDataFromVisibleRecipe = function() return updated end
gutil.TriggerCustomEvent = function(_, event, ...)
    if event == "CRAFTSIM_RECIPE_DATA_MODIFIED" then craftSim.MODULES:CRAFTSIM_RECIPE_DATA_MODIFIED(...) end
end
assert(compat:UpdateCraftSimUI())
eq(craftSim.MODULES.recipeData, updated, "UI refresh")
local recipe = {
    reagentData = { requiredReagents = { {
        IsOrderReagentIn = function() return false end,
        items = { { quantity = 12, item = { GetItemID = function() return 101 end,
            GetItemName = function() return "Vendor Butter" end } } },
    } }, GetActiveOptionalReagents = function() return {} end },
    IsSelfCraftedReagent = function() return false end,
    HasRequiredSelectableReagent = function() return false end,
    GetCrafterUID = function() return "Crafter" end,
}
craftSim.CRAFTQ.craftQueue = { craftQueueItems = { { recipeData = recipe, amount = 1 } } }
assert(loadfile("CraftSimEnhancer/Modules/VendorBuy.lua"))("CraftSimEnhancer", ns)
eq(ns.Modules.VendorBuy:GetQueuedNeededItems()[101].quantity, 10, "vendor queue quantity")
local calls = 0
assert(compat:HookShoppingListCreated(function()
    calls = calls + 1
    eq(published["CraftSim Queue"][1], "Vendor Butter", "hook runs after publication")
    -- Enhancer replaces the list to remove vendor items; this must not recurse.
    Auctionator.API.v1.CreateShoppingList("CraftSimEnhancer", "CraftSim Queue", {})
end))
craftSim.SHOPPING:CreateShoppingListFromCraftQueue()
eq(calls, 0, "no early vendor separation")
assert(pendingLoad, "item load callback scheduled")
pendingLoad()
eq(calls, 1, "delayed publication invokes hook once")
eq(#published["CraftSim Queue"], 0, "vendor removal survives publication")
craftSim.SHOPPING:CRAFTSIM_CRAFTQUEUE_QUEUE_PROCESS_FINISHED()
pendingLoad()
eq(calls, 2, "automatic queue publication invokes hook once")
assert(compat:ResetQuickBuyCache())
print("CraftSim release integration passed: " .. sourceDir)
