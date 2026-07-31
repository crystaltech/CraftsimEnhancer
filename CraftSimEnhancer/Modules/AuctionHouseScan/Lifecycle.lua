local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before lifecycle")
local EVENTS = Scanner.Shared.Events

function Scanner:AUCTION_HOUSE_SHOW()
    self:ShowButton()
end

function Scanner:AUCTION_HOUSE_CLOSED()
    self:HideAuctionHouseTab()
    if self.configPanel then
        self.configPanel:Hide()
    end
    if self.missingPanel then
        self.missingPanel:Hide()
    end
    if self.button then
        self.button:Hide()
    end
    if self.isScanning then
        self:CancelScan("Auction House closed.")
    end
end

function Scanner:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
    self:TrySendNextQuery()
end

function Scanner:AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED()
    if self.pendingQuery then
        self:RecordQueryDiagnostic(self.pendingQuery, "DROPPED")
        self.pendingQuery.error = "Auction House throttled message dropped."
        self:FinishPendingTarget({})
    end
end

function Scanner:AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED()
    if self.pendingQuery then
        -- This confirms that Blizzard answered a throttled request, but the
        -- item-specific cache may not be populated yet. Do not authorize an
        -- empty result until an item event arrives or a clean retry agrees.
        self.pendingQuery.genericResponseReceived = true
        self.pendingQuery.genericResponseTime = GetTime()
        self:RecordQueryDiagnostic(self.pendingQuery, "GENERIC_RESPONSE")
        self:SchedulePendingPoll(0.05)
    else
        self:TrySendNextQuery()
    end
end

function Scanner:AUCTION_HOUSE_NEW_RESULTS_RECEIVED(itemKey)
    local target = self.pendingQuery
    if target then
        self:RecordQueryDiagnostic(target, "NEW_RESULTS",
            tostring(itemKey and itemKey.itemID or "-") .. ":" .. tostring(itemKey and itemKey.itemLevel or "-"))
    end
    if itemKey and not self:ItemKeyMatchesTarget(itemKey, target) then
        return
    end
    if target then
        self:CaptureItemResultKey(target, itemKey)
        target.resultsReceived = true
        self:SchedulePendingPoll(0.05)
    end
end

function Scanner:COMMODITY_SEARCH_RESULTS_ADDED(itemID)
    self:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
end

function Scanner:COMMODITY_SEARCH_RESULTS_RECEIVED()
    local target = self.pendingQuery
    if not target or not self:IsLikelyCommodityTarget(target) then
        return
    end
    self:RecordQueryDiagnostic(target, "COMMODITY_RECEIVED")
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "commodity")
end

function Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
    local target = self.pendingQuery
    if target then
        self:RecordQueryDiagnostic(target, "COMMODITY_UPDATED", tostring(itemID or "-"))
    end
    if not target or tonumber(itemID) ~= tonumber(target.itemID) then
        return
    end
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "commodity")
end

function Scanner:ITEM_SEARCH_RESULTS_ADDED(itemKey)
    self:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
end

function Scanner:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
    local target = self.pendingQuery
    if target then
        self:RecordQueryDiagnostic(target, "ITEM_UPDATED",
            tostring(itemKey and itemKey.itemID or "-") .. ":" .. tostring(itemKey and itemKey.itemLevel or "-"))
    end
    if not self:ItemKeyMatchesTarget(itemKey, target) then
        return
    end
    self:CaptureItemResultKey(target, itemKey)
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "item")
end

function Scanner:Open()
    Scanner:ShowButton()
    Scanner:TogglePanel()
end

function Scanner:CanInitialize()
    local auctionAPIs = {
        "MakeItemKey",
        "GetItemKeyInfo",
        "IsThrottledMessageSystemReady",
        "SendSearchQuery",
        "SendSellSearchQuery",
        "GetNumCommoditySearchResults",
        "GetCommoditySearchResultInfo",
        "GetNumItemSearchResults",
        "GetItemSearchResultInfo",
        "HasFullCommoditySearchResults",
        "HasFullItemSearchResults",
        "RequestMoreCommoditySearchResults",
        "RequestMoreItemSearchResults",
    }
    if not C_AuctionHouse then
        return nil, "Auction House APIs are unavailable"
    end
    for _, functionName in ipairs(auctionAPIs) do
        if type(C_AuctionHouse[functionName]) ~= "function" then
            return nil, "C_AuctionHouse." .. functionName .. " is unavailable"
        end
    end
    if not Enum or not Enum.Profession or not Enum.AuctionHouseSortOrder or
        type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" or
        not C_TradeSkillUI or type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) ~= "function" or
        not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" or
        not C_Timer or type(C_Timer.After) ~= "function" or type(GetTime) ~= "function" then
        return nil, "required Auction House or profession APIs are unavailable"
    end
    return ns.Compat.CraftSim:ValidateAuctionScanner()
end

function Scanner:Initialize()
    if self.initialized then
        return true
    end
    self.eventFrame = ns:CreateEventDispatcher(self, EVENTS)
    self.initialized = true
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        self:ShowButton()
    end
    return true
end
