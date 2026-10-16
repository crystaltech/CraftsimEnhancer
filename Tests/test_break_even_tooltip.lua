local tooltipCallback
local savedCost = 10000
local requestedLink
local requestedItemID

Enum = {
    TooltipDataType = {
        Item = 1,
    },
}

TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, callback)
        assert(dataType == Enum.TooltipDataType.Item, "registered unexpected tooltip type")
        tooltipCallback = callback
    end,
}

wipe = function(tableValue)
    for key in pairs(tableValue) do
        tableValue[key] = nil
    end
end

local compat = {
    GetLastCraftingCostForTooltip = function(_, itemLink, itemID)
        requestedLink = itemLink
        requestedItemID = itemID
        return savedCost
    end,
    ValidateBreakEvenTooltip = function()
        return true
    end,
}

local wow = {
    FormatMoney = function(_, copper)
        return tostring(copper) .. " copper"
    end,
}

local registeredModule
local namespace = {
    Compat = {
        CraftSim = compat,
        WoW = wow,
    },
    Data = {
        GeneratedRecipes = {
            {
                outputs = {
                    {
                        itemIDs = { 1001 },
                        rankItemIDs = { [1] = 1001, [2] = 1002 },
                        auctionSellable = true,
                    },
                    {
                        itemIDs = { 2001 },
                        auctionSellable = false,
                    },
                },
            },
        },
    },
}
function namespace:RegisterModule(name, module)
    assert(name == "BreakEvenTooltip", "registered unexpected module")
    registeredModule = module
end

assert(loadfile("CraftSimEnhancer/Modules/BreakEvenTooltip.lua"))("CraftSimEnhancer", namespace)
local BreakEvenTooltip = assert(registeredModule)

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function newTooltip()
    local tooltip = {
        lines = {},
    }
    function tooltip:IsForbidden()
        return false
    end
    function tooltip:AddDoubleLine(left, right)
        self.lines[#self.lines + 1] = { left = left, right = right }
    end
    return tooltip
end

assertEqual(BreakEvenTooltip:CanInitialize(), true, "tooltip compatibility")
assertEqual(BreakEvenTooltip:Initialize(), true, "tooltip initialization")
assertEqual(type(tooltipCallback), "function", "tooltip callback registration")

local tooltip = newTooltip()
tooltipCallback(tooltip, {
    id = 1002,
    hyperlink = "item:1002::::::::::Quality-Tier2",
})
assertEqual(#tooltip.lines, 1, "supported item tooltip line count")
assertEqual(tooltip.lines[1].left, "CSE Break-even (5% AH):", "tooltip label")
assertEqual(tooltip.lines[1].right, "10526 copper", "tooltip break-even price")
assertEqual(requestedLink, "item:1002::::::::::Quality-Tier2", "exact-rank item link")
assertEqual(requestedItemID, 1002, "tooltip item ID")

tooltip = newTooltip()
tooltipCallback(tooltip, { id = 2001, hyperlink = "item:2001" })
assertEqual(#tooltip.lines, 0, "non-auctionable output hidden")

tooltip = newTooltip()
tooltipCallback(tooltip, { id = 9999, hyperlink = "item:9999" })
assertEqual(#tooltip.lines, 0, "unsupported item hidden")

savedCost = nil
tooltip = newTooltip()
tooltipCallback(tooltip, { id = 1001, hyperlink = "item:1001" })
assertEqual(#tooltip.lines, 0, "missing cost hidden")

assertEqual(BreakEvenTooltip:Initialize(), true, "repeat initialization")

print("break-even tooltip tests passed")
