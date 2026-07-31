local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before query engine")
local Shared = Scanner.Shared
local Config = Shared.Config
local MIN_QUERY_INTERVAL = Shared.MinQueryInterval
local PENDING_TIMEOUT_SECONDS = Shared.PendingTimeoutSeconds
local MAX_MORE_RESULT_REQUESTS = Shared.MaxMoreResultRequests
local GENERIC_RESULT_GRACE_SECONDS = Shared.GenericResultGraceSeconds

function Scanner:StartScan()
    if self.isScanning then
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:SetStatus("Open the Auction House before scanning.")
        return
    end

    self:CreatePanel()
    if self.panel and self.panel.fillInput then
        self:SaveFillQuantityInput(self.panel.fillInput)
    end

    wipe(self.priceResults)
    wipe(self.missingResults)
    wipe(self.fixedResultsByKey)
    wipe(self.outputItemRowsCache)
    self.scanComplete = false
    self.overridesPushed = false
    if self.missingPanel then
        self:UpdateMissingList()
    end
    if self.activeView == "missing" then
        self:ShowPanelView("config")
    end

    local targets, errorMessage = self:BuildScanTargets()
    if not targets then
        self:SetStatus(errorMessage)
        self:UpdateButtons()
        self:UpdateProgressText()
        return
    end
    if #targets == 0 then
        self:SetStatus("Select at least one scan target.")
        self:UpdateButtons()
        self:UpdateProgressText()
        return
    end

    self.scanTargets = targets
    self.scanIndex = 0
    self.completedTargets = 0
    self.totalTargets = #targets
    self.pendingQuery = nil
    self.pendingPollToken = self.pendingPollToken + 1
    self.isScanning = true
    self.nextQueryTime = 0

    self:SetStatus(string.format("Scanning %d AH items. Blizzard throttling may make this take a bit.", self.totalTargets))
    self:UpdateButtons()
    self:UpdateProgressText()

    self:TrySendNextQuery()
end

---@param seconds number?
function Scanner:SchedulePendingTimeout(seconds)
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    local token = self.pendingTimeoutToken
    C_Timer.After(seconds or PENDING_TIMEOUT_SECONDS, function()
        if Scanner.isScanning and Scanner.pendingQuery and
            Scanner.pendingTimeoutToken == token then
            local target = Scanner.pendingQuery
            Scanner:RecordQueryDiagnostic(target, "TIMEOUT")
            if not Scanner:IsAuctionThrottleReady() then
                Scanner:SetStatus("Waiting for the Auction House throttle.")
                Scanner:SchedulePendingTimeout()
                Scanner:SchedulePendingPoll(0.35)
                return
            end

            -- Blizzard occasionally populates the result cache without
            -- sending the corresponding result event. Inspect the cache once
            -- before retrying or declaring the request timed out.
            if Scanner:TryProcessAvailableResultsAtTimeout(target) then
                return
            end

            if Scanner:TrySendItemLevelFallback(target, true) or
                Scanner:TrySendSellSearchFallback(target, true) then
                Scanner:SchedulePendingPoll(0.35)
                return
            end
            if Scanner:CanTryItemLevelFallback(target) or
                Scanner:CanTrySellSearchFallback(target) then
                Scanner:SetStatus("Waiting for the Auction House throttle.")
                Scanner:SchedulePendingTimeout()
                Scanner:SchedulePendingPoll(0.35)
                return
            end
            if Scanner:TryResolveEmptyCompletedResultsAtTimeout(target) then
                return
            end
            target.error = "Timed out waiting for AH results."
            Scanner:FinishPendingTarget({})
        end
    end)
end

function Scanner:TrySendNextQuery()
    if not self.isScanning or self.pendingQuery then
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:CancelScan("Auction House closed.")
        return
    end

    if self.scanIndex >= self.totalTargets then
        self:FinishScan()
        return
    end

    if not self:IsAuctionThrottleReady() then
        self:SetStatus("Waiting for the Auction House throttle.")
        return
    end

    local now = GetTime()
    if now < self.nextQueryTime then
        C_Timer.After(self.nextQueryTime - now, function()
            Scanner:TrySendNextQuery()
        end)
        return
    end

    self.scanIndex = self.scanIndex + 1
    local target = self.scanTargets[self.scanIndex]
    self.pendingQuery = target
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.sellSearchFallbackSent = false
    target.itemLevelFallbackSent = false
    target.resultsReceived = false
    target.genericResponseReceived = false
    target.genericResponseTime = nil
    target.emptyResultRetrySent = false
    target.usesBroadItemSearch = self:ShouldUseBroadItemSearch(target)
    target.activeItemKey = target.usesBroadItemSearch and self:MakeClearedItemKey(target.itemID) or
        self:MakeItemKey(target.itemID, target.queryItemLevel)
    target.itemSearchKey = self:CopyItemKey(target.activeItemKey)
    target.resultItemKey = nil
    target.queryAttempts = 0
    target.diagnosticEvents = {}

    local queryItemKey = self:GetTargetQueryItemKey(target)
    local cachedRows = target.pricingMode == "output" and queryItemKey and
        tonumber(queryItemKey.itemLevel) == 0 and self.outputItemRowsCache[target.itemID]
    if cachedRows then
        target.cachedItemRows = cachedRows
        target.currentRawItemRows = cachedRows
        target.usedCachedRows = true
        target.resultsReceived = true
        self:RecordQueryDiagnostic(target, "CACHE", tostring(#cachedRows))
        self:SetStatus("Using current AH results for " .. tostring(target.label) .. " (" ..
            tostring(target.itemID) .. ")")
        self:UpdateProgressText()
        self:ScheduleResultProcessing(target, "item")
        return
    end

    local ok, err
    if target.usesBroadItemSearch then
        ok, err = pcall(C_AuctionHouse.SendSellSearchQuery, queryItemKey, self:GetSearchSorts(), false)
    else
        ok, err = pcall(C_AuctionHouse.SendSearchQuery, queryItemKey, self:GetSearchSorts(), false)
    end
    target.queryAttempts = target.queryAttempts + 1
    self:RecordQueryDiagnostic(target, target.usesBroadItemSearch and "SEND_BY_ITEM" or "SEND",
        "level=" .. tostring(target.itemSearchKey and target.itemSearchKey.itemLevel or 0))
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = tostring(err)
        ns.Debug:Log("SendSearchQuery failed for itemID " .. tostring(target.itemID) .. ": " .. tostring(err))
        self:FinishPendingTarget({})
        return
    end

    self:SetStatus("Querying " .. tostring(target.label) .. " (" .. tostring(target.itemID) .. ")")
    self:UpdateProgressText()
    self:SchedulePendingTimeout()
    self:SchedulePendingPoll(0.35)
end

---@param itemKey ItemKey
---@param target table
---@return boolean
function Scanner:ItemKeyMatchesTarget(itemKey, target)
    if not itemKey or not target then
        return false
    end
    if tonumber(itemKey.itemID) ~= tonumber(target.itemID) then
        return false
    end
    if target.itemLevel and target.itemLevel > 0 and itemKey.itemLevel and itemKey.itemLevel > 0 then
        local searchItemKey = target.itemSearchKey or self:GetTargetQueryItemKey(target)
        if target.usesBroadItemSearch or (searchItemKey and tonumber(searchItemKey.itemLevel) == 0) then
            return true
        end
        return tonumber(itemKey.itemLevel) == tonumber(target.itemLevel)
    end
    return true
end

---@param itemID number
---@return table[] rows
function Scanner:GetCommodityRows(itemID)
    local rows = {}
    local ok, numResults = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not ok then
        return rows
    end
    local target = self.pendingQuery
    if target then
        target.diagnosticCommodityAPIResults = numResults
    end

    for index = 1, numResults do
        local success, result = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
        if success and result then
            local price = tonumber(result.unitPrice)
            local quantity = tonumber(result.quantity) or 0
            if price and price > 0 and quantity > 0 then
                table.insert(rows, {
                    unitPrice = price,
                    quantity = quantity,
                })
            end
        end
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    if target then
        target.diagnosticCommodityRows = #rows
    end
    return rows
end

---@param itemKey ItemKey
---@param target table?
---@return table[] rows
function Scanner:GetItemRows(itemKey, target)
    local rows = {}
    local rawRows = target and target.cachedItemRows
    if not rawRows then
        rawRows = {}
        local ok, numResults = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
        if not ok then
            return rows
        end
        if target then
            target.diagnosticItemAPIResults = numResults
        end

        for index = 1, numResults do
            local success, result = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
            if success and result then
                local buyout = tonumber(result.buyoutAmount)
                local quantity = tonumber(result.quantity) or 1
                if buyout and buyout > 0 and quantity > 0 then
                    local itemLink = result.itemLink
                    if not itemLink and result.auctionID and C_AuctionHouse.GetAuctionInfoByID then
                        local auctionOK, auctionInfo = pcall(C_AuctionHouse.GetAuctionInfoByID, result.auctionID)
                        if auctionOK and auctionInfo then
                            itemLink = auctionInfo.itemLink
                        end
                    end
                    table.insert(rawRows, {
                        unitPrice = buyout,
                        quantity = quantity,
                        itemKey = result.itemKey or itemKey,
                        itemLink = itemLink,
                        auctionID = result.auctionID,
                    })
                end
            end
        end
        if target then
            target.currentRawItemRows = rawRows
        end
    end
    if target then
        target.diagnosticRawItemRows = #rawRows
        local observedLevels = {}
        local observedLevelMap = {}
        for _, rawRow in ipairs(rawRows) do
            local observedLevel = tonumber(rawRow.itemKey and rawRow.itemKey.itemLevel)
            if observedLevel and observedLevel > 0 and not observedLevelMap[observedLevel] then
                observedLevelMap[observedLevel] = true
                table.insert(observedLevels, observedLevel)
            end
        end
        table.sort(observedLevels)
        for index, observedLevel in ipairs(observedLevels) do
            observedLevels[index] = tostring(observedLevel)
        end
        target.diagnosticItemLevels = table.concat(observedLevels, ",")
    end

    local rankItemLevels
    if target and target.requiredBonusIDs then
        rankItemLevels = self:InferRankItemLevels(target, rawRows)
        target.itemLevel = rankItemLevels and rankItemLevels[target.outputQualityID] or 0
        target.rankClassificationResolved = target.itemLevel > 0
    end

    for _, result in ipairs(rawRows) do
        local resultItemKey = result.itemKey or itemKey
        local matchesTarget = not target or tonumber(resultItemKey.itemID) == tonumber(target.itemID)
        if matchesTarget and target and target.requiredBonusIDs then
            local bonusMatch = self:ItemLinkMatchesBonusIDs(result.itemLink, target.requiredBonusIDs)
            local inferredItemLevel = rankItemLevels and rankItemLevels[target.outputQualityID]
            local itemLevelMatch = inferredItemLevel and inferredItemLevel > 0 and
                tonumber(resultItemKey.itemLevel) == tonumber(inferredItemLevel)
            matchesTarget = bonusMatch == true or itemLevelMatch == true
        elseif matchesTarget and target and target.itemLevel and target.itemLevel > 0 then
            matchesTarget = tonumber(resultItemKey.itemLevel) == tonumber(target.itemLevel)
        end
        if matchesTarget then
            table.insert(rows, result)
        end
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    if target then
        target.diagnosticMatchedRows = #rows
    end
    return rows
end

---@param rows table[]
---@return number quantity
function Scanner:GetListedQuantity(rows)
    local quantity = 0
    for _, row in ipairs(rows) do
        quantity = quantity + (tonumber(row.quantity) or 0)
    end
    return quantity
end

---@param resultType "commodity" | "item"
---@return boolean hasFullResults
function Scanner:HasFullResults(resultType)
    local target = self.pendingQuery
    if not target then
        return true
    end

    local ok, hasFullResults
    if resultType == "commodity" and C_AuctionHouse.HasFullCommoditySearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.HasFullCommoditySearchResults, target.itemID)
    elseif resultType == "item" and C_AuctionHouse.HasFullItemSearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.HasFullItemSearchResults,
            self:GetTargetItemResultKey(target))
    end
    if ok then
        if resultType == "item" then
            target.diagnosticFullItem = hasFullResults == true
        else
            target.diagnosticFullCommodity = hasFullResults == true
        end
        return hasFullResults == true
    end
    return false
end

---@param resultType "commodity" | "item"
---@return table[] rows
function Scanner:GetRowsForResultType(resultType)
    local target = self.pendingQuery
    if not target then
        return {}
    end

    if resultType == "commodity" then
        return self:GetCommodityRows(target.itemID)
    end
    return self:GetItemRows(self:GetTargetItemResultKey(target), target)
end

---@param target table
---@return string[]
function Scanner:GetResultTypesToTry(target)
    if target.resultType == "commodity" then
        return { "commodity", "item" }
    elseif target.resultType == "item" then
        return { "item", "commodity" }
    end
    return { "commodity", "item" }
end

---@param target table
---@param force boolean?
---@return boolean sent
function Scanner:TrySendSellSearchFallback(target, force)
    if not target or target.sellSearchFallbackSent or not self:IsLikelyCommodityTarget(target) then
        return false
    end
    if not C_AuctionHouse or not C_AuctionHouse.SendSellSearchQuery then
        return false
    end
    if not self:IsAuctionThrottleReady() then
        return false
    end
    if not force and target.queryStartTime and (GetTime() - target.queryStartTime) < 1.5 then
        return false
    end

    target.sellSearchFallbackSent = true
    target.activeItemKey = self:MakeClearedItemKey(target.itemID)
    target.itemSearchKey = self:CopyItemKey(target.activeItemKey)
    target.resultItemKey = nil
    target.usesBroadItemSearch = false
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.resultsReceived = false
    target.genericResponseReceived = false
    target.genericResponseTime = nil
    target.error = nil

    local ok, err = pcall(C_AuctionHouse.SendSellSearchQuery, target.activeItemKey, self:GetSearchSorts(), false)
    target.queryAttempts = (target.queryAttempts or 0) + 1
    self:RecordQueryDiagnostic(target, "SEND_SELL")
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = "Commodity sell search failed: " .. tostring(err)
        ns.Debug:Log("SendSellSearchQuery fallback failed for itemID " .. tostring(target.itemID) .. ": " ..
            tostring(err))
        return false
    end

    self:SetStatus("Retrying exact commodity search for " .. tostring(target.label))
    self:SchedulePendingTimeout()
    return true
end

---@param target table
---@param force boolean?
---@return boolean sent
function Scanner:TrySendItemLevelFallback(target, force)
    if not target or target.pricingMode == "output" or target.itemLevelFallbackSent or not target.itemLevel or
        target.itemLevel <= 0 then
        return false
    end
    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then
        return false
    end
    if not self:IsAuctionThrottleReady() then
        return false
    end
    if not force and target.queryStartTime and (GetTime() - target.queryStartTime) < 1.5 then
        return false
    end

    target.itemLevelFallbackSent = true
    target.activeItemKey = self:MakeItemKey(target.itemID, 0)
    target.itemSearchKey = self:CopyItemKey(target.activeItemKey)
    target.resultItemKey = nil
    target.usesBroadItemSearch = false
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.resultsReceived = false
    target.genericResponseReceived = false
    target.genericResponseTime = nil
    target.error = nil

    local ok, err = pcall(C_AuctionHouse.SendSearchQuery, target.activeItemKey, self:GetSearchSorts(), false)
    target.queryAttempts = (target.queryAttempts or 0) + 1
    self:RecordQueryDiagnostic(target, "SEND_BROAD")
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = "Broad item search failed: " .. tostring(err)
        ns.Debug:Log("Broad item search failed for itemID " .. tostring(target.itemID) .. ": " .. tostring(err))
        return false
    end

    self:SetStatus("Retrying broad item search for " .. tostring(target.label))
    self:SchedulePendingTimeout()
    return true
end

---@param seconds number?
function Scanner:SchedulePendingPoll(seconds)
    self.pendingPollToken = self.pendingPollToken + 1
    local token = self.pendingPollToken
    C_Timer.After(seconds or 0.35, function()
        if Scanner.isScanning and Scanner.pendingQuery and
            Scanner.pendingPollToken == token then
            Scanner:PollPendingResults()
        end
    end)
end

---@param target table
---@param resultType "commodity" | "item"
function Scanner:ScheduleResultProcessing(target, resultType)
    C_Timer.After(0.05, function()
        if Scanner.isScanning and Scanner.pendingQuery == target and target.resultsReceived then
            Scanner:ProcessPendingResults(resultType)
        end
    end)
end

---@param target table
---@param respectRetryDelay boolean?
---@return boolean waitingForFallback
function Scanner:TryFallbacksBeforeMissing(target, respectRetryDelay)
    if self:CanTryItemLevelFallback(target) then
        if self:TrySendItemLevelFallback(target, not respectRetryDelay) then
            self:SchedulePendingPoll(0.35)
            return true
        end
        self:SchedulePendingPoll(0.35)
        return true
    end

    if self:CanTrySellSearchFallback(target) then
        if self:TrySendSellSearchFallback(target, not respectRetryDelay) then
            self:SchedulePendingPoll(0.35)
            return true
        end
        self:SchedulePendingPoll(0.35)
        return true
    end

    return false
end

function Scanner:PollPendingResults()
    local target = self.pendingQuery
    if not self.isScanning or not target then
        return
    end

    if not target.resultsReceived then
        local genericResponseAge = target.genericResponseTime and (GetTime() - target.genericResponseTime) or 0
        if target.genericResponseReceived then
            -- Populated AH rows can be short-lived when other AH consumers are
            -- active, so capture them immediately. Only empty-result handling
            -- waits for the grace period and confirmation retry.
            if self:TryProcessAvailableResultsAtTimeout(target) then
                return
            end
            if genericResponseAge >= GENERIC_RESULT_GRACE_SECONDS and
                self:TryResolveEmptyCompletedResultsAtTimeout(target) then
                return
            end
        end
        self:SchedulePendingPoll(0.35)
        return
    end

    for resultIndex, resultType in ipairs(self:GetResultTypesToTry(target)) do
        local rows = self:GetRowsForResultType(resultType)
        local hasUnfilteredRankRows = resultType == "item" and target.requiredBonusIDs and
            target.currentRawItemRows and #target.currentRawItemRows > 0
        if #rows > 0 or hasUnfilteredRankRows then
            self:RecordQueryDiagnostic(target, "CACHE_ROWS", resultType .. ":" .. tostring(#rows))
            self:ProcessPendingResults(resultType)
            return
        elseif resultIndex == 1 and self:HasFullResults(resultType) then
            if self:TryFallbacksBeforeMissing(target, false) then
                return
            end
            self:ProcessPendingResults(resultType)
            return
        end
    end

    if self:TryFallbacksBeforeMissing(target, true) then
        return
    end
    self:SchedulePendingPoll(0.35)
end

---@param target table
---@return boolean processed
function Scanner:TryProcessAvailableResultsAtTimeout(target)
    if not target or self.pendingQuery ~= target then
        return false
    end

    target.resultsReceived = true
    for _, resultType in ipairs(self:GetResultTypesToTry(target)) do
        local rows = self:GetRowsForResultType(resultType)
        local hasUnfilteredRankRows = resultType == "item" and target.requiredBonusIDs and
            target.currentRawItemRows and #target.currentRawItemRows > 0
        if #rows > 0 or hasUnfilteredRankRows then
            self:ProcessPendingResults(resultType)
            return true
        end
    end

    target.resultsReceived = false
    return false
end

---@param target table
---@return boolean sent
function Scanner:RetryEmptySearch(target)
    if not target or target.emptyResultRetrySent or not C_AuctionHouse or
        not self:IsAuctionThrottleReady() then
        return false
    end
    local sendFunction = target.usesBroadItemSearch and C_AuctionHouse.SendSellSearchQuery or
        C_AuctionHouse.SendSearchQuery
    if not sendFunction then
        return false
    end

    target.emptyResultRetrySent = true
    target.resultsReceived = false
    target.genericResponseReceived = false
    target.genericResponseTime = nil
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.currentRawItemRows = nil
    target.resultItemKey = nil
    target.activeItemKey = target.usesBroadItemSearch and self:MakeClearedItemKey(target.itemID) or
        self:MakeItemKey(target.itemID, target.queryItemLevel)
    target.itemSearchKey = self:CopyItemKey(target.activeItemKey)

    local ok, err = pcall(sendFunction, self:GetTargetQueryItemKey(target),
        self:GetSearchSorts(), false)
    target.queryAttempts = (target.queryAttempts or 0) + 1
    self:RecordQueryDiagnostic(target,
        target.usesBroadItemSearch and "SEND_EMPTY_RETRY_BY_ITEM" or "SEND_EMPTY_RETRY")
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = "Empty-result retry failed: " .. tostring(err)
        ns.Debug:Log("Empty-result retry failed for itemID " .. tostring(target.itemID) .. ": " .. tostring(err))
        return false
    end

    self:SetStatus("Confirming empty AH results for " .. tostring(target.label))
    self:SchedulePendingTimeout()
    self:SchedulePendingPoll(0.35)
    return true
end

---@param target table
---@return boolean handled
function Scanner:TryResolveEmptyCompletedResultsAtTimeout(target)
    if not target or not target.genericResponseReceived then
        return false
    end

    local resultTypes = self:GetResultTypesToTry(target)
    local resultType = resultTypes[1]
    if not resultType or not self:HasFullResults(resultType) then
        return false
    end
    self:RecordQueryDiagnostic(target, "EMPTY_FULL", resultType)

    local alreadyRetried = target.emptyResultRetrySent or target.sellSearchFallbackSent or
        target.itemLevelFallbackSent
    if not alreadyRetried then
        return self:RetryEmptySearch(target)
    end

    target.resultsReceived = true
    self:ProcessPendingResults(resultType)
    return true
end

---@param resultType "commodity" | "item"
---@return boolean waitingForMore
function Scanner:RequestMoreResultsIfNeeded(resultType, rows)
    local target = self.pendingQuery
    if not target then
        return false
    end
    if target.cachedItemRows then
        return false
    end
    local needsSharedOutputSnapshot = target.pricingMode == "output" and target.requiredBonusIDs ~= nil
    if not self:TargetUsesFillQuantity(target) and not needsSharedOutputSnapshot and #rows > 0 then
        return false
    end

    local fillQuantity = Config:GetFillQuantity()
    if (not needsSharedOutputSnapshot and self:GetListedQuantity(rows) >= fillQuantity) or
        self:HasFullResults(resultType) then
        return false
    end

    if target.moreRequests >= MAX_MORE_RESULT_REQUESTS then
        return false
    end

    target.moreRequests = target.moreRequests + 1
    local ok, hasFullResults
    if resultType == "commodity" and C_AuctionHouse.RequestMoreCommoditySearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.RequestMoreCommoditySearchResults, target.itemID)
    elseif resultType == "item" and C_AuctionHouse.RequestMoreItemSearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.RequestMoreItemSearchResults,
            self:GetTargetItemResultKey(target))
    end

    if ok and hasFullResults == false then
        target.resultsReceived = false
        target.genericResponseReceived = false
        target.genericResponseTime = nil
        self:RecordQueryDiagnostic(target, "MORE", resultType)
        self:SetStatus("Loading more results for " .. tostring(target.label))
        self:SchedulePendingTimeout()
        self:SchedulePendingPoll(0.35)
        return true
    end

    return false
end

---@param values number[]
---@return number[] trimmed
