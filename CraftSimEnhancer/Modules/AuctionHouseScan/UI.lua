local _, ns = ...

local Scanner = assert(ns.Modules.AuctionHouseScan, "AuctionHouseScan core must load before UI")
local Shared = Scanner.Shared
local Config = Shared.Config
local AUCTION_HOUSE_TAB_ID = Shared.AuctionHouseTabID
local AUCTION_HOUSE_TAB_PADDING = Shared.AuctionHouseTabPadding
local AUCTION_HOUSE_TAB_MIN_WIDTH = Shared.AuctionHouseTabMinWidth
local SMALL_AUCTION_HOUSE_TAB_PADDING = Shared.SmallAuctionHouseTabPadding
local SMALL_AUCTION_HOUSE_TAB_MIN_WIDTH = Shared.SmallAuctionHouseTabMinWidth
local ESTIMATED_RESULT_SOURCE = Shared.EstimatedResultSource
local SetButtonEnabled = Shared.SetButtonEnabled

function Scanner:GetAuctionHouseTabLibrary()
    if not LibStub then
        return nil
    end
    local success, library = pcall(function()
        return LibStub("LibAHTab-1-0", true)
    end)
    if success and library and type(library.CreateTab) == "function" and type(library.SetSelected) == "function" then
        return library
    end
    return nil
end

---@return boolean
function Scanner:UsesSmallAuctionHouseTabs()
    local auctionator = _G.Auctionator
    local config = auctionator and auctionator.Config
    local options = config and config.Options
    if not config or type(config.Get) ~= "function" or not options or not options.SMALL_TABS then
        return false
    end

    local success, useSmallTabs = pcall(config.Get, options.SMALL_TABS)
    return success and useSmallTabs == true
end

---@param button Button|nil
function Scanner:ResizeAuctionHouseTab(button)
    -- LibAHTab owns the size of every button it creates. In particular, TSM
    -- temporarily scales AuctionHouseFrame down while its replacement UI is
    -- open; recalculating a library button while that transition is happening
    -- can leave the tab with a scale-adjusted width when Blizzard's UI returns.
    if self.usesTabLibrary or not button or not PanelTemplates_TabResize then
        return
    end

    if self:UsesSmallAuctionHouseTabs() then
        PanelTemplates_TabResize(button, SMALL_AUCTION_HOUSE_TAB_PADDING, nil, SMALL_AUCTION_HOUSE_TAB_MIN_WIDTH)
    else
        PanelTemplates_TabResize(button, AUCTION_HOUSE_TAB_PADDING, nil, AUCTION_HOUSE_TAB_MIN_WIDTH)
    end
end

---@param displayMode any
---@return boolean
function Scanner:IsBuiltInAuctionHouseDisplayMode(displayMode)
    if displayMode == nil then
        return false
    end
    return type(displayMode) ~= "table" or next(displayMode) ~= nil
end

function Scanner:HideAuctionHouseTab()
    if self.panel then
        self.panel:Hide()
    end
    if self.missingExportPanel then
        self.missingExportPanel:Hide()
    end
    if self.button and PanelTemplates_DeselectTab then
        PanelTemplates_DeselectTab(self.button)
    end
end

function Scanner:SelectAuctionHouseTab()
    self:CreatePanel()
    self:CreateButton()
    if not self.panel or not self.button or not AuctionHouseFrame then
        return
    end

    if self.usesTabLibrary and self.tabLibrary then
        self.tabLibrary:SetSelected(AUCTION_HOUSE_TAB_ID)
    else
        AuctionHouseFrame:SetDisplayMode({})
        AuctionHouseFrame.displayMode = nil
        for _, tab in ipairs(AuctionHouseFrame.Tabs or {}) do
            if PanelTemplates_DeselectTab then
                PanelTemplates_DeselectTab(tab)
            end
        end
        if PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(self.button)
        end
        if AuctionHouseFrame.SetTitle then
            AuctionHouseFrame:SetTitle("CSE Recon")
        end
        self.panel:Show()
    end

    self:UpdateLauncherTabState()
end

function Scanner:CreateButton()
    if self.button or not AuctionHouseFrame then
        return
    end

    self:CreatePanel()
    if not self.panel then
        return
    end

    local library = self:GetAuctionHouseTabLibrary()
    local button
    if library then
        if not library:DoesIDExist(AUCTION_HOUSE_TAB_ID) then
            library:CreateTab(AUCTION_HOUSE_TAB_ID, self.panel, "CSE Recon", "CSE Recon")
        end
        button = library:GetButton(AUCTION_HOUSE_TAB_ID)
        self.tabLibrary = library
        self.usesTabLibrary = true
    else
        button = CreateFrame("Button", "CraftSimEnhancerAuctionHouseScanButton", AuctionHouseFrame,
            "AuctionHouseFrameDisplayModeTabTemplate")
        button:SetText("CSE Recon")
        button:SetScript("OnClick", function()
            Scanner:SelectAuctionHouseTab()
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            end
        end)
    end

    if not button then
        return
    end

    button.craftSimIsLauncherTab = true
    self:ResizeAuctionHouseTab(button)
    if not self.usesTabLibrary then
        button:HookScript("OnShow", function(selfButton)
            Scanner:ResizeAuctionHouseTab(selfButton)
        end)
    end
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CSE Recon")
        GameTooltip:AddLine("Scan the Auction House for CraftSim pricing intelligence.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    self.button = button
    self:AttachLauncherTabToAuctionHouseTabs()

    if not self.displayModeHooked and hooksecurefunc then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, displayMode)
            if Scanner:IsBuiltInAuctionHouseDisplayMode(displayMode) then
                Scanner:HideAuctionHouseTab()
                Scanner:UpdateLauncherTabState()
            end
        end)
        self.displayModeHooked = true
    end

    self:UpdateLauncherTabState()
end

function Scanner:AttachLauncherTabToAuctionHouseTabs()
    local button = self.button
    if not button or not AuctionHouseFrame then
        return
    end

    if self.usesTabLibrary or not AuctionHouseFrame.Tabs then
        return
    end

    -- Keep the fallback launcher out of Blizzard's Tabs collection. Adding it
    -- there and calling PanelTemplates_SetNumTabs re-anchors every built-in tab
    -- and conflicts with replacement UIs such as TSM when they restore the
    -- default Auction House frame.
    local tabs = AuctionHouseFrame.Tabs
    button:ClearAllPoints()
    local previousTab = tabs[#tabs]
    if previousTab then
        button:SetPoint("LEFT", previousTab, "RIGHT", -15, 0)
    else
        button:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, -28)
    end
    self:ResizeAuctionHouseTab(button)
end

function Scanner:UpdateLauncherTabState()
    local button = self.button
    if not button then
        return
    end

    local selected = self.panel and self.panel:IsShown() or false
    if button.SetChecked then
        button:SetChecked(selected)
    end

    if selected then
        if PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(button)
        end
    elseif PanelTemplates_DeselectTab then
        PanelTemplates_DeselectTab(button)
    end

    if button.Enable then
        button:Enable()
    end
end

---@param view "config" | "missing"
function Scanner:ShowPanelView(view)
    self:CreateConfigPanel()
    self:CreateMissingPanel()

    if view == "missing" and #self.missingResults == 0 then
        self:SetStatus("No missing scan items to show.")
        view = "config"
    end

    self.activeView = view == "missing" and "missing" or "config"
    if self.configPanel then
        self.configPanel:SetShown(self.activeView == "config")
    end
    if self.missingPanel then
        self.missingPanel:SetShown(self.activeView == "missing")
    end

    if self.activeView == "missing" then
        self:UpdateMissingList()
    else
        self:UpdateConfigList()
    end

end

---@param parent Frame
---@param professionInfo table
---@param y number
---@return CheckButton
function Scanner:CreateProfessionCheckbox(parent, professionInfo, y)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    checkbox:SetChecked(self:GetSelectedProfessions()[professionInfo.name] == true)
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    checkbox.text:SetWidth(150)
    checkbox.text:SetJustifyH("LEFT")
    checkbox.text:SetText(self:GetProfessionLabel(professionInfo))
    checkbox:SetScript("OnClick", function(selfCheckbox)
        Config:SaveProfessionSelected(professionInfo.name, selfCheckbox:GetChecked())
        Scanner.scanComplete = false
        Scanner.overridesPushed = false
        wipe(Scanner.priceResults)
        wipe(Scanner.missingResults)
        if Scanner.activeView == "missing" then
            Scanner:ShowPanelView("config")
        elseif Scanner.configPanel and Scanner.configPanel:IsShown() then
            Scanner:UpdateConfigList()
        end
        Scanner:UpdateMissingList()
        Scanner:UpdateButtons()
        Scanner:UpdateProgressText()
    end)
    return checkbox
end

function Scanner:CreatePanel()
    if self.panel or not AuctionHouseFrame then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanPanel", AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -25)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 4)
    panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 10)
    panel:EnableMouse(true)

    panel.background = panel:CreateTexture(nil, "BACKGROUND")
    panel.background:SetAllPoints(panel)
    panel.background:SetColorTexture(0.035, 0.035, 0.035, 0.96)

    panel.leftPane = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.leftPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    panel.leftPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
    panel.leftPane:SetWidth(198)
    panel.leftPane:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel.leftPane:SetBackdropColor(0.025, 0.025, 0.025, 0.94)
    panel.leftPane:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

    panel.contentHost = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.contentHost:SetPoint("TOPLEFT", panel.leftPane, "TOPRIGHT", 6, 0)
    panel.contentHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    panel.contentHost:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel.contentHost:SetBackdropColor(0.025, 0.025, 0.025, 0.94)
    panel.contentHost:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

    panel.title = panel.leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", panel.leftPane, "TOP", 0, -14)
    panel.title:SetWidth(178)
    panel.title:SetJustifyH("CENTER")
    panel.title:SetText("Professions")

    panel.professionsLabel = panel.leftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.professionsLabel:SetPoint("TOP", panel.title, "BOTTOM", 0, -4)
    panel.professionsLabel:SetWidth(178)
    panel.professionsLabel:SetJustifyH("CENTER")
    panel.professionsLabel:SetText("Choose what to include")

    self:EnsureProfessionSelectionForCurrentCrafter()
    wipe(self.professionCheckboxes)
    local y = -56
    for _, professionInfo in ipairs(self.PROFESSIONS) do
        local checkbox = self:CreateProfessionCheckbox(panel.leftPane, professionInfo, y)
        self.professionCheckboxes[professionInfo.name] = checkbox
        y = y - 24
    end

    panel.scanLabel = panel.leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.scanLabel:SetPoint("TOP", panel.leftPane, "TOP", 0, y - 10)
    panel.scanLabel:SetWidth(178)
    panel.scanLabel:SetJustifyH("CENTER")
    panel.scanLabel:SetText("Auction House Scan")

    panel.scanButton = CreateFrame("Button", nil, panel.leftPane, "UIPanelButtonTemplate")
    panel.scanButton:SetSize(164, 24)
    panel.scanButton:SetPoint("TOP", panel.scanLabel, "BOTTOM", 0, -6)
    panel.scanButton:SetText("Scan Now")
    panel.scanButton:SetScript("OnClick", function()
        local scanner = Scanner
        if scanner.isScanning then
            scanner:CancelScan("Scan stopped.")
        elseif scanner.scanComplete and not scanner.overridesPushed and scanner:HasOverridesToPush() then
            scanner:PushOverrides()
        else
            scanner:StartScan()
        end
    end)

    panel.missingButton = CreateFrame("Button", nil, panel.leftPane, "UIPanelButtonTemplate")
    panel.missingButton:SetSize(164, 24)
    panel.missingButton:SetPoint("TOP", panel.scanButton, "BOTTOM", 0, -6)
    panel.missingButton:SetText("Missing (0)")
    panel.missingButton:SetScript("OnClick", function()
        Scanner:ToggleMissingPanel()
    end)

    panel.progressText = panel.leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.progressText:SetPoint("TOPLEFT", panel.missingButton, "BOTTOMLEFT", 0, -12)
    panel.progressText:SetWidth(164)
    panel.progressText:SetHeight(14)
    panel.progressText:SetJustifyH("LEFT")

    panel.statusText = panel.leftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.statusText:SetPoint("TOPLEFT", panel.progressText, "BOTTOMLEFT", 0, -8)
    panel.statusText:SetWidth(164)
    panel.statusText:SetHeight(108)
    panel.statusText:SetJustifyH("LEFT")
    panel.statusText:SetJustifyV("TOP")
    panel.statusText:SetText("")

    panel:SetScript("OnShow", function()
        Scanner:ShowPanelView(Scanner.activeView or "config")
        Scanner:UpdateButtons()
        Scanner:UpdateProgressText()
        Scanner:UpdateLauncherTabState()
    end)
    panel:SetScript("OnHide", function()
        Scanner:UpdateLauncherTabState()
    end)

    panel:Hide()
    self.panel = panel
    self:CreateConfigPanel()
    self:CreateMissingPanel()
    self:UpdateButtons()
end

function Scanner:ShowButton()
    self:CreatePanel()
    self:CreateButton()
    self:AttachLauncherTabToAuctionHouseTabs()
    if self.button then
        self:ResizeAuctionHouseTab(self.button)
        self.button:Show()
        self:UpdateLauncherTabState()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Scanner.button and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
                Scanner:AttachLauncherTabToAuctionHouseTabs()
                Scanner:ResizeAuctionHouseTab(Scanner.button)
                Scanner:UpdateLauncherTabState()
            end
        end)
    end
end

function Scanner:TogglePanel()
    self:SelectAuctionHouseTab()
end

function Scanner:ToggleMissingPanel()
    if #self.missingResults == 0 then
        self:SetStatus("No missing scan items to show.")
        return
    end

    if self.activeView == "missing" then
        self:ShowPanelView("config")
    else
        self:ShowPanelView("missing")
    end
end

function Scanner:CreateMissingPanel()
    if self.missingPanel or not self.panel or not self.panel.contentHost then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanMissingPanel", self.panel.contentHost)
    panel:SetAllPoints(self.panel.contentHost)
    panel:SetFrameLevel((self.panel.contentHost:GetFrameLevel() or 1) + 1)
    panel:EnableMouse(true)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    panel.title:SetText("Missing AH Items")

    panel.backButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.backButton:SetSize(118, 22)
    panel.backButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -10)
    panel.backButton:SetText("Back to Configure")
    panel.backButton:SetScript("OnClick", function()
        Scanner:ShowPanelView("config")
    end)

    panel.copyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.copyButton:SetSize(104, 22)
    panel.copyButton:SetPoint("RIGHT", panel.backButton, "LEFT", -8, 0)
    panel.copyButton:SetText("Copy Report")
    panel.copyButton:SetScript("OnClick", function()
        Scanner:OpenMissingReport()
    end)

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -52)
    panel.headerText:SetText("Item                                              ItemID       Reason")

    panel.emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.emptyText:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -78)
    panel.emptyText:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.emptyText:SetJustifyH("LEFT")
    panel.emptyText:SetText("No missing items from the latest scan.")

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -70)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(536, 1)
    panel.scrollFrame:SetScrollChild(panel.scrollChild)

    panel:Hide()
    self.missingPanel = panel
end

---@param result table
---@return string
function Scanner:GetMissingRowTooltip(result)
    local lines = {
        tostring(result.label or ("Item " .. tostring(result.itemID))),
        "ItemID: " .. tostring(result.itemID),
    }
    if result.count and result.count > 1 then
        table.insert(lines, "Scan Targets: " .. tostring(result.count))
    end
    if result.itemLevelOrder and #result.itemLevelOrder > 0 then
        local levels = {}
        for _, itemLevel in ipairs(result.itemLevelOrder) do
            table.insert(levels, tostring(itemLevel))
        end
        table.insert(lines, "Item Levels: " .. table.concat(levels, ", "))
    elseif result.itemLevel and result.itemLevel > 0 then
        table.insert(lines, "Item Level: " .. tostring(result.itemLevel))
    end
    table.insert(lines, "Reason: " .. tostring(result.error or "No posted auctions found."))
    if result.estimatedPrice then
        table.insert(lines, "Override source: " .. ESTIMATED_RESULT_SOURCE)
        table.insert(lines, "Estimated price: " .. ns.Compat.WoW:FormatMoney(result.estimatedPrice))
        table.insert(lines, "CraftSim average cost: " .. ns.Compat.WoW:FormatMoney(result.craftingCost))
        if result.costQualityID and result.qualityID and result.costQualityID ~= result.qualityID then
            table.insert(lines, "Cost fallback: saved rank " .. tostring(result.costQualityID))
        end
        if result.estimateCapped then
            table.insert(lines, "Capped below a real higher-rank listing.")
        end
    elseif result.estimateSkipped then
        table.insert(lines, "Estimate skipped: CraftSim has no saved average crafting cost.")
    elseif result.estimateOnPush then
        table.insert(lines, "Result override on push: break-even estimate from CraftSim's saved average cost.")
    end
    return table.concat(lines, "\n")
end

---@param result table
---@return string
function Scanner:GetMissingReasonShort(result)
    local errorText = tostring(result.error or "No posted auctions found.")
    local lowerError = string.lower(errorText)
    if string.find(lowerError, "timed out", 1, true) then
        return "Timeout"
    elseif string.find(lowerError, "rank could not be identified", 1, true) then
        return "Rank unknown"
    elseif string.find(lowerError, "no posted", 1, true) then
        if result and result.estimatedPrice then
            return ESTIMATED_RESULT_SOURCE
        elseif result and result.estimateSkipped then
            return "No cost; skipped"
        end
        return result and result.estimateOnPush and "Estimate on push" or "No auctions"
    elseif string.find(lowerError, "throttled", 1, true) then
        return "Throttled"
    elseif string.find(lowerError, "dropped", 1, true) then
        return "Dropped"
    end
    return errorText
end

---@param result table
---@return boolean
function Scanner:IsConfirmedNoAuctionResult(result)
    local errorText = string.lower(tostring(result and result.error or ""))
    return string.find(errorText, "no posted auctions", 1, true) ~= nil
end

---@param result table
---@return boolean
function Scanner:MissingResultHasOutputOverride(result)
    for _, overrideTarget in ipairs(result and result.overrideTargets or {}) do
        if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
            return true
        end
    end
    return false
end

---@return table[] results
function Scanner:GetDisplayMissingResults()
    local grouped = {}
    local results = {}

    for _, result in ipairs(self.missingResults) do
        result.estimateOnPush = self:IsConfirmedNoAuctionResult(result) and self:MissingResultHasOutputOverride(result)
        local reasonShort = self:GetMissingReasonShort(result)
        local key = tostring(result.itemID) .. ":" .. tostring(reasonShort)
        local display = grouped[key]
        if not display then
            display = {
                itemID = result.itemID,
                itemLevel = result.itemLevel,
                label = result.label,
                error = result.error,
                reasonShort = reasonShort,
                count = 0,
                itemLevelMap = {},
                itemLevelOrder = {},
                estimateOnPush = result.estimateOnPush,
                estimatedPrice = result.estimatedPrice,
                craftingCost = result.craftingCost,
                qualityID = result.qualityID,
                costQualityID = result.costQualityID,
                estimateCapped = result.estimateCapped,
                estimateSkipped = result.estimateSkipped,
                diagnosticMap = {},
                diagnostics = {},
            }
            grouped[key] = display
            table.insert(results, display)
        end

        display.count = display.count + 1
        if not display.error and result.error then
            display.error = result.error
        end
        display.estimateOnPush = display.estimateOnPush or result.estimateOnPush
        display.estimatedPrice = display.estimatedPrice or result.estimatedPrice
        display.craftingCost = display.craftingCost or result.craftingCost
        display.qualityID = display.qualityID or result.qualityID
        display.costQualityID = display.costQualityID or result.costQualityID
        display.estimateCapped = display.estimateCapped or result.estimateCapped
        display.estimateSkipped = display.estimateSkipped or result.estimateSkipped

        if result.diagnostic and result.diagnostic ~= "" and not display.diagnosticMap[result.diagnostic] then
            display.diagnosticMap[result.diagnostic] = true
            table.insert(display.diagnostics, result.diagnostic)
        end

        local itemLevel = tonumber(result.itemLevel) or 0
        if itemLevel > 0 and not display.itemLevelMap[itemLevel] then
            display.itemLevelMap[itemLevel] = true
            table.insert(display.itemLevelOrder, itemLevel)
        end
    end

    for _, result in ipairs(results) do
        table.sort(result.itemLevelOrder)
    end

    return results
end

---@return number
function Scanner:GetMissingDisplayCount()
    return #self:GetDisplayMissingResults()
end

---@param value any
---@return string
function Scanner:SanitizeMissingReportField(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\r", " ")
    text = string.gsub(text, "\n", " ")
    text = string.gsub(text, "\t", " ")
    return text
end

---@return string report
function Scanner:GetMissingReportText()
    local displayResults = self:GetDisplayMissingResults()
    local lines = {
        "CraftSim Enhancer Missing AH Report",
        "Addon Version\t" .. tostring(ns.version or "unknown"),
        "Grouped Missing Items\t" .. tostring(#displayResults),
        "Missing Scan Targets\t" .. tostring(#self.missingResults),
        "",
        "Item\tItemID\tTargets\tItem Levels\tReason\tDetails\tDiagnostics",
    }

    for _, result in ipairs(displayResults) do
        local levels = ""
        if result.itemLevelOrder and #result.itemLevelOrder > 0 then
            local values = {}
            for _, itemLevel in ipairs(result.itemLevelOrder) do
                table.insert(values, tostring(itemLevel))
            end
            levels = table.concat(values, ",")
        elseif result.itemLevel and result.itemLevel > 0 then
            levels = tostring(result.itemLevel)
        end

        table.insert(lines, table.concat({
            self:SanitizeMissingReportField(result.label or ("Item " .. tostring(result.itemID))),
            tostring(result.itemID or ""),
            tostring(result.count or 1),
            levels,
            self:SanitizeMissingReportField(result.reasonShort or self:GetMissingReasonShort(result)),
            self:SanitizeMissingReportField(result.error or "No posted auctions found."),
            self:SanitizeMissingReportField(table.concat(result.diagnostics or {}, " || ")),
        }, "\t"))
    end

    return table.concat(lines, "\n")
end

function Scanner:CreateMissingExportPanel()
    if self.missingExportPanel then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanMissingExportPanel", UIParent,
        "BackdropTemplate")
    panel:SetSize(680, 500)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(200)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    panel.title:SetText("Missing AH Report")

    panel.instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.instructions:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
    panel.instructions:SetText("Press Ctrl+C (Windows) or Command+C (Mac), then paste the report into a message.")

    panel.closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    panel.closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    panel.selectButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.selectButton:SetSize(100, 22)
    panel.selectButton:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    panel.selectButton:SetText("Select All")

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -68)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -38, 48)

    panel.editBox = CreateFrame("EditBox", nil, panel.scrollFrame)
    panel.editBox:SetMultiLine(true)
    panel.editBox:SetAutoFocus(false)
    panel.editBox:SetFontObject(ChatFontNormal)
    panel.editBox:SetWidth(610)
    panel.editBox:SetMaxLetters(0)
    panel.editBox:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
        panel:Hide()
    end)
    panel.editBox:SetScript("OnTextChanged", function()
        panel.scrollFrame:UpdateScrollChildRect()
    end)
    panel.scrollFrame:SetScrollChild(panel.editBox)

    panel.selectButton:SetScript("OnClick", function()
        panel.editBox:SetFocus()
        panel.editBox:HighlightText()
    end)

    panel:Hide()
    self.missingExportPanel = panel
end

function Scanner:OpenMissingReport()
    if #self.missingResults == 0 then
        self:SetStatus("No missing scan items to copy.")
        return
    end

    self:CreateMissingExportPanel()
    local panel = self.missingExportPanel
    if not panel then
        return
    end

    local report = self:GetMissingReportText()
    local _, newlineCount = string.gsub(report, "\n", "\n")
    panel.editBox:SetHeight(math.max(380, ((newlineCount or 0) + 1) * 14 + 20))
    panel.editBox:SetText(report)
    panel:Show()
    panel.editBox:SetFocus()
    panel.editBox:HighlightText()
end

---@param row Frame
---@param result table
function Scanner:UpdateMissingRow(row, result)
    row.result = result
    local label = tostring(result.label or ("Item " .. tostring(result.itemID)))
    if result.count and result.count > 1 then
        label = label .. " x" .. tostring(result.count)
    end
    row.nameText:SetText(label)
    row.itemIDText:SetText(tostring(result.itemID))
    row.reasonText:SetText(result.reasonShort or self:GetMissingReasonShort(result))
    row.tooltipText = self:GetMissingRowTooltip(result)
end

---@param parent Frame
---@return Frame
function Scanner:CreateMissingRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(536, 26)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.03)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.nameText:SetWidth(310)
    row.nameText:SetJustifyH("LEFT")
    if row.nameText.SetWordWrap then
        row.nameText:SetWordWrap(false)
    end
    if row.nameText.SetMaxLines then
        row.nameText:SetMaxLines(1)
    end

    row.itemIDText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.itemIDText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)
    row.itemIDText:SetWidth(72)
    row.itemIDText:SetJustifyH("LEFT")
    if row.itemIDText.SetWordWrap then
        row.itemIDText:SetWordWrap(false)
    end
    if row.itemIDText.SetMaxLines then
        row.itemIDText:SetMaxLines(1)
    end

    row.reasonText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.reasonText:SetPoint("LEFT", row.itemIDText, "RIGHT", 8, 0)
    row.reasonText:SetWidth(126)
    row.reasonText:SetJustifyH("LEFT")
    if row.reasonText.SetWordWrap then
        row.reasonText:SetWordWrap(false)
    end
    if row.reasonText.SetMaxLines then
        row.reasonText:SetMaxLines(1)
    end

    row:SetScript("OnEnter", function(selfRow)
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Missing AH Item")
        GameTooltip:AddLine(selfRow.tooltipText or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdateMissingList()
    self:CreateMissingPanel()
    local panel = self.missingPanel
    if not panel then
        return
    end

    for _, row in ipairs(self.missingRows) do
        row:Hide()
    end

    local displayResults = self:GetDisplayMissingResults()
    if #displayResults == 0 then
        panel.emptyText:Show()
        panel.scrollFrame:Hide()
        return
    end

    panel.emptyText:Hide()
    panel.scrollFrame:Show()

    local rowHeight = 26
    for index, result in ipairs(displayResults) do
        local row = self.missingRows[index]
        if not row then
            row = self:CreateMissingRow(panel.scrollChild)
            self.missingRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight))
        if index % 2 == 0 then
            row.bg:Show()
        else
            row.bg:Hide()
        end
        self:UpdateMissingRow(row, result)
        row:Show()
    end

    panel.scrollChild:SetHeight(math.max(1, #displayResults * rowHeight))
end
