local addonName, ns = ...

local function InitializeModule(name)
    local module = ns.Modules[name]
    local status = ns.ModuleStatus[name]
    status.enabled = ns.Config:IsModuleEnabled(name)
    if not status.enabled then
        status.error = "disabled in settings"
        return
    end

    if type(module.CanInitialize) == "function" then
        local compatible, compatibilityError = module:CanInitialize()
        if not compatible then
            status.error = compatibilityError or "compatibility check failed"
            ns:WarnOnce("module-" .. name, name .. " disabled: " .. status.error)
            return
        end
    end

    local initialized, initializationError = module:Initialize()
    if not initialized then
        status.error = initializationError or "initialization failed"
        ns:WarnOnce("module-" .. name, name .. " disabled: " .. status.error)
        return
    end
    status.initialized = true
    status.error = nil
    ns.Debug:Log(name .. " initialized")
end

local function PrintHelp()
    ns:Print("Commands:")
    ns:Print("/cse help - show commands")
    ns:Print("/cse status - show compatibility and module status")
    ns:Print("/cse debug - toggle debug output")
    ns:Print("/cse reset - show reset confirmation")
    ns:Print("/cse reset confirm - reset only CraftSim Enhancer settings")
    ns:Print("/cse module <scan|tooltip|vendor|notice> <on|off> - set a module for the next reload")
    ns:Print("/cse scan - open the Auction House scanner")
    ns:Print("/cse_scanqty <quantity> - set the reagent pricing sample quantity (5-1000)")
    ns:Print("/cse vendor - show Vendor Materials or refresh Vendor Buy at an open merchant")
end

local function PrintStatus()
    ns:Print("Version: " .. ns.version)
    ns:Print("CraftSim loaded: " .. tostring(ns.Compat.WoW:IsAddonLoaded("CraftSim")))
    ns:Print("CraftSim version: " .. tostring(ns.Compat.CraftSim:GetVersion()))
    ns:Print("CraftSim compatibility tested against: " .. ns.Compat.CraftSim.testedVersion)
    ns:Print("WoW interface: " .. tostring(ns.Compat.WoW:GetInterfaceVersion()))
    ns:Print("WoW interface tested against: " .. tostring(ns.Compat.WoW.testedInterface))
    ns:Print("Debug: " .. tostring(ns.Debug:IsEnabled()))
    ns:Print("Migration: " .. ns.Config:GetMigrationStatus())
    ns:Print("Reagent scan sample quantity: " .. tostring(ns.Config.AuctionHouseScan:GetFillQuantity()))
    for _, name in ipairs(ns.ModuleOrder) do
        local status = ns.ModuleStatus[name]
        local summary = status.initialized and "initialized" or (status.error or "not initialized")
        ns:Print(name .. ": enabled=" .. tostring(status.enabled) .. ", " .. summary)
    end
    if next(ns.warnings) == nil then
        ns:Print("Compatibility warnings: none")
    else
        for key, warning in pairs(ns.warnings) do
            ns:Print("Compatibility warning [" .. tostring(key) .. "]: " .. tostring(warning))
        end
    end
end

local function WarnForUntestedVersions()
    local interfaceVersion = tonumber(ns.Compat.WoW:GetInterfaceVersion())
    local testedInterface = tonumber(ns.Compat.WoW.testedInterface)
    if interfaceVersion and testedInterface and interfaceVersion ~= testedInterface then
        ns:WarnOnce("wow-interface-version",
            "Running WoW interface " .. tostring(interfaceVersion) .. "; tested against " ..
            tostring(testedInterface) .. ". Capability checks passed, but complete the compatibility checklist.")
    end

    local craftSimVersion = tostring(ns.Compat.CraftSim:GetVersion())
    local testedCraftSimVersion = tostring(ns.Compat.CraftSim.testedVersion)
    if craftSimVersion ~= "unknown" and craftSimVersion ~= testedCraftSimVersion then
        ns:WarnOnce("craftsim-version",
            "Running CraftSim " .. craftSimVersion .. "; tested against " .. testedCraftSimVersion ..
            ". Capability checks passed, but internal behavior may have changed.")
    end
end

local function HandleScanQuantityCommand(message)
    local argument = string.match(message or "", "^%s*(.-)%s*$")
    local config = ns.Config.AuctionHouseScan
    local minimum, maximum = config:GetFillQuantityLimits()

    if argument == "" then
        ns:Print("Reagent scan sample quantity: " .. tostring(config:GetFillQuantity()))
        ns:Print(string.format("Usage: /cse_scanqty <quantity> (%d-%d)", minimum, maximum))
        return
    end

    if not string.match(argument, "^%d+$") then
        ns:Print(string.format("Scan quantity must be a whole number from %d to %d.", minimum, maximum))
        return
    end

    local quantity = tonumber(argument)
    if not quantity or quantity < minimum or quantity > maximum then
        ns:Print(string.format("Scan quantity must be a whole number from %d to %d.", minimum, maximum))
        return
    end

    local scanner = ns.Modules.AuctionHouseScan
    if scanner and scanner.isScanning then
        ns:Print("The scan quantity cannot be changed while a scan is running.")
        return
    end

    config:SaveFillQuantity(quantity)
    ns:Print("Reagent scan sample quantity set to " .. tostring(config:GetFillQuantity()) .. ".")
end

local function HandleSlashCommand(message)
    local command, remainder = string.match(string.lower(message or ""), "^%s*(%S*)%s*(.-)%s*$")
    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "status" then
        PrintStatus()
    elseif command == "debug" then
        ns.Debug:SetEnabled(not ns.Debug:IsEnabled())
        ns:Print("Debug output " .. (ns.Debug:IsEnabled() and "enabled." or "disabled."))
    elseif command == "reset" then
        if remainder == "confirm" then
            ns.Config:Reset()
            local vendorBuy = ns.Modules.VendorBuy
            if vendorBuy and type(vendorBuy.UpdatePlanWindow) == "function" then
                vendorBuy:UpdatePlanWindow()
            end
            ns:Print(ns.L.RESET_DONE)
        else
            ns:Print(ns.L.RESET_WARNING)
        end
    elseif command == "module" then
        local shortName, value = string.match(remainder, "^(%S+)%s+(%S+)$")
        local moduleNames = {
            scan = "AuctionHouseScan",
            tooltip = "BreakEvenTooltip",
            vendor = "VendorBuy",
            notice = "VendorShoppingListNotice",
        }
        local moduleName = moduleNames[shortName or ""]
        if moduleName and (value == "on" or value == "off") then
            ns.Config:SetModuleEnabled(moduleName, value == "on")
            ns:Print(moduleName .. " will be " .. (value == "on" and "enabled" or "disabled") ..
                " after /reload.")
        else
            ns:Print("Usage: /cse module <scan|tooltip|vendor|notice> <on|off>")
        end
    elseif command == "scan" then
        local module = ns.Modules.AuctionHouseScan
        if module and ns.ModuleStatus.AuctionHouseScan.initialized then
            module:Open()
        else
            ns:Print("AuctionHouseScan is unavailable. Use /cse status for details.")
        end
    elseif command == "scanqty" then
        HandleScanQuantityCommand(remainder)
    elseif command == "vendor" then
        local module = ns.Modules.VendorBuy
        if module and ns.ModuleStatus.VendorBuy.initialized then
            module:Open()
        else
            ns:Print("VendorBuy is unavailable. Use /cse status for details.")
        end
    else
        ns:Print("Unknown command: " .. tostring(command))
        PrintHelp()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end

    ns.Config:Initialize()
    local compatible, compatibilityError = ns.Compat.CraftSim:Initialize()
    if not compatible then
        ns:WarnOnce("craftsim", compatibilityError or ns.L.CRAFTSIM_MISSING)
        for _, name in ipairs(ns.ModuleOrder) do
            ns.ModuleStatus[name].error = compatibilityError or "CraftSim unavailable"
        end
    else
        WarnForUntestedVersions()
        for _, name in ipairs(ns.ModuleOrder) do
            InitializeModule(name)
        end
    end

    SLASH_CRAFTSIMENHANCER1 = "/cse"
    SlashCmdList.CRAFTSIMENHANCER = HandleSlashCommand
    SLASH_CRAFTSIMENHANCERSCANQTY1 = "/cse_scanqty"
    SlashCmdList.CRAFTSIMENHANCERSCANQTY = HandleScanQuantityCommand
    ns.initialized = compatible == true
    ns:Print(ns.L.ADDON_LOADED)
    eventFrame:UnregisterEvent("ADDON_LOADED")
end)
