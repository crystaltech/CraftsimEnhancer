# In-game testing checklist

Enable `/console scriptErrors 1` and BugSack/BugGrabber if installed.

Before in-game testing, run these checks from the repository root:

- `lua CraftSimEnhancer/Tests/test_break_even_tooltip.lua`
- `lua CraftSimEnhancer/Tests/test_auction_house_scan.lua`
- `lua CraftSimEnhancer/Tests/test_vendor_buy.lua`

## Installation and startup

- Install stock CraftSim and `CraftSimEnhancer` as sibling addon folders.
- First login with both enabled: verify one Enhancer load message and no Lua error.
- Run `/cse status`; confirm the displayed version matches the TOC, CraftSim 26.1.10 (or the installed version), current interface, all enabled modules initialized, migration result, and no unexpected compatibility warnings.
- On a new WoW or CraftSim version, verify the non-blocking untested-version warning appears and follow `Docs/PATCH_12_1_READINESS.md` before updating the tested version markers.
- Run `/reload`; verify controls and hooks are not duplicated.
- Disable CraftSim while leaving CraftSim Enhancer selected. Because `## RequiredDeps: CraftSim` is intentional, WoW should refuse to load the Enhancer; `/cse` will not be registered. Re-enable CraftSim.
- Test a fresh install with no `CraftSimDB.auctionHouseScanDB`; status should say no legacy settings were found.
- Test once with legacy scanner settings; verify fill quantity, profession choices, target exclusions, and config profession were copied. Reload and confirm migration does not run again.

## Professions and CraftSim lifecycle

- Open CraftSim/Professions for the first time after login.
- Open every affected profession, switch professions, and switch recipes.
- Test characters with relevant professions, without them, and with different profession pairs.
- Switch characters and verify profession selections are stored per crafter.
- Open and close CraftSim windows repeatedly.
- Exercise CraftSim frames that are created lazily; no enhancer module should assume a numeric child index.

## Auction House Scanner

- Open the Auction House and verify one `CSE Recon` launcher/tab appears.
- With Auctionator's **Use small tabs** option enabled, verify `CSE Recon` uses the same compact tab width after opening or reopening the Auction House.
- Open/close the scanner, configuration panel, and missing-results panel repeatedly.
- Select/deselect professions and verify defaults reflect learned professions on first use.
- Apply profession and category presets, then override individual targets.
- Run a scan with inputs and outputs. Confirm progress, throttling waits, results, missing rows, cancellation, and retry behavior.
- Confirm reagent inputs use fill-quantity/outlier pricing and outputs use lowest buyout.
- Confirm vendor-priced reagents appear without an AH query where metadata supplies a fixed price.
- Enable CraftSim's **Update Last Crafting Cost DB** option and run Recipe Scan once to seed average costs.
- Push overrides and verify CraftSim pricing refreshes.
- Confirm missing outputs are labeled as estimates and use `floor(average cost / 0.95)`, not 1 copper.
- Confirm a missing lower-rank estimate is capped to one copper below the cheapest real higher-rank result.
- Confirm an output without a saved CraftSim cost is skipped and any legacy 1-copper Enhancer override is removed.
- Hover a supported crafted output with a saved CraftSim cost. Confirm the tooltip shows `CSE Break-even (5% AH)` for the exact item rank and omits the line when the cost is unavailable.
- Close the Auction House during a scan and confirm clean cancellation.
- Enter/leave combat before opening the Auction House and verify no blocked-action or taint error.

## Vendor Buy and shopping-list notice

- Build a CraftSim queue with normal, optional, required-selectable, self-crafted, order-provided, soulbound, and vendor-sold reagents.
- Create the Auctionator CraftSim list; verify vendor reagents are immediately removed while normal AH reagents remain.
- Verify the split is all-or-nothing: the automated test confirms an unmatched vendor entry leaves the original Auctionator list unchanged.
- Confirm the reminder appears and the Vendor Materials window lists each removed item, remaining quantity, and estimated cost.
- Move, resize, collapse, close, and reopen the window with `/cse vendor`; reload and verify its position, expanded size, state, and unfinished plan persist.
- Visit a merchant that sells none, some, and all outstanding vendor reagents.
- Verify the button count, enabled state, tooltip, estimated gold cost, limited stock, and insufficient-gold behavior.
- Click `Buy Vendor Mats` and confirm the correct quantities are bought from that merchant only.
- Immediately after clicking, verify the button reads `Confirming Purchase...` and cannot be clicked again.
- Confirm the plan decreases only after the purchased items appear in bags. With insufficient bag space or a partial purchase, verify the unreceived quantity remains planned.
- Verify purchased rows disappear from Vendor Materials, items sold elsewhere remain, totals update, and the window automatically closes after the final purchase.
- With Auctionator's automatic list search enabled, create the list while its Shopping tab is visible and confirm removed vendor items do not remain in the active results.
- Verify extended-cost and unusable merchant rows are not auto-purchased.
- Open/close merchants repeatedly, switch vendors, and check bag updates refresh the button without duplicates.
- Enter/leave combat with a merchant open and confirm no protected-action or taint error.

## Commands and settings

- Run `/cse`, `/cse help`, `/cse status`, and `/cse debug` twice; debug starts disabled and toggles cleanly without chat flooding.
- Run `/cse scan` with and without the Auction House open.
- Run `/cse vendor` with and without a merchant open.
- Use `/cse module scan off`, `/cse module vendor off`, and `/cse module notice off` one at a time, reload, and verify only that module is disabled. Re-enable each and reload.
- Run `/cse reset`; verify it only prints the confirmation instruction.
- Run `/cse reset confirm`, reload, and verify Enhancer defaults return while CraftSim settings and price overrides remain untouched.

## Update resilience

- Update or replace only `Interface/AddOns/CraftSim/` through CurseForge.
- Confirm `Interface/AddOns/CraftSimEnhancer/` remains present and unchanged.
- Run `/cse status` and the scanner/vendor smoke tests.
- If a module is disabled, inspect `Compat/CraftSim.lua` against the updated CraftSim implementations named in the status/analysis report before changing the feature module.
