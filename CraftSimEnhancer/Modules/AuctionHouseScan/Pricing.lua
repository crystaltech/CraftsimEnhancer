local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before pricing")
local Shared = Scanner.Shared
local Config = Shared.Config
local MIN_QUERY_INTERVAL = Shared.MinQueryInterval
local AUCTION_HOUSE_CUT = Shared.AuctionHouseCut
local ESTIMATED_RESULT_SOURCE = Shared.EstimatedResultSource
local SystemPrint = Shared.SystemPrint

function Scanner:TrimOutliers(values)
    local count = #values
    if count < 8 then
        return values
    end

    local q1 = values[math.max(1, math.floor((count + 1) * 0.25))]
    local q3 = values[math.max(1, math.floor((count + 1) * 0.75))]
    local iqr = q3 - q1
    local lower = math.max(0, q1 - 1.5 * iqr)
    local upper = q3 + 1.5 * iqr
    if iqr <= 0 then
        upper = q3 * 3
    end

    local trimmed = {}
    for _, value in ipairs(values) do
        if value >= lower and value <= upper then
            table.insert(trimmed, value)
        end
    end

    if #trimmed == 0 then
        return values
    end
    return trimmed
end

---@param rows table[]
---@return number? price
---@return number quantityUsed
---@return number listedQuantity
---@return number trimmedUnits
function Scanner:CalculateTrimmedFillPrice(rows)
    local fillQuantity = Config:GetFillQuantity()
    local remaining = fillQuantity
    local unitPrices = {}
    local listedQuantity = 0

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)

    for _, row in ipairs(rows) do
        local quantity = math.max(0, math.floor(tonumber(row.quantity) or 0))
        local unitPrice = tonumber(row.unitPrice)
        listedQuantity = listedQuantity + quantity
        if unitPrice and unitPrice > 0 and remaining > 0 then
            local fillFromRow = math.min(quantity, remaining)
            for _ = 1, fillFromRow do
                table.insert(unitPrices, unitPrice)
            end
            remaining = remaining - fillFromRow
        end
        if remaining <= 0 then
            break
        end
    end

    if #unitPrices == 0 then
        return nil, 0, listedQuantity, 0
    end

    table.sort(unitPrices)
    local trimmed = self:TrimOutliers(unitPrices)
    local total = 0
    for _, unitPrice in ipairs(trimmed) do
        total = total + unitPrice
    end

    local price = math.floor((total / #trimmed) + 0.5)
    return price, #unitPrices, listedQuantity, #unitPrices - #trimmed
end

---@param rows table[]
---@return number? price
---@return number quantityUsed
---@return number listedQuantity
---@return number trimmedUnits
function Scanner:CalculateLowestBuyoutPrice(rows)
    if #rows == 0 then
        return nil, 0, 0, 0
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)

    local price = tonumber(rows[1].unitPrice)
    if not price or price <= 0 then
        return nil, 0, self:GetListedQuantity(rows), 0
    end

    return math.floor(price + 0.5), 1, self:GetListedQuantity(rows), 0
end

---@param target table
---@return number? price
function Scanner:GetTSMFallbackPrice(target)
    if not target or not target.itemID then
        return nil
    end

    local isReagent = target.kindMap and target.kindMap.input == true and target.kindMap.output ~= true
    local price = ns.Compat.CraftSim:GetTSMFallbackPrice(target.itemID, isReagent)
    if price and price > 0 then
        return math.floor(price + 0.5)
    end
    return nil
end

---@param resultType "commodity" | "item"
function Scanner:ProcessPendingResults(resultType)
    if not self.isScanning or not self.pendingQuery then
        return
    end

    local target = self.pendingQuery
    if not target.resultsReceived then
        self:SchedulePendingPoll(0.35)
        return
    end
    local rows = self:GetRowsForResultType(resultType)

    if #rows == 0 then
        if self:TryFallbacksBeforeMissing(target, false) then
            return
        end

        local hasUnfilteredRankRows = resultType == "item" and target.requiredBonusIDs and
            target.currentRawItemRows and #target.currentRawItemRows > 0
        local alreadyRetried = target.emptyResultRetrySent or target.sellSearchFallbackSent or
            target.itemLevelFallbackSent
        if not hasUnfilteredRankRows and not alreadyRetried and self:HasFullResults(resultType) and
            self:RetryEmptySearch(target) then
            return
        end
    end

    if self:RequestMoreResultsIfNeeded(resultType, rows) then
        return
    end

    self:FinishPendingTarget(rows, resultType)
end

---@param rows table[]
---@param resultType "commodity" | "item"?
function Scanner:FinishPendingTarget(rows, resultType)
    local target = self.pendingQuery
    if not target then
        return
    end

    self.pendingTimeoutToken = self.pendingTimeoutToken + 1

    local queryItemKey = self:GetTargetQueryItemKey(target)
    local itemSearchKey = target.itemSearchKey or queryItemKey
    if target.pricingMode == "output" and itemSearchKey and tonumber(itemSearchKey.itemLevel) == 0 and
        target.currentRawItemRows then
        self.outputItemRowsCache[target.itemID] = target.currentRawItemRows
    end

    local price, quantityUsed, listedQuantity, trimmedUnits
    if self:TargetUsesFillQuantity(target) then
        price, quantityUsed, listedQuantity, trimmedUnits = self:CalculateTrimmedFillPrice(rows)
    else
        price, quantityUsed, listedQuantity, trimmedUnits = self:CalculateLowestBuyoutPrice(rows)
    end
    local source = "AH"
    -- A shared item ID cannot use an item-level-zero TSM price as a quality
    -- fallback. It would assign one generic item price to an arbitrary rank.
    local allowTSMFallback = target.pricingMode ~= "output" or
        (target.requiredBonusIDs == nil and (not target.itemLevel or target.itemLevel <= 0))
    if not price and allowTSMFallback then
        price = self:GetTSMFallbackPrice(target)
        if price then
            source = "TSM fallback"
            quantityUsed = 0
            listedQuantity = 0
            trimmedUnits = 0
        end
    end

    if price then
        table.insert(self.priceResults, {
            itemID = target.itemID,
            itemLevel = target.itemLevel,
            itemKey = self:GetTargetQueryItemKey(target),
            label = target.label,
            price = price,
            source = source,
            quantityUsed = quantityUsed,
            listedQuantity = listedQuantity,
            trimmedUnits = trimmedUnits,
            overrideTargets = target.overrideTargets,
        })
        if source ~= "AH" then
            self:SetStatus("Using " .. source .. " for " .. tostring(target.label) .. " (" ..
                tostring(target.itemID) .. ")")
        end
    else
        if target.requiredBonusIDs and target.currentRawItemRows and #target.currentRawItemRows > 0 and
            not target.rankClassificationResolved then
            target.error = target.error or "Posted auctions found, but rank could not be identified."
        else
            target.error = target.error or "No posted auctions found."
        end
        table.insert(self.missingResults, {
            targetKey = target.key,
            itemID = target.itemID,
            itemLevel = target.itemLevel,
            label = target.label,
            pricingMode = target.pricingMode,
            typeText = self:GetTargetTypeText(target),
            sourceNames = target.sourceNames,
            error = target.error,
            diagnostic = self:GetTargetDiagnosticSummary(target),
            overrideTargets = target.overrideTargets,
        })
        self:SetStatus("Skipping " .. tostring(target.label) .. " (" .. tostring(target.itemID) .. "): " ..
            tostring(target.error))
    end

    self.completedTargets = self.completedTargets + 1
    self.pendingQuery = nil
    self.pendingPollToken = self.pendingPollToken + 1
    self:UpdateProgressText()
    self:UpdateButtons()

    -- Cached rank variants do not send another AH request. Process the next
    -- target immediately; TrySendNextQuery still enforces nextQueryTime before
    -- the next real request.
    local nextTargetDelay = target.usedCachedRows and 0 or MIN_QUERY_INTERVAL
    C_Timer.After(nextTargetDelay, function()
        Scanner:TrySendNextQuery()
    end)
end

function Scanner:FinishScan()
    self.isScanning = false
    self.pendingQuery = nil
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    self.pendingPollToken = self.pendingPollToken + 1
    self.scanComplete = true
    local pricedTargets, unpricedTargets, processedTargets, groupedItems = self:GetScanOutcomeCounts()
    self:SetStatus("Scan complete. Press Push Overrides to apply.")
    self:UpdateProgressText()
    self:UpdateButtons()
    if self.missingPanel and self.missingPanel:IsShown() then
        self:UpdateMissingList()
    end
    SystemPrint(string.format("Scan complete: %d/%d price targets processed; %d priced, %d unpriced (%d grouped items).",
        processedTargets, self.totalTargets, pricedTargets, unpricedTargets, groupedItems))
end

---@param reason string?
function Scanner:CancelScan(reason)
    self.isScanning = false
    self.pendingQuery = nil
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    self.pendingPollToken = self.pendingPollToken + 1
    self.scanComplete = false
    self:SetStatus(reason or "Scan cancelled.")
    self:UpdateProgressText()
    self:UpdateButtons()
end

---@return table<string, number> pricesByOverrideKey
---@return number cappedCount
---@return table<number, table<number, number>> pricesByRecipeAndQuality
function Scanner:GetNormalizedResultOverridePrices()
    local pricesByRecipe = {}

    for _, result in ipairs(self.priceResults or {}) do
        local price = math.floor((tonumber(result.price) or 0) + 0.5)
        if price > 0 then
            for _, overrideTarget in ipairs(result.overrideTargets or {}) do
                local recipeID = tonumber(overrideTarget.recipeID)
                local qualityID = tonumber(overrideTarget.qualityID)
                if overrideTarget.kind == "result" and recipeID and qualityID then
                    pricesByRecipe[recipeID] = pricesByRecipe[recipeID] or {}
                    local current = pricesByRecipe[recipeID][qualityID]
                    pricesByRecipe[recipeID][qualityID] = current and math.min(current, price) or price
                end
            end
        end
    end

    local normalized = {}
    local normalizedByRecipe = {}
    local cappedCount = 0
    for recipeID, pricesByQuality in pairs(pricesByRecipe) do
        normalizedByRecipe[recipeID] = {}
        local qualityIDs = {}
        for qualityID in pairs(pricesByQuality) do
            table.insert(qualityIDs, qualityID)
        end
        table.sort(qualityIDs, function(a, b) return a > b end)

        local cheapestEqualOrBetter
        for _, qualityID in ipairs(qualityIDs) do
            local listedPrice = pricesByQuality[qualityID]
            if not cheapestEqualOrBetter or listedPrice < cheapestEqualOrBetter then
                cheapestEqualOrBetter = listedPrice
            elseif listedPrice > cheapestEqualOrBetter then
                cappedCount = cappedCount + 1
            end
            normalized[tostring(recipeID) .. ":" .. tostring(qualityID)] = cheapestEqualOrBetter
            normalizedByRecipe[recipeID][qualityID] = cheapestEqualOrBetter
        end
    end

    return normalized, cappedCount, normalizedByRecipe
end

---@param expectedCost number
---@param betterRankPrice number?
---@return number? price
---@return boolean capped
function Scanner:CalculateMissingResultPrice(expectedCost, betterRankPrice)
    expectedCost = tonumber(expectedCost)
    if not expectedCost or expectedCost <= 0 then
        return nil, false
    end

    -- Round down so the estimate cannot create a small artificial profit after
    -- the Auction House cut. A real better-rank listing is always the ceiling.
    local price = math.max(1, math.floor(expectedCost / (1 - AUCTION_HOUSE_CUT)))
    local cap = tonumber(betterRankPrice)
    if cap and cap > 0 then
        cap = math.max(1, math.floor(cap) - 1)
        if price > cap then
            return cap, true
        end
    end
    return price, false
end

---@param pricesByRecipeAndQuality table<number, table<number, number>>
---@param recipeID number
---@param qualityID number
---@return number? price
function Scanner:GetCheapestRealBetterRankPrice(pricesByRecipeAndQuality, recipeID, qualityID)
    local pricesByQuality = pricesByRecipeAndQuality[tonumber(recipeID)] or {}
    local cheapest
    for listedQualityID, price in pairs(pricesByQuality) do
        if tonumber(listedQualityID) > tonumber(qualityID) and (not cheapest or price < cheapest) then
            cheapest = price
        end
    end
    return cheapest
end

function Scanner:PushOverrides()
    if not self.scanComplete or not self:HasOverridesToPush() then
        self:SetStatus("Run a scan before pushing overrides.")
        return
    end

    local savedGlobals = {}
    local savedResults = {}
    local globalCount = 0
    local resultCount = 0
    local estimatedResultCount = 0
    local skippedEstimateCount = 0
    local clearedLegacyCount = 0
    local normalizedResultPrices, cappedResultCount, pricesByRecipeAndQuality =
        self:GetNormalizedResultOverridePrices()

    for _, result in ipairs(self.priceResults) do
        local price = math.floor((tonumber(result.price) or 0) + 0.5)
        if price > 0 then
            for _, overrideTarget in ipairs(result.overrideTargets or {}) do
                if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
                    local key = tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
                    if not savedResults[key] then
                        local resultPrice = normalizedResultPrices[key] or price
                        local saved, saveError = ns.Compat.CraftSim:SaveResultOverride({
                            recipeID = overrideTarget.recipeID,
                            itemID = overrideTarget.itemID or result.itemID,
                            qualityID = overrideTarget.qualityID,
                            price = resultPrice,
                        })
                        if not saved then
                            self:SetStatus(saveError)
                            return
                        end
                        savedResults[key] = true
                        resultCount = resultCount + 1
                    end
                elseif overrideTarget.kind == "global" and overrideTarget.itemID then
                    local key = tostring(overrideTarget.itemID)
                    if not savedGlobals[key] then
                        local saved, saveError = ns.Compat.CraftSim:SaveGlobalOverride({
                            recipeID = overrideTarget.recipeID or 0,
                            itemID = overrideTarget.itemID,
                            qualityID = overrideTarget.qualityID,
                            price = price,
                        })
                        if not saved then
                            self:SetStatus(saveError)
                            return
                        end
                        savedGlobals[key] = true
                        globalCount = globalCount + 1
                    end
                end
            end
        end
    end

    for _, missingResult in ipairs(self.missingResults or {}) do
        missingResult.estimatedPrice = nil
        missingResult.craftingCost = nil
        missingResult.qualityID = nil
        missingResult.costQualityID = nil
        missingResult.estimateCapped = nil
        missingResult.estimateSkipped = nil
        if self:IsConfirmedNoAuctionResult(missingResult) then
            for _, overrideTarget in ipairs(missingResult.overrideTargets or {}) do
                if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
                    local key = tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
                    if not savedResults[key] then
                        local itemID = overrideTarget.itemID or missingResult.itemID
                        local cost, costTimestamp, crafterUID, costQualityID = ns.Compat.CraftSim:GetLastCraftingCost(
                            itemID, overrideTarget.qualityID)
                        local betterRankPrice = self:GetCheapestRealBetterRankPrice(
                            pricesByRecipeAndQuality, overrideTarget.recipeID, overrideTarget.qualityID)
                        local estimatedPrice, wasCapped = self:CalculateMissingResultPrice(cost, betterRankPrice)

                        if estimatedPrice then
                            local saved, saveError = ns.Compat.CraftSim:SaveResultOverride({
                                recipeID = overrideTarget.recipeID,
                                itemID = itemID,
                                qualityID = overrideTarget.qualityID,
                                price = estimatedPrice,
                                source = ESTIMATED_RESULT_SOURCE,
                                estimated = true,
                                craftingCost = cost,
                                costTimestamp = costTimestamp,
                                crafterUID = crafterUID,
                                costQualityID = costQualityID,
                            })
                            if not saved then
                                self:SetStatus(saveError)
                                return
                            end
                            savedResults[key] = true
                            resultCount = resultCount + 1
                            estimatedResultCount = estimatedResultCount + 1
                            if wasCapped then
                                cappedResultCount = cappedResultCount + 1
                            end
                            missingResult.estimatedPrice = estimatedPrice
                            missingResult.craftingCost = cost
                            missingResult.qualityID = tonumber(overrideTarget.qualityID)
                            missingResult.costQualityID = costQualityID
                            missingResult.estimateCapped = wasCapped
                        else
                            if ns.Compat.CraftSim:ClearEstimatedResultOverride(
                                    overrideTarget.recipeID, overrideTarget.qualityID, ESTIMATED_RESULT_SOURCE) then
                                clearedLegacyCount = clearedLegacyCount + 1
                            end
                            missingResult.estimateSkipped = true
                            skippedEstimateCount = skippedEstimateCount + 1
                        end
                    end
                end
            end
        end
    end

    ns.Compat.CraftSim:UpdateCraftSimUI()

    self.overridesPushed = true
    self:SetStatus(string.format(
        "Pushed %d reagent and %d result overrides (%d estimated); capped %d lower-rank prices; skipped %d estimates without cost.",
        globalCount, resultCount, estimatedResultCount, cappedResultCount, skippedEstimateCount))
    self:UpdateButtons()
    if self.missingPanel and self.missingPanel:IsShown() then
        self:UpdateMissingList()
    end
    SystemPrint(string.format(
        "Pushed %d reagent and %d result overrides (%d estimated); capped %d lower-rank prices; skipped %d estimates without cost%s.",
        globalCount, resultCount, estimatedResultCount, cappedResultCount, skippedEstimateCount,
        clearedLegacyCount > 0 and string.format("; cleared %d legacy 1c overrides", clearedLegacyCount) or ""))
end
