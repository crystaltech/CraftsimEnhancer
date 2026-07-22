local addonName, ns = ...

local Compat = ns.Compat.CraftSim
local Notice = {}
local POPUP_KEY = "CRAFTSIM_ENHANCER_VENDOR_REAGENTS_IN_SHOPPING_LIST"

function Notice:IsVendorSold(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return false
    end

    local metadata = ns.Data.ItemMetadata[itemID]
    if metadata and metadata.vendorSold == true then
        return true
    end

    local auctionator = _G.Auctionator
    local api = auctionator and auctionator.API and auctionator.API.v1
    if api and type(api.GetVendorPriceByItemID) == "function" then
        local success, vendorPrice = pcall(api.GetVendorPriceByItemID, addonName, itemID)
        return success and vendorPrice ~= nil
    end
    return false
end

function Notice:ShowForCurrentQueue()
    local vendorBuy = ns.Modules.VendorBuy
    if not vendorBuy or type(vendorBuy.GetQueuedNeededItems) ~= "function" then
        return
    end

    local signatureParts = {}
    local vendorItemCount = 0
    for itemID, info in pairs(vendorBuy:GetQueuedNeededItems()) do
        if self:IsVendorSold(itemID) then
            vendorItemCount = vendorItemCount + 1
            table.insert(signatureParts, tostring(itemID) .. ":" .. tostring(info.quantity or 0))
        end
    end

    if vendorItemCount == 0 then
        return
    end
    table.sort(signatureParts)
    local signature = table.concat(signatureParts, ",")
    if signature == self.lastSignature then
        return
    end
    self.lastSignature = signature

    local itemText = vendorItemCount == 1 and "A vendor-sold reagent was" or
        (tostring(vendorItemCount) .. " vendor-sold reagents were")
    StaticPopup_Show(POPUP_KEY,
        itemText .. " added to the CraftSim shopping list.\n\nVisit your profession vendors before buying these items from the Auction House.")
end

function Notice:CanInitialize()
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then
        return nil, "static popup APIs are unavailable"
    end
    if not ns.Modules.VendorBuy then
        return nil, "VendorBuy queue analysis is unavailable"
    end
    local queueItems, queueError = Compat:GetCraftQueueItems()
    if not queueItems and queueError ~= "CraftSim craft queue is not initialized" then
        return nil, queueError
    end
    local craftSim = Compat.craftSim
    local queueModule = craftSim and craftSim.CRAFTQ
    if not queueModule or type(queueModule.CreateAuctionatorShoppingList) ~= "function" then
        return nil, "CraftSim shopping-list creation function is unavailable"
    end
    return true
end

function Notice:Initialize()
    if self.initialized then
        return true
    end

    StaticPopupDialogs[POPUP_KEY] = {
        text = "%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    local hooked, hookError = Compat:HookShoppingListCreated(function()
        Notice:ShowForCurrentQueue()
    end)
    if not hooked then
        return nil, hookError
    end
    self.initialized = true
    return true
end

ns:RegisterModule("VendorShoppingListNotice", Notice)
