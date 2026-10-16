# CraftSim Enhancer

CraftSim Enhancer is a standalone World of Warcraft Retail companion addon for CraftSim. It adds the **CSE Recon** Auction House scanner, exact-rank break-even tooltips, and a safer Vendor Materials workflow without modifying CraftSim.

CraftSim Enhancer is independently developed. It is not affiliated with, maintained by, endorsed by, or part of the CraftSim project. CraftSim is a required dependency and must be installed separately.

## Install

Extract the release ZIP and place its CraftSimEnhancer folder beside CraftSim:

```text
Interface/AddOns/CraftSim/
Interface/AddOns/CraftSimEnhancer/
```

Enable both addons, log in, and run `/cse status`. Do not place this folder inside `CraftSim`.

Release 1.7.0 targets World of Warcraft Retail interfaces 120100 and 120105 (12.1.0 and 12.1.5). The 12.1.5.70077 UI-source review found no breaking changes in the APIs used by the addon. Automated integration checks pass against CraftSim 27.0.7, still the latest official release when rechecked October 16, 2026. See [readiness results and the in-game checklist](../Tests/PATCH_12_1_5_READINESS.md).

Current in-game usage has a positive user report; the full 12.1.5 / CraftSim 27.0.7 validation checklist remains incomplete. `/cse status` retains the last in-game tested markers and reports these versions as untested. The combined catalog covers 10,637 records from Classic through Midnight, including the verified 1,030-recipe / 347-decor baseline. LibProfessionDB identifiers and names are imported offline; no library installation is required. Current client tables resolve scan relationships; 2,426 unresolved entries are shown as disabled catalog-only recipes. Recon groups recipes by profession, expansion, and category. The expansion dropdown changes the view and preserves selections from other expansions; scans include selected recipes across views. Bulk select/deselect affects the visible view. See [catalog validation and performance limits](../Tests/CATALOG_1_7.md). Crafting quantities come from the game through CraftSim; rerun CraftSim Recipe Scan with **Update Last Crafting Cost DB** enabled and recreate shopping lists after the patch to refresh saved costs and quantities. CraftSim 27.0.7's own TOC currently lists interfaces through 120100, so testing may require enabling **Load out of date AddOns** for CraftSim.

CraftSim 27.0.3 source and automated integration checks passed on September 11, 2026. This release fixes its deferred Auctionator shopping-list publication. The user subsequently reported successful in-game testing; see [compatibility results](../Tests/CRAFTSIM_27_0_3.md).

See the [12.1.5 decor coverage and validation notes](../Tests/PATCH_12_1_5_DECOR.md).

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
- `/cse dev <dump|catalog|perf|status|cancel|clear>` — export live profession data and diagnostics; see [instructions](DEV_EXPORT.md).
- `/cse scan` — open CSE Recon at the Auction House.
- `/cse_scanqty <quantity>` — set how many reagent units (5–1000, default 20) are sampled for scan pricing. `/cse scanqty <quantity>` is also accepted.
- `/cse vendor` — reopen or refresh Vendor Materials.
- `/cse module <scan|tooltip|vendor|notice> <on|off>` — change a module state after `/reload`.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.

## Help and source

Documentation, releases, and issue reporting are available at:

https://github.com/crystaltech/CraftsimEnhancer

For scanner problems, include the exported Unpriced AH report. For other problems, include `/cse status`, installed versions, reproduction steps, and any Lua error.

## License

CraftSim Enhancer is distributed under the MIT License. See [LICENSE](../CraftSimEnhancer/LICENSE) in the addon folder.

CraftSim, Auctionator, TradeSkillMaster, and World of Warcraft are separate projects or products. Their names are used only to identify compatibility. No affiliation or endorsement is implied.

## Recipe availability

Use the **Availability** menu in Configure Scan to browse All, Learned on this
character, Unlearned, or Unchecked recipes. It filters both browsing views and
visible bulk actions while preserving hidden selections. Unlearned recipes are
dimmed, with availability labels and tooltips, and remain selectable for market
research. Recipes with unresolved scan data stay disabled regardless of learning.

Open your own professions each login to populate the session cache, switching
expansion views where necessary. Missing or unavailable recipe information stays
Unchecked. Linked, guild and NPC profession views never populate this cache.
The addon checks only IDs exposed in your loaded profession and does not infer
unlearned status from absence. Named transforms without recipe IDs stay Unchecked.

The separate **Scan learned recipes only** toggle in the same menu defaults off.
When enabled, an asterisk appears on the Availability button; scans include only
confirmed learned recipe sources, across expansion views. Unlearned and unchecked
sources cannot contribute targets through individual overrides either. Shared
materials can still scan if a learned source contributes them. Turning the option
off restores the full selected set without reselecting recipes.

Observations refresh when your own profession opens or changes and when learning
recipes. Routine list updates reuse confirmed entries and retry unchecked IDs.
Refreshes are coalesced and batched; browsing/scrolling uses cached state without
profession API queries. Forgetting a profession invalidates its observations.
`/cse dev perf` includes availability counts and refresh timing.

Unpriced reports distinguish absent ranks/variants from empty searches. **Rank not listed** means other ranks have buyout listings but the requested rank does not. It can still receive a saved-cost break-even estimate on Push Overrides; unknown rank classification and scan errors remain separate.

See the [October 16 CraftSim recheck](../Tests/CRAFTSIM_RECHECK_2026_10_16.md) for the published-release status, unreleased changes, source integration results and current in-game report.
