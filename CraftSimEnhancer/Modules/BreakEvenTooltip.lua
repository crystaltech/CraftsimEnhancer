local _, ns = ...

local BreakEvenTooltip = {}
local AUCTION_HOUSE_CUT = 0.05

BreakEvenTooltip.supportedOutputItemIDs = {}
BreakEvenTooltip.tooltipHooked = false

function BreakEvenTooltip:BuildSupportedOutputIndex()
    wipe(self.supportedOutputItemIDs)
    for _, recipe in ipairs(ns.Data.GeneratedRecipes or {}) do
        for _, output in ipairs(recipe.outputs or {}) do
            if output.auctionSellable ~= false then
                for _, itemID in ipairs(output.itemIDs or {}) do
                    itemID = tonumber(itemID)
                    if itemID then
                        self.supportedOutputItemIDs[itemID] = true
                    end
                end
                for _, itemID in pairs(output.rankItemIDs or {}) do
                    itemID = tonumber(itemID)
                    if itemID then
                        self.supportedOutputItemIDs[itemID] = true
                    end
                end
            end
        end
    end
end

---@param craftingCost number?
---@return number? breakEvenPrice
function BreakEvenTooltip:CalculateBreakEvenPrice(craftingCost)
    craftingCost = tonumber(craftingCost)
    if not craftingCost or craftingCost <= 0 then
        return nil
    end
    return math.max(1, math.floor(craftingCost / (1 - AUCTION_HOUSE_CUT)))
end

---@param tooltip GameTooltip
---@param tooltipInfo TooltipData
function BreakEvenTooltip:AddItemTooltipLine(tooltip, tooltipInfo)
    if not tooltip or type(tooltip.AddDoubleLine) ~= "function" or not tooltipInfo then
        return
    end
    if type(tooltip.IsForbidden) == "function" and tooltip:IsForbidden() then
        return
    end

    local itemID = tonumber(tooltipInfo.id)
    if not itemID or not self.supportedOutputItemIDs[itemID] then
        return
    end

    local craftingCost = ns.Compat.CraftSim:GetLastCraftingCostForTooltip(tooltipInfo.hyperlink, itemID)
    local breakEvenPrice = self:CalculateBreakEvenPrice(craftingCost)
    if not breakEvenPrice then
        return
    end

    tooltip:AddDoubleLine("CSE Break-even (5% AH):", ns.Compat.WoW:FormatMoney(breakEvenPrice),
        0.2, 1, 0.6, 1, 1, 1)
end

function BreakEvenTooltip:CanInitialize()
    if not TooltipDataProcessor or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function" or
        not Enum or not Enum.TooltipDataType or not Enum.TooltipDataType.Item then
        return nil, "item tooltip APIs are unavailable"
    end
    return ns.Compat.CraftSim:ValidateBreakEvenTooltip()
end

function BreakEvenTooltip:Initialize()
    if self.tooltipHooked then
        return true
    end

    self:BuildSupportedOutputIndex()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tooltipInfo)
        BreakEvenTooltip:AddItemTooltipLine(tooltip, tooltipInfo)
    end)
    self.tooltipHooked = true
    return true
end

ns:RegisterModule("BreakEvenTooltip", BreakEvenTooltip)
