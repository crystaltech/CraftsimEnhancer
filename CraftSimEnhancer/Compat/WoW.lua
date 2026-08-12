local _, ns = ...

local WoW = {}
ns.Compat.WoW = WoW

-- The 12.1.0.69273 source surface is verified; keep this at the last completed
-- in-game compatibility checklist until the 12.1 smoke test passes.
WoW.testedInterface = 120007

function WoW:GetInterfaceVersion()
    local _, _, _, interfaceVersion = GetBuildInfo()
    return interfaceVersion
end

function WoW:IsAddonLoaded(name)
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then
        return false
    end
    local _, loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded == true
end

function WoW:GetAddonVersion(name)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(name, "Version")
    end
end

function WoW:GetCrafterUID()
    local playerName = UnitName("player") or "Player"
    local realmName = GetNormalizedRealmName() or GetRealmName() or "Realm"
    return tostring(playerName) .. "-" .. tostring(realmName)
end

function WoW:IsItemSoulbound(itemID)
    local bindType = select(14, C_Item.GetItemInfo(itemID))
    return bindType == Enum.ItemBind.OnAcquire
end

function WoW:GetMerchantItems()
    local items = {}
    if not GetMerchantNumItems or not GetMerchantItemLink or not C_MerchantFrame or
        not C_MerchantFrame.GetItemInfo then
        return nil, "merchant APIs are unavailable"
    end

    for index = 1, GetMerchantNumItems() do
        local info = C_MerchantFrame.GetItemInfo(index)
        local itemLink = GetMerchantItemLink(index)
        local itemID = itemLink and C_Item.GetItemInfoInstant(itemLink)
        if info and itemID and info.isPurchasable and not info.hasExtendedCost then
            items[itemID] = {
                index = index,
                name = info.name,
                price = info.price or 0,
                stackCount = math.max(1, info.stackCount or 1),
                numAvailable = info.numAvailable or -1,
            }
        end
    end
    return items
end

function WoW:GetBagItemCount(itemID)
    if not C_Item or type(C_Item.GetItemCount) ~= "function" then
        return nil, "C_Item.GetItemCount is unavailable"
    end

    local success, count = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
    if not success then
        return nil, tostring(count)
    end
    return math.max(0, math.floor(tonumber(count) or 0))
end

function WoW:BuyMerchantItem(index, quantity)
    if not BuyMerchantItem then
        return nil, "BuyMerchantItem is unavailable"
    end
    local success, buyError = pcall(BuyMerchantItem, index, quantity)
    if not success then
        return nil, tostring(buyError)
    end
    return true
end

function WoW:FormatMoney(copper)
    return GetMoneyString(math.max(0, tonumber(copper) or 0))
end

function WoW:OpenContextMenu(owner, generator)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        return nil, "Blizzard_Menu is unavailable"
    end
    return MenuUtil.CreateContextMenu(owner, generator)
end
