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

Scanner.button = nil
Scanner.panel = nil
Scanner.configPanel = nil
Scanner.missingPanel = nil
Scanner.missingExportPanel = nil
Scanner.professionCheckboxes = {}
Scanner.configRows = {}
Scanner.configTargets = {}
Scanner.presetRows = {}
Scanner.configView = "presets"
Scanner.missingRows = {}
Scanner.activeConfigPresets = {}
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
        return "Output"
    end
    return "Input"
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
        return "Selected Professions"
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
        self.panel.progressText:SetText(string.format("%d priced, %d missing", priced, missing))
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

    if panel.scanButton then
        panel.scanButton:ClearAllPoints()
        if showMissing then
            panel.scanButton:SetPoint("TOPLEFT", panel.scanLabel, "BOTTOMLEFT", 8, -6)
        else
            panel.scanButton:SetPoint("TOP", panel.scanLabel, "BOTTOM", 0, -6)
        end
    end

    panel.missingButton:SetText("Missing (" .. tostring(missing) .. ")")
    panel.missingButton:SetShown(showMissing)
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

function Scanner:UpdateButtons()
    local panel = self.panel
    if not panel then
        return
    end

    if panel.scanButton then
        if self.isScanning then
            panel.scanButton:SetText("Stop Scan")
        elseif self.scanComplete and not self.overridesPushed and self:HasOverridesToPush() then
            panel.scanButton:SetText("Push Overrides")
        else
            panel.scanButton:SetText("Scan Now")
        end
    end

    SetButtonEnabled(panel.scanButton, true)
    SetButtonEnabled(panel.configureButton, not self.isScanning and self:HasSelectedProfession())
    for _, checkbox in pairs(self.professionCheckboxes) do
        SetButtonEnabled(checkbox, not self.isScanning)
    end
    self:UpdateMissingButton()
end

---@param input EditBox
function Scanner:SaveFillQuantityInput(input)
    local value = tonumber(input:GetText()) or Config:GetFillQuantity()
    Config:SaveFillQuantity(value)
    input:SetText(tostring(Config:GetFillQuantity()))
end

function Scanner:CreateButton()
    if self.button or not AuctionHouseFrame then
        return
    end

    local isTabButton, button = pcall(CreateFrame, "Button", "CraftSimEnhancerAuctionHouseScanButton", AuctionHouseFrame,
        "PanelTabButtonTemplate")
    if not isTabButton or not button then
        isTabButton = false
        button = CreateFrame("Button", "CraftSimEnhancerAuctionHouseScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
    end

    button.craftSimIsLauncherTab = isTabButton
    button:SetSize(isTabButton and 80 or 145, isTabButton and 32 or 24)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 30)
    button:SetText(isTabButton and "CraftSim" or "CraftSim AH Scan")
    if isTabButton and PanelTemplates_TabResize then
        PanelTemplates_TabResize(button, 20, nil, 70)
    end
    button:SetScript("OnClick", function()
        Scanner:TogglePanel()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end
    end)
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CraftSim AH Scan")
        GameTooltip:AddLine("Scan selected generated crafts and reagents, then push the prices to CraftSim overrides.", 1,
            1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    self.button = button
    self:AttachLauncherTabToAuctionHouseTabs()
    self:UpdateLauncherTabState()
end

function Scanner:AttachLauncherTabToAuctionHouseTabs()
    local button = self.button
    if not button or not AuctionHouseFrame then
        return
    end

    if not button.craftSimIsLauncherTab or not AuctionHouseFrame.Tabs then
        if button and AuctionHouseFrame then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 70, -36)
        end
        return
    end

    local tabs = AuctionHouseFrame.Tabs
    for index = #tabs, 1, -1 do
        if tabs[index] == button then
            table.remove(tabs, index)
        end
    end

    local insertAfterIndex = #tabs
    for index, tab in ipairs(tabs) do
        if tab == AuctionHouseFrame.AuctionsTab then
            insertAfterIndex = index
            break
        end
    end

    table.insert(tabs, insertAfterIndex + 1, button)
    for index, tab in ipairs(tabs) do
        if tab.SetID then
            tab:SetID(index)
        end
    end

    button:ClearAllPoints()
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(button, 20, nil, 70)
    end
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(AuctionHouseFrame, #tabs)
    end
end

function Scanner:UpdateLauncherTabState()
    local button = self.button
    if not button then
        return
    end

    local selected = self.panel and self.panel:IsShown()
    if button.SetChecked then
        button:SetChecked(selected)
    end

    if button.craftSimIsLauncherTab then
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
end

---@param parent Frame
---@param y number
---@return CheckButton
function Scanner:CreateProfessionCheckbox(parent, professionInfo, y)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 58, y)
    checkbox:SetChecked(self:GetSelectedProfessions()[professionInfo.name] == true)
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    checkbox.text:SetText(self:GetProfessionLabel(professionInfo))
    checkbox:SetScript("OnClick", function(selfCheckbox)
        Config:SaveProfessionSelected(professionInfo.name, selfCheckbox:GetChecked())
        Scanner.scanComplete = false
        Scanner.overridesPushed = false
        wipe(Scanner.priceResults)
        wipe(Scanner.missingResults)
        if Scanner.configPanel and Scanner.configPanel:IsShown() then
            Scanner:UpdateConfigList()
        end
        Scanner:UpdateButtons()
        Scanner:UpdateProgressText()
    end)
    return checkbox
end

function Scanner:CreatePanel()
    if self.panel or not AuctionHouseFrame then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetSize(310, 485)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 8, -32)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 40)
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
    panel.title:SetPoint("TOP", panel, "TOP", 0, -14)
    panel.title:SetWidth(278)
    panel.title:SetJustifyH("CENTER")
    panel.title:SetText("|cffffd100=-|r |cffffff00CraftSim Scanner|r |cffffd100-=|r")

    panel.closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    panel.closeButton:SetScript("OnClick", function()
        panel:Hide()
        if Scanner.configPanel then
            Scanner.configPanel:Hide()
        end
        if Scanner.missingPanel then
            Scanner.missingPanel:Hide()
        end
        if Scanner.missingExportPanel then
            Scanner.missingExportPanel:Hide()
        end
        Scanner:UpdateLauncherTabState()
    end)

    panel.professionsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.professionsLabel:SetPoint("TOP", panel, "TOP", 0, -44)
    panel.professionsLabel:SetWidth(278)
    panel.professionsLabel:SetJustifyH("CENTER")
    panel.professionsLabel:SetText("Step 1: Choose professions")

    self:EnsureProfessionSelectionForCurrentCrafter()
    wipe(self.professionCheckboxes)
    local y = -66
    for _, professionInfo in ipairs(self.PROFESSIONS) do
        local checkbox = self:CreateProfessionCheckbox(panel, professionInfo, y)
        self.professionCheckboxes[professionInfo.name] = checkbox
        y = y - 24
    end

    panel.configureLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.configureLabel:SetPoint("TOP", panel, "TOP", 0, y - 8)
    panel.configureLabel:SetWidth(278)
    panel.configureLabel:SetJustifyH("CENTER")
    panel.configureLabel:SetText("Step 2: Configure what to scan")

    panel.configureButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.configureButton:SetSize(150, 24)
    panel.configureButton:SetPoint("TOP", panel.configureLabel, "BOTTOM", 0, -6)
    panel.configureButton:SetText("Configure")
    panel.configureButton:SetScript("OnClick", function()
        local scanner = Scanner
        if not scanner:HasSelectedProfession() then
            scanner:SetStatus("Choose at least one profession first.")
            return
        end
        scanner:ToggleConfigPanel()
    end)

    panel.scanLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.scanLabel:SetPoint("TOP", panel.configureButton, "BOTTOM", 0, -12)
    panel.scanLabel:SetWidth(278)
    panel.scanLabel:SetJustifyH("CENTER")
    panel.scanLabel:SetText("Step 3: Scan and push prices")

    panel.scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.scanButton:SetSize(150, 24)
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

    panel.missingButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.missingButton:SetSize(104, 24)
    panel.missingButton:SetPoint("LEFT", panel.scanButton, "RIGHT", 8, 0)
    panel.missingButton:SetText("Missing")
    panel.missingButton:SetScript("OnClick", function()
        Scanner:ToggleMissingPanel()
    end)
    panel.missingButton:Hide()

    panel.progressText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.progressText:SetPoint("TOPLEFT", panel.scanLabel, "BOTTOMLEFT", 0, -42)
    panel.progressText:SetWidth(278)
    panel.progressText:SetHeight(14)
    panel.progressText:SetJustifyH("LEFT")

    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.statusText:SetPoint("TOPLEFT", panel.progressText, "BOTTOMLEFT", 0, -8)
    panel.statusText:SetWidth(278)
    panel.statusText:SetHeight(48)
    panel.statusText:SetJustifyH("LEFT")
    panel.statusText:SetJustifyV("TOP")
    panel.statusText:SetText("")

    panel:Hide()
    self.panel = panel
    self:UpdateButtons()
end

function Scanner:ShowButton()
    self:CreateButton()
    self:CreatePanel()
    self:AttachLauncherTabToAuctionHouseTabs()
    if self.button then
        self.button:Show()
        self:UpdateLauncherTabState()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Scanner.button and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
                Scanner:AttachLauncherTabToAuctionHouseTabs()
                Scanner:UpdateLauncherTabState()
            end
        end)
    end
end

function Scanner:TogglePanel()
    self:CreatePanel()
    if not self.panel then
        return
    end
    if self.panel:IsShown() then
        self.panel:Hide()
        if self.configPanel then
            self.configPanel:Hide()
        end
        if self.missingPanel then
            self.missingPanel:Hide()
        end
        if self.missingExportPanel then
            self.missingExportPanel:Hide()
        end
    else
        self.panel:Show()
        self:UpdateButtons()
        self:UpdateProgressText()
    end
    self:UpdateLauncherTabState()
end

function Scanner:ToggleMissingPanel()
    if #self.missingResults == 0 then
        self:SetStatus("No missing scan items to show.")
        return
    end

    self:CreateMissingPanel()
    if not self.missingPanel then
        return
    end

    if self.missingPanel:IsShown() then
        self.missingPanel:Hide()
    else
        if self.configPanel then
            self.configPanel:Hide()
        end
        self.missingPanel:Show()
        self:UpdateMissingList()
    end
end

function Scanner:CreateMissingPanel()
    if self.missingPanel or not AuctionHouseFrame then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanMissingPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetSize(480, 320)
    panel:SetPoint("TOPLEFT", self.panel or AuctionHouseFrame, "TOPRIGHT", 8, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 45)
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
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    panel.title:SetText("Missing AH Items")

    panel.closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    panel.closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    panel.copyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.copyButton:SetSize(104, 22)
    panel.copyButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -10)
    panel.copyButton:SetText("Copy Report")
    panel.copyButton:SetScript("OnClick", function()
        Scanner:OpenMissingReport()
    end)

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -44)
    panel.headerText:SetText("Item                                    ItemID       Reason")

    panel.emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.emptyText:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -72)
    panel.emptyText:SetWidth(436)
    panel.emptyText:SetJustifyH("LEFT")
    panel.emptyText:SetText("No missing items from the latest scan.")

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -62)
    panel.scrollFrame:SetSize(436, 238)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(430, 1)
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
    if result.suppressOnPush then
        table.insert(lines, "Result override on push: 0g 0s 1c")
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
        return result and result.suppressOnPush and "1c on push" or "No auctions"
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
        result.suppressOnPush = self:IsConfirmedNoAuctionResult(result) and self:MissingResultHasOutputOverride(result)
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
                suppressOnPush = result.suppressOnPush,
            }
            grouped[key] = display
            table.insert(results, display)
        end

        display.count = display.count + 1
        if not display.error and result.error then
            display.error = result.error
        end
        display.suppressOnPush = display.suppressOnPush or result.suppressOnPush

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
        "Item\tItemID\tTargets\tItem Levels\tReason\tDetails",
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
    row:SetSize(430, 26)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.03)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.nameText:SetWidth(220)
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
    row.reasonText:SetWidth(116)
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

function Scanner:ToggleConfigPanel()
    if not self:HasSelectedProfession() then
        self:SetStatus("Choose at least one profession first.")
        return
    end

    self:CreateConfigPanel()
    if not self.configPanel then
        return
    end

    if self.configPanel:IsShown() then
        self.configPanel:Hide()
    else
        if self.missingPanel then
            self.missingPanel:Hide()
        end
        self.configPanel:Show()
        self:UpdateConfigList()
    end
end

---@return string profession
function Scanner:GetConfigProfession()
    local profession = Config:GetConfigProfession()
    local selectedProfessions = self:GetSelectedProfessions()
    if profession ~= "ALL" and (not self:GetProfessionInfoByName(profession) or not selectedProfessions[profession]) then
        profession = "ALL"
        Config:SaveConfigProfession(profession)
    end
    return profession
end

---@param target table
---@param profession string
---@return boolean
function Scanner:IsTargetInConfigProfession(target, profession)
    return profession == "ALL" or (target.professionMap and target.professionMap[profession] == true)
end

---@return table[] targets
function Scanner:GetConfigTargets()
    self:EnsureProfessionSelectionForCurrentCrafter()
    if not self:HasSelectedProfession() then
        return {}
    end

    local targets = self:BuildScanTargets({
        includeAllProfessions = true,
        ignoreSavedFilter = true,
        skipFixedPrices = true,
    }) or {}

    local profession = self:GetConfigProfession()
    return ns.Filter(targets, function(target)
        return self:IsTargetInSelectedProfessions(target) and self:IsTargetInConfigProfession(target, profession)
    end)
end

function Scanner:UpdateConfigSummary()
    local panel = self.configPanel
    if not panel or not panel.summaryText then
        return
    end

    local enabled = 0
    for _, target in ipairs(self.configTargets or {}) do
        if Config:IsTargetSelected(target.key) then
            enabled = enabled + 1
        end
    end
    panel.summaryText:SetText(string.format("%d/%d selected", enabled, #(self.configTargets or {})))
end

---@param target table
---@return string
function Scanner:GetConfigRowTooltip(target)
    local lines = {
        tostring(target.label or ("Item " .. tostring(target.itemID))),
        "ItemID: " .. tostring(target.itemID),
        "Type: " .. self:GetTargetTypeText(target),
    }

    local sourceNames = {}
    local profession = self:GetConfigProfession()
    local sourceMap = target.sourceNames or {}
    if profession ~= "ALL" and target.sourceNamesByProfession then
        sourceMap = target.sourceNamesByProfession[profession] or sourceMap
    elseif profession == "ALL" and target.sourceNamesByProfession then
        sourceMap = {}
        for selectedProfession, selected in pairs(self:GetSelectedProfessions()) do
            if selected then
                for sourceName in pairs(target.sourceNamesByProfession[selectedProfession] or {}) do
                    sourceMap[sourceName] = true
                end
            end
        end
    end
    for sourceName in pairs(sourceMap) do
        table.insert(sourceNames, sourceName)
    end
    table.sort(sourceNames)

    if #sourceNames > 0 then
        table.insert(lines, "Recipes:")
        for index, sourceName in ipairs(sourceNames) do
            if index > 8 then
                table.insert(lines, "...")
                break
            end
            table.insert(lines, "- " .. tostring(sourceName))
        end
    end

    return table.concat(lines, "\n")
end

---@param row Frame
---@param target table
function Scanner:UpdateConfigRow(row, target)
    row.target = target
    row.checkbox:SetChecked(Config:IsTargetSelected(target.key))
    row.typeText:SetText(self:GetTargetTypeText(target))
    row.nameText:SetText(tostring(target.label or ("Item " .. tostring(target.itemID))))
    row.itemIDText:SetText(tostring(target.itemID))
    row.sourceCountText:SetText(tostring(target.sourceCount or 0))
    row.tooltipText = self:GetConfigRowTooltip(target)
end

---@param parent Frame
---@return Frame row
function Scanner:CreateConfigRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(470, 24)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.03)

    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(22, 22)
    row.checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.checkbox:SetScript("OnClick", function(checkbox)
        local target = row.target
        if target then
            Config:SaveTargetSelected(target.key, checkbox:GetChecked())
            Scanner:UpdateConfigSummary()
            Scanner.scanComplete = false
            Scanner:UpdateButtons()
            Scanner:UpdateProgressText()
        end
    end)

    row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.typeText:SetPoint("LEFT", row.checkbox, "RIGHT", 2, 0)
    row.typeText:SetWidth(42)
    row.typeText:SetJustifyH("LEFT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.typeText, "RIGHT", 8, 0)
    row.nameText:SetWidth(235)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.itemIDText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.itemIDText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)
    row.itemIDText:SetWidth(58)
    row.itemIDText:SetJustifyH("LEFT")

    row.sourceCountText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sourceCountText:SetPoint("LEFT", row.itemIDText, "RIGHT", 8, 0)
    row.sourceCountText:SetWidth(32)
    row.sourceCountText:SetJustifyH("LEFT")

    row:SetScript("OnEnter", function(selfRow)
        if not selfRow.tooltipText then
            return
        end
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:AddLine("CraftSim Scan Item")
        GameTooltip:AddLine(selfRow.tooltipText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdateConfigList()
    self:CreateConfigPanel()
    local panel = self.configPanel
    if not panel then
        return
    end

    panel.professionButton:SetText(self:GetProfessionDropdownText(self:GetConfigProfession()))

    for _, row in ipairs(self.configRows) do
        row:Hide()
    end
    for _, row in ipairs(self.presetRows) do
        row:Hide()
    end

    self.configTargets = self:GetConfigTargets()

    if self.configView == "presets" then
        panel.headerText:SetText("Preset                                                      Selected")
        panel.presetButton:SetText("Items")
        self:UpdatePresetList()
        self:UpdateConfigSummary()
        return
    end

    panel.headerText:SetText("Type       Item                                      ItemID     Recipes")
    panel.presetButton:SetText("Presets")

    local rowHeight = 24
    for index, target in ipairs(self.configTargets) do
        local row = self.configRows[index]
        if not row then
            row = self:CreateConfigRow(panel.scrollChild)
            self.configRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight))
        if index % 2 == 0 then
            row.bg:Show()
        else
            row.bg:Hide()
        end
        self:UpdateConfigRow(row, target)
        row:Show()
    end

    panel.scrollChild:SetHeight(math.max(1, #self.configTargets * rowHeight))
    self:UpdateConfigSummary()
end

---@return table[] entries
function Scanner:GetPresetListEntries()
    local entries = {
        { kind = "header", label = "Quick Sets" },
        { kind = "preset", label = "Select All", id = self.PRESET_IDS.ALL },
        { kind = "preset", label = "Clear All", id = self.PRESET_IDS.NONE },
        { kind = "preset", label = "Inputs", id = self.PRESET_IDS.INPUTS },
        { kind = "preset", label = "Outputs", id = self.PRESET_IDS.OUTPUTS },
        { kind = "preset", label = "Commodities", id = self.PRESET_IDS.COMMODITIES },
        { kind = "preset", label = "Equipment", id = self.PRESET_IDS.EQUIPMENT },
        { kind = "preset", label = "Materials", id = self.PRESET_IDS.MATERIALS },
    }

    local configProfession = self:GetConfigProfession()
    local professions = {}
    if configProfession == "ALL" then
        professions = self:GetSelectedProfessionInfos()
    else
        professions = ns.Filter(self.PROFESSIONS, function(professionInfo)
            return professionInfo.name == configProfession
        end)
    end

    for _, professionInfo in ipairs(professions) do
        table.insert(entries, {
            kind = "header",
            label = self:GetProfessionDisplayName(professionInfo),
        })
        for _, section in ipairs(self.PROFESSION_PRESET_MENUS[professionInfo.name] or {}) do
            table.insert(entries, {
                kind = "section",
                label = section.label,
            })
            for _, preset in ipairs(section.presets or {}) do
                table.insert(entries, {
                    kind = "preset",
                    label = preset.label,
                    id = preset.id,
                    contextProfession = professionInfo.name,
                })
            end
        end
    end

    return entries
end

---@param row Frame
---@param entry table
function Scanner:UpdatePresetRow(row, entry)
    row.entry = entry
    row:SetAlpha(1)
    row.headerText:Hide()
    row.stateText:Hide()
    row.labelText:Hide()
    row.countText:Hide()
    row:EnableMouse(false)

    if entry.kind == "header" or entry.kind == "section" then
        row.headerText:SetText(entry.label)
        row.headerText:SetTextColor(entry.kind == "header" and 1 or 0.75, entry.kind == "header" and 0.82 or 0.75,
            entry.kind == "header" and 0 or 0.75)
        row.headerText:ClearAllPoints()
        row.headerText:SetPoint("LEFT", row, "LEFT", entry.kind == "section" and 18 or 2, 0)
        row.headerText:Show()
        return
    end

    local state, selectedCount, totalCount = self:GetPresetSelectionState(entry.id, entry.contextProfession)
    local stateText = "[ ]"
    local red, green, blue = 0.65, 0.65, 0.65
    if state == "all" then
        stateText = "[x]"
        red, green, blue = 0.2, 1, 0.2
    elseif state == "partial" then
        stateText = "[-]"
        red, green, blue = 1, 0.82, 0
    end

    row.stateText:SetText(stateText)
    row.stateText:SetTextColor(red, green, blue)
    row.labelText:SetText(entry.label)
    row.countText:SetText(string.format("%d/%d", selectedCount, totalCount))
    row.stateText:Show()
    row.labelText:Show()
    row.countText:Show()
    row:EnableMouse(totalCount > 0)
    row:SetAlpha(totalCount > 0 and 1 or 0.45)
end

---@param parent Frame
---@return Frame row
function Scanner:CreatePresetRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(470, 24)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.04)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(1, 0.82, 0, 0.08)

    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.headerText:SetWidth(440)
    row.headerText:SetJustifyH("LEFT")

    row.stateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.stateText:SetPoint("LEFT", row, "LEFT", 18, 0)
    row.stateText:SetWidth(28)
    row.stateText:SetJustifyH("LEFT")

    row.labelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.labelText:SetPoint("LEFT", row.stateText, "RIGHT", 4, 0)
    row.labelText:SetWidth(340)
    row.labelText:SetJustifyH("LEFT")
    row.labelText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.countText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.countText:SetWidth(62)
    row.countText:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(selfRow)
        local entry = selfRow.entry
        if entry and entry.kind == "preset" then
            Scanner:ApplyConfigPreset(entry.id, entry.contextProfession)
        end
    end)
    row:SetScript("OnEnter", function(selfRow)
        local entry = selfRow.entry
        if not entry or entry.kind ~= "preset" then
            return
        end
        local state, selectedCount, totalCount = Scanner:GetPresetSelectionState(entry.id, entry.contextProfession)
        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.label)
        GameTooltip:AddLine(string.format("%d of %d matching items selected (%s).", selectedCount, totalCount, state),
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

function Scanner:UpdatePresetList()
    local panel = self.configPanel
    if not panel then
        return
    end

    self.presetMenuTargetCache = {
        ["__CURRENT__"] = self.configTargets,
    }
    local entries = self:GetPresetListEntries()
    local offset = 0
    for index, entry in ipairs(entries) do
        local row = self.presetRows[index]
        if not row then
            row = self:CreatePresetRow(panel.scrollChild)
            self.presetRows[index] = row
        end
        local rowHeight = entry.kind == "header" and 28 or entry.kind == "section" and 22 or 24
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -offset)
        row.bg:SetShown(entry.kind == "preset" and index % 2 == 0)
        self:UpdatePresetRow(row, entry)
        row:Show()
        offset = offset + rowHeight
    end
    self.presetMenuTargetCache = nil
    panel.scrollChild:SetHeight(math.max(1, offset))
end

---@param view "items" | "presets"
function Scanner:SetConfigView(view)
    self.configView = view == "items" and "items" or "presets"
    if self.configPanel and self.configPanel.scrollFrame then
        self.configPanel.scrollFrame:SetVerticalScroll(0)
    end
    self:UpdateConfigList()
end

---@param presetID string
---@param contextProfession string?
function Scanner:ApplyConfigPreset(presetID, contextProfession)
    local configProfession = self:GetConfigProfession()
    local profession = contextProfession or configProfession
    local targets = self:GetPresetScopeTargets(contextProfession)
    local scopeText = contextProfession and (" for " .. tostring(contextProfession)) or ""

    if presetID == self.PRESET_IDS.ALL or presetID == self.PRESET_IDS.NONE then
        local selected = presetID == self.PRESET_IDS.ALL
        for _, target in ipairs(targets) do
            Config:SaveTargetSelected(target.key, selected)
        end
        if contextProfession then
            self:ClearActivePresetMap(contextProfession)
        elseif configProfession == "ALL" then
            self:ClearActivePresetMap()
        else
            self:ClearActivePresetMap(configProfession)
        end
        self.scanComplete = false
        self:SetStatus(selected and ("Selected all scan items" .. scopeText .. ".") or
            ("Cleared all scan items" .. scopeText .. "."))
        self:UpdateButtons()
        self:UpdateProgressText()
        self:UpdateConfigList()
        return
    end

    local matchedTargets = self:GetPresetMatchedTargets(presetID, contextProfession, targets)

    if #matchedTargets == 0 then
        self:SetStatus("Preset matched 0 scan items" .. scopeText .. ".")
        self:UpdateConfigList()
        return
    end

    local activePresets = self:GetActivePresetMap(profession)
    local selectedCount = self:GetSelectedTargetCount(matchedTargets)
    local presetState = self:GetPresetSelectionStateFromCounts(presetID, selectedCount, #matchedTargets)
    local selected = presetState ~= "all"
    local changedCount = 0
    for _, target in ipairs(matchedTargets) do
        if Config:IsTargetSelected(target.key) ~= selected then
            changedCount = changedCount + 1
        end
        Config:SaveTargetSelected(target.key, selected)
    end

    activePresets[presetID] = selected or nil
    self.scanComplete = false
    self:SetStatus(string.format("%s %d item(s) from preset%s. %d changed.",
        selected and "Added" or "Removed", #matchedTargets, scopeText, changedCount))
    self:UpdateButtons()
    self:UpdateProgressText()
    self:UpdateConfigList()
end

---@param menu any
---@param label string
---@param presetID string
---@param contextProfession string?
function Scanner:AddPresetMenuButton(menu, label, presetID, contextProfession)
    menu:CreateButton(self:GetPresetMenuLabel(label, presetID, contextProfession), function()
        Scanner:ApplyConfigPreset(presetID, contextProfession)
        return MenuResponse.Close
    end)
end

---@param menu any
---@param profession string
---@param contextProfession string?
function Scanner:AddProfessionPresetSections(menu, profession, contextProfession)
    local presetIDs = self.PRESET_IDS
    self:AddPresetMenuButton(menu, "Select This Profession", presetIDs.ALL, contextProfession)
    self:AddPresetMenuButton(menu, "Clear This Profession", presetIDs.NONE, contextProfession)
    menu:CreateDivider()

    local definitions = self.PROFESSION_PRESET_MENUS[profession] or {}
    for sectionIndex, section in ipairs(definitions) do
        if sectionIndex > 1 then
            menu:CreateDivider()
        end
        local sectionMenu = menu:CreateButton(self:GetPresetGroupMenuLabel(section.label, section.presets, contextProfession))
        for _, preset in ipairs(section.presets or {}) do
            self:AddPresetMenuButton(sectionMenu, preset.label, preset.id, contextProfession)
        end
    end
end

---@param rootDescription any
function Scanner:BuildPresetMenu(rootDescription)
    local presetIDs = self.PRESET_IDS
    local profession = self:GetConfigProfession()
    local selectedProfessionInfos = self:GetSelectedProfessionInfos()
    local quickSetPresets = {
        { label = "Inputs", id = presetIDs.INPUTS },
        { label = "Outputs", id = presetIDs.OUTPUTS },
        { label = "Commodities", id = presetIDs.COMMODITIES },
        { label = "Equipment", id = presetIDs.EQUIPMENT },
        { label = "Materials", id = presetIDs.MATERIALS },
    }

    self.presetMenuTargetCache = {}
    self:AddPresetMenuButton(rootDescription, "Select All", presetIDs.ALL)
    self:AddPresetMenuButton(rootDescription, "Clear All", presetIDs.NONE)
    rootDescription:CreateDivider()
    local quickSets = rootDescription:CreateButton(self:GetPresetGroupMenuLabel("Quick Sets", quickSetPresets))
    for _, preset in ipairs(quickSetPresets) do
        self:AddPresetMenuButton(quickSets, preset.label, preset.id)
    end

    if profession ~= "ALL" then
        rootDescription:CreateDivider()
        self:AddProfessionPresetSections(rootDescription, profession, profession)
        self.presetMenuTargetCache = nil
        return
    end

    rootDescription:CreateDivider()
    for _, professionInfo in ipairs(selectedProfessionInfos) do
        local professionMenu = rootDescription:CreateButton(
            self:GetPresetMenuLabel(self:GetProfessionLabel(professionInfo), presetIDs.ALL, professionInfo.name))
        self:AddProfessionPresetSections(professionMenu, professionInfo.name, professionInfo.name)
    end
    self.presetMenuTargetCache = nil
end

function Scanner:CreateConfigPanel()
    if self.configPanel or not AuctionHouseFrame then
        return
    end

    local panel = CreateFrame("Frame", "CraftSimEnhancerAuctionHouseScanConfigPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetSize(520, 585)
    panel:SetPoint("TOPLEFT", self.panel or AuctionHouseFrame, "TOPRIGHT", 8, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 45)
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
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    panel.title:SetText("Configure AH Scan")

    panel.closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    panel.closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    panel.helpBg = panel:CreateTexture(nil, "BACKGROUND")
    panel.helpBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42)
    panel.helpBg:SetSize(486, 58)
    panel.helpBg:SetColorTexture(0, 0, 0, 0.22)

    panel.helpTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.helpTitle:SetPoint("TOPLEFT", panel.helpBg, "TOPLEFT", 8, -7)
    panel.helpTitle:SetText("Quick setup")

    panel.helpText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.helpText:SetPoint("TOPLEFT", panel.helpTitle, "BOTTOMLEFT", 0, -4)
    panel.helpText:SetWidth(470)
    panel.helpText:SetHeight(34)
    panel.helpText:SetJustifyH("LEFT")
    panel.helpText:SetJustifyV("TOP")
    panel.helpText:SetText("Shows only professions selected on the scanner panel. Choose preset groups, then use Items to fine tune the scan list.\nInput rows price reagents. Output rows price crafted items.")

    panel.professionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.professionButton:SetSize(150, 24)
    panel.professionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -112)
    panel.professionButton:SetText(self:GetProfessionDropdownText(self:GetConfigProfession()))
    panel.professionButton:SetScript("OnClick", function(button)
        ns.Compat.WoW:OpenContextMenu(button, function(_, rootDescription)
            rootDescription:CreateRadio("Selected Professions", function()
                return Config:GetConfigProfession() == "ALL"
            end, function()
                Config:SaveConfigProfession("ALL")
                Scanner:UpdateConfigList()
                return MenuResponse.Close
            end)
            rootDescription:CreateDivider()
            for _, professionInfo in ipairs(Scanner:GetSelectedProfessionInfos()) do
                local profession = professionInfo.name
                rootDescription:CreateRadio(Scanner:GetProfessionLabel(professionInfo), function()
                    return Config:GetConfigProfession() == profession
                end, function()
                    Config:SaveConfigProfession(profession)
                    Scanner:UpdateConfigList()
                    return MenuResponse.Close
                end)
            end
        end)
    end)
    panel.professionButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Profession View")
        GameTooltip:AddLine("Filters the selected-profession list so you can tune one profession at a time.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.professionButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.presetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.presetButton:SetSize(110, 24)
    panel.presetButton:SetPoint("LEFT", panel.professionButton, "RIGHT", 8, 0)
    panel.presetButton:SetText("Items")
    panel.presetButton:SetScript("OnClick", function()
        Scanner:SetConfigView(Scanner.configView == "presets" and "items" or "presets")
    end)
    panel.presetButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if Scanner.configView == "presets" then
            GameTooltip:AddLine("Items")
            GameTooltip:AddLine("Fine tune individual scan items.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Presets")
            GameTooltip:AddLine("Select common scan groups.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    panel.presetButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.summaryText:SetPoint("LEFT", panel.presetButton, "RIGHT", 12, 0)
    panel.summaryText:SetWidth(160)
    panel.summaryText:SetJustifyH("LEFT")

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -146)
    panel.headerText:SetText("Type       Item                                      ItemID     Recipes")

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -164)
    panel.scrollFrame:SetSize(476, 390)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(470, 1)
    panel.scrollFrame:SetScrollChild(panel.scrollChild)

    panel:Hide()
    self.configPanel = panel
end

---@param target table
---@param overrideTarget table
function Scanner:AddOverrideTarget(target, overrideTarget)
    target.overrideMap = target.overrideMap or {}
    target.overrideTargets = target.overrideTargets or {}

    local key
    if overrideTarget.kind == "result" then
        key = "result:" .. tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
    else
        key = "global:" .. tostring(overrideTarget.itemID)
    end

    if target.overrideMap[key] then
        return
    end
    target.overrideMap[key] = true
    table.insert(target.overrideTargets, overrideTarget)
end

---@param sourceKind "input" | "output"
---@param overrideTarget table?
---@return "input" | "output" pricingMode
function Scanner:GetTargetPricingMode(sourceKind, overrideTarget)
    if sourceKind == "output" or (overrideTarget and overrideTarget.kind == "result") then
        return "output"
    end
    return "input"
end

---@param target table?
---@return boolean usesFillQuantity
function Scanner:TargetUsesFillQuantity(target)
    return target and target.pricingMode == "input"
end

---@param targetsByKey table<string, table>
---@param targets table[]
---@param itemID number?
---@param itemLevel number?
---@param label string?
---@param overrideTarget table
---@param sourceKind "input" | "output"
---@param profession string?
---@param sourceName string?
---@param sourceData table?
---@return table?
function Scanner:AddScanTarget(targetsByKey, targets, itemID, itemLevel, label, overrideTarget, sourceKind, profession,
                               sourceName, sourceData)
    itemID = tonumber(itemID)
    if not itemID then
        return nil
    end

    local scanInfo = self:GetItemScanInfo(itemID)
    if scanInfo.skip then
        return nil
    end

    itemLevel = tonumber(itemLevel) or 0
    local pricingMode = self:GetTargetPricingMode(sourceKind, overrideTarget)
    local key = self:GetTargetKey(itemID, itemLevel, pricingMode)
    local target = targetsByKey[key]
    if not target then
        local queryItemLevel = itemLevel
        if pricingMode == "output" and itemLevel > 0 then
            queryItemLevel = 0
        end
        target = {
            key = key,
            itemID = itemID,
            itemLevel = itemLevel,
            pricingMode = pricingMode,
            itemKey = self:MakeItemKey(itemID, queryItemLevel),
            label = label or ("Item " .. tostring(itemID)),
            moreRequests = 0,
            sourceCount = 0,
        }
        targetsByKey[key] = target
        table.insert(targets, target)
    end

    self:AddTargetMetadata(target, itemID)
    if sourceData and sourceData.isCommodity == true then
        target.isCommodity = true
    end
    if target.isCommodity == true then
        target.resultType = "commodity"
    else
        target.resultType = target.resultType or self:GetAuctionResultType(itemID, target)
    end
    self:AddTargetSource(target, sourceKind, profession, sourceName, overrideTarget and overrideTarget.recipeID)
    self:AddOverrideTarget(target, overrideTarget)
    return target
end

---@param itemID number?
---@param price number?
---@param label string?
---@param overrideTarget table
function Scanner:AddFixedPriceResult(itemID, price, label, overrideTarget)
    itemID = tonumber(itemID)
    price = tonumber(price)
    if not itemID or not price or price <= 0 then
        return
    end

    self.fixedResultsByKey = self.fixedResultsByKey or {}

    local roundedPrice = math.floor(price + 0.5)
    local key = tostring(itemID) .. ":" .. tostring(roundedPrice)
    local result = self.fixedResultsByKey[key]
    if not result then
        result = {
            itemID = itemID,
            itemLevel = 0,
            label = label or ("Item " .. tostring(itemID)),
            price = roundedPrice,
            source = "Vendor",
            quantityUsed = 0,
            listedQuantity = 0,
            trimmedUnits = 0,
            overrideTargets = {},
            overrideMap = {},
        }
        self.fixedResultsByKey[key] = result
        table.insert(self.priceResults, result)
    end
    self:AddOverrideTarget(result, overrideTarget)
end

---@param qualityMap table<number, number>
---@param rankCount number?
---@param callback fun(qualityID: number, itemID: number)
local function ForEachQualityItem(qualityMap, rankCount, callback)
    if not qualityMap then
        return
    end

    local seen = {}
    local maxRank = tonumber(rankCount) or #qualityMap
    for qualityID = 1, maxRank do
        local itemID = qualityMap[qualityID]
        if itemID then
            seen[qualityID] = true
            callback(qualityID, itemID)
        end
    end

    for qualityID, itemID in pairs(qualityMap) do
        if not seen[qualityID] and tonumber(qualityID) then
            callback(tonumber(qualityID), itemID)
        end
    end
end

---@param output table
---@param qualityID number?
---@return number itemLevel
function Scanner:GetOutputItemLevel(output, qualityID)
    if not output or output.isCommodity == true then
        return 0
    end

    if qualityID and output.rankItemLevels then
        return tonumber(output.rankItemLevels[qualityID]) or tonumber(output.baseItemLevel) or 0
    end

    if qualityID and output.rankItemLevelDeltas then
        local baseItemLevel = tonumber(output.baseItemLevel)
        local rankDelta = tonumber(output.rankItemLevelDeltas[qualityID])
        if baseItemLevel and rankDelta then
            return baseItemLevel + rankDelta
        end
    end

    return tonumber(output.baseItemLevel) or 0
end

---@param recipe table
---@param output table
---@param targetsByKey table<string, table>
---@param targets table[]
---@return boolean added
function Scanner:AddOutputTargets(recipe, output, targetsByKey, targets)
    if output.auctionSellable == false or not recipe.recipeID then
        return false
    end

    local added = false
    if output.rankItemIDs then
        ForEachQualityItem(output.rankItemIDs, output.rankCount, function(qualityID, itemID)
            -- The item ID already identifies the quality.  Filtering these
            -- results by generated item level can hide valid listings when
            -- Blizzard changes an expansion's item-level scale.
            added = self:AddScanTarget(targetsByKey, targets, itemID, 0, output.itemRef, {
                kind = "result",
                recipeID = recipe.recipeID,
                itemID = itemID,
                qualityID = qualityID,
            }, "output", recipe.profession, recipe.stratName, output) ~= nil or added
        end)
        return added
    end

    if output.rankBonusIDs and output.itemIDs and output.itemIDs[1] then
        local rankCount = tonumber(output.rankCount) or #(output.rankItemLevels or {})
        for qualityID = 1, rankCount do
            local itemID = output.itemIDs[1]
            local itemLevel = self:GetOutputItemLevel(output, qualityID)
            local target = self:AddScanTarget(targetsByKey, targets, itemID, itemLevel, output.itemRef, {
                kind = "result",
                recipeID = recipe.recipeID,
                itemID = itemID,
                qualityID = qualityID,
            }, "output", recipe.profession, recipe.stratName, output)
            if target then
                target.requiredBonusIDs = output.rankBonusIDs[qualityID]
                target.outputQualityID = qualityID
                target.rankItemLevelDeltas = output.rankItemLevelDeltas
                target.rankBonusIDsByQuality = output.rankBonusIDs
                added = true
            end
        end
        return added
    end

    for qualityID, itemID in ipairs(output.itemIDs or {}) do
        -- Unranked outputs (bags are a common example) use a broad item key.
        -- Their AH result itemKey may report item level zero even when the
        -- generated recipe data has a base item level.
        added = self:AddScanTarget(targetsByKey, targets, itemID, 0, output.itemRef, {
            kind = "result",
            recipeID = recipe.recipeID,
            itemID = itemID,
            qualityID = qualityID,
        }, "output", recipe.profession, recipe.stratName, output) ~= nil or added
    end
    return added
end

---@param recipe table
---@param reagent table
---@param targetsByKey table<string, table>
---@param targets table[]
---@param options table?
function Scanner:AddReagentTargets(recipe, reagent, targetsByKey, targets, options)
    options = options or {}
    local vendorItemID = tonumber(reagent.vendorItemID)

    local function addReagent(itemID, qualityID)
        itemID = tonumber(itemID)
        if not itemID then
            return
        end

        local overrideTarget = {
            kind = "global",
            recipeID = recipe.recipeID or 0,
            itemID = itemID,
            qualityID = qualityID,
        }

        local scanInfo = self:GetItemScanInfo(itemID, reagent)
        local vendorPriceCopper = tonumber(scanInfo.vendorPriceCopper)
        local hasFixedVendorPrice = scanInfo.vendorSold and vendorPriceCopper and vendorPriceCopper > 0 and
            (not vendorItemID or vendorItemID == itemID)
        if hasFixedVendorPrice then
            if not options.skipFixedPrices then
                self:AddFixedPriceResult(itemID, vendorPriceCopper, reagent.itemRef, overrideTarget)
            end
        elseif scanInfo.skip then
            return
        else
            self:AddScanTarget(targetsByKey, targets, itemID, 0, reagent.itemRef, overrideTarget, "input",
                recipe.profession, recipe.stratName, reagent)
        end
    end

    if reagent.rankItemIDs then
        ForEachQualityItem(reagent.rankItemIDs, reagent.rankCount, function(qualityID, itemID)
            addReagent(itemID, qualityID)
        end)
    else
        for index, itemID in ipairs(reagent.itemIDs or {}) do
            addReagent(itemID, reagent.rankCount and index or nil)
        end
    end
end

---@param targets table[]
---@param options table?
function Scanner:ApplyLegacyTargetSelectionCompatibility(targets, options)
    local skippedTargets = Config:GetSkippedTargets()
    local migratedLegacyKeys = {}

    for _, target in ipairs(targets or {}) do
        local legacyKey = tostring(target.itemID) .. ":" .. tostring(tonumber(target.itemLevel) or 0)
        if skippedTargets[legacyKey] == true then
            skippedTargets[target.key] = skippedTargets[target.key] or true
            migratedLegacyKeys[legacyKey] = true
        end
    end

    if options and options.includeAllProfessions then
        for legacyKey in pairs(migratedLegacyKeys) do
            skippedTargets[legacyKey] = nil
        end
    end
end

---@param options table?
---@return table[]? targets
---@return string? errorMessage
function Scanner:BuildScanTargets(options)
    options = options or {}

    local recipes = self:GetGeneratedRecipes()
    if #recipes == 0 then
        return nil, "No generated recipe data is loaded."
    end

    local selectedProfessions = self:GetSelectedProfessions()
    local selectedCount = 0
    if not options.includeAllProfessions and not options.profession then
        for _, professionInfo in ipairs(self.PROFESSIONS) do
            if selectedProfessions[professionInfo.name] then
                selectedCount = selectedCount + 1
            end
        end

        if selectedCount == 0 then
            return nil, "Select at least one profession."
        end
    end

    local targetsByKey = {}
    local targets = {}

    for _, recipe in ipairs(recipes) do
        local includeProfession = recipe.profession and
            (options.includeAllProfessions or options.profession == recipe.profession or selectedProfessions[recipe.profession])
        if includeProfession then
            local hasScannableOutput = false
            for _, output in ipairs(recipe.outputs or {}) do
                hasScannableOutput = self:AddOutputTargets(recipe, output, targetsByKey, targets) or hasScannableOutput
            end
            if hasScannableOutput then
                for _, reagent in ipairs(recipe.reagents or {}) do
                    self:AddReagentTargets(recipe, reagent, targetsByKey, targets, {
                        skipFixedPrices = options.skipFixedPrices,
                    })
                end
            end
        end
    end

    self:ApplyLegacyTargetSelectionCompatibility(targets, options)

    table.sort(targets, function(a, b)
        return tostring(a.label or a.itemID) < tostring(b.label or b.itemID)
    end)

    if not options.ignoreSavedFilter then
        targets = ns.Filter(targets, function(target)
            return Config:IsTargetSelected(target.key)
        end)
    end

    return targets
end

function Scanner:StartScan()
    if self.isScanning then
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:SetStatus("Open the Auction House before scanning.")
        return
    end

    self:CreatePanel()
    if self.panel and self.panel.fillInput then
        self:SaveFillQuantityInput(self.panel.fillInput)
    end

    wipe(self.priceResults)
    wipe(self.missingResults)
    wipe(self.fixedResultsByKey)
    wipe(self.outputItemRowsCache)
    self.scanComplete = false
    self.overridesPushed = false
    if self.missingPanel then
        self.missingPanel:Hide()
        self:UpdateMissingList()
    end

    local targets, errorMessage = self:BuildScanTargets()
    if not targets then
        self:SetStatus(errorMessage)
        self:UpdateButtons()
        self:UpdateProgressText()
        return
    end

    self.scanTargets = targets
    self.scanIndex = 0
    self.completedTargets = 0
    self.totalTargets = #targets
    self.pendingQuery = nil
    self.pendingPollToken = self.pendingPollToken + 1
    self.isScanning = true
    self.nextQueryTime = 0

    self:SetStatus(string.format("Scanning %d AH items. Blizzard throttling may make this take a bit.", self.totalTargets))
    self:UpdateButtons()
    self:UpdateProgressText()

    if self.totalTargets == 0 then
        self:FinishScan()
        return
    end

    self:TrySendNextQuery()
end

---@param seconds number?
function Scanner:SchedulePendingTimeout(seconds)
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    local token = self.pendingTimeoutToken
    C_Timer.After(seconds or PENDING_TIMEOUT_SECONDS, function()
        if Scanner.isScanning and Scanner.pendingQuery and
            Scanner.pendingTimeoutToken == token then
            local target = Scanner.pendingQuery
            if not Scanner:IsAuctionThrottleReady() then
                Scanner:SetStatus("Waiting for the Auction House throttle.")
                Scanner:SchedulePendingTimeout()
                Scanner:SchedulePendingPoll(0.35)
                return
            end

            -- Blizzard occasionally populates the result cache without
            -- sending the corresponding result event. Inspect the cache once
            -- before retrying or declaring the request timed out.
            if Scanner:TryProcessAvailableResultsAtTimeout(target) then
                return
            end

            if Scanner:TrySendItemLevelFallback(target, true) or
                Scanner:TrySendSellSearchFallback(target, true) then
                Scanner:SchedulePendingPoll(0.35)
                return
            end
            if Scanner:CanTryItemLevelFallback(target) or
                Scanner:CanTrySellSearchFallback(target) then
                Scanner:SetStatus("Waiting for the Auction House throttle.")
                Scanner:SchedulePendingTimeout()
                Scanner:SchedulePendingPoll(0.35)
                return
            end
            target.error = "Timed out waiting for AH results."
            Scanner:FinishPendingTarget({})
        end
    end)
end

function Scanner:TrySendNextQuery()
    if not self.isScanning or self.pendingQuery then
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:CancelScan("Auction House closed.")
        return
    end

    if self.scanIndex >= self.totalTargets then
        self:FinishScan()
        return
    end

    if not self:IsAuctionThrottleReady() then
        self:SetStatus("Waiting for the Auction House throttle.")
        return
    end

    local now = GetTime()
    if now < self.nextQueryTime then
        C_Timer.After(self.nextQueryTime - now, function()
            Scanner:TrySendNextQuery()
        end)
        return
    end

    self.scanIndex = self.scanIndex + 1
    local target = self.scanTargets[self.scanIndex]
    self.pendingQuery = target
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.sellSearchFallbackSent = false
    target.itemLevelFallbackSent = false
    target.resultsReceived = false
    target.activeItemKey = target.itemKey

    local queryItemKey = self:GetTargetQueryItemKey(target)
    local cachedRows = target.pricingMode == "output" and queryItemKey and
        tonumber(queryItemKey.itemLevel) == 0 and self.outputItemRowsCache[target.itemID]
    if cachedRows then
        target.cachedItemRows = cachedRows
        target.currentRawItemRows = cachedRows
        target.usedCachedRows = true
        target.resultsReceived = true
        self:SetStatus("Using current AH results for " .. tostring(target.label) .. " (" ..
            tostring(target.itemID) .. ")")
        self:UpdateProgressText()
        self:ScheduleResultProcessing(target, "item")
        return
    end

    local ok, err = pcall(C_AuctionHouse.SendSearchQuery, queryItemKey, self:GetSearchSorts(), false)
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = tostring(err)
        ns.Debug:Log("SendSearchQuery failed for itemID " .. tostring(target.itemID) .. ": " .. tostring(err))
        self:FinishPendingTarget({})
        return
    end

    self:SetStatus("Querying " .. tostring(target.label) .. " (" .. tostring(target.itemID) .. ")")
    self:UpdateProgressText()
    self:SchedulePendingTimeout()
    self:SchedulePendingPoll(0.35)
end

---@param itemKey ItemKey
---@param target table
---@return boolean
function Scanner:ItemKeyMatchesTarget(itemKey, target)
    if not itemKey or not target then
        return false
    end
    if tonumber(itemKey.itemID) ~= tonumber(target.itemID) then
        return false
    end
    if target.itemLevel and target.itemLevel > 0 and itemKey.itemLevel and itemKey.itemLevel > 0 then
        local activeItemKey = self:GetTargetQueryItemKey(target)
        if activeItemKey and tonumber(activeItemKey.itemLevel) == 0 then
            return true
        end
        return tonumber(itemKey.itemLevel) == tonumber(target.itemLevel)
    end
    return true
end

---@param itemID number
---@return table[] rows
function Scanner:GetCommodityRows(itemID)
    local rows = {}
    local ok, numResults = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not ok then
        return rows
    end

    for index = 1, numResults do
        local success, result = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
        if success and result then
            local price = tonumber(result.unitPrice)
            local quantity = tonumber(result.quantity) or 0
            if price and price > 0 and quantity > 0 then
                table.insert(rows, {
                    unitPrice = price,
                    quantity = quantity,
                })
            end
        end
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    return rows
end

---@param itemKey ItemKey
---@param target table?
---@return table[] rows
function Scanner:GetItemRows(itemKey, target)
    local rows = {}
    local rawRows = target and target.cachedItemRows
    if not rawRows then
        rawRows = {}
        local ok, numResults = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
        if not ok then
            return rows
        end

        for index = 1, numResults do
            local success, result = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
            if success and result then
                local buyout = tonumber(result.buyoutAmount)
                local quantity = tonumber(result.quantity) or 1
                if buyout and buyout > 0 and quantity > 0 then
                    local itemLink = result.itemLink
                    if not itemLink and result.auctionID and C_AuctionHouse.GetAuctionInfoByID then
                        local auctionOK, auctionInfo = pcall(C_AuctionHouse.GetAuctionInfoByID, result.auctionID)
                        if auctionOK and auctionInfo then
                            itemLink = auctionInfo.itemLink
                        end
                    end
                    table.insert(rawRows, {
                        unitPrice = buyout,
                        quantity = quantity,
                        itemKey = result.itemKey or itemKey,
                        itemLink = itemLink,
                        auctionID = result.auctionID,
                    })
                end
            end
        end
        if target then
            target.currentRawItemRows = rawRows
        end
    end

    local rankItemLevels
    if target and target.requiredBonusIDs then
        rankItemLevels = self:InferRankItemLevels(target, rawRows)
        target.itemLevel = rankItemLevels and rankItemLevels[target.outputQualityID] or 0
        target.rankClassificationResolved = target.itemLevel > 0
    end

    for _, result in ipairs(rawRows) do
        local resultItemKey = result.itemKey or itemKey
        local matchesTarget = not target or tonumber(resultItemKey.itemID) == tonumber(target.itemID)
        if matchesTarget and target and target.requiredBonusIDs then
            local bonusMatch = self:ItemLinkMatchesBonusIDs(result.itemLink, target.requiredBonusIDs)
            local inferredItemLevel = rankItemLevels and rankItemLevels[target.outputQualityID]
            local itemLevelMatch = inferredItemLevel and inferredItemLevel > 0 and
                tonumber(resultItemKey.itemLevel) == tonumber(inferredItemLevel)
            matchesTarget = bonusMatch == true or itemLevelMatch == true
        elseif matchesTarget and target and target.itemLevel and target.itemLevel > 0 then
            matchesTarget = tonumber(resultItemKey.itemLevel) == tonumber(target.itemLevel)
        end
        if matchesTarget then
            table.insert(rows, result)
        end
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    return rows
end

---@param rows table[]
---@return number quantity
function Scanner:GetListedQuantity(rows)
    local quantity = 0
    for _, row in ipairs(rows) do
        quantity = quantity + (tonumber(row.quantity) or 0)
    end
    return quantity
end

---@param resultType "commodity" | "item"
---@return boolean hasFullResults
function Scanner:HasFullResults(resultType)
    local target = self.pendingQuery
    if not target then
        return true
    end

    local ok, hasFullResults
    if resultType == "commodity" and C_AuctionHouse.HasFullCommoditySearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.HasFullCommoditySearchResults, target.itemID)
    elseif resultType == "item" and C_AuctionHouse.HasFullItemSearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.HasFullItemSearchResults, self:GetTargetQueryItemKey(target))
    end
    if ok then
        return hasFullResults == true
    end
    return false
end

---@param resultType "commodity" | "item"
---@return table[] rows
function Scanner:GetRowsForResultType(resultType)
    local target = self.pendingQuery
    if not target then
        return {}
    end

    if resultType == "commodity" then
        return self:GetCommodityRows(target.itemID)
    end
    return self:GetItemRows(self:GetTargetQueryItemKey(target), target)
end

---@param target table
---@return string[]
function Scanner:GetResultTypesToTry(target)
    if target.resultType == "commodity" then
        return { "commodity", "item" }
    elseif target.resultType == "item" then
        return { "item", "commodity" }
    end
    return { "commodity", "item" }
end

---@param target table
---@param force boolean?
---@return boolean sent
function Scanner:TrySendSellSearchFallback(target, force)
    if not target or target.sellSearchFallbackSent or not self:IsLikelyCommodityTarget(target) then
        return false
    end
    if not C_AuctionHouse or not C_AuctionHouse.SendSellSearchQuery then
        return false
    end
    if not self:IsAuctionThrottleReady() then
        return false
    end
    if not force and target.queryStartTime and (GetTime() - target.queryStartTime) < 1.5 then
        return false
    end

    target.sellSearchFallbackSent = true
    target.activeItemKey = self:MakeItemKey(target.itemID, 0)
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.resultsReceived = false
    target.error = nil

    local ok, err = pcall(C_AuctionHouse.SendSellSearchQuery, target.activeItemKey, self:GetSearchSorts(), false)
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = "Commodity sell search failed: " .. tostring(err)
        ns.Debug:Log("SendSellSearchQuery fallback failed for itemID " .. tostring(target.itemID) .. ": " ..
            tostring(err))
        return false
    end

    self:SetStatus("Retrying exact commodity search for " .. tostring(target.label))
    self:SchedulePendingTimeout()
    return true
end

---@param target table
---@param force boolean?
---@return boolean sent
function Scanner:TrySendItemLevelFallback(target, force)
    if not target or target.pricingMode == "output" or target.itemLevelFallbackSent or not target.itemLevel or
        target.itemLevel <= 0 then
        return false
    end
    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then
        return false
    end
    if not self:IsAuctionThrottleReady() then
        return false
    end
    if not force and target.queryStartTime and (GetTime() - target.queryStartTime) < 1.5 then
        return false
    end

    target.itemLevelFallbackSent = true
    target.activeItemKey = self:MakeItemKey(target.itemID, 0)
    target.moreRequests = 0
    target.queryStartTime = GetTime()
    target.resultsReceived = false
    target.error = nil

    local ok, err = pcall(C_AuctionHouse.SendSearchQuery, target.activeItemKey, self:GetSearchSorts(), false)
    self.nextQueryTime = GetTime() + MIN_QUERY_INTERVAL
    if not ok then
        target.error = "Broad item search failed: " .. tostring(err)
        ns.Debug:Log("Broad item search failed for itemID " .. tostring(target.itemID) .. ": " .. tostring(err))
        return false
    end

    self:SetStatus("Retrying broad item search for " .. tostring(target.label))
    self:SchedulePendingTimeout()
    return true
end

---@param seconds number?
function Scanner:SchedulePendingPoll(seconds)
    self.pendingPollToken = self.pendingPollToken + 1
    local token = self.pendingPollToken
    C_Timer.After(seconds or 0.35, function()
        if Scanner.isScanning and Scanner.pendingQuery and
            Scanner.pendingPollToken == token then
            Scanner:PollPendingResults()
        end
    end)
end

---@param target table
---@param resultType "commodity" | "item"
function Scanner:ScheduleResultProcessing(target, resultType)
    C_Timer.After(0.05, function()
        if Scanner.isScanning and Scanner.pendingQuery == target and target.resultsReceived then
            Scanner:ProcessPendingResults(resultType)
        end
    end)
end

---@param target table
---@param respectRetryDelay boolean?
---@return boolean waitingForFallback
function Scanner:TryFallbacksBeforeMissing(target, respectRetryDelay)
    if self:CanTryItemLevelFallback(target) then
        if self:TrySendItemLevelFallback(target, not respectRetryDelay) then
            self:SchedulePendingPoll(0.35)
            return true
        end
        self:SchedulePendingPoll(0.35)
        return true
    end

    if self:CanTrySellSearchFallback(target) then
        if self:TrySendSellSearchFallback(target, not respectRetryDelay) then
            self:SchedulePendingPoll(0.35)
            return true
        end
        self:SchedulePendingPoll(0.35)
        return true
    end

    return false
end

function Scanner:PollPendingResults()
    local target = self.pendingQuery
    if not self.isScanning or not target then
        return
    end

    if not target.resultsReceived then
        self:SchedulePendingPoll(0.35)
        return
    end

    for _, resultType in ipairs(self:GetResultTypesToTry(target)) do
        local rows = self:GetRowsForResultType(resultType)
        local hasUnfilteredRankRows = resultType == "item" and target.requiredBonusIDs and
            target.currentRawItemRows and #target.currentRawItemRows > 0
        if #rows > 0 or hasUnfilteredRankRows then
            self:ProcessPendingResults(resultType)
            return
        elseif self:HasFullResults(resultType) then
            if self:TryFallbacksBeforeMissing(target, false) then
                return
            end
            self:ProcessPendingResults(resultType)
            return
        end
    end

    if self:TryFallbacksBeforeMissing(target, true) then
        return
    end
    self:SchedulePendingPoll(0.35)
end

---@param target table
---@return boolean processed
function Scanner:TryProcessAvailableResultsAtTimeout(target)
    if not target or self.pendingQuery ~= target then
        return false
    end

    target.resultsReceived = true
    for _, resultType in ipairs(self:GetResultTypesToTry(target)) do
        local rows = self:GetRowsForResultType(resultType)
        local hasUnfilteredRankRows = resultType == "item" and target.requiredBonusIDs and
            target.currentRawItemRows and #target.currentRawItemRows > 0
        if #rows > 0 or hasUnfilteredRankRows or self:HasFullResults(resultType) then
            self:ProcessPendingResults(resultType)
            return true
        end
    end

    target.resultsReceived = false
    return false
end

---@param resultType "commodity" | "item"
---@return boolean waitingForMore
function Scanner:RequestMoreResultsIfNeeded(resultType, rows)
    local target = self.pendingQuery
    if not target then
        return false
    end
    local needsSharedOutputSnapshot = target.pricingMode == "output" and target.requiredBonusIDs ~= nil
    if not self:TargetUsesFillQuantity(target) and not needsSharedOutputSnapshot and #rows > 0 then
        return false
    end

    local fillQuantity = Config:GetFillQuantity()
    if (not needsSharedOutputSnapshot and self:GetListedQuantity(rows) >= fillQuantity) or
        self:HasFullResults(resultType) then
        return false
    end

    if target.moreRequests >= MAX_MORE_RESULT_REQUESTS then
        return false
    end

    target.moreRequests = target.moreRequests + 1
    local ok, hasFullResults
    if resultType == "commodity" and C_AuctionHouse.RequestMoreCommoditySearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.RequestMoreCommoditySearchResults, target.itemID)
    elseif resultType == "item" and C_AuctionHouse.RequestMoreItemSearchResults then
        ok, hasFullResults = pcall(C_AuctionHouse.RequestMoreItemSearchResults, self:GetTargetQueryItemKey(target))
    end

    if ok and hasFullResults == false then
        target.resultsReceived = false
        self:SetStatus("Loading more results for " .. tostring(target.label))
        self:SchedulePendingTimeout()
        self:SchedulePendingPoll(0.35)
        return true
    end

    return false
end

---@param values number[]
---@return number[] trimmed
function Scanner:TrimOutliers(values)
    local count = #values
    if count < 8 then
        return values
    end

    local q1 = values[math.max(1, math.floor((count + 1) * 0.25))]
    local q3 = values[math.max(1, math.floor((count + 1) * 0.75))]
    local iqr = q3 - q1
    local lower = math.max(0, q1 - 1.5 * iqr)
    local upper = q3 + 1.5 * iqr
    if iqr <= 0 then
        upper = q3 * 3
    end

    local trimmed = {}
    for _, value in ipairs(values) do
        if value >= lower and value <= upper then
            table.insert(trimmed, value)
        end
    end

    if #trimmed == 0 then
        return values
    end
    return trimmed
end

---@param rows table[]
---@return number? price
---@return number quantityUsed
---@return number listedQuantity
---@return number trimmedUnits
function Scanner:CalculateTrimmedFillPrice(rows)
    local fillQuantity = Config:GetFillQuantity()
    local remaining = fillQuantity
    local unitPrices = {}
    local listedQuantity = 0

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)

    for _, row in ipairs(rows) do
        local quantity = math.max(0, math.floor(tonumber(row.quantity) or 0))
        local unitPrice = tonumber(row.unitPrice)
        listedQuantity = listedQuantity + quantity
        if unitPrice and unitPrice > 0 and remaining > 0 then
            local fillFromRow = math.min(quantity, remaining)
            for _ = 1, fillFromRow do
                table.insert(unitPrices, unitPrice)
            end
            remaining = remaining - fillFromRow
        end
        if remaining <= 0 then
            break
        end
    end

    if #unitPrices == 0 then
        return nil, 0, listedQuantity, 0
    end

    table.sort(unitPrices)
    local trimmed = self:TrimOutliers(unitPrices)
    local total = 0
    for _, unitPrice in ipairs(trimmed) do
        total = total + unitPrice
    end

    local price = math.floor((total / #trimmed) + 0.5)
    return price, #unitPrices, listedQuantity, #unitPrices - #trimmed
end

---@param rows table[]
---@return number? price
---@return number quantityUsed
---@return number listedQuantity
---@return number trimmedUnits
function Scanner:CalculateLowestBuyoutPrice(rows)
    if #rows == 0 then
        return nil, 0, 0, 0
    end

    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)

    local price = tonumber(rows[1].unitPrice)
    if not price or price <= 0 then
        return nil, 0, self:GetListedQuantity(rows), 0
    end

    return math.floor(price + 0.5), 1, self:GetListedQuantity(rows), 0
end

---@param target table
---@return number? price
function Scanner:GetTSMFallbackPrice(target)
    if not target or not target.itemID then
        return nil
    end

    local isReagent = target.kindMap and target.kindMap.input == true and target.kindMap.output ~= true
    local price = ns.Compat.CraftSim:GetTSMFallbackPrice(target.itemID, isReagent)
    if price and price > 0 then
        return math.floor(price + 0.5)
    end
    return nil
end

---@param resultType "commodity" | "item"
function Scanner:ProcessPendingResults(resultType)
    if not self.isScanning or not self.pendingQuery then
        return
    end

    local target = self.pendingQuery
    if not target.resultsReceived then
        self:SchedulePendingPoll(0.35)
        return
    end
    local rows = self:GetRowsForResultType(resultType)

    if #rows == 0 then
        if self:TryFallbacksBeforeMissing(target, false) then
            return
        end
    end

    if self:RequestMoreResultsIfNeeded(resultType, rows) then
        return
    end

    self:FinishPendingTarget(rows, resultType)
end

---@param rows table[]
---@param resultType "commodity" | "item"?
function Scanner:FinishPendingTarget(rows, resultType)
    local target = self.pendingQuery
    if not target then
        return
    end

    self.pendingTimeoutToken = self.pendingTimeoutToken + 1

    local queryItemKey = self:GetTargetQueryItemKey(target)
    if target.pricingMode == "output" and queryItemKey and tonumber(queryItemKey.itemLevel) == 0 and
        target.currentRawItemRows then
        self.outputItemRowsCache[target.itemID] = target.currentRawItemRows
    end

    local price, quantityUsed, listedQuantity, trimmedUnits
    if self:TargetUsesFillQuantity(target) then
        price, quantityUsed, listedQuantity, trimmedUnits = self:CalculateTrimmedFillPrice(rows)
    else
        price, quantityUsed, listedQuantity, trimmedUnits = self:CalculateLowestBuyoutPrice(rows)
    end
    local source = "AH"
    -- A shared item ID cannot use an item-level-zero TSM price as a quality
    -- fallback. It would assign one generic item price to an arbitrary rank.
    local allowTSMFallback = target.pricingMode ~= "output" or
        (target.requiredBonusIDs == nil and (not target.itemLevel or target.itemLevel <= 0))
    if not price and allowTSMFallback then
        price = self:GetTSMFallbackPrice(target)
        if price then
            source = "TSM fallback"
            quantityUsed = 0
            listedQuantity = 0
            trimmedUnits = 0
        end
    end

    if price then
        table.insert(self.priceResults, {
            itemID = target.itemID,
            itemLevel = target.itemLevel,
            itemKey = self:GetTargetQueryItemKey(target),
            label = target.label,
            price = price,
            source = source,
            quantityUsed = quantityUsed,
            listedQuantity = listedQuantity,
            trimmedUnits = trimmedUnits,
            overrideTargets = target.overrideTargets,
        })
        if source ~= "AH" then
            self:SetStatus("Using " .. source .. " for " .. tostring(target.label) .. " (" ..
                tostring(target.itemID) .. ")")
        end
    else
        if target.requiredBonusIDs and target.currentRawItemRows and #target.currentRawItemRows > 0 and
            not target.rankClassificationResolved then
            target.error = target.error or "Posted auctions found, but rank could not be identified."
        else
            target.error = target.error or "No posted auctions found."
        end
        table.insert(self.missingResults, {
            itemID = target.itemID,
            itemLevel = target.itemLevel,
            label = target.label,
            error = target.error,
            overrideTargets = target.overrideTargets,
        })
        self:SetStatus("Skipping " .. tostring(target.label) .. " (" .. tostring(target.itemID) .. "): " ..
            tostring(target.error))
    end

    self.completedTargets = self.completedTargets + 1
    self.pendingQuery = nil
    self.pendingPollToken = self.pendingPollToken + 1
    self:UpdateProgressText()
    self:UpdateButtons()

    -- Cached rank variants do not send another AH request. Process the next
    -- target immediately; TrySendNextQuery still enforces nextQueryTime before
    -- the next real request.
    local nextTargetDelay = target.usedCachedRows and 0 or MIN_QUERY_INTERVAL
    C_Timer.After(nextTargetDelay, function()
        Scanner:TrySendNextQuery()
    end)
end

function Scanner:FinishScan()
    self.isScanning = false
    self.pendingQuery = nil
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    self.pendingPollToken = self.pendingPollToken + 1
    self.scanComplete = true
    self:SetStatus(string.format("Scan complete. %d prices ready, %d missing. Press Push Overrides to apply.",
        #self.priceResults, self:GetMissingDisplayCount()))
    self:UpdateProgressText()
    self:UpdateButtons()
    if self.missingPanel and self.missingPanel:IsShown() then
        self:UpdateMissingList()
    end
    SystemPrint(string.format("Scan complete: %d prices found, %d missing.", #self.priceResults,
        self:GetMissingDisplayCount()))
end

---@param reason string?
function Scanner:CancelScan(reason)
    self.isScanning = false
    self.pendingQuery = nil
    self.pendingTimeoutToken = self.pendingTimeoutToken + 1
    self.pendingPollToken = self.pendingPollToken + 1
    self.scanComplete = false
    self:SetStatus(reason or "Scan cancelled.")
    self:UpdateProgressText()
    self:UpdateButtons()
end

---@return table<string, number> pricesByOverrideKey
---@return number cappedCount
function Scanner:GetNormalizedResultOverridePrices()
    local pricesByRecipe = {}

    for _, result in ipairs(self.priceResults or {}) do
        local price = math.floor((tonumber(result.price) or 0) + 0.5)
        if price > 0 then
            for _, overrideTarget in ipairs(result.overrideTargets or {}) do
                local recipeID = tonumber(overrideTarget.recipeID)
                local qualityID = tonumber(overrideTarget.qualityID)
                if overrideTarget.kind == "result" and recipeID and qualityID then
                    pricesByRecipe[recipeID] = pricesByRecipe[recipeID] or {}
                    local current = pricesByRecipe[recipeID][qualityID]
                    pricesByRecipe[recipeID][qualityID] = current and math.min(current, price) or price
                end
            end
        end
    end

    local normalized = {}
    local cappedCount = 0
    for recipeID, pricesByQuality in pairs(pricesByRecipe) do
        local qualityIDs = {}
        for qualityID in pairs(pricesByQuality) do
            table.insert(qualityIDs, qualityID)
        end
        table.sort(qualityIDs, function(a, b) return a > b end)

        local cheapestEqualOrBetter
        for _, qualityID in ipairs(qualityIDs) do
            local listedPrice = pricesByQuality[qualityID]
            if not cheapestEqualOrBetter or listedPrice < cheapestEqualOrBetter then
                cheapestEqualOrBetter = listedPrice
            elseif listedPrice > cheapestEqualOrBetter then
                cappedCount = cappedCount + 1
            end
            normalized[tostring(recipeID) .. ":" .. tostring(qualityID)] = cheapestEqualOrBetter
        end
    end

    return normalized, cappedCount
end

function Scanner:PushOverrides()
    if not self.scanComplete or not self:HasOverridesToPush() then
        self:SetStatus("Run a scan before pushing overrides.")
        return
    end

    local savedGlobals = {}
    local savedResults = {}
    local globalCount = 0
    local resultCount = 0
    local suppressedResultCount = 0
    local normalizedResultPrices, cappedResultCount = self:GetNormalizedResultOverridePrices()

    for _, result in ipairs(self.priceResults) do
        local price = math.floor((tonumber(result.price) or 0) + 0.5)
        if price > 0 then
            for _, overrideTarget in ipairs(result.overrideTargets or {}) do
                if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
                    local key = tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
                    if not savedResults[key] then
                        local resultPrice = normalizedResultPrices[key] or price
                        local saved, saveError = ns.Compat.CraftSim:SaveResultOverride({
                            recipeID = overrideTarget.recipeID,
                            itemID = overrideTarget.itemID or result.itemID,
                            qualityID = overrideTarget.qualityID,
                            price = resultPrice,
                        })
                        if not saved then
                            self:SetStatus(saveError)
                            return
                        end
                        savedResults[key] = true
                        resultCount = resultCount + 1
                    end
                elseif overrideTarget.kind == "global" and overrideTarget.itemID then
                    local key = tostring(overrideTarget.itemID)
                    if not savedGlobals[key] then
                        local saved, saveError = ns.Compat.CraftSim:SaveGlobalOverride({
                            recipeID = overrideTarget.recipeID or 0,
                            itemID = overrideTarget.itemID,
                            qualityID = overrideTarget.qualityID,
                            price = price,
                        })
                        if not saved then
                            self:SetStatus(saveError)
                            return
                        end
                        savedGlobals[key] = true
                        globalCount = globalCount + 1
                    end
                end
            end
        end
    end

    for _, missingResult in ipairs(self.missingResults or {}) do
        if self:IsConfirmedNoAuctionResult(missingResult) then
            for _, overrideTarget in ipairs(missingResult.overrideTargets or {}) do
                if overrideTarget.kind == "result" and overrideTarget.recipeID and overrideTarget.qualityID then
                    local key = tostring(overrideTarget.recipeID) .. ":" .. tostring(overrideTarget.qualityID)
                    if not savedResults[key] then
                        local saved, saveError = ns.Compat.CraftSim:SaveResultOverride({
                            recipeID = overrideTarget.recipeID,
                            itemID = overrideTarget.itemID or missingResult.itemID,
                            qualityID = overrideTarget.qualityID,
                            price = 1,
                        })
                        if not saved then
                            self:SetStatus(saveError)
                            return
                        end
                        savedResults[key] = true
                        suppressedResultCount = suppressedResultCount + 1
                    end
                end
            end
        end
    end

    ns.Compat.CraftSim:UpdateCraftSimUI()

    self.overridesPushed = true
    self:SetStatus(string.format(
        "Pushed %d reagent and %d result overrides; capped %d lower-rank prices; suppressed %d missing results.",
        globalCount, resultCount, cappedResultCount, suppressedResultCount))
    self:UpdateButtons()
    SystemPrint(string.format(
        "Pushed %d reagent and %d result overrides; capped %d lower-rank prices; suppressed %d missing results.",
        globalCount, resultCount, cappedResultCount, suppressedResultCount))
end

function Scanner:AUCTION_HOUSE_SHOW()
    self:ShowButton()
end

function Scanner:AUCTION_HOUSE_CLOSED()
    if self.panel then
        self.panel:Hide()
    end
    if self.configPanel then
        self.configPanel:Hide()
    end
    if self.missingPanel then
        self.missingPanel:Hide()
    end
    self:UpdateLauncherTabState()
    if self.button then
        self.button:Hide()
    end
    if self.isScanning then
        self:CancelScan("Auction House closed.")
    end
end

function Scanner:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
    self:TrySendNextQuery()
end

function Scanner:AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED()
    if self.pendingQuery then
        self.pendingQuery.error = "Auction House throttled message dropped."
        self:FinishPendingTarget({})
    end
end

function Scanner:AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED()
    if self.pendingQuery then
        -- Some non-commodity searches only produce the generic throttle
        -- response after their result cache has been populated.  Treat it as
        -- permission to inspect the cache instead of waiting indefinitely for
        -- a second, item-specific event that may never be sent.
        self.pendingQuery.resultsReceived = true
        self:SchedulePendingPoll(0.05)
    else
        self:TrySendNextQuery()
    end
end

function Scanner:AUCTION_HOUSE_NEW_RESULTS_RECEIVED(itemKey)
    local target = self.pendingQuery
    if itemKey and not self:ItemKeyMatchesTarget(itemKey, target) then
        return
    end
    if target then
        target.resultsReceived = true
        self:SchedulePendingPoll(0.05)
    end
end

function Scanner:COMMODITY_SEARCH_RESULTS_ADDED(itemID)
    self:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
end

function Scanner:COMMODITY_SEARCH_RESULTS_RECEIVED()
    local target = self.pendingQuery
    if not target or not self:IsLikelyCommodityTarget(target) then
        return
    end
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "commodity")
end

function Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
    local target = self.pendingQuery
    if not target or tonumber(itemID) ~= tonumber(target.itemID) then
        return
    end
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "commodity")
end

function Scanner:ITEM_SEARCH_RESULTS_ADDED(itemKey)
    self:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
end

function Scanner:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
    local target = self.pendingQuery
    if not self:ItemKeyMatchesTarget(itemKey, target) then
        return
    end
    target.resultsReceived = true
    self:ScheduleResultProcessing(target, "item")
end

function Scanner:Open()
    Scanner:ShowButton()
    Scanner:TogglePanel()
end

function Scanner:CanInitialize()
    local auctionAPIs = {
        "MakeItemKey",
        "GetItemKeyInfo",
        "IsThrottledMessageSystemReady",
        "SendSearchQuery",
        "SendSellSearchQuery",
        "GetNumCommoditySearchResults",
        "GetCommoditySearchResultInfo",
        "GetNumItemSearchResults",
        "GetItemSearchResultInfo",
        "HasFullCommoditySearchResults",
        "HasFullItemSearchResults",
        "RequestMoreCommoditySearchResults",
        "RequestMoreItemSearchResults",
    }
    if not C_AuctionHouse then
        return nil, "Auction House APIs are unavailable"
    end
    for _, functionName in ipairs(auctionAPIs) do
        if type(C_AuctionHouse[functionName]) ~= "function" then
            return nil, "C_AuctionHouse." .. functionName .. " is unavailable"
        end
    end
    if not Enum or not Enum.Profession or not Enum.AuctionHouseSortOrder or
        type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" or
        not C_TradeSkillUI or type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) ~= "function" or
        not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" or
        not C_Timer or type(C_Timer.After) ~= "function" or type(GetTime) ~= "function" then
        return nil, "required Auction House or profession APIs are unavailable"
    end
    return ns.Compat.CraftSim:ValidateAuctionScanner()
end

function Scanner:Initialize()
    if self.initialized then
        return true
    end
    self.eventFrame = ns:CreateEventDispatcher(self, EVENTS)
    self.initialized = true
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        self:ShowButton()
    end
    return true
end

ns:RegisterModule("AuctionHouseScan", Scanner)
