local _, ns = ...

local Config = ns.Config.AuctionHouseScan
local Scanner = {}
local EVENTS = {
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    "AUCTION_HOUSE_NEW_RESULTS_RECEIVED",
    "COMMODITY_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_RECEIVED",
    "ITEM_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED",
}

local MIN_QUERY_INTERVAL = 0.65
local PENDING_TIMEOUT_SECONDS = 10
local MAX_MORE_RESULT_REQUESTS = 5
local GENERIC_RESULT_GRACE_SECONDS = 1.0
local AUCTION_HOUSE_CUT = 0.05
local ESTIMATED_RESULT_SOURCE = "Estimated — no auctions"
local AUCTION_HOUSE_TAB_ID = "CraftSimEnhancerAuctionHouseScan"
local AUCTION_HOUSE_TAB_PADDING = 20
local AUCTION_HOUSE_TAB_MIN_WIDTH = 70
local SMALL_AUCTION_HOUSE_TAB_PADDING = 0
local SMALL_AUCTION_HOUSE_TAB_MIN_WIDTH = 36
local NATIVE_ROCK_TEXTURE = "Interface\\FrameGeneral\\UI-Background-Rock"
local NATIVE_INSET_BACKDROP = {
    bgFile = NATIVE_ROCK_TEXTURE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 128,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local NATIVE_LIST_BACKDROP = {
    bgFile = NATIVE_ROCK_TEXTURE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 128,
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

Scanner.button = nil
Scanner.panel = nil
Scanner.configPanel = nil
Scanner.missingPanel = nil
Scanner.missingExportPanel = nil
Scanner.tabLibrary = nil
Scanner.usesTabLibrary = false
Scanner.displayModeHooked = false
Scanner.activeView = "config"
Scanner.professionCheckboxes = {}
Scanner.configRows = {}
Scanner.configTargets = {}
Scanner.recipeRows = {}
Scanner.configView = "recipes"
Scanner.expandedProfessionGroups = {}
Scanner.expandedCategoryGroups = {}
Scanner.missingRows = {}
Scanner.itemSearchText = ""
Scanner.showSelectedItemsOnly = false
Scanner.isScanning = false
Scanner.scanComplete = false
Scanner.overridesPushed = false
Scanner.scanTargets = {}
Scanner.scanIndex = 0
Scanner.completedTargets = 0
Scanner.totalTargets = 0
Scanner.priceResults = {}
Scanner.missingResults = {}
Scanner.fixedResultsByKey = {}
Scanner.outputItemRowsCache = {}
Scanner.pendingQuery = nil
Scanner.pendingTimeoutToken = 0
Scanner.pendingPollToken = 0
Scanner.nextQueryTime = 0

Scanner.PROFESSIONS = {
    { name = "Alchemy",        enum = Enum.Profession.Alchemy },
    { name = "Blacksmithing",  enum = Enum.Profession.Blacksmithing },
    { name = "Cooking",        enum = Enum.Profession.Cooking },
    { name = "Enchanting",     enum = Enum.Profession.Enchanting },
    { name = "Engineering",    enum = Enum.Profession.Engineering },
    { name = "Inscription",    enum = Enum.Profession.Inscription },
    { name = "Jewelcrafting",  enum = Enum.Profession.Jewelcrafting },
    { name = "Leatherworking", enum = Enum.Profession.Leatherworking },
    { name = "Tailoring",      enum = Enum.Profession.Tailoring },
}

Scanner.SCAN_SCOPES = {
    PRODUCTS = "PRODUCTS",
    REAGENTS = "REAGENTS",
    BOTH = "BOTH",
}

Scanner.MANUAL_ITEM_OVERRIDES = {
    [245345] = { vendorSold = true, vendorPriceCopper = 10000 },
    [274267] = { vendorSold = true, vendorPriceCopper = 10000 },
    [256963] = { skip = true, skipReason = "Bind-on-pickup reagent is not auction-sellable." },
}

local PTR_NEXT_PATCH_ITEM_IDS = {
    271889,
    271890,
    273056,
    273057,
    273062,
    273063,
    273065,
    273066,
    273068,
    273069,
    274591,
    275266,
    275276,
    275278,
    275303,
    279360,
    279361,
    279363,
    279364,
    279365,
    279366,
    279367,
    279368,
    279369,
    279370,
    279371,
    279372,
    279373,
    279375,
    279376,
}

for _, itemID in ipairs(PTR_NEXT_PATCH_ITEM_IDS) do
    Scanner.MANUAL_ITEM_OVERRIDES[itemID] = {
        skip = true,
        skipReason = "PTR/next-patch item is not available in live Auction House data yet.",
    }
end

local WARBOUND_ITEM_IDS = {
    244755,
    244756,
    244757,
    244758,
    244759,
    244760,
    244761,
    244762,
    244767,
    244768,
    244769,
    244770,
}

for _, itemID in ipairs(WARBOUND_ITEM_IDS) do
    Scanner.MANUAL_ITEM_OVERRIDES[itemID] = {
        auctionSellable = false,
        skip = true,
        skipReason = "Bind-to-Warband item is not auction-sellable.",
    }
end

local REMOVED_TEST_ITEM_IDS = {
    206023,
    206024,
    275321,
    275329,
    275339,
}

for _, itemID in ipairs(REMOVED_TEST_ITEM_IDS) do
    Scanner.MANUAL_ITEM_OVERRIDES[itemID] = {
        auctionSellable = false,
        skip = true,
        skipReason = "Removed/test item is not available in game.",
    }
end

local function SetButtonEnabled(button, enabled)
    if not button then
        return
    end
    if button.SetEnabled then
        button:SetEnabled(enabled)
    elseif enabled then
        button:Enable()
    else
        button:Disable()
    end
end

---@param parent Frame
---@param width number
---@param height number?
---@return Button
local function CreateNativeActionButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    return button
end

---@param parent Frame
---@param height number?
---@return Frame
local function CreateNativeHeaderBand(parent, height)
    local band = CreateFrame("Frame", nil, parent)
    band:SetFrameLevel(parent:GetFrameLevel() or 1)
    band:SetHeight(height or 38)
    band.bottomLine = band:CreateTexture(nil, "BORDER")
    band.bottomLine:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 5, 0)
    band.bottomLine:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -5, 0)
    band.bottomLine:SetHeight(1)
    band.bottomLine:SetColorTexture(0.48, 0.43, 0.32, 0.34)
    return band
end

---@param parent Frame
---@return Frame
local function CreateNativeListWell(parent)
    local well = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    well:SetFrameLevel(parent:GetFrameLevel() or 1)
    well:SetBackdrop(NATIVE_LIST_BACKDROP)
    well:SetBackdropColor(0.60, 0.59, 0.56, 0.96)
    well:SetBackdropBorderColor(0.26, 0.25, 0.23, 0.84)

    well.shadowTop = well:CreateTexture(nil, "BORDER")
    well.shadowTop:SetPoint("TOPLEFT", well, "TOPLEFT", 5, -4)
    well.shadowTop:SetPoint("TOPRIGHT", well, "TOPRIGHT", -5, -4)
    well.shadowTop:SetHeight(2)
    well.shadowTop:SetColorTexture(0.03, 0.03, 0.03, 0.42)

    well.shadowTopFade = well:CreateTexture(nil, "BORDER")
    well.shadowTopFade:SetPoint("TOPLEFT", well.shadowTop, "BOTTOMLEFT", 0, 0)
    well.shadowTopFade:SetPoint("TOPRIGHT", well.shadowTop, "BOTTOMRIGHT", 0, 0)
    well.shadowTopFade:SetHeight(3)
    well.shadowTopFade:SetColorTexture(0.03, 0.03, 0.03, 0.16)

    well.shadowLeft = well:CreateTexture(nil, "BORDER")
    well.shadowLeft:SetPoint("TOPLEFT", well, "TOPLEFT", 4, -5)
    well.shadowLeft:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 4, 5)
    well.shadowLeft:SetWidth(2)
    well.shadowLeft:SetColorTexture(0.03, 0.03, 0.03, 0.42)

    well.shadowLeftFade = well:CreateTexture(nil, "BORDER")
    well.shadowLeftFade:SetPoint("TOPLEFT", well.shadowLeft, "TOPRIGHT", 0, 0)
    well.shadowLeftFade:SetPoint("BOTTOMLEFT", well.shadowLeft, "BOTTOMRIGHT", 0, 0)
    well.shadowLeftFade:SetWidth(3)
    well.shadowLeftFade:SetColorTexture(0.03, 0.03, 0.03, 0.16)

    well.innerBevelBottom = well:CreateTexture(nil, "BORDER")
    well.innerBevelBottom:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 5, 4)
    well.innerBevelBottom:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -5, 4)
    well.innerBevelBottom:SetHeight(1)
    well.innerBevelBottom:SetColorTexture(0.72, 0.67, 0.56, 0.16)

    well.innerBevelRight = well:CreateTexture(nil, "BORDER")
    well.innerBevelRight:SetPoint("TOPRIGHT", well, "TOPRIGHT", -4, -5)
    well.innerBevelRight:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -4, 5)
    well.innerBevelRight:SetWidth(1)
    well.innerBevelRight:SetColorTexture(0.72, 0.67, 0.56, 0.12)
    return well
end

---@param message string
local function SystemPrint(message)
    ns:Print("AH Scan: " .. tostring(message))
end

---@param itemID number
---@param itemLevel number?
---@return ItemKey
function Scanner:MakeItemKey(itemID, itemLevel)
    itemLevel = tonumber(itemLevel) or 0
    if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
        return C_AuctionHouse.MakeItemKey(itemID, itemLevel, 0, 0)
    end
    return {
        itemID = itemID,
        itemLevel = itemLevel,
        itemSuffix = 0,
        battlePetSpeciesID = 0,
    }
end

---@param itemID number
---@return ItemKey
function Scanner:MakeClearedItemKey(itemID)
    local itemKey = self:MakeItemKey(itemID, 0)
    -- MakeItemKey can normalize level zero to the item's base level. Blizzard's
    -- by-item search requires these fields to be explicitly cleared, just as
    -- AuctionHouseUtil.ConvertItemSellItemKey does in the base UI.
    itemKey.itemLevel = 0
    itemKey.itemSuffix = 0
    return itemKey
end

---@param itemKey ItemKey?
---@return ItemKey?
function Scanner:CopyItemKey(itemKey)
    if not itemKey then
        return nil
    end
    return {
        itemID = tonumber(itemKey.itemID) or 0,
        itemLevel = tonumber(itemKey.itemLevel) or 0,
        itemSuffix = tonumber(itemKey.itemSuffix) or 0,
        battlePetSpeciesID = tonumber(itemKey.battlePetSpeciesID) or 0,
    }
end

---@param target table?
---@return boolean
function Scanner:ShouldUseBroadItemSearch(target)
    if not target or target.resultType ~= "item" then
        return false
    end

    -- Blizzard's sell-search path is the supported way to compare equipment
    -- by item ID. A normal level-zero search is normalized to one concrete
    -- item-level bucket and can therefore miss the other crafted ranks.
    if target.requiredBonusIDs then
        return true
    end

    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, itemKeyInfo = pcall(C_AuctionHouse.GetItemKeyInfo,
            self:MakeItemKey(target.itemID, 0), false)
        return ok and itemKeyInfo and itemKeyInfo.isEquipment == true
    end
    return false
end

---@param target table?
---@return ItemKey?
function Scanner:GetTargetItemResultKey(target)
    if not target then
        return nil
    end
    return target.resultItemKey or target.itemSearchKey or self:GetTargetQueryItemKey(target)
end

---@param target table
---@param itemKey ItemKey
function Scanner:CaptureItemResultKey(target, itemKey)
    if not target or not itemKey then
        return
    end
    target.resultItemKey = self:CopyItemKey(itemKey)
end

---@param itemLink string?
---@param requiredBonusIDs number[]?
---@return boolean? matches nil when the link cannot be inspected
function Scanner:ItemLinkMatchesBonusIDs(itemLink, requiredBonusIDs)
    if type(itemLink) ~= "string" or type(requiredBonusIDs) ~= "table" or not requiredBonusIDs[1] then
        return nil
    end

    local itemString = string.match(itemLink, "|Hitem:([^|]+)|h") or string.match(itemLink, "^item:(.+)")
    if not itemString then
        return nil
    end

    local fields = {}
    for field in string.gmatch(itemString .. ":", "(.-):") do
        table.insert(fields, field)
    end

    local bonusCount = tonumber(fields[13])
    if not bonusCount then
        return nil
    end

    local bonuses = {}
    for index = 1, bonusCount do
        local bonusID = tonumber(fields[13 + index])
        if bonusID then
            bonuses[bonusID] = true
        end
    end

    for _, requiredBonusID in ipairs(requiredBonusIDs) do
        if bonuses[tonumber(requiredBonusID)] then
            return true
        end
    end
    return false
end

---@param itemLink string?
---@param rankBonusIDs table<number, number[]>?
---@return number? qualityID
function Scanner:GetQualityIDFromItemLink(itemLink, rankBonusIDs)
    if type(itemLink) ~= "string" or type(rankBonusIDs) ~= "table" then
        return nil
    end
    for qualityID, requiredBonusIDs in pairs(rankBonusIDs) do
        if self:ItemLinkMatchesBonusIDs(itemLink, requiredBonusIDs) == true then
            return tonumber(qualityID)
        end
    end
    return nil
end

---@param target table
---@param rawRows table[]
---@return table<number, number>? itemLevelsByQuality
function Scanner:InferRankItemLevels(target, rawRows)
    local deltas = target and target.rankItemLevelDeltas
    if type(deltas) ~= "table" or type(rawRows) ~= "table" then
        return nil
    end

    local levels = {}
    local levelSet = {}
    local directQualityLevels = {}
    local candidateBases = {}
    for _, row in ipairs(rawRows) do
        local itemLevel = tonumber(row.itemKey and row.itemKey.itemLevel)
        if itemLevel and itemLevel > 0 then
            if not levelSet[itemLevel] then
                levelSet[itemLevel] = true
                table.insert(levels, itemLevel)
            end

            local linkedQualityID = self:GetQualityIDFromItemLink(row.itemLink, target.rankBonusIDsByQuality)
            local linkedDelta = linkedQualityID and tonumber(deltas[linkedQualityID])
            if linkedQualityID and linkedDelta then
                directQualityLevels[linkedQualityID] = itemLevel
                candidateBases[itemLevel - linkedDelta] = true
            end

            for _, rankDeltaValue in pairs(deltas) do
                local rankDelta = tonumber(rankDeltaValue)
                if rankDelta then
                    candidateBases[itemLevel - rankDelta] = true
                end
            end
        end
    end

    if #levels == 0 then
        return nil
    end

    local bestBase
    local bestBonusMatches = -1
    local bestLevelMatches = -1
    local bestIsTied = false
    for candidateBase in pairs(candidateBases) do
        local bonusMatches = 0
        for qualityID, itemLevel in pairs(directQualityLevels) do
            local rankDelta = tonumber(deltas[qualityID])
            if rankDelta and candidateBase + rankDelta == itemLevel then
                bonusMatches = bonusMatches + 1
            end
        end

        local levelMatches = 0
        for _, rankDeltaValue in pairs(deltas) do
            local rankDelta = tonumber(rankDeltaValue)
            if rankDelta and levelSet[candidateBase + rankDelta] then
                levelMatches = levelMatches + 1
            end
        end

        if bonusMatches > bestBonusMatches or
            (bonusMatches == bestBonusMatches and levelMatches > bestLevelMatches) then
            bestBase = candidateBase
            bestBonusMatches = bonusMatches
            bestLevelMatches = levelMatches
            bestIsTied = false
        elseif bonusMatches == bestBonusMatches and levelMatches == bestLevelMatches and candidateBase ~= bestBase then
            bestIsTied = true
        end
    end

    -- A bonus-ID match identifies a rank directly. Without links, require at
    -- least two item levels to agree on one delta pattern; a lone item level
    -- cannot safely identify which quality it represents.
    if not bestBase or (bestBonusMatches <= 0 and (bestLevelMatches < 2 or bestIsTied)) then
        if next(directQualityLevels) then
            return directQualityLevels
        end
        return nil
    end

    local itemLevelsByQuality = {}
    for qualityIDValue, rankDeltaValue in pairs(deltas) do
        local qualityID = tonumber(qualityIDValue)
        local rankDelta = tonumber(rankDeltaValue)
        if qualityID and rankDelta then
            itemLevelsByQuality[qualityID] = bestBase + rankDelta
        end
    end
    for qualityID, itemLevel in pairs(directQualityLevels) do
        itemLevelsByQuality[qualityID] = itemLevel
    end
    return itemLevelsByQuality
end

---@param target table?
---@return ItemKey?
function Scanner:GetTargetQueryItemKey(target)
    if not target then
        return nil
    end
    return target.activeItemKey or target.itemKey
end

---@return AuctionHouseSortType[]
function Scanner:GetSearchSorts()
    if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
        return {
            { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
        }
    end
    return {}
end

---@param professionInfo table
---@return string
function Scanner:GetProfessionDisplayName(professionInfo)
    local label = ns.Compat.CraftSim:GetProfessionLabel(professionInfo.enum, professionInfo.name)
    local displayName = string.gsub(label, "|T.-|t%s*", "")
    return displayName
end

---@param professionInfo table
---@return string
function Scanner:GetProfessionLabel(professionInfo)
    return ns.Compat.CraftSim:GetProfessionLabel(professionInfo.enum, professionInfo.name)
end

---@return table[] recipes
function Scanner:GetGeneratedRecipes()
    return ns.Data.GeneratedRecipes or {}
end

---@param itemID number
---@return table?
function Scanner:GetItemMetadata(itemID)
    local metadata = ns.Data.ItemMetadata
    if not metadata then
        return nil
    end
    return metadata[tonumber(itemID)]
end

---@param itemID number
---@param reagent table?
---@return table
function Scanner:GetItemScanInfo(itemID, reagent)
    itemID = tonumber(itemID)
    local metadata = itemID and self:GetItemMetadata(itemID) or nil
    local manual = (itemID and self.MANUAL_ITEM_OVERRIDES[itemID]) or {}
    local vendorPriceCopper = tonumber(manual.vendorPriceCopper)
        or tonumber(reagent and reagent.vendorPriceCopper)
        or tonumber(metadata and metadata.vendorPriceCopper)
    local vendorSold = manual.vendorSold == true
        or (reagent and reagent.vendorSold == true)
        or (metadata and metadata.vendorSold == true)
    local auctionSellable = true
    if metadata and metadata.auctionSellable == false then
        auctionSellable = false
    end
    if manual.auctionSellable == false then
        auctionSellable = false
    end

    local skip = manual.skip == true or (auctionSellable == false and not vendorSold)
    local skipReason = manual.skipReason
    if not skipReason and skip then
        skipReason = "Item is not auction-sellable."
    end

    return {
        vendorSold = vendorSold,
        vendorPriceCopper = vendorPriceCopper,
        auctionSellable = auctionSellable,
        skip = skip,
        skipReason = skipReason,
    }
end

---@param itemID number
---@param itemLevel number?
---@param pricingMode "input" | "output"?
---@return string
function Scanner:GetTargetKey(itemID, itemLevel, pricingMode)
    return tostring(itemID) .. ":" .. tostring(tonumber(itemLevel) or 0) .. ":" .. tostring(pricingMode or "input")
end

---@param target table
---@param itemID number
function Scanner:AddTargetMetadata(target, itemID)
    local metadata = self:GetItemMetadata(itemID)
    if not metadata then
        return
    end

    target.itemMetadata = target.itemMetadata or metadata
    target.itemClassID = target.itemClassID or metadata.itemClassID
    target.itemClass = target.itemClass or metadata.itemClass
    target.itemSubClassID = target.itemSubClassID or metadata.itemSubClassID
    target.itemSubClass = target.itemSubClass or metadata.itemSubClass
    target.inventoryType = target.inventoryType or metadata.inventoryType
    if metadata.isCommodity == true then
        target.isCommodity = true
    end
    target.categoryTags = target.categoryTags or {}

    for _, tag in ipairs(metadata.categoryTags or {}) do
        self:AddTargetCategoryTag(target, tag)
    end
end

---@param itemID number
---@param target table?
---@return "commodity" | "item" | nil
function Scanner:GetAuctionResultType(itemID, target)
    if target and target.isCommodity == true then
        return "commodity"
    end

    local metadata = target and target.itemMetadata or self:GetItemMetadata(itemID)
    if metadata and metadata.isCommodity == true then
        return "commodity"
    end

    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local itemKey = target and target.itemKey or self:MakeItemKey(itemID, 0)
        local ok, itemKeyInfo = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey, false)
        if ok and itemKeyInfo then
            if itemKeyInfo.isCommodity == true then
                return "commodity"
            elseif itemKeyInfo.isEquipment == true or itemKeyInfo.battlePetLink then
                return "item"
            end
        end
    end

    if not metadata then
        return nil
    end

    local classID = tonumber(metadata.itemClassID)
    if classID == 0 or classID == 3 or classID == 5 or classID == 7 or classID == 8 then
        return "commodity"
    end

    return "item"
end

---@param target table?
---@return boolean
function Scanner:IsLikelyCommodityTarget(target)
    if not target then
        return false
    end
    if target.resultType == "commodity" then
        return true
    end
    if target.isCommodity == true then
        return true
    end

    local classID = tonumber(target.itemClassID)
    return classID == 0 or classID == 3 or classID == 5 or classID == 7 or classID == 8
end

---@return boolean
function Scanner:IsAuctionThrottleReady()
    return not (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and
        not C_AuctionHouse.IsThrottledMessageSystemReady())
end

---@param target table?
---@return boolean
function Scanner:CanTryItemLevelFallback(target)
    return target and target.pricingMode ~= "output" and not target.itemLevelFallbackSent and target.itemLevel and
        target.itemLevel > 0 and
        C_AuctionHouse and C_AuctionHouse.SendSearchQuery
end

---@param target table?
---@return boolean
function Scanner:CanTrySellSearchFallback(target)
    return target and not target.sellSearchFallbackSent and self:IsLikelyCommodityTarget(target) and
        C_AuctionHouse and C_AuctionHouse.SendSellSearchQuery
end

---@param target table
---@param tag string?
function Scanner:AddTargetCategoryTag(target, tag)
    if not target or not tag or tag == "" then
        return
    end
    target.categoryTags = target.categoryTags or {}
    target.categoryTags[tag] = true
end

---@param target table
---@param sourceName string?
function Scanner:AddSourceNameCategoryTags(target, sourceName)
    local text = string.lower(tostring(sourceName or ""))
    if text == "" then
        return
    end
    local paddedText = " " .. text .. " "

    local function add(tag)
        self:AddTargetCategoryTag(target, tag)
    end

    if self:TextMatchesAny(text, { "transmute", "transmutation" }) then
        add("transform")
        add("transmute")
    end
    if string.find(text, "milling", 1, true) then
        add("transform")
        add("milling")
    end
    if string.find(text, "prospect", 1, true) then
        add("transform")
        add("prospecting")
    end
    if string.find(paddedText, " shatter ", 1, true) then
        add("transform")
        add("shatter")
    end
    if string.find(text, "contract:", 1, true) then
        add("contract")
    end
    if string.find(text, "darkmoon", 1, true) then
        add("darkmoon_card")
    end
    if string.find(text, "vantus rune", 1, true) then
        add("raid_consumable")
        add("vantus_rune")
    end
    if string.find(text, "armor kit", 1, true) then
        add("item_enhancement")
        add("armor_kit")
    end
    if string.find(text, "spellthread", 1, true) then
        add("item_enhancement")
        add("spellthread")
    end
    if string.find(text, "weapon wrap", 1, true) then
        add("temporary_enhancement")
        add("weapon_wrap")
    end
end

---@param target table
---@param sourceKind "input" | "output"
---@param profession string?
---@param sourceName string?
---@param recipeID number?
function Scanner:AddTargetSource(target, sourceKind, profession, sourceName, recipeID)
    target.kindMap = target.kindMap or {}
    target.professionMap = target.professionMap or {}
    target.sourceNames = target.sourceNames or {}
    target.sourceNamesByProfession = target.sourceNamesByProfession or {}
    target.sourceRecipeMap = target.sourceRecipeMap or {}
    target.sourceRecipeKindMap = target.sourceRecipeKindMap or {}

    target.kindMap[sourceKind] = true
    target.sourceRecipeKindMap[sourceKind] = target.sourceRecipeKindMap[sourceKind] or {}
    if profession then
        target.professionMap[profession] = true
        target.sourceNamesByProfession[profession] = target.sourceNamesByProfession[profession] or {}
    end
    if sourceName and sourceName ~= "" and not target.sourceNames[sourceName] then
        target.sourceNames[sourceName] = true
        target.sourceCount = (target.sourceCount or 0) + 1
    end
    if profession and sourceName and sourceName ~= "" then
        target.sourceNamesByProfession[profession][sourceName] = true
    end
    self:AddSourceNameCategoryTags(target, sourceName)

    recipeID = tonumber(recipeID)
    if recipeID and recipeID > 0 then
        target.sourceRecipeMap[recipeID] = true
        target.sourceRecipeKindMap[sourceKind][recipeID] = true
    end
end

---@param target table
---@return string
function Scanner:GetTargetTypeText(target)
    local isInput = target.kindMap and target.kindMap.input
    local isOutput = target.kindMap and target.kindMap.output
    if isInput and isOutput then
        return "Both"
    elseif isOutput then
        return "Product"
    end
    return "Reagent"
end

---@param scope string?
---@return string label
function Scanner:GetScanScopeLabel(scope)
    scope = scope or Config:GetScanScope()
    if scope == self.SCAN_SCOPES.PRODUCTS then
        return "Crafted products"
    elseif scope == self.SCAN_SCOPES.REAGENTS then
        return "Required reagents"
    end
    return "Products + reagents"
end

---@param target table?
---@param scope string?
---@return boolean
function Scanner:TargetMatchesScanScope(target, scope)
    if not target then
        return false
    end
    scope = scope or Config:GetScanScope()
    if scope == self.SCAN_SCOPES.PRODUCTS then
        return target.kindMap and target.kindMap.output == true
    elseif scope == self.SCAN_SCOPES.REAGENTS then
        return target.kindMap and target.kindMap.input == true
    end
    return true
end

---@param targets table[]?
---@param scope string?
---@return table[]
function Scanner:GetTargetsForScanScope(targets, scope)
    return ns.Filter(targets or {}, function(target)
        return self:TargetMatchesScanScope(target, scope)
    end)
end

---@param profession string
---@return table?
function Scanner:GetProfessionInfoByName(profession)
    for _, professionInfo in ipairs(self.PROFESSIONS) do
        if professionInfo.name == profession then
            return professionInfo
        end
    end
end

---@param profession string
---@return string
function Scanner:GetProfessionDropdownText(profession)
    if profession == "ALL" then
        return "Profession: All Selected"
    end
    local professionInfo = self:GetProfessionInfoByName(profession)
    if professionInfo then
        return "Profession: " .. self:GetProfessionDisplayName(professionInfo)
    end
    return "Profession: " .. tostring(profession)
end

---@return table<string, boolean> learnedProfessions
function Scanner:GetLearnedProfessionSelection()
    local learnedProfessions = {}
    local professionIndexes = { GetProfessions() }

    for _, professionInfo in ipairs(self.PROFESSIONS) do
        for _, professionIndex in pairs(professionIndexes) do
            local skillLineID = select(7, GetProfessionInfo(professionIndex))
            local info = skillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
            if info and info.profession == professionInfo.enum then
                learnedProfessions[professionInfo.name] = true
                break
            end
        end
    end

    return learnedProfessions
end

---@return table<string, boolean> selectedProfessions
function Scanner:EnsureProfessionSelectionForCurrentCrafter()
    return Config:EnsureSelectedProfessions(self:GetLearnedProfessionSelection())
end

---@return table<string, boolean> selectedProfessions
function Scanner:GetSelectedProfessions()
    return self:EnsureProfessionSelectionForCurrentCrafter()
end

---@return number count
function Scanner:GetSelectedProfessionCount()
    local count = 0
    for _, selected in pairs(self:GetSelectedProfessions()) do
        if selected then
            count = count + 1
        end
    end
    return count
end

---@return boolean hasSelectedProfession
function Scanner:HasSelectedProfession()
    return self:GetSelectedProfessionCount() > 0
end

---@return table[] selectedProfessionInfos
function Scanner:GetSelectedProfessionInfos()
    local selectedProfessions = self:GetSelectedProfessions()
    return ns.Filter(self.PROFESSIONS, function(professionInfo)
        return selectedProfessions[professionInfo.name] == true
    end)
end

---@param target table
---@return boolean selected
function Scanner:IsTargetInSelectedProfessions(target)
    local selectedProfessions = self:GetSelectedProfessions()
    for profession, selected in pairs(selectedProfessions) do
        if selected and target.professionMap and target.professionMap[profession] == true then
            return true
        end
    end
    return false
end

---@param text string
---@param patterns string[]
---@return boolean
function Scanner:TextMatchesAny(text, patterns)
    for _, pattern in ipairs(patterns) do
        if string.find(text, pattern, 1, true) then
            return true
        end
    end
    return false
end

---@param text string
function Scanner:SetStatus(text)
    if self.panel and self.panel.statusText then
        self.panel.statusText:SetText(text or "")
    end
end

function Scanner:InvalidateScanConfiguration()
    self.scanComplete = false
    self.overridesPushed = false
    self:SetStatus("")
end

---@param count number
---@param singular string
---@param plural string?
---@return string
function Scanner:Pluralize(count, singular, plural)
    return tonumber(count) == 1 and singular or (plural or (singular .. "s"))
end

---@param target table?
---@param eventName string
---@param detail string?
function Scanner:RecordQueryDiagnostic(target, eventName, detail)
    if not target then
        return
    end
    target.diagnosticEvents = target.diagnosticEvents or {}
    if #target.diagnosticEvents >= 24 then
        return
    end
    local entry = tostring(eventName)
    if detail and detail ~= "" then
        entry = entry .. "(" .. tostring(detail) .. ")"
    end
    table.insert(target.diagnosticEvents, entry)
end

---@param target table?
---@return string
function Scanner:GetTargetDiagnosticSummary(target)
    if not target then
        return ""
    end
    local parts = {
        "type=" .. tostring(target.resultType or "unknown"),
        "mode=" .. tostring(target.pricingMode or "unknown"),
        "q=" .. tostring(target.outputQualityID or "-"),
        "attempts=" .. tostring(target.queryAttempts or 0),
        "search=" .. tostring(target.usesBroadItemSearch and "by-item" or
            (target.itemSearchKey and target.itemSearchKey.itemLevel or "-")),
        "readLevel=" .. tostring(self:GetTargetItemResultKey(target) and
            self:GetTargetItemResultKey(target).itemLevel or "-"),
        "itemAPI=" .. tostring(target.diagnosticItemAPIResults or "-"),
        "itemRows=" .. tostring(target.diagnosticRawItemRows or "-"),
        "matched=" .. tostring(target.diagnosticMatchedRows or "-"),
        "commodityAPI=" .. tostring(target.diagnosticCommodityAPIResults or "-"),
        "commodityRows=" .. tostring(target.diagnosticCommodityRows or "-"),
        "fullItem=" .. tostring(target.diagnosticFullItem),
        "fullCommodity=" .. tostring(target.diagnosticFullCommodity),
    }
    if target.diagnosticItemLevels and target.diagnosticItemLevels ~= "" then
        table.insert(parts, "levels=" .. target.diagnosticItemLevels)
    end
    if target.diagnosticEvents and #target.diagnosticEvents > 0 then
        table.insert(parts, "events=" .. table.concat(target.diagnosticEvents, ">"))
    end
    return table.concat(parts, ";")
end

---@return number pricedTargets
---@return number unpricedTargets
---@return number processedTargets
---@return number groupedUnpricedItems
function Scanner:GetScanOutcomeCounts()
    local processedTargets = math.max(0, tonumber(self.completedTargets) or 0)
    local unpricedTargets = #(self.missingResults or {})
    local pricedTargets = math.max(0, processedTargets - unpricedTargets)
    local groupedUnpricedItems = self:GetMissingDisplayCount()
    return pricedTargets, unpricedTargets, processedTargets, groupedUnpricedItems
end

function Scanner:UpdateProgressText()
    if not self.panel or not self.panel.progressText then
        return
    end

    if self.isScanning then
        if self.panel.progressBar then
            self.panel.progressBar:SetMinMaxValues(0, math.max(1, tonumber(self.totalTargets) or 0))
            self.panel.progressBar:SetValue(math.max(0, tonumber(self.completedTargets) or 0))
            self.panel.progressBar:Show()
        end
        self.panel.progressText:SetText(string.format("%d/%d price targets", self.completedTargets, self.totalTargets))
        return
    end

    if self.panel.progressBar then
        self.panel.progressBar:Hide()
    end

    if self.scanComplete then
        local pricedTargets, unpricedTargets, processedTargets = self:GetScanOutcomeCounts()
        self.panel.progressText:SetText(string.format("%d/%d targets processed\n%d priced · %d unpriced",
            processedTargets, self.totalTargets, pricedTargets, unpricedTargets))
    else
        self.panel.progressText:SetText("")
    end
end

function Scanner:UpdateMissingButton()
    local panel = self.panel
    if not panel or not panel.missingButton then
        return
    end

    local groupedItems = self:GetMissingDisplayCount()
    local showMissing = self.scanComplete and not self.isScanning and groupedItems > 0

    panel.missingButton:SetText("Unpriced items (" .. tostring(groupedItems) .. ")")
    panel.missingButton:Show()
    SetButtonEnabled(panel.missingButton, showMissing)
    if panel.missingButtonHover then
        panel.missingButtonHover:SetShown(not showMissing)
    end
end

---@return boolean
function Scanner:HasOverridesToPush()
    if #self.priceResults > 0 then
        return true
    end
    for _, missingResult in ipairs(self.missingResults or {}) do
        if self:IsConfirmedNoAuctionResult(missingResult) then
            for _, overrideTarget in ipairs(missingResult.overrideTargets or {}) do
                if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
                    return true
                end
            end
        end
    end
    return false
end

---@return number selectedTargetCount
function Scanner:GetSelectedScanTargetCount()
    if not self:HasSelectedProfession() then
        return 0
    end

    -- Fixed vendor prices do not require Auction House queries, so count only
    -- the currently enabled targets that can actually be scanned.
    local targets = self:BuildScanTargets({ skipFixedPrices = true }) or {}
    return #targets
end

function Scanner:UpdateButtons()
    local panel = self.panel
    if not panel then
        return
    end

    local canPushOverrides = self.scanComplete and not self.overridesPushed and self:HasOverridesToPush()
    local selectedTargetCount = 0
    if not self.isScanning and not canPushOverrides then
        selectedTargetCount = self:GetSelectedScanTargetCount()
    end

    if panel.scanButton then
        if self.isScanning then
            panel.scanButton:SetText("Stop Scan")
        elseif canPushOverrides then
            panel.scanButton:SetText("Push Overrides")
        elseif selectedTargetCount == 0 then
            panel.scanButton:SetText("Select Scan Targets")
        else
            panel.scanButton:SetText("Scan Now")
        end
    end

    SetButtonEnabled(panel.scanButton, self.isScanning or canPushOverrides or selectedTargetCount > 0)
    SetButtonEnabled(panel.configureButton, not self.isScanning and self:HasSelectedProfession())
    for _, checkbox in pairs(self.professionCheckboxes) do
        SetButtonEnabled(checkbox, not self.isScanning)
    end
    if self.configPanel then
        self:UpdateScanScopeButtons()
        for _, viewButton in pairs(self.configPanel.viewButtons or {}) do
            SetButtonEnabled(viewButton, not self.isScanning)
            viewButton:SetAlpha(self.isScanning and 0.5 or 1)
        end
        SetButtonEnabled(self.configPanel.selectAllButton, not self.isScanning)
        SetButtonEnabled(self.configPanel.clearAllButton, not self.isScanning)
        SetButtonEnabled(self.configPanel.treeExpansionButton, not self.isScanning)
        SetButtonEnabled(self.configPanel.professionButton, not self.isScanning)
        SetButtonEnabled(self.configPanel.searchBox, not self.isScanning)
        SetButtonEnabled(self.configPanel.selectedOnlyCheckbox, not self.isScanning)
    end
    self:UpdateMissingButton()
end

---@param input EditBox
function Scanner:SaveFillQuantityInput(input)
    local value = tonumber(input:GetText()) or Config:GetFillQuantity()
    Config:SaveFillQuantity(value)
    input:SetText(tostring(Config:GetFillQuantity()))
end

-- Internal dependencies shared by the focused scanner implementation files.
-- Keeping these values here preserves one source of truth while the public
-- module surface remains the Scanner table registered below.
Scanner.Shared = {
    Config = Config,
    Events = EVENTS,
    MinQueryInterval = MIN_QUERY_INTERVAL,
    PendingTimeoutSeconds = PENDING_TIMEOUT_SECONDS,
    MaxMoreResultRequests = MAX_MORE_RESULT_REQUESTS,
    GenericResultGraceSeconds = GENERIC_RESULT_GRACE_SECONDS,
    AuctionHouseCut = AUCTION_HOUSE_CUT,
    EstimatedResultSource = ESTIMATED_RESULT_SOURCE,
    AuctionHouseTabID = AUCTION_HOUSE_TAB_ID,
    AuctionHouseTabPadding = AUCTION_HOUSE_TAB_PADDING,
    AuctionHouseTabMinWidth = AUCTION_HOUSE_TAB_MIN_WIDTH,
    SmallAuctionHouseTabPadding = SMALL_AUCTION_HOUSE_TAB_PADDING,
    SmallAuctionHouseTabMinWidth = SMALL_AUCTION_HOUSE_TAB_MIN_WIDTH,
    NativeRockTexture = NATIVE_ROCK_TEXTURE,
    NativeInsetBackdrop = NATIVE_INSET_BACKDROP,
    SetButtonEnabled = SetButtonEnabled,
    CreateNativeActionButton = CreateNativeActionButton,
    CreateNativeHeaderBand = CreateNativeHeaderBand,
    CreateNativeListWell = CreateNativeListWell,
    SystemPrint = SystemPrint,
}

ns:RegisterModule("AuctionHouseScan", Scanner)
