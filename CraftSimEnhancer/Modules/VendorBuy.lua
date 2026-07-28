local addonName, ns = ...

local Compat = ns.Compat.CraftSim
local WoW = ns.Compat.WoW
local Auctionator = _G.Auctionator
local VendorBuy = {}
local EVENTS = { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }
local PLAN_WINDOW_WIDTH = 410
local PLAN_HEADER_HEIGHT = 34
local PLAN_FOOTER_HEIGHT = 30
local PLAN_ROW_HEIGHT = 26
local PLAN_MAX_VISIBLE_ROWS = 8
local PLAN_MIN_WIDTH = 330
local PLAN_MAX_WIDTH = 720
local PLAN_MIN_EXPANDED_HEIGHT = PLAN_HEADER_HEIGHT + PLAN_FOOTER_HEIGHT + PLAN_ROW_HEIGHT + 4
local PLAN_MAX_HEIGHT = 520

VendorBuy.button = nil
VendorBuy.planFrame = nil
VendorBuy.planRows = {}

---@class CraftSim.VendorBuy.NeededItem
---@field itemName string?
---@field quantity number

---@param itemID number
---@return boolean vendorSold
---@return number? unitPrice
function VendorBuy:GetVendorInfo(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return false
    end

    local metadata = ns.Data.ItemMetadata[itemID]
    if metadata and metadata.vendorSold == true then
        local unitPrice = tonumber(metadata.vendorPriceCopper)
        return true, unitPrice and unitPrice > 0 and unitPrice or nil
    end

    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and type(api.GetVendorPriceByItemID) == "function" then
        local success, vendorPrice = pcall(api.GetVendorPriceByItemID, addonName, itemID)
        vendorPrice = success and tonumber(vendorPrice) or nil
        if vendorPrice and vendorPrice > 0 then
            return true, vendorPrice
        end
    end

    return false
end

function VendorBuy:GetVendorPlanItems()
    return ns.Config.VendorPlan:GetItems()
end

function VendorBuy:HasVendorPlan()
    for _, info in pairs(self:GetVendorPlanItems()) do
        if (tonumber(info.quantity) or 0) > 0 then
            return true
        end
    end
    return false
end

---@return table<ItemID, CraftSim.VendorBuy.NeededItem>
function VendorBuy:GetPlannedNeededItems()
    local result = {}
    for itemID, info in pairs(self:GetVendorPlanItems()) do
        local quantity = math.max(0, math.floor(tonumber(info.quantity) or 0))
        if quantity > 0 then
            result[tonumber(itemID)] = {
                itemName = info.itemName,
                quantity = quantity,
                unitPrice = tonumber(info.unitPrice),
            }
        end
    end
    return result
end

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

---@return table<ItemID, CraftSim.VendorBuy.NeededItem>
function VendorBuy:GetNeededVendorItems()
    if self:HasVendorPlan() then
        return self:GetPlannedNeededItems()
    end
    return self:GetQueuedNeededItems()
end

---@param shoppingListName string
---@return string? resolvedName
---@return string[]? items
function VendorBuy:FindAuctionatorShoppingList(shoppingListName)
    local success, items = self:GetAuctionatorShoppingListItems(shoppingListName)
    if success then
        return shoppingListName, items
    end

    local crafterListName = shoppingListName .. " " .. Compat:GetPlayerCrafterUID()
    success, items = self:GetAuctionatorShoppingListItems(crafterListName)
    if success then
        return crafterListName, items
    end
end

---@param searchString string
---@param plannedItems table<ItemID, table>
---@return number? itemID
function VendorBuy:MatchShoppingListItem(searchString, plannedItems)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or type(api.ConvertFromSearchString) ~= "function" then
        return nil
    end

    local success, terms = pcall(api.ConvertFromSearchString, addonName, searchString)
    if not success or type(terms) ~= "table" or type(terms.searchString) ~= "string" then
        return nil
    end

    local searchName = string.lower(terms.searchString)
    for itemID, info in pairs(plannedItems) do
        if type(info.itemName) == "string" and string.lower(info.itemName) == searchName then
            return tonumber(itemID)
        end
    end
end

---@param shoppingListName string
function VendorBuy:RefreshAuctionatorSearch(shoppingListName)
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end

    C_Timer.After(0, function()
        local shoppingFrame = _G.AuctionatorShoppingFrame
        local listManager = Auctionator and Auctionator.Shopping and Auctionator.Shopping.ListManager
        if not shoppingFrame or not shoppingFrame:IsShown() or not listManager or
            type(shoppingFrame.StopSearch) ~= "function" or type(shoppingFrame.DoSearch) ~= "function" or
            type(listManager.GetIndexForName) ~= "function" or type(listManager.GetByName) ~= "function" then
            return
        end

        if not listManager:GetIndexForName(shoppingListName) then
            return
        end
        local list = listManager:GetByName(shoppingListName)
        local expandedList = shoppingFrame.ListsContainer and shoppingFrame.ListsContainer:GetExpandedList()
        if not list or not expandedList or type(expandedList.GetName) ~= "function" or
            expandedList:GetName() ~= shoppingListName then
            return
        end

        shoppingFrame:StopSearch()
        local remainingSearches = list:GetAllItems()
        if #remainingSearches > 0 then
            shoppingFrame:DoSearch(remainingSearches)
        elseif shoppingFrame.DataProvider and type(shoppingFrame.DataProvider.Reset) == "function" then
            shoppingFrame.DataProvider:Reset()
        end
    end)
end

---@param plannedItems table<ItemID, table>
---@return table<ItemID, table> removedItems
---@return string? resolvedListName
function VendorBuy:RemovePlannedItemsFromAuctionator(plannedItems)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or type(api.DeleteShoppingListItem) ~= "function" or
        type(api.ConvertFromSearchString) ~= "function" then
        return {}
    end

    local baseListName = Compat:GetAuctionatorShoppingListName()
    if not baseListName then
        return {}
    end
    local shoppingListName, shoppingListItems = self:FindAuctionatorShoppingList(baseListName)
    if not shoppingListName or not shoppingListItems then
        return {}
    end

    local removedItems = {}
    for _, searchString in ipairs(shoppingListItems) do
        local itemID = self:MatchShoppingListItem(searchString, plannedItems)
        if itemID and not removedItems[itemID] then
            local success = pcall(api.DeleteShoppingListItem, addonName, shoppingListName, searchString)
            if success then
                removedItems[itemID] = plannedItems[itemID]
            end
        end
    end

    if next(removedItems) then
        Compat:ResetQuickBuyCache()
        self:RefreshAuctionatorSearch(shoppingListName)
    end
    return removedItems, shoppingListName
end

---@return table? summary
function VendorBuy:CreateVendorPlanFromCurrentQueue()
    local plannedItems = {}
    for itemID, info in pairs(self:GetQueuedNeededItems()) do
        local vendorSold, unitPrice = self:GetVendorInfo(itemID)
        if vendorSold and (tonumber(info.quantity) or 0) > 0 then
            plannedItems[itemID] = {
                itemName = info.itemName,
                quantity = math.floor(tonumber(info.quantity) or 0),
                unitPrice = unitPrice,
            }
        end
    end

    if not next(plannedItems) then
        ns.Config.VendorPlan:Clear()
        self:UpdatePlanWindow()
        return nil
    end

    local removedItems, shoppingListName = self:RemovePlannedItemsFromAuctionator(plannedItems)
    if not next(removedItems) then
        ns.Config.VendorPlan:Clear()
        self:UpdatePlanWindow()
        ns:WarnOnce("vendor-plan-split", "Vendor materials could not be separated from the Auctionator list.")
        return nil
    end

    ns.Config.VendorPlan:Replace(removedItems, shoppingListName)

    local itemCount = 0
    local totalQuantity = 0
    local estimatedCost = 0
    for _, info in pairs(removedItems) do
        itemCount = itemCount + 1
        totalQuantity = totalQuantity + (tonumber(info.quantity) or 0)
        estimatedCost = estimatedCost + (tonumber(info.quantity) or 0) * (tonumber(info.unitPrice) or 0)
    end

    self:ShowPlanWindow()
    return {
        itemCount = itemCount,
        totalQuantity = totalQuantity,
        estimatedCost = estimatedCost,
        shoppingListName = shoppingListName,
    }
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

---@return table<ItemID, { index: number, name: string?, quantity: number, neededQuantity: number, purchaseQuantity: number, price: number }>
---@return number totalQuantity
---@return number totalCost
function VendorBuy:GetPurchasableItems()
    local neededItems = self:GetNeededVendorItems()
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
                    neededQuantity = math.min(neededInfo.quantity, quantity),
                    purchaseQuantity = purchaseQuantity,
                    price = merchantInfo.price or 0,
                }
                totalQuantity = totalQuantity + math.min(neededInfo.quantity, quantity)
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

---@param purchasedItems table<ItemID, { neededQuantity: number?, quantity: number? }>
function VendorBuy:ConsumeVendorPlanItems(purchasedItems)
    if not self:HasVendorPlan() then
        return false
    end

    local planItems = self:GetVendorPlanItems()
    for itemID, boughtInfo in pairs(purchasedItems) do
        local plannedInfo = planItems[itemID]
        if plannedInfo then
            local purchasedQuantity = tonumber(boughtInfo.neededQuantity) or tonumber(boughtInfo.quantity) or 0
            plannedInfo.quantity = math.max(0, (tonumber(plannedInfo.quantity) or 0) - purchasedQuantity)
            if plannedInfo.quantity <= 0 then
                planItems[itemID] = nil
            end
        end
    end

    if not next(planItems) then
        ns.Config.VendorPlan:Clear()
        if self.planFrame then
            self.planFrame:Hide()
        end
        if self.button then
            self.button:SetEnabled(false)
            self.button:SetText("Buy Vendor Mats (0)")
        end
        ns:Print("All vendor materials purchased.")
    else
        self:UpdatePlanWindow()
    end
    return true
end

function VendorBuy:BuyQueuedVendorItems()
    local purchasableItems, totalQuantity, totalCost = self:GetPurchasableItems()
    if totalQuantity == 0 then
        ns:Print("No planned vendor materials are available from this merchant.")
        return
    end

    if GetMoney() < totalCost then
        ns:Print("Not enough gold for vendor materials. Missing: " .. WoW:FormatMoney(totalCost - GetMoney()))
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

    if not self:ConsumeVendorPlanItems(purchasableItems) then
        self:DeductAuctionatorShoppingListItems(purchasableItems)
    end

    ns:Print("Bought " .. tostring(totalQuantity) .. " vendor materials for " .. WoW:FormatMoney(totalCost) .. ".")
end

function VendorBuy:SavePlanWindowPosition()
    if not self.planFrame then
        return
    end
    local point, _, relativePoint, x, y = self.planFrame:GetPoint(1)
    local window = ns.Config.VendorPlan:GetWindow()
    window.point = point or "CENTER"
    window.relativePoint = relativePoint or point or "CENTER"
    window.x = math.floor((tonumber(x) or 0) + 0.5)
    window.y = math.floor((tonumber(y) or 0) + 0.5)
end

function VendorBuy:SavePlanWindowSize(userSized)
    if not self.planFrame or ns.Config.VendorPlan:GetWindow().collapsed then
        return
    end
    local window = ns.Config.VendorPlan:GetWindow()
    window.width = math.floor((tonumber(self.planFrame:GetWidth()) or PLAN_WINDOW_WIDTH) + 0.5)
    window.height = math.floor((tonumber(self.planFrame:GetHeight()) or PLAN_MIN_EXPANDED_HEIGHT) + 0.5)
    if userSized then
        window.userSized = true
    end
end

function VendorBuy:SetPlanWindowCollapsed(collapsed)
    local window = ns.Config.VendorPlan:GetWindow()
    if collapsed then
        self:SavePlanWindowSize(false)
    end
    window.collapsed = collapsed == true
    self:UpdatePlanWindow()
end

function VendorBuy:CreatePlanRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PLAN_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.quantityText:SetWidth(54)
    row.quantityText:SetJustifyH("RIGHT")

    row.costText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.costText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.costText:SetWidth(96)
    row.costText:SetJustifyH("RIGHT")
    row.quantityText:SetPoint("RIGHT", row.costText, "LEFT", -6, 0)
    row.nameText:SetPoint("RIGHT", row.quantityText, "LEFT", -8, 0)

    row:SetScript("OnEnter", function(selfRow)
        if not selfRow.itemID then
            return
        end
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        local itemLink = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(selfRow.itemID))
        if itemLink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:AddLine(selfRow.itemName or ("Item " .. tostring(selfRow.itemID)))
        end
        GameTooltip:AddLine("Remaining: " .. tostring(selfRow.quantity or 0), 1, 1, 1)
        if selfRow.availableHere then
            GameTooltip:AddLine("Available from this merchant", 0.2, 1, 0.2)
        elseif selfRow.merchantOpen then
            GameTooltip:AddLine("Not sold by this merchant", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Estimated vendor cost", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

function VendorBuy:CreatePlanWindow()
    if self.planFrame then
        return
    end

    local frame = CreateFrame("Frame", "CraftSimEnhancerVendorMaterialsFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(PLAN_MIN_WIDTH, PLAN_HEADER_HEIGHT, PLAN_MAX_WIDTH, PLAN_MAX_HEIGHT)
    end

    local window = ns.Config.VendorPlan:GetWindow()
    frame:SetSize(tonumber(window.width) or PLAN_WINDOW_WIDTH,
        tonumber(window.height) and window.height > 0 and window.height or 160)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.018, 0.018, 0.022, 0.97)
    frame:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)

    frame:SetPoint(window.point or "CENTER", UIParent, window.relativePoint or "CENTER",
        tonumber(window.x) or 0, tonumber(window.y) or 0)

    frame.header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.header:SetHeight(PLAN_HEADER_HEIGHT - 4)
    frame.header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.header:SetBackdropColor(0.035, 0.035, 0.043, 1)
    frame.header:SetBackdropBorderColor(0.11, 0.11, 0.14, 1)
    frame.header:EnableMouse(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        VendorBuy:SavePlanWindowPosition()
    end)

    frame.header.topHighlight = frame.header:CreateTexture(nil, "ARTWORK")
    frame.header.topHighlight:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 1, -1)
    frame.header.topHighlight:SetPoint("TOPRIGHT", frame.header, "TOPRIGHT", -1, -1)
    frame.header.topHighlight:SetHeight(1)
    frame.header.topHighlight:SetColorTexture(0.24, 0.24, 0.30, 0.5)

    frame.header.bottomShadow = frame.header:CreateTexture(nil, "ARTWORK")
    frame.header.bottomShadow:SetPoint("BOTTOMLEFT", frame.header, "BOTTOMLEFT", 1, 1)
    frame.header.bottomShadow:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", -1, 1)
    frame.header.bottomShadow:SetHeight(1)
    frame.header.bottomShadow:SetColorTexture(0, 0, 0, 0.9)

    frame.closeButton = CreateFrame("Button", nil, frame.header, "UIPanelCloseButton")
    frame.closeButton:SetSize(28, 28)
    frame.closeButton:SetPoint("TOPRIGHT", frame.header, "TOPRIGHT", 1, 1)
    frame.closeButton:SetScript("OnClick", function()
        ns.Config.VendorPlan:GetWindow().hidden = true
        frame:Hide()
    end)

    frame.collapseButton = CreateFrame("Button", nil, frame.header)
    frame.collapseButton:SetSize(24, 20)
    frame.collapseButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -1, 0)
    frame.collapseButton.text = frame.collapseButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.collapseButton.text:SetPoint("CENTER", frame.collapseButton, "CENTER", 0, 1)
    frame.collapseButton.highlight = frame.collapseButton:CreateTexture(nil, "HIGHLIGHT")
    frame.collapseButton.highlight:SetAllPoints(frame.collapseButton)
    frame.collapseButton.highlight:SetColorTexture(1, 1, 1, 0.08)
    frame.collapseButton:SetScript("OnClick", function()
        VendorBuy:SetPlanWindowCollapsed(not ns.Config.VendorPlan:GetWindow().collapsed)
    end)
    frame.collapseButton:SetScript("OnEnter", function(selfButton)
        selfButton.text:SetTextColor(1, 1, 1)
    end)
    frame.collapseButton:SetScript("OnLeave", function(selfButton)
        selfButton.text:SetTextColor(1, 0.82, 0)
    end)

    frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.header, "LEFT", 10, 0)
    frame.title:SetPoint("RIGHT", frame.collapseButton, "LEFT", -6, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetText("Vendor Materials")

    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 10, -2)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, PLAN_FOOTER_HEIGHT)
    frame.scrollFrame:EnableMouseWheel(true)
    frame.scrollFrame:SetScript("OnMouseWheel", function(selfFrame, delta)
        local current = selfFrame:GetVerticalScroll()
        local maximum = selfFrame:GetVerticalScrollRange()
        selfFrame:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * PLAN_ROW_HEIGHT * 3)))
    end)

    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetWidth(math.max(PLAN_MIN_WIDTH - 46, frame:GetWidth() - 46))
    frame.scrollChild:SetHeight(1)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)

    frame.totalCostText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.totalCostText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 11)
    frame.totalCostText:SetWidth(160)
    frame.totalCostText:SetJustifyH("RIGHT")

    frame.remainingText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.remainingText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 11)
    frame.remainingText:SetPoint("RIGHT", frame.totalCostText, "LEFT", -8, 0)
    frame.remainingText:SetJustifyH("LEFT")

    frame.resizeButton = CreateFrame("Button", nil, frame)
    frame.resizeButton:SetSize(16, 16)
    frame.resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not ns.Config.VendorPlan:GetWindow().collapsed then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    frame.resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        VendorBuy:SavePlanWindowSize(true)
    end)

    frame:SetScript("OnSizeChanged", function(selfFrame, width)
        if selfFrame.scrollChild then
            selfFrame.scrollChild:SetWidth(math.max(PLAN_MIN_WIDTH - 46, width - 46))
        end
    end)

    frame:Hide()
    self.planFrame = frame
end

function VendorBuy:GetSortedPlanEntries()
    local entries = {}
    for itemID, info in pairs(self:GetVendorPlanItems()) do
        local quantity = math.max(0, math.floor(tonumber(info.quantity) or 0))
        if quantity > 0 then
            table.insert(entries, {
                itemID = tonumber(itemID),
                itemName = info.itemName or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)),
                quantity = quantity,
                unitPrice = tonumber(info.unitPrice),
            })
        end
    end
    table.sort(entries, function(a, b)
        return string.lower(a.itemName or tostring(a.itemID)) < string.lower(b.itemName or tostring(b.itemID))
    end)
    return entries
end

function VendorBuy:UpdatePlanWindow()
    if not self:HasVendorPlan() then
        if self.planFrame then
            self.planFrame:Hide()
        end
        return
    end
    self:CreatePlanWindow()

    local frame = self.planFrame
    local entries = self:GetSortedPlanEntries()
    local window = ns.Config.VendorPlan:GetWindow()
    local collapsed = window.collapsed == true
    local merchantOpen = MerchantFrame and MerchantFrame:IsShown()
    local merchantItems = self:GetMerchantItems()
    local totalQuantity = 0
    local estimatedCost = 0

    for index, entry in ipairs(entries) do
        local row = self.planRows[index]
        if not row then
            row = self:CreatePlanRow(frame.scrollChild)
            self.planRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, -((index - 1) * PLAN_ROW_HEIGHT))
        row:SetPoint("RIGHT", frame.scrollChild, "RIGHT", 0, 0)

        local merchantInfo = merchantItems[entry.itemID]
        local rowCost = (entry.unitPrice or 0) * entry.quantity
        if merchantInfo then
            rowCost = math.ceil(entry.quantity / merchantInfo.stackCount) * (merchantInfo.price or 0)
        end

        row.itemID = entry.itemID
        row.itemName = entry.itemName
        row.quantity = entry.quantity
        row.availableHere = merchantInfo ~= nil
        row.merchantOpen = merchantOpen == true
        row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemID) or 134400)
        row.nameText:SetText(entry.itemName or ("Item " .. tostring(entry.itemID)))
        row.nameText:SetTextColor(merchantInfo and 0.2 or 1, merchantInfo and 1 or 0.82,
            merchantInfo and 0.2 or 0, 1)
        row.quantityText:SetText("x" .. tostring(entry.quantity))
        row.costText:SetText((merchantInfo and "" or "~") .. WoW:FormatMoney(rowCost))
        row.background:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.045 or 0.015)
        row:Show()

        totalQuantity = totalQuantity + entry.quantity
        estimatedCost = estimatedCost + rowCost
    end
    for index = #entries + 1, #self.planRows do
        self.planRows[index]:Hide()
    end

    frame.scrollChild:SetHeight(math.max(1, #entries * PLAN_ROW_HEIGHT))
    frame.collapseButton.text:SetText(collapsed and "+" or "-")
    frame.collapseButton.text:SetTextColor(1, 0.82, 0)
    frame.scrollFrame:SetShown(not collapsed)
    frame.remainingText:SetShown(not collapsed)
    frame.totalCostText:SetShown(not collapsed)
    frame.resizeButton:SetShown(not collapsed)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(PLAN_MIN_WIDTH, collapsed and PLAN_HEADER_HEIGHT or PLAN_MIN_EXPANDED_HEIGHT,
            PLAN_MAX_WIDTH, PLAN_MAX_HEIGHT)
    end
    frame:SetResizable(not collapsed)

    if collapsed then
        frame:SetHeight(PLAN_HEADER_HEIGHT)
        frame.title:SetText("Vendor Materials — " .. tostring(#entries) .. " items, " ..
            tostring(totalQuantity) .. " remaining")
    else
        local width = math.max(PLAN_MIN_WIDTH, math.min(PLAN_MAX_WIDTH,
            tonumber(window.width) or PLAN_WINDOW_WIDTH))
        local height
        if window.userSized and (tonumber(window.height) or 0) > 0 then
            height = math.max(PLAN_MIN_EXPANDED_HEIGHT, math.min(PLAN_MAX_HEIGHT, tonumber(window.height)))
        else
            local visibleRows = math.min(#entries, PLAN_MAX_VISIBLE_ROWS)
            height = PLAN_HEADER_HEIGHT + PLAN_FOOTER_HEIGHT + visibleRows * PLAN_ROW_HEIGHT + 4
        end
        frame:SetSize(width, height)
        frame.title:SetText("Vendor Materials")
        frame.remainingText:SetText(tostring(#entries) .. " items · " .. tostring(totalQuantity) .. " remaining")
        frame.totalCostText:SetText("Est. " .. WoW:FormatMoney(estimatedCost))
    end
end

function VendorBuy:ShowPlanWindow(force)
    if not self:HasVendorPlan() then
        return false
    end
    local window = ns.Config.VendorPlan:GetWindow()
    if force then
        window.hidden = false
    end
    self:UpdatePlanWindow()
    if not window.hidden and self.planFrame then
        self.planFrame:Show()
    end
    return true
end

function VendorBuy:UpdateButton()
    self:UpdatePlanWindow()
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
    self.button:SetText("Buy Vendor Mats (" .. tostring(totalQuantity) .. ")")

    self.button.tooltipText = totalQuantity > 0
        and ("Buy materials from the CSE vendor plan that this merchant sells.\nAvailable here: " ..
            tostring(totalQuantity) .. "\nEstimated cost: " .. WoW:FormatMoney(totalCost))
        or "No planned vendor materials are available from this merchant."
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
    button:SetSize(168, 20)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 30)
    if button.SetMotionScriptsWhileDisabled then
        button:SetMotionScriptsWhileDisabled(true)
    end
    button:SetText("Buy Vendor Mats")
    button:SetScript("OnClick", function()
        VendorBuy:BuyQueuedVendorItems()
    end)
    button:SetScript("OnEnter", function(selfButton)
        if not selfButton.tooltipText then
            return
        end
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CSE Vendor Materials")
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
    self:UpdatePlanWindow()
end

function VendorBuy:BAG_UPDATE_DELAYED()
    self:UpdateButton()
end

function VendorBuy:Open()
    local planShown = self:ShowPlanWindow(true)
    if MerchantFrame and MerchantFrame:IsShown() then
        self:ShowButton()
    elseif not planShown then
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
    self:ShowPlanWindow()
    if MerchantFrame and MerchantFrame:IsShown() then
        self:ShowButton()
    end
    return true
end

ns:RegisterModule("VendorBuy", VendorBuy)
