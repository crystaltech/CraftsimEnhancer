local _, ns = ...

local Compat = ns.Compat.CraftSim
local Notice = {}
local POPUP_KEY = "CRAFTSIM_ENHANCER_VENDOR_REAGENTS_IN_SHOPPING_LIST"

function Notice:ShowForCurrentQueue()
    local vendorBuy = ns.Modules.VendorBuy
    if not vendorBuy or type(vendorBuy.CreateVendorPlanFromCurrentQueue) ~= "function" then
        return
    end

    local summary = vendorBuy:CreateVendorPlanFromCurrentQueue()
    if summary and summary.separationFailed then
        StaticPopup_Show(POPUP_KEY,
            "Vendor materials were NOT removed from the Auctionator list.\n\n" ..
            tostring(summary.error or "The list could not be safely updated.") ..
            "\n\nReview the shopping list before buying from the Auction House.")
        return
    end
    if not summary or (tonumber(summary.itemCount) or 0) == 0 then
        return
    end

    local itemText = summary.itemCount == 1 and "1 vendor reagent was" or
        (tostring(summary.itemCount) .. " vendor reagents were")
    StaticPopup_Show(POPUP_KEY, itemText .. " moved out of the Auctionator list.\n\n" ..
        "Buy the Auction House materials first, then visit vendors. The Vendor Materials window will track " ..
        tostring(summary.totalQuantity) .. " remaining items.")
end

function Notice:CanInitialize()
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then
        return nil, "static popup APIs are unavailable"
    end
    if not ns.Modules.VendorBuy or not ns.ModuleStatus.VendorBuy or
        not ns.ModuleStatus.VendorBuy.initialized then
        return nil, "VendorBuy queue analysis is unavailable"
    end
    local queueItems, queueError = Compat:GetCraftQueueItems()
    if not queueItems and queueError ~= "CraftSim craft queue is not initialized" then
        return nil, queueError
    end
    return Compat:ValidateShoppingListHook()
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
