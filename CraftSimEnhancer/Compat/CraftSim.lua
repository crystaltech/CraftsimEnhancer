local _, ns = ...

local Compat = {}
ns.Compat.CraftSim = Compat

Compat.testedVersion = "26.1.10"
Compat.internalDependencies = {
    "CraftSim.CRAFTQ.craftQueue.craftQueueItems",
    "CraftSim.CRAFTQ:GetNonSoulboundAlternativeItemID",
    "CraftSim.CRAFTQ:GetItemCountFromCraftQueueCache",
    "CraftSim.CRAFTQ:CreateAuctionatorShoppingList",
    "CraftSim.DB.PRICE_OVERRIDE",
    "CraftSim.DB.LAST_CRAFTING_COST (missing-output estimates and break-even tooltips)",
    "CraftSim.CONST profession metadata and shopping-list name",
    "CraftSim.MODULES:UpdateUI",
    "CraftSimTSM:GetMinBuyoutByItemID",
}

function Compat:Initialize()
    if not ns.Compat.WoW:IsAddonLoaded("CraftSim") then
        return nil, "CraftSim is not loaded"
    end
    if type(CraftSimAPI) ~= "table" or type(CraftSimAPI.GetCraftSim) ~= "function" then
        return nil, "the documented CraftSimAPI:GetCraftSim function is unavailable"
    end

    local craftSim = CraftSimAPI:GetCraftSim()
    if type(craftSim) ~= "table" then
        return nil, "CraftSimAPI:GetCraftSim did not return the addon namespace"
    end
    self.craftSim = craftSim
    self.version = ns.Compat.WoW:GetAddonVersion("CraftSim") or "unknown"
    return true
end

function Compat:GetVersion()
    return self.version or ns.Compat.WoW:GetAddonVersion("CraftSim") or "unknown"
end

function Compat:GetCraftQueueItems()
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    local queue = queueModule and queueModule.craftQueue
    local items = queue and queue.craftQueueItems
    if type(items) ~= "table" then
        return nil, "CraftSim craft queue is not initialized"
    end
    return items
end

function Compat:GetNonSoulboundAlternativeItemID(itemID)
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if not queueModule or type(queueModule.GetNonSoulboundAlternativeItemID) ~= "function" then
        return nil, "CraftSim non-soulbound reagent helper is unavailable"
    end
    return queueModule:GetNonSoulboundAlternativeItemID(itemID)
end

function Compat:GetCraftQueueItemCount(crafterUID, itemID)
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if not queueModule or type(queueModule.GetItemCountFromCraftQueueCache) ~= "function" then
        return nil, "CraftSim queue inventory helper is unavailable"
    end
    return queueModule:GetItemCountFromCraftQueueCache(crafterUID, itemID)
end

function Compat:GetPlayerCrafterUID()
    local util = self.craftSim and self.craftSim.UTIL
    if util and type(util.GetPlayerCrafterUID) == "function" then
        return util:GetPlayerCrafterUID()
    end
    return ns.Compat.WoW:GetCrafterUID()
end

function Compat:GetAuctionatorShoppingListName()
    local constants = self.craftSim and self.craftSim.CONST
    local name = constants and constants.AUCTIONATOR_SHOPPING_LIST_QUEUE_NAME
    if type(name) ~= "string" then
        return nil, "CraftSim Auctionator shopping-list name is unavailable"
    end
    return name
end

function Compat:ResetQuickBuyCache()
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if queueModule and type(queueModule.ResetQuickBuyCache) == "function" then
        queueModule:ResetQuickBuyCache()
    end
end

function Compat:SaveGlobalOverride(data)
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.PRICE_OVERRIDE
    if not repository or type(repository.SaveGlobalOverride) ~= "function" then
        return nil, "CraftSim global price-override repository is unavailable"
    end
    repository:SaveGlobalOverride(data)
    return true
end

function Compat:SaveResultOverride(data)
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.PRICE_OVERRIDE
    if not repository or type(repository.SaveResultOverride) ~= "function" then
        return nil, "CraftSim result price-override repository is unavailable"
    end
    repository:SaveResultOverride(data)
    return true
end

---@param itemID number
---@param qualityID number
---@return number? cost
---@return number? timestamp
---@return string? crafterUID
---@return number? costQualityID
function Compat:GetLastCraftingCost(itemID, qualityID)
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.LAST_CRAFTING_COST
    if not repository then
        return nil
    end

    local crafterUID, cost, timestamp
    if type(repository.GetCheapestByItemIDAndQuality) == "function" then
        local success
        success, crafterUID, cost, timestamp = pcall(
            repository.GetCheapestByItemIDAndQuality, repository, itemID, qualityID)
        if success and tonumber(cost) and tonumber(cost) > 0 then
            return tonumber(cost), tonumber(timestamp), crafterUID, tonumber(qualityID)
        end
    end

    if type(repository.GetCheapestByItemID) == "function" then
        local success
        success, crafterUID, cost, timestamp = pcall(repository.GetCheapestByItemID, repository, itemID)
        if success and tonumber(cost) and tonumber(cost) > 0 then
            return tonumber(cost), tonumber(timestamp), crafterUID
        end
    end

    -- CraftSim stores ranked gear only at the quality produced by its latest
    -- recipe scan. Reuse the cheapest saved rank cost when the exact rank has
    -- not been recorded; it is still CraftSim's expected per-item cost for the
    -- same recipe output and avoids inventing material math here.
    if type(repository.GetCheapestByItemIDAndQuality) == "function" then
        local cheapestCost, cheapestTimestamp, cheapestCrafterUID, cheapestQualityID
        for candidateQualityID = 1, 5 do
            if candidateQualityID ~= tonumber(qualityID) then
                local success, candidateCrafterUID, candidateCost, candidateTimestamp = pcall(
                    repository.GetCheapestByItemIDAndQuality, repository, itemID, candidateQualityID)
                candidateCost = success and tonumber(candidateCost) or nil
                if candidateCost and candidateCost > 0 and
                    (not cheapestCost or candidateCost < cheapestCost) then
                    cheapestCost = candidateCost
                    cheapestTimestamp = tonumber(candidateTimestamp)
                    cheapestCrafterUID = candidateCrafterUID
                    cheapestQualityID = candidateQualityID
                end
            end
        end
        if cheapestCost then
            return cheapestCost, cheapestTimestamp, cheapestCrafterUID, cheapestQualityID
        end
    end

    return nil
end

---@param itemLink string?
---@param itemID number?
---@return number? cost
---@return number? timestamp
---@return string? crafterUID
function Compat:GetLastCraftingCostForTooltip(itemLink, itemID)
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.LAST_CRAFTING_COST
    if not repository then
        return nil
    end

    local getter
    local key
    if type(itemLink) == "string" and itemLink ~= "" and
        type(repository.GetCheapestByItemLink) == "function" then
        getter = repository.GetCheapestByItemLink
        key = itemLink
    elseif tonumber(itemID) and type(repository.GetCheapestByItemID) == "function" then
        getter = repository.GetCheapestByItemID
        key = tonumber(itemID)
    else
        return nil
    end

    local success, crafterUID, cost, timestamp = pcall(getter, repository, key)
    cost = success and tonumber(cost) or nil
    if not cost or cost <= 0 then
        return nil
    end
    return cost, tonumber(timestamp), crafterUID
end

---@param recipeID number
---@param qualityID number
---@param source string
---@return boolean cleared
function Compat:ClearEstimatedResultOverride(recipeID, qualityID, source)
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.PRICE_OVERRIDE
    if not repository or type(repository.GetResultOverride) ~= "function" or
        type(repository.DeleteResultOverride) ~= "function" then
        return false
    end

    local current = repository:GetResultOverride(recipeID, qualityID)
    if current and (current.source == source or tonumber(current.price) == 1) then
        repository:DeleteResultOverride(recipeID, qualityID)
        return true
    end
    return false
end

function Compat:UpdateCraftSimUI()
    local modules = self.craftSim and self.craftSim.MODULES
    if modules and type(modules.UpdateUI) == "function" then
        modules:UpdateUI()
    end
end

function Compat:GetProfessionLabel(professionEnum, fallback)
    local craftSim = self.craftSim
    local constants = craftSim and craftSim.CONST
    local label = fallback
    local localizationID = constants and constants.PROFESSION_LOCALIZATION_IDS and
        constants.PROFESSION_LOCALIZATION_IDS[professionEnum]
    if localizationID and craftSim.LOCAL and type(craftSim.LOCAL.GetText) == "function" then
        label = craftSim.LOCAL:GetText(localizationID)
    end
    local icon = constants and constants.PROFESSION_ICONS and constants.PROFESSION_ICONS[professionEnum]
    if icon then
        return string.format("|T%s:16:16|t %s", tostring(icon), tostring(label))
    end
    return tostring(label)
end

function Compat:GetTSMFallbackPrice(itemID, isReagent)
    if type(CraftSimTSM) ~= "table" or type(CraftSimTSM.GetMinBuyoutByItemID) ~= "function" then
        return nil
    end
    local success, price = pcall(CraftSimTSM.GetMinBuyoutByItemID, CraftSimTSM, itemID, isReagent)
    if success then
        return tonumber(price)
    end
end

function Compat:HookShoppingListCreated(callback)
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if not queueModule or type(queueModule.CreateAuctionatorShoppingList) ~= "function" then
        return nil, "CraftSim shopping-list creation function is unavailable"
    end
    hooksecurefunc(queueModule, "CreateAuctionatorShoppingList", callback)
    return true
end

function Compat:ValidateAuctionScanner()
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.PRICE_OVERRIDE
    if not repository or type(repository.SaveGlobalOverride) ~= "function" or
        type(repository.SaveResultOverride) ~= "function" then
        return nil, "CraftSim price overrides are unavailable"
    end
    return true
end

function Compat:ValidateBreakEvenTooltip()
    local repository = self.craftSim and self.craftSim.DB and self.craftSim.DB.LAST_CRAFTING_COST
    if not repository or type(repository.GetCheapestByItemLink) ~= "function" or
        type(repository.GetCheapestByItemID) ~= "function" then
        return nil, "CraftSim last-crafting-cost repository is unavailable"
    end
    return true
end

function Compat:ValidateVendorBuy()
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if not queueModule or type(queueModule.GetNonSoulboundAlternativeItemID) ~= "function" or
        type(queueModule.GetItemCountFromCraftQueueCache) ~= "function" then
        return nil, "required CraftSim craft-queue helpers are unavailable"
    end
    return true
end
