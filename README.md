# CraftSim Enhancer

[![Latest release](https://img.shields.io/github/v/release/crystaltech/CraftsimEnhancer)](https://github.com/crystaltech/CraftsimEnhancer/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

CraftSim Enhancer is a standalone World of Warcraft Retail companion addon for [CraftSim](https://www.curseforge.com/wow/addons/craftsim). It adds Auction House pricing intelligence and a safer vendor-material workflow without modifying or placing files inside CraftSim.

> CraftSim Enhancer is independently developed. It is not affiliated with, maintained by, endorsed by, or part of the CraftSim project. CraftSim remains a required dependency and is installed separately.

## Current compatibility

- World of Warcraft Retail interface: **120007 (12.0.7)**
- CraftSim: **26.1.10**

Other versions may work when their required capabilities remain compatible. Run `/cse status` after updating World of Warcraft or CraftSim; the addon reports untested versions and disables only a feature whose required interface is unavailable.

World of Warcraft 12.1 will not be marked as supported until the live client and generated item data have been validated.

## What it adds

### CSE Recon

- A full Auction House tab with profession, recipe-category, and individual-item selection.
- Generated Midnight recipe and reagent scan targets.
- Fill-quantity and outlier-aware reagent pricing.
- Exact-rank crafted-output pricing using the lowest current buyout.
- Unpriced-item reports with query diagnostics and future-scan exclusion.
- Direct export into CraftSim's existing price-override system.

### Break-even intelligence

- Unlisted products use CraftSim's saved crafting cost to estimate a sale price after the 5% Auction House cut.
- Unlisted lower ranks are capped below the cheapest real higher-rank listing.
- Supported crafted-item tooltips show `CSE Break-even (5% AH)` for the exact item rank when CraftSim has a saved cost.
- Real Auction House results replace estimates during a later scan and push.

### Vendor Materials

- Vendor-sold reagents are separated from CraftSim's Auctionator shopping list, preventing accidental Auction House purchases.
- A movable, resizable, and collapsible window tracks the vendor items, quantities, and estimated cost.
- `Buy Vendor Mats` buys only items offered by the current merchant.
- Purchases are removed from the plan only after the items appear in the player's bags.
- The plan persists across reloads and closes automatically when complete.

## Requirements and optional integrations

- [CraftSim](https://www.curseforge.com/wow/addons/craftsim) is required.
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) is optional and enables shopping-list separation.
- [TradeSkillMaster](https://www.tradeskillmaster.com/) is optional and can provide fallback prices to CraftSim.

CraftSim Enhancer does not bundle any of these projects.

## Installation

1. Download the addon ZIP from the [latest release](https://github.com/crystaltech/CraftsimEnhancer/releases/latest).
2. Extract the ZIP into `_retail_/Interface/AddOns/`.
3. Install or update CraftSim separately.
4. Confirm that both addons are enabled at the character screen.
5. Log in and run `/cse status`.

The final folder layout should be:

```text
Interface/AddOns/CraftSim/
Interface/AddOns/CraftSimEnhancer/
```

Do not place `CraftSimEnhancer` inside the `CraftSim` folder.

## Quick start

1. In CraftSim's Recipe Scan or Craft Lists options, enable **Update Last Crafting Cost DB** and run a CraftSim scan once. This supplies costs for break-even estimates and tooltips.
2. Open the Auction House and select the **CSE Recon** tab.
3. Choose whether to scan **Crafted products**, **Required reagents**, or both.
4. Select professions, then use the persistent **Recipes** or **Individual items** tab to build the list. A recipe-tree change resets individual overrides within that branch, while shared items remain selected when another selected recipe needs them. The summary distinguishes selected recipes from the unique product, rank, and reagent price targets they produce.
5. Review any **Unpriced Items**, use **Skip future** for unwanted targets, and click **Push Overrides** when the scan completes.
6. Use CraftSim normally to choose crafts and create its Auctionator shopping list.
7. Buy the Auction House materials first, then visit vendors listed in the **Vendor Materials** window.

Large scans are intentionally paced around Blizzard's Auction House throttle and can take several minutes. Keep the Auction House open until the scan finishes or cancel it before leaving.

Completed-scan totals use price targets throughout, so priced plus unpriced always equals processed. The **Unpriced items** button separately reports grouped review rows because several ranks or variants can share one row.

## Pricing behavior

- Reagents use the selected fill quantity after trimming unusually high outlier listings.
- Crafted outputs use the lowest matching buyout for the exact output rank.
- A confirmed output with no listings is estimated as `floor(saved crafting cost / 0.95)`.
- An unlisted lower-rank estimate is capped to one copper below the cheapest real higher-rank result.
- An output without a saved CraftSim cost is skipped; CraftSim Enhancer does not invent a nominal price.
- The tooltip shows the uncapped break-even value. It may therefore be higher than a deliberately rank-capped override.

Scan results are temporary. Prices are persisted only when **Push Overrides** writes them to CraftSim's own price-override database.

## Recommended TSM expressions

When TradeSkillMaster is CraftSim's selected price source, open **CraftSim Options → TSM** and consider these conservative alternatives to the defaults.

### Crafting Reagents Price Expression

```text
max(first(dbminbuyout, dbrecent, dbmarket, dbregionmarketavg), 80% first(dbrecent, dbmarket, dbregionmarketavg))
```

This follows the best available current source while preventing an unusually small listing from reducing material costs below 80% of a recent or longer-term market value.

### Crafted Items Price Expression

```text
min(first(dbminbuyout, dbrecent, dbmarket, dbregionmarketavg), 120% first(dbrecent, dbmarket, dbregionmarketavg))
```

This follows the lowest available listing while limiting unusually high or thin listings to 120% of a recent or longer-term market value.

### Sold-per-day restock option

```text
ifgte(dbregionsoldperday, 0.1, min(20, max(1, roundup(3 * dbregionsoldperday))), 0)
```

This targets roughly three days of regional sales, skips items averaging fewer than 0.1 sales per day, and caps the target at 20. It returns a target inventory quantity; CraftSim subtracts owned inventory separately.

CraftSim also has a separate **TSM sale-rate threshold** in the gear menu beside **Send to Craft Queue**. New items may have no regional sales data, so a positive threshold can reject every result. Set it to `0` when new items should remain eligible. Temporarily disabling **Use TSM Restock Expression** makes CraftSim use its **Default Queue Amount** and is a useful troubleshooting check.

For slower gear, a one-week target capped at five is more conservative:

```text
min(5, max(1, roundup(7 * dbregionsoldperday)))
```

For high-volume consumables, a two-day target between five and 100 may be more useful:

```text
min(100, max(5, roundup(2 * dbregionsoldperday)))
```

`DBRegionSoldPerDay` is TSM's estimated regional average, not the player's personal sales rate. CraftSim Enhancer overrides take priority for items pushed by CSE Recon; TSM remains a fallback for other items. `DBMinBuyout` is TSM's most recently processed minimum and is not guaranteed to be live.

## Commands

- `/cse` or `/cse help` — show available commands.
- `/cse status` — show versions, module states, migration status, and compatibility warnings.
- `/cse debug` — toggle diagnostic output.
- `/cse scan` — open CSE Recon while the Auction House is open.
- `/cse vendor` — reopen Vendor Materials or refresh Vendor Buy at an open merchant.
- `/cse module <scan|tooltip|vendor|notice> <on|off>` — change a module state after the next reload.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.

## Updating and troubleshooting

CraftSim Enhancer stores its settings in `CraftSimEnhancerDB` and does not modify CraftSim files. Updating or replacing the `CraftSim` folder will not overwrite the Enhancer.

After updating World of Warcraft or CraftSim:

1. Run `/cse status`.
2. Reload once and confirm controls are not duplicated.
3. Run a small CSE Recon scan and push.
4. Test one vendor-material purchase before processing a large queue.

When reporting a problem in [GitHub Issues](https://github.com/crystaltech/CraftsimEnhancer/issues), include:

- The output of `/cse status`.
- The CraftSim Enhancer, CraftSim, and World of Warcraft versions.
- Any Lua error from BugSack/BugGrabber or `/console scriptErrors 1`.
- The exported Unpriced AH report when the problem involves scanning.
- Clear steps that reproduce the issue.

## License and project independence

CraftSim Enhancer is distributed under the [MIT License](LICENSE). Release ZIPs also include the license inside the addon folder.

CraftSim, Auctionator, TradeSkillMaster, and World of Warcraft are separate projects or products. Their names are used only to identify compatibility. No affiliation or endorsement is implied.
