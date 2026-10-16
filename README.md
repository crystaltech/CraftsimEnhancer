# CraftSim Enhancer

## Workspace layout

Run development commands from the repository root. The maintainer workspace also contains private tools, upstream references, caches, and a local installer; those are not distributed in the public repository or addon ZIP.

```text
CraftSimEnhancer/             Installable addon: TOC, Lua files, and license
Tests/                       Automated tests and validation notes
docs/                        Addon user documentation
tools/                       Data generators, overlays, and internal notes
References/                  Blizzard UI reference copies
legacy/CraftSim/              Preserved modified upstream source
legacy/CraftSim_stock/        Preserved stock upstream comparison
tmp/                         Cached downloads and generated candidates
Install_CraftSimEnhancer.command
zip/                         Release archives and backups
```

Install by copying only `CraftSimEnhancer` into WoW's `Interface/AddOns`, or use the local maintainer installer `Install_CraftSimEnhancer.command` if available. The installer locates the sibling addon folder automatically. User documentation is in [docs/ADDON_README.md](docs/ADDON_README.md).

Download the [1.7.0 addon ZIP](https://github.com/crystaltech/CraftsimEnhancer/releases/download/v1.7.0/CraftSimEnhancer-v1.7.0.zip). It contains only the installable addon and required license notices. Local archives are preserved under `zip/`. See the [release notes](docs/RELEASE_1_7_0.md).

To check the workspace:

```bash
for test in Tests/test_*.lua; do lua "$test" || exit 1; done
# Additional checks in the maintainer workspace (private tools/sources):
python3 -m unittest tools.test_generate_generated_recipes tools.test_import_profession_catalog
python3 tools/generate_generated_recipes.py --verify-only \
  --input-dir legacy/CraftSim/Data/GeneratedRecipes \
  --overlay tools/patches/12.1.5.json \
  --check-output CraftSimEnhancer/Data/GeneratedRecipes
```

[![Latest release](https://img.shields.io/github/v/release/crystaltech/CraftsimEnhancer)](https://github.com/crystaltech/CraftsimEnhancer/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

CraftSim Enhancer is a standalone World of Warcraft Retail companion addon for [CraftSim](https://www.curseforge.com/wow/addons/craftsim). It adds Auction House pricing intelligence and a safer vendor-material workflow without modifying or placing files inside CraftSim.

> CraftSim Enhancer is independently developed. It is not affiliated with, maintained by, endorsed by, or part of the CraftSim project. CraftSim remains a required dependency and is installed separately.

## Current compatibility

- Last completed in-game checklist: **120007 (12.0.7)**
- Current release: **1.7.0**, targeting **120100 and 120105 (12.1.0 and 12.1.5)**
- Recipe data refreshed October 15, 2026 from client build **12.1.5.70391**: **10,637 catalog records** from Classic through Midnight, including the verified **1,030-recipe / 347-decor** baseline. **2,426** imported records remain catalog-only until their scan data can be resolved.
- CraftSim compatibility adapters: **26.1.10, 27.0.0, and 27.0.3**
- CraftSim 27.0.0 core in-game checklist: **passed August 17, 2026**
- CraftSim 27.0.3: **automated integration checks passed; user reported successful in-game testing**
- CraftSim 27.0.5: **source review and automated integration checks passed September 17, 2026; in-game validation pending**. No Enhancer code changes required by these checks; see [compatibility results](Tests/CRAFTSIM_27_0_5.md).
- Latest official CraftSim release rechecked October 16, 2026: **27.0.7**. Its actual release modules pass automated integration checks, including automatic shopping-list creation enabled and disabled. See [12.1.5 readiness and in-game checklist](Tests/PATCH_12_1_5_READINESS.md).
- WoW **12.1.5.70077** UI-source review found no breaking changes in the APIs used by the addon. **12.1.5 and CraftSim 27.0.7 in-game validation remain pending**; tested-version markers retain their previous values.

The [October 16 recheck](Tests/CRAFTSIM_RECHECK_2026_10_16.md) found no newer published release. Three unreleased commits affect inventory/restock, bound-material queue limits, and the data-mining build marker; the CSE source integration harness passes against both 27.0.7 and the pinned development snapshot. Current in-game usage has a positive user report; the complete checklist markers remain unchanged.

Other versions may work when their required capabilities remain compatible. Run `/cse status` after updating World of Warcraft or CraftSim; the addon reports untested versions and disables only a feature whose required interface is unavailable.

The 12.1 live Auction House, merchant, item, tooltip, and profession APIs used by CraftSim Enhancer have been validated against the shipped UI source. Generated profession data and current TSM public item coverage have also been refreshed. CraftSim 27's Shopping module, event-driven price refresh, break-even tooltip, and Vendor Materials paths have passed their core in-game checks. `/cse status` retains the broader WoW-interface warning until the complete 12.1 checklist passes.

Recon's **Availability** menu offers All, Learned, Unlearned, and Unchecked browsing filters. Confirmed unlearned recipes are dimmed but remain selectable. Open your own professions each login to populate the per-character session cache; linked/guild/NPC views do not populate it. Browsing preserves selections. The separate **Scan learned recipes only** option excludes unlearned and unchecked sources, including individual overrides; it defaults off.

The 1.7 catalog needs no LibProfessionDB installation. Recon groups recipes by profession, expansion, and category; its expansion dropdown changes the view while preserving selections. Large preparation jobs yield between batches, and scrolling reuses visible rows. Run `/cse dev perf` for a timing/memory snapshot. See [catalog validation and performance limits](Tests/CATALOG_1_7.md).

See the [12.1.5 decor coverage and validation notes](Tests/PATCH_12_1_5_DECOR.md).

## What it adds

### CSE Recon

- A full Auction House tab with profession, recipe-category, and individual-item selection.
- Generated Midnight recipe and reagent scan targets, plus crafted decor from older expansions.
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

Unpriced reports distinguish **Rank not listed** (other ranks have listings), **Variant not listed** (other item levels have listings), **No auctions** (empty buyout search), **Variant not recognized**, and **Scan problem**. Missing ranks remain eligible for saved-cost break-even estimates when pushing; unresolved variants and query failures do not.

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
- `/cse dev <dump|catalog|perf|status|cancel|clear>` — capture live profession data and diagnostics; see [export instructions](docs/DEV_EXPORT.md).
- `/cse scan` — open CSE Recon while the Auction House is open.
- `/cse_scanqty <quantity>` — set how many reagent units (5–1000, default 20) are sampled for scan pricing. `/cse scanqty <quantity>` is also accepted.
- `/cse vendor` — reopen Vendor Materials or refresh Vendor Buy at an open merchant.
- `/cse module <scan|tooltip|vendor|notice> <on|off>` — change a module state after the next reload.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.

Follow the [12.1.5 in-game checklist](Tests/MANUAL_12_1_5.md) when validating this release.

## Updating and troubleshooting

CraftSim Enhancer stores its settings in `CraftSimEnhancerDB` and does not modify CraftSim files. Updating or replacing the `CraftSim` folder will not overwrite the Enhancer.

For the 12.1.5 decor cost reductions, rerun CraftSim Recipe Scan with **Update Last Crafting Cost DB** enabled and recreate queued shopping lists. Existing saved break-even costs and vendor plans retain their old values until refreshed.

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

## Thanks and inspiration

Thank you to the creators, maintainers, and contributors whose addons inspired CraftSim Enhancer and helped make its features possible:

- **[CraftSim](https://www.curseforge.com/wow/addons/craftsim)** — genju and the CraftSim contributors, for the crafting simulation and profession tools that CSE builds on.
- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** — the Auctionator team and contributors, for accessible Auction House tools and shopping-list integration.
- **[TradeSkillMaster](https://www.tradeskillmaster.com/)** — the TSM team and contributors, for their pricing tools and crafting-economy workflows.
- **[LibProfessionDB](https://www.curseforge.com/wow/addons/libprofessiondb)** — Pimptasty and contributors, for the offline profession data that helped expand CSE's recipe catalog.

We appreciate the time, care, and knowledge you share with the WoW addon community.

## License and project independence

CraftSim Enhancer is distributed under the [MIT License](LICENSE). Release ZIPs also include the license inside the addon folder.

CraftSim, Auctionator, TradeSkillMaster, and World of Warcraft are separate projects or products. These credits acknowledge their work; no affiliation or endorsement is implied.
