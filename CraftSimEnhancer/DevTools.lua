local _, ns = ...

local Dev = { logs = {}, active = nil }
ns.DevTools = Dev
local BATCH_SIZE = 15

-- SavedVariables must contain ordinary serializable values, never UI objects.
local function Copy(value, seen, depth, checkpoint)
    if checkpoint then checkpoint() end
    if issecretvalue and issecretvalue(value) then return "<secret>" end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then return value end
    if kind == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then return value end
        return tostring(value)
    end
    if kind ~= "table" then return nil end
    seen, depth = seen or {}, depth or 0
    if seen[value] or depth > 18 then return "<cycle or depth limit>" end
    seen[value] = true
    local result = {}
    for key, entry in pairs(value) do
        if not (issecretvalue and issecretvalue(key)) and (type(key) == "string" or type(key) == "number") then
            result[key] = Copy(entry, seen, depth + 1, checkpoint)
        end
    end
    seen[value] = nil
    return result
end

local function Now()
    return type(GetServerTime) == "function" and GetServerTime() or time()
end

local function Call(record, api, ...)
    local fn = C_TradeSkillUI and C_TradeSkillUI[api]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Copy(value) end
    record.errors = record.errors or {}
    record.errors[#record.errors + 1] = { api = api, message = tostring(value) }
end

local function Context()
    if ProfessionsFrame and type(ProfessionsFrame.IsShown) == "function" and not ProfessionsFrame:IsShown() then return nil end
    local base = Call({}, "GetBaseProfessionInfo")
    local child = Call({}, "GetChildProfessionInfo")
    if not base or not tonumber(base.professionID) or base.professionID <= 0 then return nil end
    return tostring(base.professionID) .. ":" .. tostring(child and child.professionID or 0), base, child
end

function Dev:Log(message)
    self.logs[#self.logs + 1] = { timestamp = Now(), message = tostring(message) }
    if #self.logs > 200 then table.remove(self.logs, 1) end
end

function Dev:GetDB()
    if type(CraftSimEnhancerDevDB) ~= "table" or CraftSimEnhancerDevDB.schemaVersion ~= 1 then
        CraftSimEnhancerDevDB = { schemaVersion = 1, captures = {} }
    end
    CraftSimEnhancerDevDB.captures = CraftSimEnhancerDevDB.captures or {}
    return CraftSimEnhancerDevDB
end

function Dev:Cancel(reason)
    if not self.active then return end
    if self.active.finalization then self.active.finalization.cancelled = true end
    self.active = nil
    ns:Print(reason or "Profession dump cancelled; previously completed dumps are unchanged.")
end

function Dev:Dump(catalog)
    if self.active then
        ns:Print("A profession dump is running. Use /cse dev status or /cse dev cancel.")
        return
    end
    local context, base, child
    if catalog then context = "catalog"
    else context, base, child = Context() end
    if not C_TradeSkillUI or (catalog and type(C_TradeSkillUI.GetRecipeSchematic) ~= "function") then
        ns:Print("Developer dump unavailable: profession schematic API missing.")
        return
    end
    if not catalog and (not context or type(C_TradeSkillUI.GetAllRecipeIDs) ~= "function") then
        ns:Print("Open your profession window, wait for recipes to load, then use /cse dev dump.")
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        ns:Print("Profession dump unavailable: timer API missing.")
        return
    end
    local header = { errors = {} }
    local recipeIDs = catalog and {} or Call(header, "GetAllRecipeIDs")
    if not catalog and (type(recipeIDs) ~= "table" or #recipeIDs == 0) then
        ns:Print("No profession recipes are available yet. Wait for the profession to load and retry.")
        return
    end
    local dump = {
        startedAt = Now(), baseProfession = base, childProfession = child,
        recipes = {}, categories = {}, items = {}, errors = header.errors,
        counts = { recipes = 0, schematics = 0, incompleteRecipes = 0, items = 0, uncachedItems = 0, foreignRecipes = 0 },
        context = context, recipeSources = {},
        apiAvailability = {}, mode = catalog and "catalog" or "profession",
    }
    for _, api in ipairs({ "GetAllRecipeIDs", "GetRecipeInfo", "GetRecipeSchematic", "GetRecipeOutputItemData",
        "GetRecipeQualityItemIDs", "GetProfessionInfoByRecipeID", "GetCategoryInfo" }) do
        dump.apiAvailability[api] = type(C_TradeSkillUI[api]) == "function"
    end
    local ids, seen, generatedByID = {}, {}, {}
    local function AddID(id, source)
        id = tonumber(id)
        if not id or id <= 0 then return end
        if not seen[id] then ids[#ids + 1] = id; seen[id] = true end
        dump.recipeSources[id] = dump.recipeSources[id] or {}
        dump.recipeSources[id][source] = true
    end
    for _, id in ipairs(recipeIDs) do AddID(id, "professionAPI") end
    local scanner = ns.Modules.AuctionHouseScan
    local professionName
    for _, info in ipairs(scanner and scanner.PROFESSIONS or {}) do
        if base and info.enum == base.profession then professionName = info.name; break end
    end
    local allRecipes = ns.Catalog and ns.Catalog:GetIndex().recipes or ns.Data.GeneratedRecipes or {}
    for _, recipe in ipairs(allRecipes) do
        if catalog or (professionName and recipe.profession == professionName) then
            AddID(recipe.recipeID, "generatedData")
            if recipe.recipeID then generatedByID[recipe.recipeID] = recipe end
        end
    end
    if #ids == 0 then ns:Print("No generated recipe IDs are available for a catalog dump."); return end
    table.sort(ids)
    dump.requestedRecipeIDs = ids
    dump.scope = catalog and "Generated recipe IDs across all supported professions and eras; client visibility only."
        or "Current profession API recipe list plus generated recipes for that profession; client visibility only."
    local job = { dump = dump, ids = ids, index = 1, context = context, itemIDs = {} }
    self.active = job

    local function AddItem(id)
        id = tonumber(id)
        if not id or id <= 0 or job.itemIDs[id] then return end
        job.itemIDs[id] = true
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    local function Category(id)
        id = tonumber(id)
        if not id or id <= 0 or dump.categories[id] then return end
        local category = Call(dump, "GetCategoryInfo", id)
        dump.categories[id] = category or { unavailable = true }
        if category then Category(category.parentCategoryID) end
    end
    local function CaptureSnapshot(checkpoint)
        local function Snapshot(value) return Copy(value, nil, nil, checkpoint) end
        if self.active ~= job then return end
        if not catalog and Context() ~= job.context then self:Cancel("Profession changed; dump cancelled. Run it again in the new profession."); return end
        local itemFields = { "name", "link", "quality", "itemLevel", "minLevel", "class", "subclass", "maxStack",
            "equipLocation", "icon", "sellPriceCopper", "classID", "subclassID", "bindType", "expansionID", "setID", "isReagent" }
        for id in pairs(job.itemIDs) do
            local item = { generatedMetadata = Snapshot(ns.Data.ItemMetadata[id]) }
            if C_Item and type(C_Item.GetItemInfo) == "function" then
                local values = { pcall(C_Item.GetItemInfo, id) }
                if values[1] then
                    for index, field in ipairs(itemFields) do item[field] = Snapshot(values[index + 1]) end
                else item.error = tostring(values[2]) end
            end
            item.cached = item.name ~= nil
            dump.items[id] = item
            dump.counts.items = dump.counts.items + 1
            if not item.cached then dump.counts.uncachedItems = dump.counts.uncachedItems + 1 end
            checkpoint()
        end
        dump.completedAt = Now()
        dump.complete = dump.counts.incompleteRecipes == 0 and dump.counts.uncachedItems == 0
            and dump.counts.foreignRecipes == 0 and #dump.errors == 0
        local buildVersion, buildNumber, buildDate, interface = GetBuildInfo()
        local compat = ns.Compat.CraftSim
        local crafter = ns.Compat.WoW:GetCrafterUID()
        dump.crafter = crafter
        local environment = { addonVersion = ns.version, wowVersion = buildVersion, wowBuild = buildNumber,
            wowBuildDate = buildDate, interface = interface, locale = GetLocale(),
            craftSimVersion = compat:GetVersion(), moduleStatus = Snapshot(ns.ModuleStatus), warnings = Snapshot(ns.warnings) }
        local generatedData = { recipes = Snapshot(allRecipes), metadata = Snapshot(ns.Data.ItemMetadata),
            categories = Snapshot(ns.Data.RecipeCategories), source = Snapshot(ns.Data.CatalogSource) }
        local diagnostics = { capturedAt = Now(), settings = Snapshot(ns.Config.db), logs = Snapshot(self.logs),
            performance = ns.Catalog and Snapshot(ns.Catalog.perf),
            craftSimPriceOverrides = Snapshot(type(CraftSimDB) == "table" and CraftSimDB.priceOverrideDB and
                CraftSimDB.priceOverrideDB.data),
            scanner = scanner and { isScanning = scanner.isScanning, scanComplete = scanner.scanComplete,
                completedTargets = scanner.completedTargets, totalTargets = scanner.totalTargets,
                priceResults = Snapshot(scanner.priceResults), missingResults = Snapshot(scanner.missingResults) } }
        return { environment = environment, generatedData = generatedData, diagnostics = diagnostics, crafter = crafter }
    end
    local function Publish(snapshot)
        if self.active ~= job or not snapshot then return end
        if not catalog and Context() ~= job.context then self:Cancel("Profession changed; dump cancelled. Run it again in the new profession."); return end
        local db = self:GetDB()
        db.environment, db.generatedData, db.diagnostics = snapshot.environment, snapshot.generatedData, snapshot.diagnostics
        db.captures[tostring(snapshot.crafter) .. ":" .. context] = dump
        self.active = nil
        ns:Print(string.format("Dump captured: %d recipes, %d schematics, %d incomplete, %d uncached items, %d foreign recipes. Use /reload to save to disk.",
            dump.counts.recipes, dump.counts.schematics, dump.counts.incompleteRecipes, dump.counts.uncachedItems, dump.counts.foreignRecipes))
        ns:Print("File: WTF/Account/<account>/SavedVariables/CraftSimEnhancer.lua (CraftSimEnhancerDevDB).")
    end
    local function Finish()
        if self.active ~= job then return end
        if ns.Catalog then
            job.finalization = ns.Catalog:RunJob(CaptureSnapshot, Publish, function(message)
                if self.active == job then self:Cancel("Dump finalization failed: " .. message) end
            end)
        else Publish(CaptureSnapshot(function() end)) end
    end
    local function Batch()
        if self.active ~= job then return end
        if not catalog and Context() ~= job.context then self:Cancel("Profession changed; dump cancelled. Run it again in the new profession."); return end
        local started = ns.Catalog and ns.Catalog:Now() or 0
        local last = math.min(job.index + BATCH_SIZE - 1, #ids)
        for index = job.index, last do
            local id = ids[index]
            local record = { recipeID = id }
            local generated = generatedByID[id]
            if generated then
                record.generatedProfession = generated.profession
                record.generatedRecipeName = generated.stratName
                record.generatedCatalogOnlyReason = generated.catalogOnlyReason
            end
            record.profession = Call(record, "GetProfessionInfoByRecipeID", id)
            local recipeBase = record.profession and record.profession.parentProfessionID
            if not recipeBase or recipeBase <= 0 then recipeBase = record.profession and record.profession.professionID end
            if not catalog and recipeBase and recipeBase ~= base.professionID then
                record.foreignProfession = true
                dump.counts.foreignRecipes = dump.counts.foreignRecipes + 1
            else
                record.info = Call(record, "GetRecipeInfo", id)
                record.schematic = Call(record, "GetRecipeSchematic", id, false)
                if (record.info and record.info.recipeID and record.info.recipeID ~= id) or
                    (record.schematic and record.schematic.recipeID and record.schematic.recipeID ~= id) then
                    record.recipeIDMismatch = true
                end
                if record.schematic and not record.recipeIDMismatch then dump.counts.schematics = dump.counts.schematics + 1 end
                record.output = Call(record, "GetRecipeOutputItemData", id)
                record.qualityItemIDs = Call(record, "GetRecipeQualityItemIDs", id)
                record.outputsByQuality = {}
                if record.info and record.info.supportsQualities then
                    local maxQuality = tonumber(record.info.maxQuality) or #(record.qualityItemIDs or {})
                    if maxQuality == 0 then record.qualityDataIncomplete = true end
                    for quality = 1, math.min(maxQuality, 5) do
                        local output = Call(record, "GetRecipeOutputItemData", id, nil, nil, quality)
                        record.outputsByQuality[quality] = output
                        if output then AddItem(output.itemID)
                        else record.qualityDataIncomplete = true end
                    end
                end
                if record.info then Category(record.info.categoryID) end
                if record.schematic then
                    AddItem(record.schematic.outputItemID)
                    for _, slot in ipairs(record.schematic.reagentSlotSchematics or {}) do
                        for _, reagent in ipairs(slot.reagents or {}) do AddItem(reagent.itemID) end
                    end
                end
                if record.output then AddItem(record.output.itemID) end
                for _, itemID in pairs(record.qualityItemIDs or {}) do AddItem(itemID) end
                record.savedCraftingCosts = {}
                local outputIDs = Copy(record.qualityItemIDs) or {}
                for quality, output in pairs(record.outputsByQuality) do outputIDs[quality] = output.itemID end
                if next(outputIDs) == nil then
                    outputIDs[1] = record.output and record.output.itemID or record.schematic and record.schematic.outputItemID
                end
                for quality, itemID in pairs(outputIDs) do
                    local getter = ns.Compat.CraftSim.GetLastCraftingCost
                    if type(getter) == "function" then
                        local ok, cost, timestamp, crafter = pcall(getter, ns.Compat.CraftSim, itemID, quality)
                        if ok and cost then record.savedCraftingCosts[quality] = {
                            itemID = itemID, copper = cost, timestamp = timestamp, crafter = crafter } end
                    end
                end
            end
            record.incomplete = record.recipeIDMismatch or record.foreignProfession or record.qualityDataIncomplete or not record.profession or not record.info or
                not record.schematic or record.errors ~= nil
            if record.incomplete then dump.counts.incompleteRecipes = dump.counts.incompleteRecipes + 1 end
            dump.recipes[id] = record
            dump.counts.recipes = dump.counts.recipes + 1
            job.index = index + 1
            if ns.Catalog and ns.Catalog:Now() - started >= 2 then break end
        end
        if job.index <= #ids then C_Timer.After(0.05, Batch)
        else C_Timer.After(2, Finish) end -- Give requested item data time to arrive; missing items remain explicit.
    end
    if catalog then ns:Print(string.format("Capturing %d known recipe IDs across professions. A profession window is not required.", #ids))
    else ns:Print(string.format("Capturing %d recipe IDs. Keep this profession open until the completion message.", #ids)) end
    C_Timer.After(0, Batch)
end

function Dev:HandleCommand(command)
    if command == "dump" then self:Dump()
    elseif command == "catalog" then self:Dump(true)
    elseif command == "perf" then self:PrintPerformance()
    elseif command == "cancel" then self:Cancel()
    elseif command == "clear" then
        self:Cancel()
        CraftSimEnhancerDevDB = nil
        self.logs = {}
        ns:Print("Developer dumps cleared; /reload saves the change. Addon settings are unchanged.")
    elseif command == "status" then
        if self.active and self.active.finalization then
            ns:Print("Finalizing the export in background batches. Wait for the completion message.")
        elseif self.active then
            ns:Print(string.format("Dump progress: %d / %d recipes.", self.active.index - 1, #self.active.ids))
        else
            local count = 0
            for _ in pairs(type(CraftSimEnhancerDevDB) == "table" and CraftSimEnhancerDevDB.captures or {}) do count = count + 1 end
            ns:Print("No dump running. Saved captures: " .. count .. ". /reload writes captures to disk.")
        end
    else ns:Print("Usage: /cse dev <dump|catalog|perf|status|cancel|clear>") end
end

function Dev:PrintPerformance()
    if not ns.Catalog then ns:Print("Catalog performance metrics are unavailable."); return end
    local index, perf = ns.Catalog:GetIndex(), ns.Catalog.perf
    ns:Print(string.format("Catalog: %d recipes (%d catalog-only); one-time index %.2f ms.",
        #index.recipes, index.catalogOnly, perf.indexBuildMs or 0))
    ns:Print(string.format("Last view: %d recipes / %d targets; largest preparation slice %.2f ms; %d cache hits.",
        perf.configRecipes or 0, perf.configTargets or 0, perf.maxConfigSliceMs or 0, perf.configCacheHits or 0))
    ns:Print(string.format("Tree: %d entries, %.2f ms; allocated rows: %d recipes / %d items.",
        perf.treeRows or 0, perf.treeBuildMs or 0, perf.allocatedRecipeRows or 0, perf.allocatedItemRows or 0))
    ns:Print(string.format("Last scan build considered %d recipes; selected-count build %.2f ms; largest scan-preparation slice %.2f ms.",
        perf.lastScanRecipeCount or 0, perf.selectedTargetsMs or perf.maxSelectionSliceMs or 0,
        perf.maxScanPreparationSliceMs or 0))
    if ns.RecipeAvailability then
        local availability = ns.RecipeAvailability
        local character, learned, unlearned = availability:GetCharacter(), 0, 0
        for _, known in pairs(character.recipes) do
            if known then learned = learned + 1 else unlearned = unlearned + 1 end
        end
        ns:Print(string.format("Availability this login: %d learned / %d unlearned; other recipes unchecked; last refresh %d IDs, largest slice %.2f ms.",
            learned, unlearned, availability.lastRecipeCount or 0, availability.maxSliceMs or 0))
    end
    local update = C_AddOns and C_AddOns.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local memory = C_AddOns and C_AddOns.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if type(update) == "function" and type(memory) == "function" then
        pcall(update)
        local ok, value = pcall(memory, ns.name)
        if ok and tonumber(value) then ns:Print(string.format("Addon memory snapshot: %.2f MB.", value / 1024)) end
    end
    ns:Print("Timings are observations on this client, not an FPS guarantee. No continuous profiler is enabled.")
end
