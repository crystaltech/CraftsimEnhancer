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
Scanner.presetRows = {}
Scanner.configView = "presets"
Scanner.expandedQuickSetGroups = {}
Scanner.expandedProfessionGroups = {}
Scanner.expandedCategoryGroups = {}
Scanner.missingRows = {}
Scanner.activeConfigPresets = {}
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

Scanner.PRESET_IDS = {
    ALL = "ALL",
    NONE = "NONE",
    INPUTS = "INPUTS",
    OUTPUTS = "OUTPUTS",
    COMMODITIES = "COMMODITIES",
    EQUIPMENT = "EQUIPMENT",
    ARMOR = "ARMOR",
    ARMOR_CLOTH = "ARMOR_CLOTH",
    ARMOR_LEATHER = "ARMOR_LEATHER",
    ARMOR_MAIL = "ARMOR_MAIL",
    ARMOR_PLATE = "ARMOR_PLATE",
    JEWELRY = "JEWELRY",
    SHIELDS = "SHIELDS",
    CLOAKS = "CLOAKS",
    WEAPONS = "WEAPONS",
    ONE_HAND_WEAPONS = "ONE_HAND_WEAPONS",
    TWO_HAND_WEAPONS = "TWO_HAND_WEAPONS",
    RANGED_WEAPONS = "RANGED_WEAPONS",
    PROFESSION_TOOLS = "PROFESSION_TOOLS",
    ENCHANTS = "ENCHANTS",
    WEAPON_ENCHANTS = "WEAPON_ENCHANTS",
    RING_ENCHANTS = "RING_ENCHANTS",
    ARMOR_ENCHANTS = "ARMOR_ENCHANTS",
    TOOL_ENCHANTS = "TOOL_ENCHANTS",
    ARMOR_KITS = "ARMOR_KITS",
    SPELLTHREADS = "SPELLTHREADS",
    GEMS = "GEMS",
    RAID_CONSUMABLES = "RAID_CONSUMABLES",
    CONSUMABLES = "CONSUMABLES",
    POTIONS = "POTIONS",
    FLASKS_PHIALS = "FLASKS_PHIALS",
    FOOD_FEASTS = "FOOD_FEASTS",
    VANTUS_RUNES = "VANTUS_RUNES",
    BANDAGES = "BANDAGES",
    TEMPORARY_ENHANCEMENTS = "TEMPORARY_ENHANCEMENTS",
    MATERIALS = "MATERIALS",
    HERBS = "HERBS",
    ORE_STONE = "ORE_STONE",
    CLOTH_MATERIALS = "CLOTH_MATERIALS",
    LEATHER_MATERIALS = "LEATHER_MATERIALS",
    COOKING_MATERIALS = "COOKING_MATERIALS",
    ELEMENTAL_MATERIALS = "ELEMENTAL_MATERIALS",
    ENCHANTING_MATERIALS = "ENCHANTING_MATERIALS",
    ENGINEERING_PARTS = "ENGINEERING_PARTS",
    JEWELCRAFTING_MATERIALS = "JEWELCRAFTING_MATERIALS",
    INSCRIPTION_MATERIALS = "INSCRIPTION_MATERIALS",
    OPTIONAL_REAGENTS = "OPTIONAL_REAGENTS",
    FINISHING_REAGENTS = "FINISHING_REAGENTS",
    CONTAINERS = "CONTAINERS",
    BAGS = "BAGS",
    REAGENT_BAGS = "REAGENT_BAGS",
    HOUSING = "HOUSING",
    CONTRACTS = "CONTRACTS",
    DARKMOON_CARDS = "DARKMOON_CARDS",
    COSMETICS = "COSMETICS",
    TRANSFORMS = "TRANSFORMS",
    TRANSMUTES = "TRANSMUTES",
    MILLING = "MILLING",
    PROSPECTING = "PROSPECTING",
    SHATTER = "SHATTER",
    ALCHEMY_REAGENTS = "ALCHEMY_REAGENTS",
    ALLOYS = "ALLOYS",
    WEAPON_STONES = "WEAPON_STONES",
    INKS_PIGMENTS = "INKS_PIGMENTS",
    MISSIVES = "MISSIVES",
    TREATISES = "TREATISES",
    CODEXES = "CODEXES",
    ENGINEERING_DEVICES = "ENGINEERING_DEVICES",
    ENGINEERING_GOGGLES = "ENGINEERING_GOGGLES",
    SCOPES_AMMO = "SCOPES_AMMO",
    FISH_MEAT = "FISH_MEAT",
    JEWELCRAFTING_REFINES = "JEWELCRAFTING_REFINES",
    LEATHERWORKING_DRUMS = "LEATHERWORKING_DRUMS",
    TAILORING_BOLTS = "TAILORING_BOLTS",
    COMPETITOR_GEAR = "COMPETITOR_GEAR",
}

Scanner.SCAN_SCOPES = {
    PRODUCTS = "PRODUCTS",
    REAGENTS = "REAGENTS",
    BOTH = "BOTH",
}

Scanner.PRESET_CATEGORY_TAGS = {
    [Scanner.PRESET_IDS.EQUIPMENT] = { "armor", "weapon", "jewelry", "profession_tool", "cloak", "armor_shield" },
    [Scanner.PRESET_IDS.ARMOR] = { "armor" },
    [Scanner.PRESET_IDS.ARMOR_CLOTH] = { "armor_cloth" },
    [Scanner.PRESET_IDS.ARMOR_LEATHER] = { "armor_leather" },
    [Scanner.PRESET_IDS.ARMOR_MAIL] = { "armor_mail" },
    [Scanner.PRESET_IDS.ARMOR_PLATE] = { "armor_plate" },
    [Scanner.PRESET_IDS.JEWELRY] = { "jewelry" },
    [Scanner.PRESET_IDS.SHIELDS] = { "armor_shield" },
    [Scanner.PRESET_IDS.CLOAKS] = { "cloak" },
    [Scanner.PRESET_IDS.WEAPONS] = { "weapon" },
    [Scanner.PRESET_IDS.ONE_HAND_WEAPONS] = { "weapon_one_hand" },
    [Scanner.PRESET_IDS.TWO_HAND_WEAPONS] = { "weapon_two_hand" },
    [Scanner.PRESET_IDS.RANGED_WEAPONS] = { "weapon_ranged" },
    [Scanner.PRESET_IDS.PROFESSION_TOOLS] = { "profession_tool" },
    [Scanner.PRESET_IDS.ENCHANTS] = { "enchant" },
    [Scanner.PRESET_IDS.WEAPON_ENCHANTS] = { "enchant_weapon" },
    [Scanner.PRESET_IDS.RING_ENCHANTS] = { "enchant_ring" },
    [Scanner.PRESET_IDS.ARMOR_ENCHANTS] = {
        "enchant_head", "enchant_shoulder", "enchant_cloak", "enchant_chest", "enchant_wrist",
        "enchant_hands", "enchant_waist", "enchant_legs", "enchant_feet", "enchant_shield_offhand",
    },
    [Scanner.PRESET_IDS.TOOL_ENCHANTS] = { "enchant_tool" },
    [Scanner.PRESET_IDS.ARMOR_KITS] = { "armor_kit" },
    [Scanner.PRESET_IDS.SPELLTHREADS] = { "spellthread" },
    [Scanner.PRESET_IDS.GEMS] = { "gem" },
    [Scanner.PRESET_IDS.RAID_CONSUMABLES] = { "raid_consumable" },
    [Scanner.PRESET_IDS.CONSUMABLES] = { "consumable" },
    [Scanner.PRESET_IDS.POTIONS] = { "potion" },
    [Scanner.PRESET_IDS.FLASKS_PHIALS] = { "flask_phial" },
    [Scanner.PRESET_IDS.FOOD_FEASTS] = { "food_feast" },
    [Scanner.PRESET_IDS.VANTUS_RUNES] = { "vantus_rune" },
    [Scanner.PRESET_IDS.BANDAGES] = { "bandage" },
    [Scanner.PRESET_IDS.TEMPORARY_ENHANCEMENTS] = { "temporary_enhancement", "weapon_wrap" },
    [Scanner.PRESET_IDS.MATERIALS] = { "material" },
    [Scanner.PRESET_IDS.HERBS] = { "herb" },
    [Scanner.PRESET_IDS.ORE_STONE] = { "ore_stone" },
    [Scanner.PRESET_IDS.CLOTH_MATERIALS] = { "cloth_material" },
    [Scanner.PRESET_IDS.LEATHER_MATERIALS] = { "leather_material" },
    [Scanner.PRESET_IDS.COOKING_MATERIALS] = { "cooking_material" },
    [Scanner.PRESET_IDS.ELEMENTAL_MATERIALS] = { "elemental_material" },
    [Scanner.PRESET_IDS.ENCHANTING_MATERIALS] = { "enchanting_material" },
    [Scanner.PRESET_IDS.ENGINEERING_PARTS] = { "engineering_part" },
    [Scanner.PRESET_IDS.JEWELCRAFTING_MATERIALS] = { "jewelcrafting_material" },
    [Scanner.PRESET_IDS.INSCRIPTION_MATERIALS] = { "inscription_material" },
    [Scanner.PRESET_IDS.OPTIONAL_REAGENTS] = { "optional_reagent" },
    [Scanner.PRESET_IDS.FINISHING_REAGENTS] = { "finishing_reagent" },
    [Scanner.PRESET_IDS.CONTAINERS] = { "container" },
    [Scanner.PRESET_IDS.BAGS] = { "bag" },
    [Scanner.PRESET_IDS.REAGENT_BAGS] = { "reagent_bag" },
    [Scanner.PRESET_IDS.HOUSING] = { "housing" },
    [Scanner.PRESET_IDS.CONTRACTS] = { "contract" },
    [Scanner.PRESET_IDS.DARKMOON_CARDS] = { "darkmoon_card" },
    [Scanner.PRESET_IDS.COSMETICS] = { "cosmetic", "illusion" },
    [Scanner.PRESET_IDS.TRANSFORMS] = { "transform" },
    [Scanner.PRESET_IDS.TRANSMUTES] = { "transmute" },
    [Scanner.PRESET_IDS.MILLING] = { "milling" },
    [Scanner.PRESET_IDS.PROSPECTING] = { "prospecting" },
    [Scanner.PRESET_IDS.SHATTER] = { "shatter" },
    [Scanner.PRESET_IDS.ALCHEMY_REAGENTS] = { "herb", "elemental_material" },
    [Scanner.PRESET_IDS.ALLOYS] = { "ore_stone" },
    [Scanner.PRESET_IDS.WEAPON_STONES] = { "temporary_enhancement", "weapon_wrap" },
    [Scanner.PRESET_IDS.INKS_PIGMENTS] = { "inscription_material" },
    [Scanner.PRESET_IDS.ENGINEERING_GOGGLES] = { "armor_cloth", "armor_leather", "armor_mail", "armor_plate" },
    [Scanner.PRESET_IDS.FISH_MEAT] = { "cooking_material" },
    [Scanner.PRESET_IDS.TAILORING_BOLTS] = { "cloth_material" },
}

Scanner.PRESET_TEXT_PATTERNS = {
    [Scanner.PRESET_IDS.ARMOR] = {
        "armor", "armguards", "banding", "basinet", "belt", "bracer", "bracers", "breastplate",
        "chest", "chestplate", "cloak", "cuffs", "gauntlets", "gloves", "greaves", "guards",
        "helm", "leggings", "pauldrons", "robe", "sabatons", "shield", "shoulders", "waistguard",
    },
    [Scanner.PRESET_IDS.ARMOR_CLOTH] = { "cloth", "robe", "cowl", "slippers", "wraps" },
    [Scanner.PRESET_IDS.ARMOR_LEATHER] = { "leather", "leathers", "hide", "boots", "grips" },
    [Scanner.PRESET_IDS.ARMOR_MAIL] = { "mail", "chain", "hauberk" },
    [Scanner.PRESET_IDS.ARMOR_PLATE] = { "plate", "breastplate", "gauntlets", "sabatons" },
    [Scanner.PRESET_IDS.JEWELRY] = { "ring", "necklace", "amulet", "pendant", "choker", "trinket" },
    [Scanner.PRESET_IDS.SHIELDS] = { "shield", "buckler", "bulwark" },
    [Scanner.PRESET_IDS.CLOAKS] = { "cloak", "cape", "drape" },
    [Scanner.PRESET_IDS.WEAPONS] = {
        "axe", "blade", "bow", "bulwark", "claw", "dagger", "edge", "glaive", "greatsword", "gun",
        "knife", "knuckles", "mace", "polearm", "shield", "splitter", "staff", "sword", "wand",
        "warblade", "weapon",
    },
    [Scanner.PRESET_IDS.ONE_HAND_WEAPONS] = { "dagger", "fist", "knife", "mace", "sword", "warglaive", "wand" },
    [Scanner.PRESET_IDS.TWO_HAND_WEAPONS] = { "greatsword", "polearm", "staff", "two-handed", "warblade" },
    [Scanner.PRESET_IDS.RANGED_WEAPONS] = { "bow", "crossbow", "gun", "ranged" },
    [Scanner.PRESET_IDS.PROFESSION_TOOLS] = {
        "apron", "bag", "backpack", "clampers", "cover", "cutters", "fishing rod", "hardhat",
        "hat", "knife", "multitool", "needle set", "pickaxe", "profession tool", "rod", "sickle",
        "snippers", "toolbox", "toolset",
    },
    [Scanner.PRESET_IDS.ENCHANTS] = { "enchant ", "enchantment" },
    [Scanner.PRESET_IDS.WEAPON_ENCHANTS] = { "enchant weapon", "weapon enchantment" },
    [Scanner.PRESET_IDS.RING_ENCHANTS] = { "enchant ring", "ring enchantment" },
    [Scanner.PRESET_IDS.ARMOR_ENCHANTS] = {
        "enchant chest", "enchant cloak", "enchant boots", "enchant bracer", "enchant bracers",
        "enchant gloves", "enchant helm", "enchant shoulder", "enchant shield", "armor banding",
    },
    [Scanner.PRESET_IDS.TOOL_ENCHANTS] = { "enchant tool", "tool enchantment" },
    [Scanner.PRESET_IDS.ARMOR_KITS] = { "armor kit" },
    [Scanner.PRESET_IDS.SPELLTHREADS] = { "spellthread" },
    [Scanner.PRESET_IDS.GEMS] = {
        "gem", "peridot", "lapis", "amethyst", "sapphire", "diamond", "emerald", "ruby", "onyx",
        "opal", "amber", "topaz",
    },
    [Scanner.PRESET_IDS.RAID_CONSUMABLES] = {
        "potion", "flask", "phial", "cauldron", "feast", "food", "rune", "enchant", "mana", "health",
    },
    [Scanner.PRESET_IDS.POTIONS] = { "potion" },
    [Scanner.PRESET_IDS.FLASKS_PHIALS] = { "flask", "phial", "cauldron" },
    [Scanner.PRESET_IDS.FOOD_FEASTS] = { "food", "feast", "meal", "banquet" },
    [Scanner.PRESET_IDS.VANTUS_RUNES] = { "vantus rune" },
    [Scanner.PRESET_IDS.BANDAGES] = { "bandage" },
    [Scanner.PRESET_IDS.TEMPORARY_ENHANCEMENTS] = {
        "oil", "razorstone", "sharpening stone", "temporary", "weapon wrap", "weightstone", "whetstone",
    },
    [Scanner.PRESET_IDS.HERBS] = { "herb", "flower", "blossom", "pollen" },
    [Scanner.PRESET_IDS.ORE_STONE] = { "alloy", "bar", "ingot", "metal", "ore", "stone" },
    [Scanner.PRESET_IDS.CLOTH_MATERIALS] = { "bolt", "cloth", "thread", "weave" },
    [Scanner.PRESET_IDS.LEATHER_MATERIALS] = { "hide", "leather", "scale", "scales" },
    [Scanner.PRESET_IDS.COOKING_MATERIALS] = { "meat", "fish", "spice" },
    [Scanner.PRESET_IDS.ELEMENTAL_MATERIALS] = { "air", "earth", "elemental", "fire", "frost", "water" },
    [Scanner.PRESET_IDS.ENCHANTING_MATERIALS] = { "crystal", "dust", "enchanting", "shard" },
    [Scanner.PRESET_IDS.ENGINEERING_PARTS] = { "cog", "gear", "part", "parts", "sprocket", "widget" },
    [Scanner.PRESET_IDS.JEWELCRAFTING_MATERIALS] = { "jewelcrafting", "gem", "jewel" },
    [Scanner.PRESET_IDS.INSCRIPTION_MATERIALS] = { "ink", "inscription", "pigment" },
    [Scanner.PRESET_IDS.OPTIONAL_REAGENTS] = { "optional reagent" },
    [Scanner.PRESET_IDS.FINISHING_REAGENTS] = { "finishing reagent" },
    [Scanner.PRESET_IDS.CONTAINERS] = { "bag", "backpack", "satchel", "toolbox", "toolset" },
    [Scanner.PRESET_IDS.BAGS] = { "bag", "backpack", "satchel" },
    [Scanner.PRESET_IDS.REAGENT_BAGS] = { "reagent bag", "reagent satchel" },
    [Scanner.PRESET_IDS.CONTRACTS] = { "contract:" },
    [Scanner.PRESET_IDS.DARKMOON_CARDS] = { "darkmoon card", "darkmoon deck", "darkmoon sigil" },
    [Scanner.PRESET_IDS.COSMETICS] = { "cosmetic", "glamour", "illusion:" },
    [Scanner.PRESET_IDS.TRANSFORMS] = { "milling", "prospect", "transmute" },
    [Scanner.PRESET_IDS.TRANSMUTES] = { "transmute" },
    [Scanner.PRESET_IDS.MILLING] = { "milling" },
    [Scanner.PRESET_IDS.PROSPECTING] = { "prospect" },
    [Scanner.PRESET_IDS.ALCHEMY_REAGENTS] = {
        "extract", "flora", "illuminant", "mote", "herb", "rootbound", "preserving agent", "residue",
    },
    [Scanner.PRESET_IDS.ALLOYS] = { "alloy", "ingot", "bar", "ore", "stone" },
    [Scanner.PRESET_IDS.WEAPON_STONES] = {
        "whetstone", "weightstone", "razorstone", "sharpening stone", "weapon wrap",
    },
    [Scanner.PRESET_IDS.INKS_PIGMENTS] = { "ink", "pigment", "cipher", "codified" },
    [Scanner.PRESET_IDS.MISSIVES] = { "missive" },
    [Scanner.PRESET_IDS.TREATISES] = { "treatise" },
    [Scanner.PRESET_IDS.CODEXES] = { "codex", "tome" },
    [Scanner.PRESET_IDS.ENGINEERING_DEVICES] = {
        "wormhole", "generator", "button", "m3ddy", "b0p", "w-47ch", "hu5h", "emergency", "beam",
        "travel-sized", "sprocket", "cogwheel", "gadget", "keychain",
    },
    [Scanner.PRESET_IDS.ENGINEERING_GOGGLES] = {
        "goggle", "goggles", "optics", "visor", "headlamp", "vision", "zoomshroud", "eye wrap",
    },
    [Scanner.PRESET_IDS.SCOPES_AMMO] = {
        "scope", "shots", "boomshots", "zoomshots", "rifle", "hawkeye", "p.o.w.",
    },
    [Scanner.PRESET_IDS.FISH_MEAT] = {
        "fish", "meat", "crab", "calamari", "tetra", "filet", "cutlet", "lumifin", "angler",
        "bloomtail", "puffer", "skewer", "wings",
    },
    [Scanner.PRESET_IDS.JEWELCRAFTING_REFINES] = { "refine", "crushing", "prism", "glass", "stone" },
    [Scanner.PRESET_IDS.LEATHERWORKING_DRUMS] = { "drums" },
    [Scanner.PRESET_IDS.TAILORING_BOLTS] = { "bolt", "linen", "silk", "weave", "lining" },
    [Scanner.PRESET_IDS.COMPETITOR_GEAR] = { "competitor" },
}

Scanner.PROFESSION_PRESET_MENUS = {
    Alchemy = {
        {
            label = "Consumables",
            presets = {
                { label = "Potions & Mana/Health", id = Scanner.PRESET_IDS.POTIONS },
                { label = "Flasks, Phials & Cauldrons", id = Scanner.PRESET_IDS.FLASKS_PHIALS },
                { label = "Raid Consumables", id = Scanner.PRESET_IDS.RAID_CONSUMABLES },
            },
        },
        {
            label = "Alchemy Materials",
            presets = {
                { label = "Alchemy Reagents", id = Scanner.PRESET_IDS.ALCHEMY_REAGENTS },
                { label = "Herbs", id = Scanner.PRESET_IDS.HERBS },
                { label = "Elemental Materials", id = Scanner.PRESET_IDS.ELEMENTAL_MATERIALS },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Special Crafts",
            presets = {
                { label = "Transmutes", id = Scanner.PRESET_IDS.TRANSMUTES },
                { label = "Alchemy Trinkets", id = Scanner.PRESET_IDS.JEWELRY },
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Housing & Utility", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Blacksmithing = {
        {
            label = "Gear",
            presets = {
                { label = "Weapons", id = Scanner.PRESET_IDS.WEAPONS },
                { label = "Plate Armor", id = Scanner.PRESET_IDS.ARMOR_PLATE },
                { label = "Shields", id = Scanner.PRESET_IDS.SHIELDS },
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Competitor Gear", id = Scanner.PRESET_IDS.COMPETITOR_GEAR },
            },
        },
        {
            label = "Materials & Consumables",
            presets = {
                { label = "Alloys, Ingots & Ore", id = Scanner.PRESET_IDS.ALLOYS },
                { label = "Weapon Stones", id = Scanner.PRESET_IDS.WEAPON_STONES },
                { label = "Metal/Stone Inputs", id = Scanner.PRESET_IDS.ORE_STONE },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Utility",
            presets = {
                { label = "Keys, Repair & Utility", id = Scanner.PRESET_IDS.TEMPORARY_ENHANCEMENTS },
                { label = "Housing", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Cooking = {
        {
            label = "Food",
            presets = {
                { label = "Food & Feasts", id = Scanner.PRESET_IDS.FOOD_FEASTS },
                { label = "Feasts & Raid Food", id = Scanner.PRESET_IDS.RAID_CONSUMABLES },
                { label = "Fish, Meat & Cooking Inputs", id = Scanner.PRESET_IDS.FISH_MEAT },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
    },
    Enchanting = {
        {
            label = "Enchants",
            presets = {
                { label = "All Enchants", id = Scanner.PRESET_IDS.ENCHANTS },
                { label = "Weapon Enchants", id = Scanner.PRESET_IDS.WEAPON_ENCHANTS },
                { label = "Ring Enchants", id = Scanner.PRESET_IDS.RING_ENCHANTS },
                { label = "Armor Enchants", id = Scanner.PRESET_IDS.ARMOR_ENCHANTS },
                { label = "Tool Enchants", id = Scanner.PRESET_IDS.TOOL_ENCHANTS },
            },
        },
        {
            label = "Materials & Utility",
            presets = {
                { label = "Enchanting Materials", id = Scanner.PRESET_IDS.ENCHANTING_MATERIALS },
                { label = "Shatters", id = Scanner.PRESET_IDS.SHATTER },
                { label = "Weapon Oils", id = Scanner.PRESET_IDS.TEMPORARY_ENHANCEMENTS },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Cosmetics & Gear",
            presets = {
                { label = "Glamours & Illusions", id = Scanner.PRESET_IDS.COSMETICS },
                { label = "Codexes & Tomes", id = Scanner.PRESET_IDS.CODEXES },
                { label = "Wands, Focuses & Rods", id = Scanner.PRESET_IDS.WEAPONS },
                { label = "Housing", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Engineering = {
        {
            label = "Parts & Devices",
            presets = {
                { label = "Engineering Parts", id = Scanner.PRESET_IDS.ENGINEERING_PARTS },
                { label = "Devices & Gadgets", id = Scanner.PRESET_IDS.ENGINEERING_DEVICES },
                { label = "Scopes, Shots & Rifles", id = Scanner.PRESET_IDS.SCOPES_AMMO },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Gear",
            presets = {
                { label = "Goggles & Bracers", id = Scanner.PRESET_IDS.ENGINEERING_GOGGLES },
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Competitor Gear", id = Scanner.PRESET_IDS.COMPETITOR_GEAR },
            },
        },
        {
            label = "Housing",
            presets = {
                { label = "Housing & Toys", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Inscription = {
        {
            label = "Documents",
            presets = {
                { label = "Missives", id = Scanner.PRESET_IDS.MISSIVES },
                { label = "Treatises", id = Scanner.PRESET_IDS.TREATISES },
                { label = "Contracts", id = Scanner.PRESET_IDS.CONTRACTS },
                { label = "Vantus Runes", id = Scanner.PRESET_IDS.VANTUS_RUNES },
            },
        },
        {
            label = "Cards & Reagents",
            presets = {
                { label = "Darkmoon Cards & Sigils", id = Scanner.PRESET_IDS.DARKMOON_CARDS },
                { label = "Inks, Pigments & Ciphers", id = Scanner.PRESET_IDS.INKS_PIGMENTS },
                { label = "Milling", id = Scanner.PRESET_IDS.MILLING },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Gear & Housing",
            presets = {
                { label = "Staves, Offhands & Ranged", id = Scanner.PRESET_IDS.WEAPONS },
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Housing & Decor", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Jewelcrafting = {
        {
            label = "Gems & Refines",
            presets = {
                { label = "Gems", id = Scanner.PRESET_IDS.GEMS },
                { label = "Jewelcrafting Materials", id = Scanner.PRESET_IDS.JEWELCRAFTING_MATERIALS },
                { label = "Refines & Crushing", id = Scanner.PRESET_IDS.JEWELCRAFTING_REFINES },
                { label = "Prospecting", id = Scanner.PRESET_IDS.PROSPECTING },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Jewelry & Tools",
            presets = {
                { label = "Rings, Necks & Trinkets", id = Scanner.PRESET_IDS.JEWELRY },
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Housing & Decor", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
    Leatherworking = {
        {
            label = "Armor",
            presets = {
                { label = "Leather Armor", id = Scanner.PRESET_IDS.ARMOR_LEATHER },
                { label = "Mail Armor", id = Scanner.PRESET_IDS.ARMOR_MAIL },
                { label = "Armor Kits", id = Scanner.PRESET_IDS.ARMOR_KITS },
                { label = "Competitor Gear", id = Scanner.PRESET_IDS.COMPETITOR_GEAR },
            },
        },
        {
            label = "Profession Gear & Utility",
            presets = {
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Drums", id = Scanner.PRESET_IDS.LEATHERWORKING_DRUMS },
                { label = "Weapon Wraps", id = Scanner.PRESET_IDS.WEAPON_STONES },
                { label = "Housing", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
        {
            label = "Materials",
            presets = {
                { label = "Leather, Hides & Scales", id = Scanner.PRESET_IDS.LEATHER_MATERIALS },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
    },
    Tailoring = {
        {
            label = "Cloth Goods",
            presets = {
                { label = "Bolts & Cloth Materials", id = Scanner.PRESET_IDS.TAILORING_BOLTS },
                { label = "Cloth Armor", id = Scanner.PRESET_IDS.ARMOR_CLOTH },
                { label = "Cloaks", id = Scanner.PRESET_IDS.CLOAKS },
                { label = "Competitor Gear", id = Scanner.PRESET_IDS.COMPETITOR_GEAR },
            },
        },
        {
            label = "Utility",
            presets = {
                { label = "Bags", id = Scanner.PRESET_IDS.BAGS },
                { label = "Reagent Bags", id = Scanner.PRESET_IDS.REAGENT_BAGS },
                { label = "Spellthreads", id = Scanner.PRESET_IDS.SPELLTHREADS },
                { label = "Bandages", id = Scanner.PRESET_IDS.BANDAGES },
                { label = "Commodities", id = Scanner.PRESET_IDS.COMMODITIES },
            },
        },
        {
            label = "Profession Gear & Housing",
            presets = {
                { label = "Profession Tools", id = Scanner.PRESET_IDS.PROFESSION_TOOLS },
                { label = "Housing & Decor", id = Scanner.PRESET_IDS.HOUSING },
            },
        },
    },
}

Scanner.MANUAL_ITEM_OVERRIDES = {
    [245345] = { vendorSold = true, vendorPriceCopper = 10000 },
    [274267] = { vendorSold = true, vendorPriceCopper = 10000 },
    [256963] = { skip = true, skipReason = "Bind-on-pickup reagent is not auction-sellable." },
}

local PTR_NEXT_PATCH_ITEM_IDS = {
    270898,
    270899,
    271883,
    271884,
    271886,
    271887,
    271889,
    271890,
    272194,
    272195,
    273056,
    273057,
    273059,
    273060,
    273062,
    273063,
    273065,
    273066,
    273068,
    273069,
    273071,
    273072,
    274589,
    274590,
    274591,
    274594,
    274777,
    274781,
    275258,
    275260,
    275261,
    275264,
    275265,
    275266,
    275276,
    275278,
    275303,
    275305,
    275676,
    275683,
    277968,
    277969,
    279359,
    279360,
    279361,
    279362,
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
    275327,
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

---@param target table
---@param profession string?
---@return string
function Scanner:GetPresetSearchText(target, profession)
    local parts = { string.lower(tostring(target.label or "")) }
    local sourceNames = target.sourceNames or {}
    if profession and profession ~= "ALL" then
        sourceNames = (target.sourceNamesByProfession and target.sourceNamesByProfession[profession]) or sourceNames
    elseif profession == "ALL" and target.sourceNamesByProfession then
        sourceNames = {}
        for selectedProfession, selected in pairs(self:GetSelectedProfessions()) do
            if selected then
                for sourceName in pairs(target.sourceNamesByProfession[selectedProfession] or {}) do
                    sourceNames[sourceName] = true
                end
            end
        end
    end
    for sourceName in pairs(sourceNames) do
        table.insert(parts, string.lower(tostring(sourceName)))
    end
    return table.concat(parts, " ")
end

---@param target table
---@param tag string
---@return boolean
function Scanner:TargetHasCategoryTag(target, tag)
    return target.categoryTags and target.categoryTags[tag] == true
end

---@param target table
---@param tags string[]?
---@return boolean
function Scanner:TargetHasAnyCategoryTag(target, tags)
    if not tags then
        return false
    end
    for _, tag in ipairs(tags) do
        if self:TargetHasCategoryTag(target, tag) then
            return true
        end
    end
    return false
end

---@param target table
---@return boolean
function Scanner:TargetHasCategoryTags(target)
    return target.categoryTags and next(target.categoryTags) ~= nil
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
---@return boolean
function Scanner:IsGemPresetText(text)
    return string.find(text, "gem", 1, true) ~= nil
        or string.find(text, "peridot", 1, true) ~= nil
        or string.find(text, "lapis", 1, true) ~= nil
        or string.find(text, "amethyst", 1, true) ~= nil
        or string.find(text, "sapphire", 1, true) ~= nil
        or string.find(text, "diamond", 1, true) ~= nil
        or string.find(text, "emerald", 1, true) ~= nil
        or string.find(text, "ruby", 1, true) ~= nil
        or string.find(text, "onyx", 1, true) ~= nil
        or string.find(text, "opal", 1, true) ~= nil
        or string.find(text, "amber", 1, true) ~= nil
        or string.find(text, "topaz", 1, true) ~= nil
end

---@param text string
---@return boolean
function Scanner:IsRaidConsumablePresetText(text)
    return string.find(text, "potion", 1, true) ~= nil
        or string.find(text, "flask", 1, true) ~= nil
        or string.find(text, "phial", 1, true) ~= nil
        or string.find(text, "cauldron", 1, true) ~= nil
        or string.find(text, "feast", 1, true) ~= nil
        or string.find(text, "food", 1, true) ~= nil
        or string.find(text, "rune", 1, true) ~= nil
        or string.find(text, "enchant", 1, true) ~= nil
        or string.find(text, "mana", 1, true) ~= nil
        or string.find(text, "health", 1, true) ~= nil
end

---@param text string
---@return boolean
function Scanner:IsArmorPresetText(text)
    return self:TextMatchesAny(text, {
        "armor", "armguards", "banding", "basinet", "belt", "bracer", "bracers", "breastplate",
        "chest", "chestplate", "cloak", "cuffs", "gauntlets", "gloves", "greaves", "guards",
        "helm", "leggings", "pauldrons", "robe", "sabatons", "shield", "shoulders", "waistguard",
    })
end

---@param text string
---@return boolean
function Scanner:IsWeaponPresetText(text)
    return self:TextMatchesAny(text, {
        "axe", "blade", "bow", "bulwark", "claw", "dagger", "edge", "glaive", "greatsword", "gun",
        "knife", "knuckles", "mace", "polearm", "shield", "splitter", "staff", "sword", "wand",
        "warblade", "weapon",
    })
end

---@param text string
---@return boolean
function Scanner:IsProfessionToolPresetText(text)
    return self:TextMatchesAny(text, {
        "apron", "bag", "backpack", "clampers", "cover", "cutters", "fishing rod", "hardhat",
        "hat", "knife", "multitool", "needle set", "pickaxe", "profession tool", "rod", "sickle",
        "snippers", "toolbox", "toolset",
    })
end

---@param text string
---@return boolean
function Scanner:IsEnchantPresetText(text)
    return self:TextMatchesAny(text, {
        "enchant ", "enchantment", "armor banding", "weapon wrap",
    })
end

---@param text string
---@return boolean
function Scanner:IsContainerPresetText(text)
    return self:TextMatchesAny(text, {
        "bag", "backpack", "satchel", "toolbox", "toolset",
    })
end

---@param target table
---@param presetID string
---@param profession string?
---@return boolean selected
function Scanner:TargetMatchesPreset(target, presetID, profession)
    local searchText = self:GetPresetSearchText(target, profession)
    local hasCategoryTags = self:TargetHasCategoryTags(target)
    if presetID == self.PRESET_IDS.ALL then
        return true
    elseif presetID == self.PRESET_IDS.NONE then
        return false
    elseif presetID == self.PRESET_IDS.INPUTS then
        return target.kindMap and target.kindMap.input == true
    elseif presetID == self.PRESET_IDS.OUTPUTS then
        return target.kindMap and target.kindMap.output == true
    elseif presetID == self.PRESET_IDS.COMMODITIES then
        return target.isCommodity == true or target.resultType == "commodity"
    end

    if self:TargetHasAnyCategoryTag(target, self.PRESET_CATEGORY_TAGS[presetID]) then
        return true
    end

    local patterns = self.PRESET_TEXT_PATTERNS[presetID]
    if not hasCategoryTags and patterns and self:TextMatchesAny(searchText, patterns) then
        return true
    end

    if self.PRESET_CATEGORY_TAGS[presetID] or self.PRESET_TEXT_PATTERNS[presetID] then
        return false
    end

    return Config:IsTargetSelected(target.key)
end

---@param presetID string
---@return boolean
function Scanner:PresetShouldIncludeRecipeInputs(presetID)
    return presetID ~= self.PRESET_IDS.ALL
        and presetID ~= self.PRESET_IDS.NONE
        and presetID ~= self.PRESET_IDS.INPUTS
        and presetID ~= self.PRESET_IDS.OUTPUTS
        and presetID ~= self.PRESET_IDS.COMMODITIES
end

---@param target table
---@param recipeIDs table<number, boolean>
---@return boolean
function Scanner:TargetHasAnyRecipe(target, recipeIDs)
    for recipeID in pairs(target.sourceRecipeMap or {}) do
        if recipeIDs[recipeID] then
            return true
        end
    end
    return false
end

---@param contextProfession string?
---@return table[] targets
function Scanner:GetPresetScopeTargets(contextProfession)
    local cacheKey = contextProfession or "__CURRENT__"
    if self.presetMenuTargetCache and self.presetMenuTargetCache[cacheKey] then
        return self.presetMenuTargetCache[cacheKey]
    end

    local targets = self.configTargets
    if not targets then
        targets = self:GetConfigTargets()
    end
    if contextProfession then
        targets = ns.Filter(targets, function(target)
            return self:IsTargetInConfigProfession(target, contextProfession)
        end)
    end

    if self.presetMenuTargetCache then
        self.presetMenuTargetCache[cacheKey] = targets
    end
    return targets
end

---@param presetID string
---@param contextProfession string?
---@param targets table[]?
---@return table[] matchedTargets
function Scanner:GetPresetMatchedTargets(presetID, contextProfession, targets)
    targets = targets or self:GetPresetScopeTargets(contextProfession)

    if presetID == self.PRESET_IDS.ALL or presetID == self.PRESET_IDS.NONE then
        return targets
    end

    local profession = contextProfession or self:GetConfigProfession()
    local presetRecipeIDs = {}
    if self:PresetShouldIncludeRecipeInputs(presetID) then
        for _, target in ipairs(targets) do
            if target.kindMap and target.kindMap.output and self:TargetMatchesPreset(target, presetID, profession) then
                for recipeID in pairs((target.sourceRecipeKindMap and target.sourceRecipeKindMap.output) or {}) do
                    presetRecipeIDs[recipeID] = true
                end
            end
        end
    end

    local matchedTargets = {}
    for _, target in ipairs(targets) do
        local matched
        if self:PresetShouldIncludeRecipeInputs(presetID) then
            matched = self:TargetMatchesPreset(target, presetID, profession) or
                self:TargetHasAnyRecipe(target, presetRecipeIDs)
        else
            matched = self:TargetMatchesPreset(target, presetID, profession)
        end
        if matched then
            table.insert(matchedTargets, target)
        end
    end

    return matchedTargets
end

---@param targets table[]
---@return number selectedCount
function Scanner:GetSelectedTargetCount(targets)
    local selectedCount = 0
    for _, target in ipairs(targets or {}) do
        if Config:IsTargetSelected(target.key) then
            selectedCount = selectedCount + 1
        end
    end
    return selectedCount
end

---@param presetID string
---@param selectedCount number
---@param totalCount number
---@return "all" | "partial" | "none" | "empty" state
function Scanner:GetPresetSelectionStateFromCounts(presetID, selectedCount, totalCount)
    if totalCount <= 0 then
        return "empty"
    end

    if presetID == self.PRESET_IDS.NONE then
        return selectedCount == 0 and "all" or "none"
    end

    if selectedCount == totalCount then
        return "all"
    elseif selectedCount > 0 then
        return "partial"
    end
    return "none"
end

---@param presetID string
---@param contextProfession string?
---@return string state
---@return number selectedCount
---@return number totalCount
function Scanner:GetPresetSelectionState(presetID, contextProfession)
    local targets = self:GetPresetMatchedTargets(presetID, contextProfession)
    local selectedCount = self:GetSelectedTargetCount(targets)
    return self:GetPresetSelectionStateFromCounts(presetID, selectedCount, #targets), selectedCount, #targets
end

---@param state string
---@return string prefix
function Scanner:GetPresetStatePrefix(state)
    if state == "all" then
        return "[x]"
    elseif state == "partial" then
        return "[-]"
    end
    return "[ ]"
end

---@param label string
---@param state string
---@param selectedCount number
---@param totalCount number
---@return string
function Scanner:GetPresetStateLabel(label, state, selectedCount, totalCount)
    local stateLabel = self:GetPresetStatePrefix(state) .. " " .. label
    if state == "partial" and totalCount > 0 then
        stateLabel = stateLabel .. string.format(" (%d/%d)", selectedCount, totalCount)
    end
    return stateLabel
end

---@param presets table[]?
---@param contextProfession string?
---@return string state
---@return number selectedCount
---@return number totalCount
function Scanner:GetPresetGroupSelectionState(presets, contextProfession)
    local targetsByKey = {}
    local targets = {}

    for _, preset in ipairs(presets or {}) do
        for _, target in ipairs(self:GetPresetMatchedTargets(preset.id, contextProfession)) do
            if target.key and not targetsByKey[target.key] then
                targetsByKey[target.key] = true
                table.insert(targets, target)
            end
        end
    end

    local selectedCount = self:GetSelectedTargetCount(targets)
    return self:GetPresetSelectionStateFromCounts(self.PRESET_IDS.ALL, selectedCount, #targets), selectedCount, #targets
end

---@param label string
---@param presets table[]?
---@param contextProfession string?
---@return string
function Scanner:GetPresetGroupMenuLabel(label, presets, contextProfession)
    local state, selectedCount, totalCount = self:GetPresetGroupSelectionState(presets, contextProfession)
    return self:GetPresetStateLabel(label, state, selectedCount, totalCount)
end

---@param presetID string
---@return boolean
function Scanner:IsTogglePreset(presetID)
    return presetID ~= self.PRESET_IDS.ALL and presetID ~= self.PRESET_IDS.NONE
end

---@param profession string?
---@return table<string, boolean>
function Scanner:GetActivePresetMap(profession)
    profession = profession or self:GetConfigProfession()
    self.activeConfigPresets[profession] = self.activeConfigPresets[profession] or {}
    return self.activeConfigPresets[profession]
end

---@param profession string?
function Scanner:ClearActivePresetMap(profession)
    if profession then
        self.activeConfigPresets[profession] = {}
    else
        wipe(self.activeConfigPresets)
    end
end

---@param presetID string
---@param profession string?
---@return boolean
function Scanner:IsPresetActive(presetID, profession)
    return self:GetActivePresetMap(profession)[presetID] == true
end

---@param label string
---@param presetID string
---@param contextProfession string?
---@return string
function Scanner:GetPresetMenuLabel(label, presetID, contextProfession)
    local state, selectedCount, totalCount = self:GetPresetSelectionState(presetID, contextProfession)
    return self:GetPresetStateLabel(label, state, selectedCount, totalCount)
end

---@param text string
function Scanner:SetStatus(text)
    if self.panel and self.panel.statusText then
        self.panel.statusText:SetText(text or "")
    end
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

function Scanner:UpdateProgressText()
    if not self.panel or not self.panel.progressText then
        return
    end

    if self.isScanning then
        self.panel.progressText:SetText(string.format("%d/%d AH queries", self.completedTargets, self.totalTargets))
        return
    end

    local priced = #self.priceResults
    local missing = self:GetMissingDisplayCount()
    if self.scanComplete then
        self.panel.progressText:SetText(string.format("%d priced, %d unpriced", priced, missing))
    else
        self.panel.progressText:SetText("")
    end
end

function Scanner:UpdateMissingButton()
    local panel = self.panel
    if not panel or not panel.missingButton then
        return
    end

    local missing = self:GetMissingDisplayCount()
    local showMissing = self.scanComplete and not self.isScanning and missing > 0

    panel.missingButton:SetText("Unpriced (" .. tostring(missing) .. ")")
    panel.missingButton:Show()
    SetButtonEnabled(panel.missingButton, showMissing)
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
        SetButtonEnabled(self.configPanel.presetButton, not self.isScanning)
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
    SetButtonEnabled = SetButtonEnabled,
    SystemPrint = SystemPrint,
}

ns:RegisterModule("AuctionHouseScan", Scanner)
