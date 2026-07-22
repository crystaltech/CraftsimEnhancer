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

function Compat:ValidateVendorBuy()
    local queueModule = self.craftSim and self.craftSim.CRAFTQ
    if not queueModule or type(queueModule.GetNonSoulboundAlternativeItemID) ~= "function" or
        type(queueModule.GetItemCountFromCraftQueueCache) ~= "function" then
        return nil, "required CraftSim craft-queue helpers are unavailable"
    end
    return true
end
