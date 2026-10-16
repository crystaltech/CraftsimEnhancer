# CraftSim 27 compatibility smoke test

Run this checklist with CraftSim 27.0.0, CraftSim Enhancer 1.6.0, and Auctionator enabled.

Core compatibility passed in game on August 17, 2026: startup capability checks, Recon override refresh, break-even tooltips, manual shopping-list vendor separation, and confirmed vendor purchasing. The automatic queue path remains a useful regression check.

## Startup

1. Log in or run `/reload`.
2. Run `/cse status`.
3. Confirm CraftSim reports `27.0.0`.
4. Confirm `AuctionHouseScan`, `BreakEvenTooltip`, `VendorBuy`, and `VendorShoppingListNotice` all report `initialized`.
5. Confirm there is no CraftSim-version compatibility warning. The WoW-interface warning remains expected until the complete 12.1 checklist passes.

## Price overrides and refresh

1. Open a known profession recipe in CraftSim and note its current reagent and result prices.
2. Open the Auction House and run a small CSE Recon scan for that recipe.
3. Push the scan results into CraftSim.
4. Confirm CraftSim's visible recipe data refreshes immediately without changing recipes or reopening the profession window.
5. Confirm the pushed reagent and exact-rank result overrides appear in CraftSim's Pricing module.

## Break-even tooltip

1. Hover one ordinary crafted item with a saved CraftSim crafting cost.
2. Hover one ranked crafted gear item with a saved CraftSim crafting cost.
3. Confirm each supported tooltip shows the expected `CSE Break-even (5% AH)` line without Lua errors.

## Shopping list and Vendor Materials

1. Add a small recipe containing at least one vendor reagent to CraftSim's craft queue.
2. Use CraftSim 27's Shopping action to create its Auctionator shopping list.
3. Confirm CSE displays the vendor-material notice after CraftSim finishes creating the list.
4. Confirm vendor reagents were removed from the Auctionator list and appear in CSE's Vendor Materials window with the expected quantities.
5. Open the appropriate merchant and buy one planned vendor material.
6. Confirm the item is deducted only after it appears in the bags, and confirm the CraftSim/Auctionator quick-buy flow still works afterward.

## Automatic queue path

1. Run one CraftSim queue operation that automatically creates or refreshes its shopping list.
2. Confirm the same vendor separation occurs exactly once and no duplicate popup or Vendor Materials rows appear.

Capture the first Lua error and the output of `/cse status` if any step fails.
