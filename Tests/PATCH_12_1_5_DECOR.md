# 12.1.5 decor data update

Candidate: **1.6.2-rc2**. Data review: **October 15, 2026**.

Recon now contains **1,030 recipes and 1,937 item metadata rows**. The update adds **267 recipes** to the previous 763-recipe list: 265 older-expansion decor recipes and two Midnight seasonal decor recipes. All **347 House Decor recipes** in the supported professions' client categories are represented, including the 80 already present. Existing non-decor recipes remain unchanged.

## Sources and generation

The source is matching [Wago.Tools client exports for build 12.1.5.70391](https://wago.tools/db2/SkillLineAbility?build=12.1.5.70391), retrieved October 15. Recipe IDs are profession crafting spells, not the similarly named spells that collect decor into the House Chest.

- `SkillLineAbility` and `TradeSkillCategory` identify each profession's House Decor recipes and expansion category.
- `SpellEffect` links crafting spells to `CraftingData`, which supplies the actual crafted item.
- `SpellReagents` supplies fixed materials. `ModifiedCraftingSpellSlot`, `ModifiedCraftingReagentSlot`, `MCRSlotXMCRCategory`, `ModifiedCraftingReagentItem`, `Item`, and `CraftingQuality` resolve required ranked materials. Optional and finishing slots are excluded.
- `ItemSparse` supplies item names, binding flags, and base prices for an explicit list of ordinary vendor supplies. A nonzero buy price alone does not classify an item as vendor-sold. Bulk vendor prices are divided by `VendorStackCount`; live merchant prices still govern actual purchases.

Developer inputs and scripts are workspace-only under `tmp/patch-12.1.5/` and `tools/`. `tools/patches/12.1.5.json` records the build, source table SHA-256 values, and the overlay. The addon ships the generated Lua data and needs no network downloads to load it.

```bash
python3 -m tools.generate_decor_overlay \
  --source-dir tmp/patch-12.1.5 \
  --baseline legacy/CraftSim/Data/GeneratedRecipes \
  --build 12.1.5.70391 --output tools/patches/12.1.5.json
python3 tools/generate_generated_recipes.py --verify-only \
  --input-dir legacy/CraftSim/Data/GeneratedRecipes \
  --overlay tools/patches/12.1.5.json \
  --check-output CraftSimEnhancer/Data/GeneratedRecipes
```

Category generation uses the same matching `SkillLineAbility` and `TradeSkillCategory` exports with `--categories-only` and `--wago-build 12.1.5.70391`. It allows older-expansion House Decor categories only within the matching profession; other older-expansion recipe categories remain outside this dataset's scope. All 1,030 recipes resolve to 190 categories.

## Runtime behavior

Profession headings spanning multiple expansions say **All Expansions**, and category rows include the expansion's profession heading. Existing category and recipe selection keys are retained.

Bound lumber never becomes an Auction House query. Five crafted decor outputs are pickup-bound in this client snapshot; their auctionable materials remain available under Products + reagents and Required reagents. Product-only scans omit those bound outputs. Reagent ranks use numeric Lua keys, including when the source overlay is JSON.

Crafting quantities are supplied by CraftSim's live recipe schematics, rather than Recon's scan-target tables. After installing, rerun CraftSim Recipe Scan with **Update Last Crafting Cost DB** enabled, recreate shopping lists, and replace any outstanding vendor plan built before the patch. This refreshes saved break-even costs and planned quantities after the [official pre-Midnight cost reductions](https://us.forums.blizzard.com/en/wow/t/crafted-decor-cost-reduction-in-1215/2376676).

## Validation and remaining checks

Automated validation covers complete generated-data reproducibility; numeric quality keys from JSON; acceptance of older decor categories and rejection of unrelated older categories; coverage of every recipe category; new Legion outputs; Dragonflight material ranks; vendor-vial exclusion; bound lumber/output exclusion; materials for bound Shadowlands decor; and mixed-expansion tree labels. Passed: all six standalone Lua suites, all addon Lua syntax checks, seven generator tests, generated-data reproducibility, and integration against the official CraftSim 27.0.7 release (SHA-256 `c2b93d7b14e59bac9cd009ccb52a233ec400fdbbd74383f10f64c7e591205d6e`). WoW and Auctionator services are mocked in the automated suites.

In-game validation remains pending. Tested-version markers have not advanced. Follow the [12.1.5 readiness checklist](PATCH_12_1_5_READINESS.md), then additionally verify one older-expansion decor recipe, one ranked Dragonflight material, and a vendor shopping list rebuilt with the reduced live quantities. Compare the ingredients against the live profession window and confirm the displayed category matches its expansion.
