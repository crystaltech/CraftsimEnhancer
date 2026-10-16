local ns, uid = {}, "A-Realm"
local function Load(path) assert(loadfile("CraftSimEnhancer/" .. path))("CraftSimEnhancer", ns) end
Load("Core.lua")
Load("Config.lua")
ns.Compat.WoW = { GetCrafterUID = function() return uid end }
ns.Config:Initialize()
Load("Catalog.lua")
Load("RecipeAvailability.lua")
local a = ns.RecipeAvailability
ns.Data.GeneratedRecipes = { {recipeID=1,profession="Alchemy",stratName="One"},
    {recipeID=2,profession="Alchemy",stratName="Two"}, {recipeID=3,profession="Alchemy",stratName="Three"} }
local pending, clock, reads, infoReads = {}, 0, 0, {}
debugprofilestop = function() return clock end
C_Timer = { After = function(_, callback) pending[#pending+1]=callback end }
local function Drain()
    local steps=0
    while #pending>0 do
        table.remove(pending,1)(); steps=steps+1; assert(steps<1000)
    end
    return steps
end
local linked, guild, npc, ready, base, shown = false, false, false, true, 171, true
ProfessionsFrame = { IsShown=function() return shown end }
local info = { [1]={recipeID=1,learned=true}, [2]={recipeID=2,learned=false},
    [4]={recipeID=999,learned=true}, [5]={recipeID=5,learned=true}, [6]={recipeID=6} }
C_TradeSkillUI = {
    IsTradeSkillLinked=function() return linked end, IsTradeSkillGuild=function() return guild end,
    IsNPCCrafting=function() return npc end, IsTradeSkillReady=function() return ready end,
    GetBaseProfessionInfo=function() return {professionID=base} end,
    GetChildProfessionInfo=function() return {professionID=2485} end,
    GetAllRecipeIDs=function() reads=reads+1; return {1,2,3,4,5,6,7} end,
    GetRecipeInfo=function(id) infoReads[id]=(infoReads[id] or 0)+1; clock=clock+1; if id==7 then error("Unavailable") end; return info[id] end,
    GetProfessionInfoByRecipeID=function(id) return {parentProfessionID=id==5 and 164 or 171,professionID=2485} end,
}
local function State(id) return a:GetState({recipeID=id}) end
assert(State(1)=="UNCHECKED" and a:GetState({stratName="Transform"})=="UNCHECKED")
a:Refresh()
assert(State(1)=="UNCHECKED", "work and publication are deferred")
assert(Drain()>2, "availability work yields between batches")
assert(State(1)=="LEARNED" and State(2)=="UNLEARNED", "explicit false survives cache")
for _,id in ipairs({3,4,5,6,7}) do assert(State(id)=="UNCHECKED", "missing, foreign or mismatched results remain unchecked") end
local revision=a.revision
local knownReads=infoReads[1]
a:Refresh(); Drain()
assert(infoReads[1]==knownReads, "ordinary list updates reuse confirmed recipe observations")
info[1].learned=false
a:TRADE_SKILL_SHOW(); Drain()
assert(State(1)=="UNLEARNED", "opening profession refreshes previously confirmed observations")
info[1].learned=true
a:TRADE_SKILL_SHOW(); Drain()
revision=a.revision
a:Refresh(); Drain()
assert(a.revision==revision, "unchanged data does not invalidate caches")
uid="B-Realm"
assert(State(1)=="UNCHECKED", "character cache isolation")
for _, kind in ipairs({"linked","guild","npc","not-ready","closed","missing-api"}) do
    linked, guild, npc, ready, shown = kind=="linked", kind=="guild", kind=="npc", kind~="not-ready", kind~="closed"
    local saved=C_TradeSkillUI.IsTradeSkillLinked
    if kind=="missing-api" then C_TradeSkillUI.IsTradeSkillLinked=nil end
    local previous=reads
    a:Refresh(); Drain()
    assert(reads==previous and State(1)=="UNCHECKED",kind .. " must not seed state")
    C_TradeSkillUI.IsTradeSkillLinked=saved
end
linked, guild, npc, ready, shown=false,false,false,true,true
a:Refresh()
table.remove(pending,1)() -- Partial private batch.
a:TRADE_SKILL_CLOSE(); Drain()
assert(State(1)=="UNCHECKED", "cancelled refresh does not publish partial state")
a:Refresh()
table.remove(pending,1)()
base=164
Drain()
assert(State(1)=="UNCHECKED" and not a.job, "context switch without event rejects stale publication")
base=171
a:ScheduleRefresh(); a:ScheduleRefresh(); a:ScheduleRefresh()
assert(#pending==1, "burst events coalesce")
Drain()
assert(State(1)=="LEARNED")
-- A new-learn event cancels old observations and updates the player cache.
a:Refresh(); table.remove(pending,1)()
a:NEW_RECIPE_LEARNED(2)
assert(State(2)=="LEARNED")
a:TRADE_SKILL_CLOSE(); Drain()
assert(State(2)=="LEARNED", "old batch cannot overwrite a new-learn event")
local owned=true
GetProfessions=function() if owned then return 1 end end
GetProfessionInfo=function() return "Alchemy",nil,1,100,0,0,171 end
a:SKILL_LINES_CHANGED()
assert(State(1)=="LEARNED" and State(2)=="LEARNED", "skill rank update retains ownership")
revision=a.revision
a:SKILL_LINES_CHANGED()
assert(a.revision==revision, "same profession signature avoids full invalidation")
owned=false
a:SKILL_LINES_CHANGED()
assert(State(1)=="UNCHECKED" and State(2)=="UNCHECKED", "forgetting profession invalidates its observations")
uid="A-Realm"
assert(State(1)=="LEARNED", "other character unaffected")
assert(#pending==0, "finished availability work leaves no polling callbacks")
print("Recipe availability tests passed")
