local pending, messages, requests = {}, {}, {}
local professionID, childID, shown = 171, 2799, true
local recipeIDs = {}
for id = 1, 20 do recipeIDs[#recipeIDs + 1] = id end
recipeIDs[#recipeIDs + 1] = 99 -- A stale recipe belonging to a different profession.
GetServerTime = function() return 123456 end
GetBuildInfo = function() return "12.1.5", "70391", "Oct 15 2026", 120105 end
GetLocale = function() return "enUS" end
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
ProfessionsFrame = { IsShown = function() return shown end }
C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionID = professionID, profession = 1 } end,
    GetChildProfessionInfo = function() return { professionID = childID } end,
    GetAllRecipeIDs = function() return recipeIDs end,
    GetProfessionInfoByRecipeID = function(id)
        return { professionID = 2799, parentProfessionID = id == 99 and 164 or 171 }
    end,
    GetRecipeInfo = function(id)
        if id == 22 then return nil end
        return { name = "Recipe " .. id, categoryID = 10, learned = id < 10,
            supportsQualities = id == 1, maxQuality = id == 1 and 2 or nil }
    end,
    GetRecipeSchematic = function(id, isRecraft)
        assert(not isRecraft)
        if id == 99 then error("Foreign recipe must not be queried") end
        return { recipeID = id, outputItemID = id + 1000, quantityMin = 1, quantityMax = 1,
            reagentSlotSchematics = {
                { quantityRequired = 5, required = true, reagents = { { itemID = 100 } } },
                { quantityRequired = 2, required = true, reagents = { { itemID = 200 }, { itemID = 201 } } },
            } }
    end,
    GetRecipeOutputItemData = function(id, _, _, quality)
        return { itemID = id + 1000, hyperlink = "item:" .. (id + 1000) .. ":quality:" .. (quality or 1) }
    end,
    GetRecipeQualityItemIDs = function(id) return { id + 1000 } end,
    GetCategoryInfo = function(id) return { name = "Category " .. id, parentCategoryID = id == 10 and 11 or 10 } end,
}
C_Item = {
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
    GetItemInfo = function(id)
        if id == 201 then return nil end -- Uncached rank must remain visible in the diagnostic report.
        return "Item " .. id, "item:" .. id, 1, 1, 1, "Trade Goods", "Other", 1000, nil, 1, 25, 7, 11, 0
    end,
}
local settings = { marker = "do not change", vendorPlan = { quantity = 5 } }
local ns = {
    version = "test", Config = { db = settings }, warnings = { example = "untested" }, ModuleStatus = {},
    Compat = { WoW = { GetCrafterUID = function() return "Tester-Realm" end },
        CraftSim = { GetVersion = function() return "27.0.7" end,
            GetLastCraftingCost = function(_, itemID) return itemID * 10, 123, "Tester-Realm" end } },
    Modules = { AuctionHouseScan = { PROFESSIONS = { { enum = 1, name = "Alchemy" } },
        priceResults = { { itemID = 100, price = 42 } }, missingResults = {} } },
    Data = { GeneratedRecipes = {
        { profession = "Alchemy", recipeID = 21 }, { profession = "Alchemy", recipeID = 22 },
        { profession = "Tailoring", recipeID = 999 },
    }, ItemMetadata = { [100] = { vendorSold = true, vendorPriceCopper = 5 } }, RecipeCategories = {} },
    Print = function(_, message) messages[#messages + 1] = message end,
}
assert(loadfile("CraftSimEnhancer/DevTools.lua"))("CraftSimEnhancer", ns)
local dev = ns.DevTools
local function Drain()
    while #pending > 0 do table.remove(pending, 1)() end
end
local function FirstCapture()
    local _, capture = next(CraftSimEnhancerDevDB.captures)
    return capture
end

dev:HandleCommand("status")
assert(CraftSimEnhancerDevDB == nil, "status does not create a dump")
shown = false
dev:Dump()
assert(not dev.active and CraftSimEnhancerDevDB == nil, "closed profession rejected")
shown = true
for i = 1, 205 do dev:Log(i) end
assert(#dev.logs == 200 and dev.logs[1].message == "6", "diagnostic logs are bounded")
dev:Dump()
assert(dev.active and CraftSimEnhancerDevDB == nil, "dump is asynchronous and unpublished until finished")
table.remove(pending, 1)()
assert(dev.active.index == 16, "recipe work is batched")
Drain()
local capture = FirstCapture()
assert(capture.counts.recipes == 23, "client list and generated recipes are merged and deduplicated")
assert(capture.counts.incompleteRecipes == 2 and capture.counts.foreignRecipes == 1, "missing and foreign data explicit")
assert(capture.counts.uncachedItems == 1 and not capture.complete, "missing cache never reported as complete")
assert(not capture.recipes[999], "other profession's generated recipes excluded")
assert(capture.recipes[21] and capture.recipeSources[21].generatedData, "generated recipe supplement")
assert(not capture.recipes[99].schematic, "foreign recipe not queried")
assert(capture.recipes[1].schematic.reagentSlotSchematics[1].quantityRequired == 5, "live quantities retained")
assert(capture.recipes[1].savedCraftingCosts[1].copper == 10010, "saved break-even cost captured")
assert(capture.recipes[1].outputsByQuality[2].hyperlink == "item:1001:quality:2", "same-ID output variants retain rank links")
assert(capture.items[100].generatedMetadata.vendorSold and requests[100] == 1, "shared item requested once")
assert(capture.items[201].cached == false, "uncached item identified")
assert(capture.categories[10] and capture.categories[11], "category ancestry cycle terminates")
assert(CraftSimEnhancerDevDB.diagnostics.settings.marker == "do not change", "settings snapshot")
assert(ns.Config.db == settings and settings.vendorPlan.quantity == 5, "settings are unchanged")
assert(#CraftSimEnhancerDevDB.diagnostics.logs == 200, "debug log captured")

dev:Dump()
childID = 2800
Drain()
assert(not dev.active and FirstCapture() == capture, "profession switch cancels without replacing completed dump")
childID = 2799
dev:Dump()
dev:HandleCommand("cancel")
Drain()
assert(FirstCapture() == capture, "explicit cancellation preserves previous capture")
recipeIDs = { 1 }
ns.Data.GeneratedRecipes = { { profession = "Alchemy", recipeID = 1 } }
local originalItemInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
    if id == 201 then return "Cached rank", "item:201" end
    return originalItemInfo(id)
end
childID = 2800
dev:Dump()
Drain()
local completed = CraftSimEnhancerDevDB.captures["Tester-Realm:171:2800"]
assert(completed and completed.complete and completed.counts.recipes == 1, "complete capture published for another view")
assert(CraftSimEnhancerDevDB.captures["Tester-Realm:171:2799"] == capture, "other expansion capture retained")
dev:HandleCommand("clear")
assert(CraftSimEnhancerDevDB == nil and ns.Config.db == settings, "clear affects diagnostics only")
recipeIDs = {}
dev:Dump()
assert(not dev.active and CraftSimEnhancerDevDB == nil, "unloaded recipe list rejected")

-- Catalog capture must work even when no profession/era is learned or open.
shown = false
C_TradeSkillUI.GetBaseProfessionInfo = function() error("Catalog must not require a learned profession") end
C_TradeSkillUI.GetChildProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo
C_TradeSkillUI.GetAllRecipeIDs = C_TradeSkillUI.GetBaseProfessionInfo
ns.Data.GeneratedRecipes = {
    { profession = "Alchemy", recipeID = 1, stratName = "Alchemy Recipe" },
    { profession = "Tailoring", recipeID = 2, stratName = "Tailoring Recipe" },
    { profession = "Alchemy", recipeID = 22, stratName = "Uncached Recipe" },
    { profession = "Alchemy", stratName = "Transform Without Spell ID" },
}
C_TradeSkillUI.GetProfessionInfoByRecipeID = function(id)
    return { professionID = 2799, parentProfessionID = id == 2 and 197 or 171 }
end
dev:HandleCommand("catalog")
assert(dev.active and #dev.active.ids == 3, "catalog uses known numeric IDs from every profession")
Drain()
local catalog = CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"]
assert(catalog.mode == "catalog" and catalog.counts.schematics == 3, "catalog works without an open profession")
assert(catalog.recipes[2].generatedProfession == "Tailoring", "cross-profession provenance retained")
assert(catalog.counts.foreignRecipes == 0, "catalog intentionally includes all professions")
assert(catalog.recipes[22].schematic and catalog.recipes[22].incomplete, "schematic retained despite missing recipe info")
assert(not catalog.complete, "partial catalog cannot be reported as fully complete")

local originalSchematic = C_TradeSkillUI.GetRecipeSchematic
C_TradeSkillUI.GetRecipeSchematic = function(id, isRecraft)
    local result = originalSchematic(id, isRecraft)
    if id == 2 then result.recipeID = 100 end
    if id == 22 then error("Recipe unavailable without its profession") end
    return result
end
dev:HandleCommand("catalog")
Drain()
catalog = CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"]
assert(catalog.counts.schematics == 1, "stale and failed schematics do not count as valid")
assert(catalog.recipes[2].recipeIDMismatch and catalog.recipes[2].incomplete, "stale recipe IDs flagged")
assert(catalog.recipes[22].errors and catalog.recipes[22].incomplete, "API failure captured without aborting catalog")

-- The runtime catalog contributes offline imported IDs, and large snapshots
-- publish only after their time-sliced finalization has completed.
assert(loadfile("CraftSimEnhancer/Catalog.lua"))("CraftSimEnhancer", ns)
ns.Data.ImportedRecipes = { { recipeID = 50, profession = "Alchemy", stratName = "Imported Recipe" } }
C_TradeSkillUI.GetRecipeSchematic = originalSchematic
local oldCatalog = CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"]
dev:HandleCommand("catalog")
while not dev.active.finalization do table.remove(pending, 1)() end
assert(CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"] == oldCatalog, "unfinished snapshot not published")
dev:Cancel()
Drain()
assert(CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"] == oldCatalog, "cancellation during finalization preserves export")
dev:HandleCommand("catalog")
Drain()
catalog = CraftSimEnhancerDevDB.captures["Tester-Realm:catalog"]
assert(catalog.recipes[50] and catalog.recipes[50].generatedRecipeName == "Imported Recipe", "imported catalog ID queried and attributed")
assert(#CraftSimEnhancerDevDB.generatedData.recipes == 5, "combined generated data snapshot retained")
dev:HandleCommand("perf")
print("Developer export tests passed")
