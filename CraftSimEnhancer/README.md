# CraftSim Enhancer

CraftSim Enhancer is a standalone World of Warcraft Retail companion addon for CraftSim. It adds the **CSE Recon** Auction House scanner, exact-rank break-even tooltips, and a safer Vendor Materials workflow without modifying CraftSim.

CraftSim Enhancer is independently developed. It is not affiliated with, maintained by, endorsed by, or part of the CraftSim project. CraftSim is a required dependency and must be installed separately.

## Install

Place this complete folder beside CraftSim:

```text
Interface/AddOns/CraftSim/
Interface/AddOns/CraftSimEnhancer/
```

Enable both addons, log in, and run `/cse status`. Do not place this folder inside `CraftSim`.

This release was tested with World of Warcraft Retail interface 120007 (12.0.7) and CraftSim 26.1.10. Compatibility warnings for different versions appear in `/cse status`.

## First use

1. Enable **Update Last Crafting Cost DB** in CraftSim's Recipe Scan or Craft Lists options and run a CraftSim scan once.
2. Open the Auction House and select **CSE Recon**.
3. Choose **Products + reagents**, **Crafted products**, or **Required reagents**, then use the persistent **Recipes** or **Individual items** tab. A recipe-tree change resets individual overrides within that branch, while shared items remain selected when another selected recipe needs them. The summary labels recipe counts and generated price-target counts separately.
4. Click **Scan Now**, review **Unpriced Items**, use **Skip future** for unwanted targets, and click **Push Overrides**.
5. Create a CraftSim Auctionator shopping list. Vendor items are separated into the **Vendor Materials** window.
6. Buy Auction House materials first, then visit the listed vendors and use **Buy Vendor Mats**.

## Key behavior

- Reagents use fill-quantity pricing with high-price outlier trimming.
- Crafted outputs use the lowest matching buyout for the exact rank.
- Unlisted products use `floor(saved crafting cost / 0.95)` when CraftSim has a saved cost.
- Unlisted lower ranks are capped below real higher-rank listings.
- `CSE Break-even (5% AH)` tooltips show the uncapped exact-rank break-even value.
- Vendor-plan quantities decrease only after purchased items appear in the player's bags.
- CraftSim Enhancer settings are independent from CraftSim updates.

## Commands

- `/cse help` — list commands.
- `/cse status` — show versions, module states, migration status, and compatibility warnings.
- `/cse debug` — toggle diagnostic output.
- `/cse scan` — open CSE Recon at the Auction House.
- `/cse vendor` — reopen or refresh Vendor Materials.
- `/cse module <scan|tooltip|vendor|notice> <on|off>` — change a module state after `/reload`.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.

## Help and source

Documentation, releases, and issue reporting are available at:

https://github.com/crystaltech/CraftsimEnhancer

For scanner problems, include the exported Unpriced AH report. For other problems, include `/cse status`, installed versions, reproduction steps, and any Lua error.

## License

CraftSim Enhancer is distributed under the MIT License. See [LICENSE](LICENSE) in this folder.

CraftSim, Auctionator, TradeSkillMaster, and World of Warcraft are separate projects or products. Their names are used only to identify compatibility. No affiliation or endorsement is implied.
