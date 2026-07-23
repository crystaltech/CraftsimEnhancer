# CraftSim Enhancer

CraftSim Enhancer is a standalone companion addon for [CraftSim](https://www.curseforge.com/wow/addons/craftsim). It adds an Auction House pricing scanner, merchant reagent purchasing for the CraftSim queue, and vendor-reagent shopping-list notices without modifying CraftSim itself.

The addon is currently developed for World of Warcraft Retail interface 120007 and CraftSim 26.1.10.

## Features

- Scan generated Midnight crafts and reagents at the Auction House.
- Filter scans by profession, category, and configurable presets.
- Calculate input prices from fill quantities with outlier trimming.
- Push reagent and recipe-result prices into CraftSim's price overrides. Missing outputs use CraftSim's saved average crafting cost divided by 95% for an AH-fee break-even estimate; lower ranks are capped below real higher-rank listings.
- Buy outstanding vendor-sold reagents directly from an open merchant.
- Deduct purchased quantities from the corresponding Auctionator shopping list when Auctionator is installed.
- Warn when a CraftSim shopping list includes vendor-sold reagents.
- Preserve settings independently from CraftSim updates.

## Requirements

- World of Warcraft Retail
- CraftSim 26.1.10 or a compatible later release
- Auctionator is optional and enables shopping-list integration
- TradeSkillMaster is optional and can provide fallback pricing

For missing-output estimates, enable CraftSim's **Update Last Crafting Cost DB** option in Recipe Scan or Craft Lists and run it once. If CraftSim has no saved cost for an output, CraftSim Enhancer skips that override instead of inventing a price.

## Recommended TSM price strings

When TradeSkillMaster is CraftSim's selected price source, open **CraftSim Options → TSM** and consider replacing CraftSim's default `first(DBRecent, DBMinBuyout)` expressions with these conservative fallbacks:

**Crafting Reagents Price Expression**

```text
max(first(dbminbuyout, dbrecent, dbmarket, dbregionmarketavg), 80% first(dbrecent, dbmarket, dbregionmarketavg))
```

This starts with the latest minimum buyout and prevents a very small or abnormal listing from reducing material costs below 80% of a recent or longer-term market value.

**Crafted Items Price Expression**

```text
min(first(dbminbuyout, dbrecent, dbmarket, dbregionmarketavg), 120% first(dbrecent, dbmarket, dbregionmarketavg))
```

This follows the lowest available listing but caps an unusually high or thin listing at 120% of a recent or longer-term market value, reducing false profit spikes.

**Crafted Items Restock Qty Expression — optional**

```text
ifgte(dbregionsoldperday, 0.1, min(20, max(1, roundup(3 * dbregionsoldperday))), 0)
```

This targets roughly three days of regional sales, skips items averaging fewer than 0.1 sales per day, and limits the target to 20. It returns a target inventory quantity, not a price or the number still needing to be crafted. CraftSim subtracts owned inventory separately, so do not subtract `numinventory` in this expression.

CraftSim also has a separate **TSM sale-rate threshold** in the gear menu beside **Send to Craft Queue**. That filter runs before the restock expression. Newly released items often have no TSM regional sales data yet, so a threshold such as `0.1` can silently reject every scan result and make the button appear to do nothing. Set that threshold to `0` when you want new items to remain eligible. Temporarily disabling **Use TSM Restock Expression** makes CraftSim use its **Default Queue Amount** instead and is a useful troubleshooting check.

For slower gear, a one-week target capped at 5 is more conservative:

```text
min(5, max(1, roundup(7 * dbregionsoldperday)))
```

For high-volume consumables, a two-day target between 5 and 100 may be more useful:

```text
min(100, max(5, roundup(2 * dbregionsoldperday)))
```

`DBRegionSoldPerDay` is TSM's estimated average quantity sold per Auction House per day across the region; it is not the player's personal sales rate. Enable CraftSim's TSM restock-expression option wherever the recipe scan or Craft List should use it. See TSM's [value-source definitions](https://support.tradeskillmaster.com/en_US/custom-strings/which-value-sources-can-i-use-and-what-do-they-mean).

CraftSim Enhancer's scanned overrides take priority over these expressions. TSM therefore acts as a fallback for unscanned items, failed queries, and items outside the generated dataset. CraftSim also handles `VendorBuy` before evaluating either expression. `DBMinBuyout` is TSM's most recently processed minimum rather than a guaranteed real-time value, so run the Enhancer scan when current AH pricing matters. See TSM's documentation for [price-source definitions](https://support.tradeskillmaster.com/custom-strings/which-price-sources-can-i-use-and-what-do-they-mean) and [`first`, `min`, and `max` behavior](https://support.tradeskillmaster.com/en_US/custom-strings/which-functions-can-i-use-and-what-do-they-mean).

## Installation

1. Download or clone this repository.
2. Copy the `CraftSimEnhancer` folder into `_retail_/Interface/AddOns/`.
3. Confirm that `CraftSim` and `CraftSimEnhancer` are sibling folders.
4. Enable both addons and log in or reload the interface.
5. Run `/cse status` to verify compatibility.

The final layout should be:

```text
Interface/AddOns/CraftSim/
Interface/AddOns/CraftSimEnhancer/
```

## Commands

- `/cse` or `/cse help` — show available commands.
- `/cse status` — show versions, module states, migration status, and compatibility failures.
- `/cse debug` — toggle debug output.
- `/cse scan` — open the scanner while the Auction House is open.
- `/cse vendor` — refresh Vendor Buy while a merchant is open.
- `/cse module <scan|vendor|notice> <on|off>` — enable or disable a module after the next reload.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.

## Updating CraftSim

CraftSim Enhancer does not place files inside CraftSim. You can update or replace the `CraftSim` folder normally, then run `/cse status` and repeat the scanner and vendor smoke tests. If CraftSim changes one of the internal interfaces used by the addon, only the affected Enhancer module is disabled and the compatibility failure is reported.

## License

CraftSim Enhancer is available under the [MIT License](LICENSE).
