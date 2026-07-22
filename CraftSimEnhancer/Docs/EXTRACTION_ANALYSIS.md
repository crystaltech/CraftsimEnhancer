# CraftSim Enhancer extraction analysis

## Compared installations

The comparison used `CraftSim_stock/` and `CraftSim_mod/`. Their roles were verified from content, not names:

- Both TOCs identify CraftSim 26.1.10 and interfaces 120000, 120001, 120005, and 120007.
- `CraftSim_stock/CHANGELOG.md` contains the packaged 26.1.10 release and the newer bundled LibDBIcon 12.0.2.
- `CraftSim_mod/` contains all custom modules and TOC load entries, while its changelog and bundled LibDBIcon still reflect the preceding package. This establishes it as the working modified installation layered across an upstream update.

The recursive comparison contained 261 stock files and 274 modified files. Files were compared again after stripping carriage returns so line-ending changes would not be misclassified as features.

## Customization inventory

1. Auction House Scanner
   - Adds a CraftSim launcher to the Auction House.
   - Selects learned professions per crafter.
   - Builds configurable scan targets from generated recipe and item metadata.
   - Provides presets, target inclusion checkboxes, progress, missing-result details, fixed vendor pricing, TSM fallback pricing, and Auction House throttling/retry handling.
   - Calculates input prices from a fill quantity with IQR outlier trimming and output prices from the lowest buyout.
   - Pushes reagent and recipe-result prices into CraftSim's existing price-override repository.

2. Generated Midnight recipe database
   - Contains 764 recipes across nine professions and metadata for 1,103 items.
   - Supplies item IDs, quality ranks, item levels, bindings, auctionability, commodity flags, vendor prices, recipe sources, and category tags used by the scanner.

3. Vendor Buy
   - Adds a `Buy Reagents` button to the merchant window.
   - Computes outstanding reagents from CraftSim's queue, excludes customer/order/self-crafted/soulbound reagents, subtracts cached inventory across queued crafters, matches the current merchant, checks available gold, buys matching stock, and deducts bought quantities from the CraftSim Auctionator shopping list.

4. Vendor-reagent shopping-list notice
   - Detects vendor-sold reagents after CraftSim creates an Auctionator list.
   - Shows a deduplicated popup recommending a vendor visit before Auction House purchases.

5. RecipeScan smart-restock rewrite
   - Reorganizes the calculation when TSM restock-expression and smart-restock options are both enabled.
   - On stock 26.1.10 this is algebraically equivalent to upstream behavior: the custom branch uses `needed`, while stock computes `max(0, target - owned)` using the same `GetSmartRestockAmount` source. No standalone runtime patch is needed for this supported version.

## File-by-file diff summary

| Path in modified CraftSim | Difference | Classification / extraction |
| --- | --- | --- |
| `CraftSim.toc` | Loads one DB file, ten generated-data files, and two modules | Custom; replaced by the Enhancer TOC |
| `DB/auctionHouseScanDB.lua` | 173-line CraftSim repository for scanner settings | Custom; rewritten into `CraftSimEnhancerDB` |
| `Data/GeneratedRecipes/*.lua` | Ten generated files | Custom; moved under the enhancer namespace |
| `Modules/AuctionHouseScan/AuctionHouseScan.lua` | 3,664-line scanner/UI | Custom; extracted as an independent module |
| `Modules/VendorBuy/VendorBuy.lua` | 444-line merchant integration | Custom; extracted behind compatibility adapters |
| `Init/Init.lua` | Adds one static popup definition | Custom; owned by the notice module now |
| `Modules/CraftQueue/CraftQueue.lua` | Adds vendor classification/popup and calls it after list creation | Custom; replaced with a secure post-hook |
| `Modules/RecipeScan/RecipeScan.lua` | Rewrites smart-restock branching | Custom but equivalent to stock 26.1.10; no patch installed |
| `CHANGELOG.md` | Modified tree has the preceding 26.1.9 package text | Upstream/package drift; not a feature |
| `Libs/LibDBIcon-1.0/LibDBIcon-1.0.toc` | Modified tree has 12.0.1 rather than stock 12.0.2 | Upstream/package drift; not a feature |
| `Data/News.lua` | Line endings only | Ignored |
| `Data/SpecializationData/Midnight/Alchemy.lua` | Line endings only | Ignored |
| `Data/SpecializationData/Midnight/Inscription.lua` | Line endings only | Ignored |
| `Data/SpecializationData/Midnight/Tailoring.lua` | Line endings only | Ignored |

## Newly added files in modified CraftSim

- `DB/auctionHouseScanDB.lua`
- `Modules/AuctionHouseScan/AuctionHouseScan.lua`
- `Modules/VendorBuy/VendorBuy.lua`
- `Data/GeneratedRecipes/ItemMetadata.lua`
- `Data/GeneratedRecipes/Alchemy.lua`
- `Data/GeneratedRecipes/Blacksmithing.lua`
- `Data/GeneratedRecipes/Cooking.lua`
- `Data/GeneratedRecipes/Enchanting.lua`
- `Data/GeneratedRecipes/Engineering.lua`
- `Data/GeneratedRecipes/Inscription.lua`
- `Data/GeneratedRecipes/Jewelcrafting.lua`
- `Data/GeneratedRecipes/Leatherworking.lua`
- `Data/GeneratedRecipes/Tailoring.lua`

## Modified upstream files

Meaningful custom changes: `CraftSim.toc`, `Init/Init.lua`, `Modules/CraftQueue/CraftQueue.lua`, and `Modules/RecipeScan/RecipeScan.lua`.

Non-feature differences that should still be restored to match the CurseForge package exactly: `CHANGELOG.md`, `Libs/LibDBIcon-1.0/LibDBIcon-1.0.toc`, `Data/News.lua`, and the three Midnight specialization files listed above.

## Feature dependency map

| Feature | Data / UI | CraftSim dependency | Blizzard dependency | Extraction method | Risk |
| --- | --- | --- | --- | --- | --- |
| AH Scanner | Generated recipes and item metadata; Auction House tab/panels | Price override repository, profession labels/icons, UI refresh, optional TSM source | Auction House query APIs/events, frames, menus, timers | Independent module plus compatibility adapter | High: Auction House frame internals and CraftSim override internals |
| Vendor Buy | Merchant button/tooltips | Queue object/recipe model, inventory-cache helpers, shopping-list name | Merchant, item, money, tooltip and bag events | Independent UI module plus compatibility adapter | High: CraftSim queue model; medium: Auctionator API |
| Vendor notice | Item metadata and popup | Shopping-list creation function and queue model | `hooksecurefunc`, static popup API | Secure post-hook | Medium: hooked internal function name/signature |
| RecipeScan restock | None | Existing public smart-restock calculation | None | No runtime patch because supported stock is equivalent | Low at 26.1.10; re-audit on change |

If any compatibility check fails, only the affected module is disabled, one warning is recorded, and `/cse status` exposes the failure. Programming errors are not hidden behind a broad `pcall`.

## CraftSim API and internal dependency report

Documented public entry point:

- `CraftSimAPI:GetCraftSim()` from `Util/API.lua`. This is used once to obtain CraftSim's namespace.

Public API inspected but not needed for a runtime RecipeScan patch:

- `CraftSimAPI:GetSmartRestockAmount(recipeData)` from `Util/API.lua`.

Internal dependencies centralized in `Compat/CraftSim.lua`:

- `CRAFTQ.craftQueue.craftQueueItems` and each queue item's recipe/reagent model.
- `CRAFTQ:GetNonSoulboundAlternativeItemID(itemID)`.
- `CRAFTQ:GetItemCountFromCraftQueueCache(crafterUID, itemID)`.
- `CRAFTQ:CreateAuctionatorShoppingList()` as a secure-hook target.
- `DB.PRICE_OVERRIDE:SaveGlobalOverride(data)` and `SaveResultOverride(data)`.
- `CONST.AUCTIONATOR_SHOPPING_LIST_QUEUE_NAME`.
- `CONST.PROFESSION_LOCALIZATION_IDS`, `CONST.PROFESSION_ICONS`, and `LOCAL:GetText`.
- `MODULES:UpdateUI()` after new overrides are saved.
- `CraftSimTSM:GetMinBuyoutByItemID` as an optional fallback.

These are internal even though `GetCraftSim()` deliberately exposes the namespace. CraftSim 26.1.10 is the tested contract. Feature modules do not contain hardcoded CraftSim table paths.

Auctionator APIs retained from the working modification are `GetVendorPriceByItemID`, `GetShoppingListItems`, `ConvertToSearchString`, `ConvertFromSearchString`, `AlterShoppingListItem`, and `DeleteShoppingListItem`. They remain optional; Vendor Buy still buys when Auctionator is absent, but list deduction and metadata fallback are skipped.

## Blizzard API usage report

The APIs were checked in `References/wow-ui-source-live` for the 12.0.7 client represented by interface 120007.

| Area | Verified APIs / definitions | Important constraints |
| --- | --- | --- |
| Addon/build | `C_AddOns.IsAddOnLoaded`, `C_AddOns.GetAddOnMetadata`, `GetBuildInfo` | Used for startup/status only |
| Auction House | `C_AuctionHouse.MakeItemKey`, `GetItemKeyInfo`, `SendSearchQuery`, `SendSellSearchQuery`, result getters/counts, full-result checks, more-result requests, throttle-ready check | Documentation limits search queries to 100/minute; scanner uses a 0.65-second minimum interval and throttle events. Query/result functions have untainted-secret argument restrictions, so narrow recoverable calls use `pcall`. `SendSellSearchQuery` receives a zero-level/suffix key as documented. |
| Auction events | `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, throttle events, commodity/item result events | Drive deterministic attachment and result processing |
| Merchant | `C_MerchantFrame.GetItemInfo`; live MerchantFrame use of `GetMerchantNumItems`, `GetMerchantItemLink`, and `BuyMerchantItem`; `MERCHANT_SHOW`, `MERCHANT_UPDATE`, `MERCHANT_CLOSED` | Extended-cost and non-purchasable rows are deliberately excluded. Purchases occur only from the user's button click. |
| Items/professions | `C_Item.GetItemInfo`, `C_Item.GetItemInfoInstant`, `C_TradeSkillUI.GetItemReagentQualityByItemInfo`, `C_TradeSkillUI.GetProfessionInfoBySkillLineID`; live uses of `GetProfessions` and `GetProfessionInfo` | Cached item info can be absent; queue objects already own loaded item mixins. Binding is checked against `Enum.ItemBind.OnAcquire`. |
| UI/menu/tooltip | `CreateFrame`, frame scripts/events, `MenuUtil.CreateContextMenu`, `MenuResponse`, `GameTooltip`, `StaticPopup_Show`, `hooksecurefunc` | Existing scripts are hooked or independent controls are created; no CraftSim function is replaced. Named controls use `CraftSimEnhancer` prefixes. |
| Timing | `C_Timer.After`, `GetTime` | Used only for Auction House minimum spacing, timeout, and short result-settle polling—not startup discovery |
| Character/money | `UnitName`, `GetNormalizedRealmName`, `GetRealmName`, `GetMoney`, `GetMoneyString` | Character key fallback and merchant affordability/status |

No deprecated dropdown API is used. `Blizzard_Menu` is the current replacement documented by the reference implementation guide. No continuous `OnUpdate` handler is used. The addon does not create protected action buttons or alter protected CraftSim frames in combat.

## SavedVariables and migration

Enhancer settings live only in `CraftSimEnhancerDB` with `schemaVersion`, `migrationVersion`, `global`, and `profile` roots. The scanner stores fill quantity, selected professions per crafter, initialized-crafter flags, skipped targets, and configuration profession. Debug and per-module enable flags also live there.

On the first Enhancer load, migration version 1 reads but never modifies `CraftSimDB.auctionHouseScanDB.data`. Tables are copied into new tables so runtime changes cannot mutate the legacy database. An older global profession selection is assigned to the current crafter when no per-crafter map exists. The migration is then marked complete and is not repeated. `/cse reset confirm` marks the new database at the current migration version so the legacy data is not immediately imported again.

CraftSim's normal `priceOverrideDB` remains in CraftSim because it is an upstream CraftSim feature consumed directly by CraftSim. The scanner intentionally writes through that stock repository; those values should not be removed during migration.

## Extraction risks and update sensitivity

- CraftSim queue item, recipe, reagent, and cached-inventory layouts are internal and are the largest Vendor Buy risk.
- CraftSim price-override repositories and `MODULES:UpdateUI` are internal and are the largest scanner-to-CraftSim risk.
- The shopping-list hook depends on the internal `CreateAuctionatorShoppingList` method retaining its name and role.
- Auctionator's shopping-list and vendor-price APIs are external and version-sensitive.
- The scanner's insertion into `AuctionHouseFrame.Tabs` follows Blizzard's current source but is not a documented C API. If it changes, the module falls back to a separately anchored button.
- Generated recipe/item data is a snapshot and must be regenerated or replaced as recipes and item metadata change.
- Manual PTR, removed-item, warbound, and vendor-price overrides are data assumptions that need review each patch.
- The RecipeScan equivalence conclusion is specific to stock CraftSim 26.1.10 and should be rechecked if either upstream restock branch changes.

No identified feature required a custom source file to remain inside CraftSim. No feature was dropped; the only omitted runtime patch is the RecipeScan rewrite whose observable calculation already matches the tested stock release.
