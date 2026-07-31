local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before targets")
local Config = Scanner.Shared.Config

function Scanner:AddOverrideTarget(target, overrideTarget)
    target.overrideMap = target.overrideMap or {}
    target.overrideTargets = target.overrideTargets or {}

    local key
    if overrideTarget.kind == "result" then
        key = "result:" .. tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
    else
        key = "global:" .. tostring(overrideTarget.itemID)
    end

    if target.overrideMap[key] then
        return
    end
    target.overrideMap[key] = true
    table.insert(target.overrideTargets, overrideTarget)
end

---@param sourceKind "input" | "output"
---@param overrideTarget table?
---@return "input" | "output" pricingMode
function Scanner:GetTargetPricingMode(sourceKind, overrideTarget)
    if sourceKind == "output" or (overrideTarget and overrideTarget.kind == "result") then
        return "output"
    end
    return "input"
end

---@param target table?
---@return boolean usesFillQuantity
function Scanner:TargetUsesFillQuantity(target)
    return target and target.pricingMode == "input"
end

---@param targetsByKey table<string, table>
---@param targets table[]
---@param itemID number?
---@param itemLevel number?
---@param label string?
---@param overrideTarget table
---@param sourceKind "input" | "output"
---@param profession string?
---@param sourceName string?
---@param sourceData table?
---@return table?
function Scanner:AddScanTarget(targetsByKey, targets, itemID, itemLevel, label, overrideTarget, sourceKind, profession,
                               sourceName, sourceData)
    itemID = tonumber(itemID)
    if not itemID then
        return nil
    end

    local scanInfo = self:GetItemScanInfo(itemID)
    if scanInfo.skip then
        return nil
    end

    itemLevel = tonumber(itemLevel) or 0
    local pricingMode = self:GetTargetPricingMode(sourceKind, overrideTarget)
    local key = self:GetTargetKey(itemID, itemLevel, pricingMode)
    local target = targetsByKey[key]
    if not target then
        local queryItemLevel = itemLevel
        if pricingMode == "output" and itemLevel > 0 then
            queryItemLevel = 0
        end
        target = {
            key = key,
            itemID = itemID,
            itemLevel = itemLevel,
            queryItemLevel = queryItemLevel,
            pricingMode = pricingMode,
            itemKey = self:MakeItemKey(itemID, queryItemLevel),
            label = label or ("Item " .. tostring(itemID)),
            moreRequests = 0,
            sourceCount = 0,
        }
        targetsByKey[key] = target
        table.insert(targets, target)
    end

    self:AddTargetMetadata(target, itemID)
    if sourceData and sourceData.isCommodity == true then
        target.isCommodity = true
    end
    if target.isCommodity == true then
        target.resultType = "commodity"
    else
        target.resultType = target.resultType or self:GetAuctionResultType(itemID, target)
    end
    self:AddTargetSource(target, sourceKind, profession, sourceName, overrideTarget and overrideTarget.recipeID)
    self:AddOverrideTarget(target, overrideTarget)
    return target
end

---@param itemID number?
---@param price number?
---@param label string?
---@param overrideTarget table
function Scanner:AddFixedPriceResult(itemID, price, label, overrideTarget)
    itemID = tonumber(itemID)
    price = tonumber(price)
    if not itemID or not price or price <= 0 then
        return
    end

    self.fixedResultsByKey = self.fixedResultsByKey or {}

    local roundedPrice = math.floor(price + 0.5)
    local key = tostring(itemID) .. ":" .. tostring(roundedPrice)
    local result = self.fixedResultsByKey[key]
    if not result then
        result = {
            itemID = itemID,
            itemLevel = 0,
            label = label or ("Item " .. tostring(itemID)),
            price = roundedPrice,
            source = "Vendor",
            quantityUsed = 0,
            listedQuantity = 0,
            trimmedUnits = 0,
            overrideTargets = {},
            overrideMap = {},
        }
        self.fixedResultsByKey[key] = result
        table.insert(self.priceResults, result)
    end
    self:AddOverrideTarget(result, overrideTarget)
end

---@param qualityMap table<number, number>
---@param rankCount number?
---@param callback fun(qualityID: number, itemID: number)
local function ForEachQualityItem(qualityMap, rankCount, callback)
    if not qualityMap then
        return
    end

    local seen = {}
    local maxRank = tonumber(rankCount) or #qualityMap
    for qualityID = 1, maxRank do
        local itemID = qualityMap[qualityID]
        if itemID then
            seen[qualityID] = true
            callback(qualityID, itemID)
        end
    end

    for qualityID, itemID in pairs(qualityMap) do
        if not seen[qualityID] and tonumber(qualityID) then
            callback(tonumber(qualityID), itemID)
        end
    end
end

---@param output table
---@param qualityID number?
---@return number itemLevel
function Scanner:GetOutputItemLevel(output, qualityID)
    if not output or output.isCommodity == true then
        return 0
    end

    if qualityID and output.rankItemLevels then
        return tonumber(output.rankItemLevels[qualityID]) or tonumber(output.baseItemLevel) or 0
    end

    if qualityID and output.rankItemLevelDeltas then
        local baseItemLevel = tonumber(output.baseItemLevel)
        local rankDelta = tonumber(output.rankItemLevelDeltas[qualityID])
        if baseItemLevel and rankDelta then
            return baseItemLevel + rankDelta
        end
    end

    return tonumber(output.baseItemLevel) or 0
end

---@param recipe table
---@param output table
---@param targetsByKey table<string, table>
---@param targets table[]
---@return boolean added
function Scanner:AddOutputTargets(recipe, output, targetsByKey, targets)
    if output.auctionSellable == false or not recipe.recipeID then
        return false
    end

    local added = false
    if output.rankItemIDs then
        ForEachQualityItem(output.rankItemIDs, output.rankCount, function(qualityID, itemID)
            -- The item ID already identifies the quality.  Filtering these
            -- results by generated item level can hide valid listings when
            -- Blizzard changes an expansion's item-level scale.
            added = self:AddScanTarget(targetsByKey, targets, itemID, 0, output.itemRef, {
                kind = "result",
                recipeID = recipe.recipeID,
                itemID = itemID,
                qualityID = qualityID,
            }, "output", recipe.profession, recipe.stratName, output) ~= nil or added
        end)
        return added
    end

    if output.rankBonusIDs and output.itemIDs and output.itemIDs[1] then
        local rankCount = tonumber(output.rankCount) or #(output.rankItemLevels or {})
        for qualityID = 1, rankCount do
            local itemID = output.itemIDs[1]
            local itemLevel = self:GetOutputItemLevel(output, qualityID)
            local target = self:AddScanTarget(targetsByKey, targets, itemID, itemLevel, output.itemRef, {
                kind = "result",
                recipeID = recipe.recipeID,
                itemID = itemID,
                qualityID = qualityID,
            }, "output", recipe.profession, recipe.stratName, output)
            if target then
                target.requiredBonusIDs = output.rankBonusIDs[qualityID]
                target.outputQualityID = qualityID
                target.rankItemLevelDeltas = output.rankItemLevelDeltas
                target.rankBonusIDsByQuality = output.rankBonusIDs
                added = true
            end
        end
        return added
    end

    for qualityID, itemID in ipairs(output.itemIDs or {}) do
        -- Unranked outputs (bags are a common example) use a broad item key.
        -- Their AH result itemKey may report item level zero even when the
        -- generated recipe data has a base item level.
        added = self:AddScanTarget(targetsByKey, targets, itemID, 0, output.itemRef, {
            kind = "result",
            recipeID = recipe.recipeID,
            itemID = itemID,
            qualityID = qualityID,
        }, "output", recipe.profession, recipe.stratName, output) ~= nil or added
    end
    return added
end

---@param recipe table
---@param reagent table
---@param targetsByKey table<string, table>
---@param targets table[]
---@param options table?
function Scanner:AddReagentTargets(recipe, reagent, targetsByKey, targets, options)
    options = options or {}
    local vendorItemID = tonumber(reagent.vendorItemID)

    local function addReagent(itemID, qualityID)
        itemID = tonumber(itemID)
        if not itemID then
            return
        end

        local overrideTarget = {
            kind = "global",
            recipeID = recipe.recipeID or 0,
            itemID = itemID,
            qualityID = qualityID,
        }

        local scanInfo = self:GetItemScanInfo(itemID, reagent)
        local vendorPriceCopper = tonumber(scanInfo.vendorPriceCopper)
        local hasFixedVendorPrice = scanInfo.vendorSold and vendorPriceCopper and vendorPriceCopper > 0 and
            (not vendorItemID or vendorItemID == itemID)
        if hasFixedVendorPrice then
            if not options.skipFixedPrices then
                self:AddFixedPriceResult(itemID, vendorPriceCopper, reagent.itemRef, overrideTarget)
            end
        elseif scanInfo.skip then
            return
        else
            self:AddScanTarget(targetsByKey, targets, itemID, 0, reagent.itemRef, overrideTarget, "input",
                recipe.profession, recipe.stratName, reagent)
        end
    end

    if reagent.rankItemIDs then
        ForEachQualityItem(reagent.rankItemIDs, reagent.rankCount, function(qualityID, itemID)
            addReagent(itemID, qualityID)
        end)
    else
        for index, itemID in ipairs(reagent.itemIDs or {}) do
            addReagent(itemID, reagent.rankCount and index or nil)
        end
    end
end

---@param targets table[]
---@param options table?
function Scanner:ApplyLegacyTargetSelectionCompatibility(targets, options)
    local skippedTargets = Config:GetSkippedTargets()
    local migratedLegacyKeys = {}

    for _, target in ipairs(targets or {}) do
        local legacyKey = tostring(target.itemID) .. ":" .. tostring(tonumber(target.itemLevel) or 0)
        if skippedTargets[legacyKey] == true then
            skippedTargets[target.key] = skippedTargets[target.key] or true
            migratedLegacyKeys[legacyKey] = true
        end
    end

    if options and options.includeAllProfessions then
        for legacyKey in pairs(migratedLegacyKeys) do
            skippedTargets[legacyKey] = nil
        end
    end
end

---@param options table?
---@return table[]? targets
---@return string? errorMessage
function Scanner:BuildScanTargets(options)
    options = options or {}

    local recipes = self:GetGeneratedRecipes()
    if #recipes == 0 then
        return nil, "No generated recipe data is loaded."
    end

    local selectedProfessions = self:GetSelectedProfessions()
    local selectedCount = 0
    if not options.includeAllProfessions and not options.profession then
        for _, professionInfo in ipairs(self.PROFESSIONS) do
            if selectedProfessions[professionInfo.name] then
                selectedCount = selectedCount + 1
            end
        end

        if selectedCount == 0 then
            return nil, "Select at least one profession."
        end
    end

    local targetsByKey = {}
    local targets = {}

    for _, recipe in ipairs(recipes) do
        local includeProfession = recipe.profession and
            (options.includeAllProfessions or options.profession == recipe.profession or selectedProfessions[recipe.profession])
        if includeProfession then
            local hasScannableOutput = false
            for _, output in ipairs(recipe.outputs or {}) do
                hasScannableOutput = self:AddOutputTargets(recipe, output, targetsByKey, targets) or hasScannableOutput
            end
            if hasScannableOutput then
                for _, reagent in ipairs(recipe.reagents or {}) do
                    self:AddReagentTargets(recipe, reagent, targetsByKey, targets, {
                        skipFixedPrices = options.skipFixedPrices,
                    })
                end
            end
        end
    end

    self:ApplyLegacyTargetSelectionCompatibility(targets, options)

    table.sort(targets, function(a, b)
        return tostring(a.label or a.itemID) < tostring(b.label or b.itemID)
    end)

    if not options.ignoreSavedFilter then
        targets = ns.Filter(targets, function(target)
            return Config:IsTargetSelected(target.key)
        end)
    end

    return targets
end
