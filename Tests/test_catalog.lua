local function enums()
    return setmetatable({}, { __index = function(t, key) local v = enums(); rawset(t, key, v); return v end })
end
Enum = enums()
for index, name in ipairs({ "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "Inscription", "Jewelcrafting", "Leatherworking", "Tailoring" }) do Enum.Profession[name] = index end
debugprofilestop = function() return os.clock() * 1000 end
local pending = {}
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local ahLookups = 0
C_AuctionHouse = {
    MakeItemKey = function(itemID, itemLevel) return { itemID = itemID, itemLevel = itemLevel } end,
    GetItemKeyInfo = function() ahLookups = ahLookups + 1; error("Catalog browsing must not query AH item info") end,
}
local ns = {}
local function Load(path) assert(loadfile("CraftSimEnhancer/" .. path))("CraftSimEnhancer", ns) end
Load("Core.lua")
Load("Config.lua")
ns.Compat.WoW = { GetCrafterUID = function() return "Test-Realm" end }
ns.Compat.CraftSim = { GetProfessionLabel = function(_, _, name) return name end }
ns.Config:Initialize()
Load("Catalog.lua")
Load("RecipeAvailability.lua")
Load("Modules/AuctionHouseScan.lua")
Load("Modules/AuctionHouseScan/ConfigurationUI.lua")
Load("Modules/AuctionHouseScan/Targets.lua")
Load("Modules/AuctionHouseScan/CatalogUI.lua")
Load("Modules/AuctionHouseScan/Query.lua")
Load("Modules/AuctionHouseScan/Pricing.lua")
local scanner, config = ns.Modules.AuctionHouseScan, ns.Config.AuctionHouseScan
scanner.GetSelectedProfessions = function() return config:GetSelectedProfessions() end
scanner.EnsureProfessionSelectionForCurrentCrafter = scanner.GetSelectedProfessions
scanner.GetProfessionDisplayName = function(_, info) return info.name end
scanner.UpdateButtons, scanner.UpdateProgressText, scanner.UpdateConfigList = function() end, function() end, function() end
scanner.SetStatus = function() end
local function Drain()
    local count = 0
    while #pending > 0 do table.remove(pending, 1)(); count = count + 1; assert(count < 10000) end
    return count
end
local function Recipe(id, profession, output, input)
    return { recipeID = id, profession = profession, stratName = "Recipe " .. id,
        outputs = { { itemRef = "Output " .. output, itemIDs = { output } } },
        reagents = { { itemRef = "Input " .. input, itemIDs = { input } } } }
end
ns.Data.GeneratedRecipes = { Recipe(1, "Alchemy", 101, 500) }
ns.Data.ImportedRecipes = { Recipe(1, "Alchemy", 999, 999), Recipe(2, "Alchemy", 102, 500),
    Recipe(3, "Tailoring", 103, 500), { recipeID = 4, profession = "Alchemy", stratName = "Unknown craft",
        catalogOnlyReason = "Unresolved output variants" } }
ns.Data.ItemMetadata = {}
for _, id in ipairs({101,102,103,500,999}) do ns.Data.ItemMetadata[id] = { itemClassID = 7, isCommodity = true } end
ns.Data.RecipeCategories = { recipeNames = {}, recipeIDs = { [1] = 11, [2] = 12, [3] = 13, [4] = 12 }, categories = {
    [11] = { name = "Potions", order = 1, expansionID = 11, expansionName = "Midnight", parentID = 100 },
    [12] = { name = "Potions", order = 1, expansionID = 0, expansionName = "Classic", parentID = 101 },
    [13] = { name = "Cloth", order = 1, expansionID = 0, expansionName = "Classic", parentID = 102 },
} }
assert(#ns.Catalog:GetIndex().recipes == 4 and ns.Catalog:GetIndex().byID[1].outputs[1].itemIDs[1] == 101,
    "verified recipe wins over imported duplicate")
config:SaveProfessionSelected("Alchemy", true)
config:SaveRecipeSelected("id:1", true)
config:SaveTargetSelected("101:0:output", true)
config:SaveTargetSelected("500:0:input", true)
config:SaveConfigExpansion(0)
assert(#scanner:GetConfigTargets() == 0 and scanner.catalogPreparation, "cold view prepares asynchronously")
Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(#scanner.configTargets == 2 and not scanner.catalogPreparation, "only visible profession/expansion targets built")
assert(config:IsTargetSelected("101:0:output"), "hidden expansion target selection preserved")
assert(config:IsTargetSelected("500:0:input"), "shared reagent remains claimed by hidden selected recipe")
local catalog = scanner:BuildRecipeSelectionCatalog(scanner.allConfigTargets)
assert(catalog["id:1"] and catalog["id:2"] and catalog["id:3"], "shared ownership crosses professions and expansions")
assert(not config:IsRecipeSelected("id:2"), "imported recipe starts unselected")
assert(ahLookups == 0, "browsing performs no AH info lookups")
local cached = scanner.allConfigTargets
scanner:GetConfigTargets()
assert(scanner.allConfigTargets == cached and #pending == 0, "warm view uses cached targets")
scanner.configView = "recipes"
scanner.expandedProfessionGroups["profession:Alchemy"] = true
scanner.expandedExpansionGroups = { ["expansion:Alchemy:0"] = true }
scanner.expandedCategoryGroups["category:Alchemy:12"] = true
local entries = scanner:GetRecipeListEntries()
assert(entries[1].kind == "profession" and entries[2].kind == "expansion" and entries[2].label == "Classic",
    "profession/expansion/category hierarchy")
assert(entries[3].kind == "category" and #entries == 5, "catalog-only recipe remains visible")
assert(entries[5].catalogOnlyReason and next(entries[5].recipeIdentities) == nil, "unresolved craft cannot be selected")
config:SaveRecipeSelected("id:2", true)
scanner:RebuildSelectedTargetsFromRecipes()
scanner:InvalidateScanConfiguration()
assert(config:IsTargetSelected("102:0:output") and config:IsTargetSelected("101:0:output"), "selecting visible recipe preserves hidden one")
local targets = scanner:BuildScanTargets({skipFixedPrices = true})
assert(#targets == 3 and ns.Catalog.perf.lastScanRecipeCount == 2, "scan visits only selected recipes across expansions")
config:SaveTargetSelectionOverride("103:0:output", true)
config:SaveProfessionSelected("Tailoring", true)
config:SaveTargetSelected("103:0:output", true)
scanner:InvalidateScanConfiguration()
targets = scanner:BuildScanTargets({skipFixedPrices = true})
assert(#targets == 4, "positive individual-item override includes its unselected source recipe")

-- Saved target keys can be stale after patch changes; selected recipes still
-- contribute their current materials, with explicit individual overrides winning.
config:SaveTargetSelected("102:0:output", false)
assert(#scanner:BuildScanTargets({skipFixedPrices = true}) == 4, "current recipe sources override stale target cache")
config:SaveTargetSelectionOverride("102:0:output", false)
assert(#scanner:BuildScanTargets({skipFixedPrices = true}) == 3, "explicit deselection wins over recipe")
config:GetTargetSelectionOverrides()["102:0:output"] = nil
scanner:RebuildSelectedTargetsFromRecipes(nil, { ["id:2"] = true })
assert(config:IsTargetSelected("102:0:output"), "incremental recipe selection refreshes affected target")
scanner:SaveIndividualTargetSelection("102:0:output", false)
assert(not config:IsTargetSelected("102:0:output"), "incremental individual deselection updates target")
config:GetTargetSelectionOverrides()["102:0:output"] = nil
scanner:RebuildSelectedTargetsFromRecipes(nil, { ["id:2"] = true })

-- Availability is an independent view filter; scan restriction is explicit.
local availability = ns.RecipeAvailability
local character = availability:GetCharacter()
character.recipes[1], character.recipes[2] = true, false
config:SaveAvailabilityFilter("LEARNED")
assert(#scanner:GetConfigRecipes() == 0, "Classic view has no confirmed learned recipe")
config:SaveConfigExpansion("ALL")
assert(#scanner:GetConfigRecipes() == 1, "learned view uses cached state")
scanner:GetConfigTargets(); Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(#scanner.configTargets == 2, "learned filter narrows actual item view")
assert(config:IsTargetSelected("102:0:output") and config:IsRecipeSelected("id:2"), "availability filtering preserves hidden selections")
assert(#scanner:BuildScanTargets({skipFixedPrices = true}) == 4, "view filter never restricts scans")
config:SaveAvailabilityFilter("UNLEARNED")
assert(#scanner:GetConfigRecipes() == 1, "unlearned excludes unchecked")
config:SaveAvailabilityFilter("UNCHECKED")
assert(#scanner:GetConfigRecipes() == 2, "unchecked remains a distinct state")
config:SaveScanLearnedOnly(true)
assert(#scanner:BuildScanTargets({skipFixedPrices = true}) == 2, "learned scan excludes unlearned and unchecked override sources")
assert(config:IsRecipeSelected("id:2") and config:GetTargetSelectionOverrides()["103:0:output"], "scan restriction preserves recipe and item choices")
config:SaveScanLearnedOnly(false)
config:SaveAvailabilityFilter("ALL")
config:SaveConfigExpansion(0)
assert(#scanner:BuildScanTargets({skipFixedPrices = true}) == 4, "disabling restriction restores selected sources")

-- Scan preparation can be stopped before it sends an AH request.
wipe = function(t) for key in pairs(t) do t[key] = nil end end
local auctionOpen, sent = true, 0
AuctionHouseFrame = { IsShown = function() return auctionOpen end }
scanner.CreatePanel = function() end
scanner.TrySendNextQuery = function() sent = sent + 1 end
scanner:StartScan()
assert(scanner.isPreparing and not scanner.isScanning and sent == 0, "scan preparation is deferred")
scanner:CancelScan()
Drain()
assert(not scanner.isPreparing and not scanner.isScanning and sent == 0, "cancelled preparation cannot start scanning")
scanner:StartScan()
Drain()
assert(scanner.isScanning and sent == 1 and #scanner.scanTargets == 4, "prepared selection starts one scan")
scanner:CancelScan()
scanner:StartScan()
auctionOpen = false
Drain()
assert(not scanner.isScanning and not scanner.isPreparing and sent == 1, "AH closing prevents a late scan start")
auctionOpen = true

-- Migrating a legacy allow-all/exclusion list never selects new imports merely
-- because they share a material with a previously selected recipe.
local legacy = config:GetData()
legacy.targetSelectionMode, legacy.recipeSelectionMode = "legacy-exclude", "legacy"
legacy.selectedRecipes, legacy.selectedTargets, legacy.targetSelectionOverrides, legacy.skippedTargets = {}, {}, {}, {}
scanner:GetConfigTargets()
Drain()
scanner:GetConfigTargets()
Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(config:IsRecipeSelectionExplicit() and config:IsRecipeSelected("id:1"), "legacy base recipe selection retained")
assert(not config:IsRecipeSelected("id:2") and not config:IsRecipeSelected("id:3"), "shared imported recipes remain unselected after migration")

-- Virtual row reuse must reset both dimming and the availability label.
local function Widget()
    local widget = {}
    for _, method in ipairs({"Hide","Show","SetShown","ClearAllPoints","SetPoint","SetWidth","SetChecked",
        "SetTextColor","EnableMouse","SetEnabled","SetAlpha","SetText"}) do
        widget[method] = function(self, value) self[method .. "Value"] = value end
    end
    return widget
end
local availabilityRow = Widget()
for _, name in ipairs({"expandButton","expandText","checkbox","mixedTexture","labelText","countText"}) do
    availabilityRow[name] = Widget()
end
local availabilityEntry = { kind="recipe",label="Recipe 2",recipeIdentities={ ["id:2"]=true },availability="UNLEARNED" }
scanner:UpdateRecipeRow(availabilityRow, availabilityEntry)
assert(availabilityRow.SetAlphaValue == 0.55 and availabilityRow.checkbox.SetEnabledValue == true,
    "unlearned recipe is dimmed but remains selectable")
assert(availabilityRow.countText.SetTextValue == "Unlearned", "row labels availability")
availabilityEntry.availability = "UNCHECKED"
scanner:UpdateRecipeRow(availabilityRow, availabilityEntry)
assert(availabilityRow.SetAlphaValue == 1 and availabilityRow.countText.SetTextValue == "Unchecked",
    "reused row resets dimming and shows unchecked separately")

-- Scroll a 10,000-entry list; row allocation depends on viewport height only.
local allocated, updates = 0, 0
local function Row()
    allocated = allocated + 1
    return { SetHeight=function() end, ClearAllPoints=function() end, SetPoint=function() end,
        Show=function() end, Hide=function() end, bg={SetShown=function() end} }
end
local offset = 0
scanner.configPanel = { scrollFrame = { GetVerticalScroll=function() return offset end, GetHeight=function() return 240 end },
    scrollChild = { SetHeight=function() end } }
scanner.CreateRecipeRow = Row
scanner.UpdateRecipeRow = function() updates = updates + 1 end
local many = {}
for i=1,10000 do many[i]={kind="recipe"} end
scanner:RenderCatalogRows("recipes",many)
assert(allocated == 12 and updates == 12, "only viewport plus overscan rows allocated")
offset = 120000
scanner:RenderCatalogRows("recipes",many)
assert(allocated == 12 and updates == 24, "scrolling reuses frame pool")
scanner.configPanel = nil

-- Validate the actual shipped catalog and measure its cold index and view jobs.
ns.Data = {}
for _, name in ipairs({"ItemMetadata","RecipeCategories","Alchemy","Blacksmithing","Cooking","Enchanting",
    "Engineering","Inscription","Jewelcrafting","Leatherworking","Tailoring","ImportedMetadata","ImportedCategories","ImportedRecipes"}) do
    Load("Data/GeneratedRecipes/" .. name .. ".lua")
end
local index = ns.Catalog:GetIndex()
assert(#index.recipes == 10637 and index.catalogOnly == 2426, "pinned combined coverage")
for _, recipe in ipairs(index.recipes) do
    if not recipe.catalogOnlyReason then
        for _, role in ipairs({"outputs","reagents"}) do
            for _, entry in ipairs(recipe[role] or {}) do
                for _, id in ipairs(entry.itemIDs or {}) do assert(ns.Data.ItemMetadata[id], "every scan item has metadata") end
            end
        end
    end
end
config:SaveConfigExpansion("ALL")
scanner:GetConfigTargets()
local slices = Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(#scanner.configTargets > 100 and slices > 1, "large actual view spans multiple slices")
assert(ahLookups == 0, "full production metadata avoids AH info reads during browsing")
scanner.recipeTreeCache = nil
assert(#scanner:GetRecipeListEntries() == 0 and scanner.treePreparation, "large recipe tree builds asynchronously")
Drain()
local actualEntries = scanner:GetRecipeListEntries()
assert(#actualEntries > 0 and not scanner.treePreparation, "prepared tree is published")
local oldTree = scanner.recipeTreeCache
scanner:GetRecipeListEntries()
assert(scanner.recipeTreeCache == oldTree and #pending == 0, "warm tree does not rebuild or schedule work")

-- A large selection's button counts are asynchronous and then cached.
local selected = 0
for _, recipe in ipairs(index.byProfession.Alchemy) do
    if not recipe.catalogOnlyReason and recipe.recipeID then
        config:SaveRecipeSelected(ns.Catalog:Identity(recipe), true)
        selected = selected + 1
        if selected == 250 then break end
    end
end
scanner:RebuildSelectedTargetsFromRecipes()
scanner:InvalidateScanConfiguration()
assert(#scanner:GetSelectedTargetsCached() == 0 and scanner.selectedPreparation, "large selected-count build yields")
Drain()
local selectedTargets = scanner:GetSelectedTargetsCached()
assert(#selectedTargets > 0 and not scanner.selectedPreparation, "selected counts published after preparation")
assert(scanner:GetSelectedTargetsCached() == selectedTargets and #pending == 0, "repeated count uses same cached targets")
local selectionMetrics = ns.Catalog.perf.maxSelectionSliceMs
local treeMetrics = ns.Catalog.perf.treeBuildMs
print(string.format("Catalog tests passed: %d recipes; cold index %.2f ms; %d queued slices; maximum work slice %.2f ms; %d view targets",
    #index.recipes,ns.Catalog.perf.indexBuildMs,slices,ns.Catalog.perf.maxConfigSliceMs,#scanner.configTargets))
print(string.format("Tree CPU %.2f ms across batches; largest selection-count slice %.2f ms; %d selected targets",treeMetrics,selectionMetrics,#selectedTargets))

-- Rapid expansion changes cancel obsolete preparation and bound view caches.
for _, info in ipairs(scanner.PROFESSIONS) do config:SaveProfessionSelected(info.name, true) end
config:SaveConfigExpansion(0)
scanner:GetConfigTargets()
local obsolete = scanner.catalogPreparation
config:SaveConfigExpansion(1)
scanner:GetConfigTargets()
assert(obsolete.job.cancelled, "changing expansion cancels obsolete preparation")
Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(scanner.catalogRequestedKey:match(":1:ALL$"), "latest requested expansion wins")
for expansion=2,5 do
    config:SaveConfigExpansion(expansion)
    scanner:GetConfigTargets(); Drain()
    scanner.configTargets = scanner:GetConfigTargets()
end
local caches = 0
for _ in pairs(scanner.catalogTargetCaches) do caches = caches + 1 end
assert(caches <= 4, "view cache capped at four branches")
config:SaveConfigExpansion("ALL")
scanner:GetConfigTargets(); Drain()
scanner.configTargets = scanner:GetConfigTargets()
assert(#scanner.configTargets > 5000 and ahLookups == 0, "all-profession view uses static metadata only")
assert(#pending == 0, "completed catalog work leaves no idle callbacks")
print(string.format("All-profession view: %d targets; maximum work slice %.2f ms; Lua heap %.1f MiB (test process)",
    #scanner.configTargets, ns.Catalog.perf.maxConfigSliceMs, collectgarbage("count") / 1024))
