local eventCallback

CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, _, callback)
            eventCallback = callback
        end,
        UnregisterEvent = function() end,
    }
end

SlashCmdList = {}

local fillQuantity = 20
local messages = {}
local namespace = {
    version = "test",
    warnings = {},
    ModuleOrder = {},
    ModuleStatus = {
        AuctionHouseScan = { initialized = true },
    },
    Modules = {
        AuctionHouseScan = { isScanning = false },
    },
    Config = {
        Initialize = function() end,
        GetMigrationStatus = function()
            return "complete"
        end,
        AuctionHouseScan = {
            GetFillQuantity = function()
                return fillQuantity
            end,
            GetFillQuantityLimits = function()
                return 5, 1000
            end,
            SaveFillQuantity = function(_, value)
                fillQuantity = value
            end,
        },
    },
    Compat = {
        CraftSim = {
            Initialize = function()
                return true
            end,
            GetVersion = function()
                return "test"
            end,
            testedVersion = "test",
        },
        WoW = {
            GetInterfaceVersion = function()
                return 1
            end,
            IsAddonLoaded = function()
                return true
            end,
            testedInterface = 1,
        },
    },
    Debug = {
        IsEnabled = function()
            return false
        end,
        SetEnabled = function() end,
        Log = function() end,
    },
    L = {
        ADDON_LOADED = "loaded",
        RESET_DONE = "reset",
        RESET_WARNING = "warning",
    },
}

function namespace:Print(message)
    messages[#messages + 1] = message
end

function namespace:WarnOnce() end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

assert(loadfile("CraftSimEnhancer/Init.lua"))("CraftSimEnhancer", namespace)
eventCallback(nil, nil, "CraftSimEnhancer")

assertEqual(SLASH_CRAFTSIMENHANCERSCANQTY1, "/cse_scanqty", "scan quantity slash registration")

SlashCmdList.CRAFTSIMENHANCERSCANQTY("75")
assertEqual(fillQuantity, 75, "dedicated scan quantity command")

SlashCmdList.CRAFTSIMENHANCER("scanqty 125")
assertEqual(fillQuantity, 125, "cse scan quantity alias")

SlashCmdList.CRAFTSIMENHANCERSCANQTY("12.5")
assertEqual(fillQuantity, 125, "decimal scan quantity rejected")

SlashCmdList.CRAFTSIMENHANCERSCANQTY("1001")
assertEqual(fillQuantity, 125, "out-of-range scan quantity rejected")

namespace.Modules.AuctionHouseScan.isScanning = true
SlashCmdList.CRAFTSIMENHANCERSCANQTY("200")
assertEqual(fillQuantity, 125, "scan quantity unchanged during active scan")

print("Slash command tests passed")
