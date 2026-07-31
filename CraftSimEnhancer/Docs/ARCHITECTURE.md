# CraftSim Enhancer Architecture

## Feature modules

`Modules/BreakEvenTooltip.lua` is an independent registered module. It builds an index of auction-sellable generated outputs and adds an exact-rank break-even line when CraftSim has saved a crafting cost for the hovered item.

## Auction House scanner

The scanner is one registered module assembled from focused implementation files. `Modules/AuctionHouseScan.lua` creates the shared `Scanner` table, owns scanner state and preset definitions, exposes a small internal `Scanner.Shared` dependency table, and registers the module. Files under `Modules/AuctionHouseScan/` add methods to that same table before addon initialization runs.

Load order is defined in `CraftSimEnhancer.toc`:

1. `AuctionHouseScan.lua` — state, preset definitions, item metadata helpers, selection logic, diagnostics, and shared constants.
2. `AuctionHouseScan/UI.lua` — Auction House tab integration, primary frame, missing-result display, and report export.
3. `AuctionHouseScan/ConfigurationUI.lua` — recipe tree, item details, preset controls, and configuration rows.
4. `AuctionHouseScan/Targets.lua` — converts generated recipes and reagents into deduplicated scan targets.
5. `AuctionHouseScan/Query.lua` — throttled Auction House query state machine, retries, result-cache reads, and timeout handling.
6. `AuctionHouseScan/Pricing.lua` — fill/outlier pricing, lowest-buyout pricing, missing-output estimates, and CraftSim override export.
7. `AuctionHouseScan/Lifecycle.lua` — Auction House event handlers, compatibility validation, slash-command entry point, and initialization.

### Invariants

- Only `AuctionHouseScan.lua` creates and registers the `Scanner` table.
- Implementation files add methods but do not initialize frames, events, or scans while loading.
- Cross-file constants and helper functions come from `Scanner.Shared`; implementation files do not duplicate them.
- Query timers verify tokens or the pending target before acting, preventing callbacks from an earlier request or cancelled scan from changing current state.
- Auction House results are converted into scanner-owned rows before pricing. Pricing code does not call Blizzard search APIs directly.
- CraftSim internal access remains behind `Compat/CraftSim.lua`.

## Vendor workflow

`VendorBuy.lua` owns vendor-plan creation, Auctionator list separation, merchant purchasing, bag-confirmed fulfillment, and the Vendor Materials window. `VendorShoppingListNotice.lua` only hooks CraftSim shopping-list creation and presents the result to the user.

Auctionator separation is prevalidated before the list is replaced. The replacement is read back for verification, and the original list is restored if replacement or verification fails. Merchant purchase requests remain pending until an increase in the matching bag item count confirms fulfillment.

## Compatibility update workflow

For a new World of Warcraft or CraftSim release:

1. Compare the live/PTR API documentation for every function validated in `AuctionHouseScan/Lifecycle.lua` and `Compat/WoW.lua`.
2. Update compatibility wrappers before changing feature code.
3. Run `lua CraftSimEnhancer/Tests/test_auction_house_scan.lua`.
4. Run `lua CraftSimEnhancer/Tests/test_vendor_buy.lua`.
5. Run the generated-data tests and Lua syntax checks documented in `Docs/TESTING.md`.
6. Complete the in-game checklist with script errors enabled before updating the tested interface or CraftSim version.
