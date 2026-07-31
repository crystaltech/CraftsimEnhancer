# Patch 12.1 Readiness

Review date: July 31, 2026

Target patch window: August 11, 2026

## Current evidence

- The [Wago Tools build feed](https://wago.tools/api/builds) listed test build `12.1.0.68914`, dated July 24, 2026, when this review was performed.
- The checked-in PTR UI source snapshot appears aligned with the June 30 test build, so it is useful for early compatibility review but is not the final 12.1 client surface.
- Blizzard's generated Auction House API documentation is identical between the checked-in live and PTR snapshots for every API validated by CSE Recon.
- The checked-in live and PTR merchant API documentation is identical.
- `C_Item.GetItemCount`, used to confirm vendor purchases, has the same arguments and return type in both snapshots.
- The Auction House frame and tab implementation used by CSE Recon is unchanged in the checked-in snapshots.
- PTR adds a bootstrap loader for the Auction House UI and persistent browse filters. CSE waits for `AUCTION_HOUSE_SHOW` before creating its tab, and its direct item queries do not read or mutate browse-filter state.

## Patch-day procedure

1. Update the PTR/live UI-source reference to the newest available 12.1 build and repeat the API comparison.
2. Install the CraftSim build intended for 12.1 without modifying its folder.
3. Log in with script errors enabled and run `/cse status`.
4. Confirm the reported WoW interface and CraftSim versions. CSE warns without disabling features when either version differs from its tested values.
5. Update `## Interface`, `WoW.testedInterface`, and `Compat.testedVersion` only after the tested client reports the final values.
6. Open the Auction House and verify CSE Recon tab creation, compact-tab sizing, profession configuration, one small scan, one full scan, missing-report export, and override push.
7. Create a mixed CraftSim shopping list and confirm atomic vendor separation.
8. Buy vendor materials and confirm the plan changes only after matching items appear in bags.
9. Run the data generator against current 12.1 recipe/item sources, review additions and removals, and repeat profession scans for newly added items.
10. Build the release archive only after the automated and in-game checklists pass.

## Do not pre-bump the interface

The development TOC remains on the currently tested live interface until 12.1 is available for direct testing. Setting a future interface value early would make the live test build appear incompatible and would claim validation that has not happened yet.
