local _, ns = ...
local Availability = { characters = {}, revision = 0 }
ns.RecipeAvailability = Availability

local function Call(api, ...)
    local fn = C_TradeSkillUI and C_TradeSkillUI[api]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function Availability:GetCharacter()
    local uid = ns.Compat.WoW:GetCrafterUID()
    self.characters[uid] = self.characters[uid] or { recipes = {}, professions = {} }
    return self.characters[uid], uid
end

function Availability:GetState(recipe, character)
    character = character or self:GetCharacter()
    local learned = recipe.recipeID and character.recipes[recipe.recipeID]
    if learned == true then return "LEARNED" end
    if learned == false then return "UNLEARNED" end
    return "UNCHECKED"
end

function Availability:Matches(recipe, filter, character)
    return filter == "ALL" or self:GetState(recipe, character) == filter
end

-- Confirm that recipe info comes from the player's own loaded profession.
-- Missing checks fail closed; linked, guild and NPC views never seed the cache.
function Availability:GetContext()
    if Call("IsTradeSkillLinked") ~= false or Call("IsTradeSkillGuild") ~= false or
        Call("IsNPCCrafting") ~= false or Call("IsTradeSkillReady") ~= true then return nil end
    if ProfessionsFrame and not ProfessionsFrame:IsShown() then return nil end
    local base, child = Call("GetBaseProfessionInfo"), Call("GetChildProfessionInfo")
    if not base or not tonumber(base.professionID) or base.professionID <= 0 then return nil end
    local _, uid = self:GetCharacter()
    return uid .. ":" .. base.professionID .. ":" .. tostring(child and child.professionID or 0), base.professionID
end

function Availability:NotifyChanged()
    self.revision = self.revision + 1
    local scanner = ns.Modules.AuctionHouseScan
    if not scanner then return end
    scanner.recipeTreeCache, scanner.catalogVisibleSummary = nil, nil
    if scanner.treePreparation and scanner.treePreparation.job then scanner.treePreparation.job.cancelled = true end
    if scanner.selectedPreparation and scanner.selectedPreparation.job then scanner.selectedPreparation.job.cancelled = true end
    scanner.treePreparation, scanner.selectedPreparation = nil, nil
    scanner:InvalidateScanConfiguration()
    if scanner.isPreparing and ns.Config.AuctionHouseScan:IsScanLearnedOnly() then
        scanner:CancelScan("Recipe availability changed; start the scan again.")
    end
    if scanner.configPanel and scanner.configPanel:IsShown() and not scanner.isScanning then scanner:UpdateConfigList() end
    if scanner.panel then scanner:UpdateButtons() end
end

function Availability:Cancel()
    if self.job and self.job.worker then self.job.worker.cancelled = true end
    self.job, self.scheduled = nil, nil
end

function Availability:Refresh(force)
    self:Cancel()
    local context, profession = self:GetContext()
    if not context then return end
    local ids = Call("GetAllRecipeIDs")
    if type(ids) ~= "table" then return end
    local character = self:GetCharacter()
    local marker = {}
    self.job = marker
    marker.worker = ns.Catalog:RunJob(function(checkpoint)
        local updates = {}
        for _, id in ipairs(ids) do
            local check = force or character.recipes[id] == nil
            local info = check and Call("GetRecipeInfo", id)
            local owner = check and Call("GetProfessionInfoByRecipeID", id)
            local parent = owner and tonumber(owner.parentProfessionID)
            local base = parent and parent > 0 and parent or owner and owner.professionID
            if info and info.recipeID == id and base == profession and type(info.learned) == "boolean" then
                updates[id] = info.learned
            end
            checkpoint()
        end
        return updates
    end, function(updates, job)
        if self.job ~= marker then return end
        self.job = nil
        if self:GetContext() ~= context then return end
        self.lastRecipeCount, self.maxSliceMs = #ids, job.maxSliceMs
        local changed = false
        for id, learned in pairs(updates) do
            if character.recipes[id] ~= learned then changed = true end
            character.recipes[id], character.professions[id] = learned, profession
        end
        if changed then self:NotifyChanged() end
    end, function()
        if self.job == marker then self.job = nil end
    end)
end

function Availability:ScheduleRefresh(force)
    if self.scheduled then
        self.scheduled.force = self.scheduled.force or force
        return
    end
    local marker = { force = force }
    self.scheduled = marker
    C_Timer.After(0.15, function()
        if self.scheduled ~= marker then return end
        self:Refresh(marker.force)
    end)
end

function Availability:TRADE_SKILL_SHOW() self:ScheduleRefresh(true) end
function Availability:TRADE_SKILL_LIST_UPDATE() self:ScheduleRefresh() end
function Availability:TRADE_SKILL_DATA_SOURCE_CHANGING() self:Cancel() end
function Availability:TRADE_SKILL_DATA_SOURCE_CHANGED() self:Cancel(); self:ScheduleRefresh(true) end
function Availability:TRADE_SKILL_CLOSE() self:Cancel() end

function Availability:NEW_RECIPE_LEARNED(recipeID)
    self:Cancel() -- Older in-flight observations must not overwrite this event.
    -- This event belongs to the player even if no profession window is open.
    local recipe = ns.Catalog:GetIndex().byID[recipeID]
    if recipe then
        local character = self:GetCharacter()
        if character.recipes[recipeID] ~= true then
            character.recipes[recipeID] = true
            local owner = Call("GetProfessionInfoByRecipeID", recipeID)
            local parent = owner and tonumber(owner.parentProfessionID)
            character.professions[recipeID] = parent and parent > 0 and parent or owner and owner.professionID
            self:NotifyChanged()
        end
    end
    self:ScheduleRefresh(true)
end

function Availability:SKILL_LINES_CHANGED()
    -- Skill ranks can change frequently. Only invalidate cached recipes when
    -- their base profession has actually been removed, rather than on each craft.
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return end
    local a, b, c, d, e = GetProfessions()
    local owned = {}
    for _, slot in pairs({ a, b, c, d, e }) do
        local id = select(7, GetProfessionInfo(slot))
        if id then owned[id] = true end
    end
    local character = self:GetCharacter()
    local ids = {}
    for id in pairs(owned) do ids[#ids + 1] = id end
    table.sort(ids)
    local signature = table.concat(ids, ":")
    if character.ownedSignature == signature then return end
    character.ownedSignature = signature
    local changed = false
    for id in pairs(character.recipes) do
        if not owned[character.professions[id]] then
            character.recipes[id], character.professions[id], changed = nil, nil, true
        end
    end
    if changed then self:Cancel(); self:NotifyChanged() end
end

function Availability:Initialize()
    if self.eventFrame then return end
    self.eventFrame = ns:CreateEventDispatcher(self, { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE",
        "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED" })
    self:ScheduleRefresh()
end
