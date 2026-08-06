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
    assertEqual(CraftSimEnhancerDB.migrationVersion, 2, "new-install migration version")
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
    assertEqual(CraftSimEnhancerDB.migrationVersion, 2, "updated migration version")
end

testNewInstallUsesSmallBatchFillQuantity()
testExistingInstallMigratesSavedFillQuantity()

print("Config tests passed")
