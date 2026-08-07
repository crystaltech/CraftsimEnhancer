local namespace = {
    Config = {},
    Compat = {
        WoW = {
            GetCrafterUID = function()
                return "Test-Realm"
            end,
        },
    },
}

assert(loadfile("CraftSimEnhancer/Config.lua"))("CraftSimEnhancer", namespace)

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function testNewInstallUsesSmallBatchFillQuantity()
    CraftSimEnhancerDB = nil
    CraftSimDB = nil

    namespace.Config:Initialize()

    assertEqual(namespace.Config.AuctionHouseScan:GetFillQuantity(), 20, "new-install fill quantity")
    assertEqual(CraftSimEnhancerDB.migrationVersion, 5, "new-install migration version")
    assertEqual(namespace.Config.AuctionHouseScan:GetScanScope(), "BOTH", "new-install scan scope")
    assertEqual(CraftSimEnhancerDB.global.auctionHouseScan.targetSelectionMode, "explicit",
        "new-install explicit target selection")
    assertEqual(CraftSimEnhancerDB.global.auctionHouseScan.recipeSelectionMode, "explicit",
        "new-install explicit recipe selection")
    assertEqual(namespace.Config.AuctionHouseScan:NeedsRecipeOverrideCleanup(), false,
        "new install does not need recipe override cleanup")
    assertEqual(namespace.Config.AuctionHouseScan:IsTargetSelected("new-target"), false,
        "new-install target starts unselected")
end

local function testExistingInstallMigratesSavedFillQuantity()
    CraftSimEnhancerDB = {
        migrationVersion = 1,
        global = {
            auctionHouseScan = {
                fillQuantity = 100,
            },
        },
    }
    CraftSimDB = nil

    namespace.Config:Initialize()

    assertEqual(namespace.Config.AuctionHouseScan:GetFillQuantity(), 20, "migrated fill quantity")
    assertEqual(CraftSimEnhancerDB.migrationVersion, 5, "updated migration version")
    assertEqual(CraftSimEnhancerDB.global.auctionHouseScan.targetSelectionMode, "legacy-exclude",
        "existing install waits for complete catalog")
    assertEqual(CraftSimEnhancerDB.global.auctionHouseScan.recipeSelectionMode, "target-allowlist",
        "existing install waits for recipe catalog")
    assertEqual(namespace.Config.AuctionHouseScan:NeedsRecipeOverrideCleanup(), true,
        "existing install schedules orphaned override cleanup")
end

local function testLegacySelectionMigratesToExplicitAllowlist()
    CraftSimEnhancerDB = {
        migrationVersion = 2,
        global = {
            auctionHouseScan = {
                skippedTargets = { ["item-b"] = true },
            },
        },
    }
    CraftSimDB = nil

    namespace.Config:Initialize()
    local config = namespace.Config.AuctionHouseScan
    assertEqual(config:IsTargetSelected("item-a"), true, "legacy included target before catalog migration")
    assertEqual(config:IsTargetSelected("item-b"), false, "legacy skipped target before catalog migration")

    assertEqual(config:EnsureExplicitTargetSelection({
        { key = "item-a" },
        { key = "item-b" },
    }), true, "catalog migration performed")
    assertEqual(config:IsTargetSelected("item-a"), true, "legacy included target retained")
    assertEqual(config:IsTargetSelected("item-b"), false, "legacy skipped target retained")
    assertEqual(config:IsTargetSelected("future-item"), false, "future target does not silently become selected")

    config:SaveTargetSelected("future-item", true)
    assertEqual(config:IsTargetSelected("future-item"), true, "explicit target can be selected")
    config:SaveTargetSelected("future-item", false)
    assertEqual(config:IsTargetSelected("future-item"), false, "explicit target can be cleared")

    assertEqual(config:IsRecipeSelectionExplicit(), false, "recipe selection awaits catalog migration")
    config:InitializeRecipeSelection({ ["id:100"] = true }, { ["item-b"] = false })
    assertEqual(config:IsRecipeSelectionExplicit(), true, "recipe selection migration completed")
    assertEqual(config:IsRecipeSelected("id:100"), true, "selected recipe retained")
    assertEqual(config:GetTargetSelectionOverride("item-b"), false, "false item override retained")
    config:ClearTargetSelectionOverride("item-b")
    assertEqual(config:GetTargetSelectionOverride("item-b"), nil, "item override can be reset by recipe action")
end

testNewInstallUsesSmallBatchFillQuantity()
testExistingInstallMigratesSavedFillQuantity()
testLegacySelectionMigratesToExplicitAllowlist()

print("Config tests passed")
