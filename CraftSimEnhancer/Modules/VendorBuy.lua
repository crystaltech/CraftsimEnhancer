local addonName, ns = ...

local Compat = ns.Compat.CraftSim
local WoW = ns.Compat.WoW
local Auctionator = _G.Auctionator
local VendorBuy = {}
local EVENTS = { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }

VendorBuy.button = nil

---@class CraftSim.VendorBuy.NeededItem
---@field itemName string?
---@field quantity number

---@return table<ItemID, CraftSim.VendorBuy.NeededItem>
function VendorBuy:GetQueuedNeededItems()
    local craftQueueItems = Compat:GetCraftQueueItems()
    if not craftQueueItems or #craftQueueItems == 0 then
        return {}
    end

    local reagentMap = {}

    for _, craftQueueItem in pairs(craftQueueItems) do
        local recipeData = craftQueueItem.recipeData
        local amount = craftQueueItem.amount or 1

        for _, reagent in pairs(recipeData.reagentData.requiredReagents) do
            if not reagent:IsOrderReagentIn(recipeData) then
                for _, reagentItem in pairs(reagent.items) do
                    local itemID = reagentItem.item:GetItemID()
                    local quantity = (reagentItem.quantity or 0) * amount
                    if itemID and quantity > 0 and not recipeData:IsSelfCraftedReagent(itemID) then
                        reagentMap[itemID] = reagentMap[itemID] or {
                            itemName = reagentItem.item:GetItemName(),
                            quantity = 0,
                        }
                        reagentMap[itemID].quantity = reagentMap[itemID].quantity + quantity
                    end
                end
            end
        end

        local activeReagents = {}
        for _, reagent in pairs(recipeData.reagentData:GetActiveOptionalReagents() or {}) do
            table.insert(activeReagents, reagent)
        end
        local quantityMap = {}
        if recipeData:HasRequiredSelectableReagent() then
            local slot = recipeData.reagentData.requiredSelectableReagentSlot
            if slot and slot:IsAllocated() and not slot:IsCurrency() and not slot:IsOrderReagentIn(recipeData) then
                tinsert(activeReagents, slot.activeReagent)
                quantityMap[slot.activeReagent.item:GetItemID()] = slot.maxQuantity or 1
            end
        end

        for _, optionalReagent in pairs(activeReagents) do
            if not optionalReagent:IsCurrency() then
                local itemID = optionalReagent.item:GetItemID()
                local isSelfCrafted = recipeData:IsSelfCraftedReagent(itemID)
                local isOrderReagent = optionalReagent:IsOrderReagentIn(recipeData)
                if itemID and not isOrderReagent and not isSelfCrafted and not WoW:IsItemSoulbound(itemID) then
                    local allocatedQuantity = quantityMap[itemID] or 1
                    reagentMap[itemID] = reagentMap[itemID] or {
                        itemName = optionalReagent.item:GetItemName(),
                        quantity = 0,
                    }
                    reagentMap[itemID].quantity = reagentMap[itemID].quantity + allocatedQuantity * amount
                end
            end
        end
    end

    local crafterUIDs = ns.ToSet(ns.Map(craftQueueItems, function(cqi)
        return cqi.recipeData:GetCrafterUID()
    end))

    local neededItems = {}
    for itemID, info in pairs(reagentMap) do
        local buyableItemID = Compat:GetNonSoulboundAlternativeItemID(itemID)
        if buyableItemID then
            local totalItemCount = ns.Fold(crafterUIDs, 0, function(itemCount, crafterUID)
                local itemCountForCrafter = Compat:GetCraftQueueItemCount(crafterUID, buyableItemID)
                return itemCount + (tonumber(itemCountForCrafter) or 0)
            end)
            local quantity = math.max((info.quantity or 0) - (tonumber(totalItemCount) or 0), 0)
            if quantity > 0 then
                neededItems[buyableItemID] = neededItems[buyableItemID] or {
                    itemName = info.itemName,
                    quantity = 0,
                }
                neededItems[buyableItemID].quantity = neededItems[buyableItemID].quantity + quantity
            end
        end
    end

    return neededItems
end

---@return table<ItemID, { index: number, name: string?, price: number, stackCount: number, numAvailable: number }>
function VendorBuy:GetMerchantItems()
    local merchantItems, merchantError = WoW:GetMerchantItems()
    if not merchantItems then
        ns.Debug:Log(merchantError)
        return {}
    end
    return merchantItems
end

---@return table<ItemID, { index: number, name: string?, quantity: number, purchaseQuantity: number, price: number }>
---@return number totalQuantity
---@return number totalCost
function VendorBuy:GetPurchasableItems()
    local neededItems = self:GetQueuedNeededItems()
    local merchantItems = self:GetMerchantItems()
    local purchasableItems = {}
    local totalQuantity = 0
    local totalCost = 0

    for itemID, neededInfo in pairs(neededItems) do
        local merchantInfo = merchantItems[itemID]
        if merchantInfo then
            local purchaseQuantity = math.ceil(neededInfo.quantity / merchantInfo.stackCount)
            if merchantInfo.numAvailable >= 0 then
                purchaseQuantity = math.min(purchaseQuantity, merchantInfo.numAvailable)
            end
            purchaseQuantity = math.floor(purchaseQuantity)
            local quantity = purchaseQuantity * merchantInfo.stackCount
            if purchaseQuantity > 0 then
                purchasableItems[itemID] = {
                    index = merchantInfo.index,
                    name = merchantInfo.name or neededInfo.itemName,
                    quantity = quantity,
                    purchaseQuantity = purchaseQuantity,
                    price = merchantInfo.price or 0,
                }
                totalQuantity = totalQuantity + quantity
                totalCost = totalCost + (merchantInfo.price or 0) * purchaseQuantity
            end
        end
    end

    return purchasableItems, totalQuantity, totalCost
end

---@param shoppingListName string
---@return boolean success
---@return string[]? shoppingListItems
function VendorBuy:GetAuctionatorShoppingListItems(shoppingListName)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 or not Auctionator.API.v1.GetShoppingListItems then
        return false, nil
    end

    local success, result = pcall(Auctionator.API.v1.GetShoppingListItems, addonName, shoppingListName)
    if success then
        return true, result
    end

    return false, nil
end

---@param purchasableItems table<ItemID, { quantity: number }>
function VendorBuy:DeductAuctionatorShoppingListItems(purchasableItems)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 or
        not Auctionator.API.v1.ConvertToSearchString or not Auctionator.API.v1.ConvertFromSearchString or
        not Auctionator.API.v1.AlterShoppingListItem or not Auctionator.API.v1.DeleteShoppingListItem then
        return
    end

    local itemMixins = ns.Map(purchasableItems, function(_, itemID)
        return Item:CreateFromItemID(itemID)
    end)

    ns.ContinueOnAllItemsLoaded(itemMixins, function()
        local shoppingListName = Compat:GetAuctionatorShoppingListName()
        if not shoppingListName then
            return
        end
        local success, shoppingListItems = self:GetAuctionatorShoppingListItems(shoppingListName)
        if not success then
            shoppingListName = shoppingListName .. " " .. Compat:GetPlayerCrafterUID()
            success, shoppingListItems = self:GetAuctionatorShoppingListItems(shoppingListName)
            if not success then
                return
            end
        end

        for itemID, boughtInfo in pairs(purchasableItems) do
            local item = Item:CreateFromItemID(itemID)
            local itemLink = item:GetItemLink()
            local itemName = item:GetItemName()
            if itemName and itemLink then
                local itemQualityID = ns.GetReagentQuality(itemLink)
                local searchTerms = {
                    searchString = itemName,
                    isExact = true,
                    tier = itemQualityID,
                }
                local searchString = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerms)
                local oldSearchString = ns.Find(shoppingListItems, function(r)
                    return ns.StringStartsWith(r, searchString)
                end)

                if oldSearchString then
                    local oldTerms = Auctionator.API.v1.ConvertFromSearchString(addonName, oldSearchString)
                    local newQuantity = (oldTerms.quantity or 0) - (boughtInfo.quantity or 0)

                    if newQuantity > 0 then
                        searchTerms.quantity = newQuantity
                        local newSearchString = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerms)
                        Auctionator.API.v1.AlterShoppingListItem(addonName, shoppingListName, oldSearchString,
                            newSearchString)
                    else
                        Auctionator.API.v1.DeleteShoppingListItem(addonName, shoppingListName, oldSearchString)
                    end
                end
            end
        end

        Compat:ResetQuickBuyCache()
    end)
end

function VendorBuy:BuyQueuedVendorItems()
    local purchasableItems, totalQuantity, totalCost = self:GetPurchasableItems()
    if totalQuantity == 0 then
        ns:Print("No queued vendor items are available from this merchant.")
        return
    end

    if GetMoney() < totalCost then
        ns:Print("Not enough gold for queued vendor items. Missing: " .. WoW:FormatMoney(totalCost - GetMoney()))
        return
    end

    for _, info in pairs(purchasableItems) do
        ns.Debug:Log("Buying vendor item: " .. tostring(info.name) .. " x" .. tostring(info.quantity))
        local bought, buyError = WoW:BuyMerchantItem(info.index, info.purchaseQuantity)
        if not bought then
            ns:WarnOnce("vendor-buy-api", buyError)
            return
        end
    end

    self:DeductAuctionatorShoppingListItems(purchasableItems)

    ns:Print("Bought " .. tostring(totalQuantity) .. " queued vendor items for " .. WoW:FormatMoney(totalCost) .. ".")
end

function VendorBuy:UpdateButton()
    if not self.button then
        self:CreateButton()
    end

    if not self.button then
        return
    end

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self.button:Hide()
        return
    end

    local _, totalQuantity, totalCost = self:GetPurchasableItems()
    self.button:SetFrameStrata("DIALOG")
    self.button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 30)
    self:PositionButton()
    self.button:Show()
    self.button:SetEnabled(totalQuantity > 0)
    self.button:SetText("Buy Reagents (" .. tostring(totalQuantity) .. ")")

    self.button.tooltipText = totalQuantity > 0
        and ("Buy vendor-sold reagents from your CraftSim queue that this merchant sells.\nAvailable here: " ..
            tostring(totalQuantity) .. "\nEstimated cost: " .. WoW:FormatMoney(totalCost))
        or "No queued vendor-sold reagents are available from this merchant."
end

function VendorBuy:PositionButton()
    if not self.button or not MerchantFrame then
        return
    end

    self.button:ClearAllPoints()
    if MerchantMoneyFrame then
        self.button:SetPoint("LEFT", MerchantFrame, "BOTTOMLEFT", 8, 15)
    else
        self.button:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 8, 5)
    end
end

function VendorBuy:CreateButton()
    if self.button or not MerchantFrame then
        return
    end

    local button = CreateFrame("Button", "CraftSimEnhancerVendorBuyButton", MerchantFrame, "UIPanelButtonTemplate")
    button:SetSize(142, 20)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 30)
    if button.SetMotionScriptsWhileDisabled then
        button:SetMotionScriptsWhileDisabled(true)
    end
    button:SetText("Buy Reagents")
    button:SetScript("OnClick", function()
        VendorBuy:BuyQueuedVendorItems()
    end)
    button:SetScript("OnEnter", function(selfButton)
        if not selfButton.tooltipText then
            return
        end
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CraftSim Vendor Buy")
        GameTooltip:AddLine(selfButton.tooltipText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    self.button = button
    self:PositionButton()
end

function VendorBuy:ShowButton()
    self:CreateButton()
    self:UpdateButton()
end

function VendorBuy:MERCHANT_SHOW()
    self:ShowButton()
end

function VendorBuy:MERCHANT_UPDATE()
    self:UpdateButton()
end

function VendorBuy:MERCHANT_CLOSED()
    if self.button then
        self.button:Hide()
    end
end

function VendorBuy:BAG_UPDATE_DELAYED()
    self:UpdateButton()
end

function VendorBuy:Open()
    if MerchantFrame and MerchantFrame:IsShown() then
        self:ShowButton()
    else
        ns:Print("Open a merchant to use Vendor Buy.")
    end
end

function VendorBuy:CanInitialize()
    if not C_MerchantFrame or not C_MerchantFrame.GetItemInfo or not GetMerchantNumItems or
        not GetMerchantItemLink or not BuyMerchantItem then
        return nil, "required merchant APIs are unavailable"
    end
    return Compat:ValidateVendorBuy()
end

function VendorBuy:Initialize()
    if self.initialized then
        return true
    end
    self.eventFrame = ns:CreateEventDispatcher(self, EVENTS)
    self.initialized = true
    if MerchantFrame and MerchantFrame:IsShown() then
        self:ShowButton()
    end
    return true
end

ns:RegisterModule("VendorBuy", VendorBuy)
