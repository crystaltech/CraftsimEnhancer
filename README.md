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
