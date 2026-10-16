# CraftSim Enhancer 1.7.0

CSE Recon now covers crafting recipes from Classic through Midnight, with expansion
and recipe-availability filters, batched catalog preparation, and clearer reports
for missing auction ranks. CraftSim remains a separate required addon; no
LibProfessionDB installation is needed.

## Changes

- Expand the catalog to 10,637 records across nine crafting professions, including
  347 verified decor recipes and the 12.1.5 decor additions. Keep 2,426 unresolved
  imports visible as disabled catalog-only entries.
- Browse Profession → Expansion → Category → Recipe. Expansion and availability
  view filters preserve saved selections and shared-material ownership.
- Add All, Learned, Unlearned and Unchecked availability views. Dim confirmed
  unlearned recipes while keeping them selectable for market research.
- Add an independent **Scan learned recipes only** option, off by default.
  Open your own professions each login to populate the availability cache.
- Batch large catalog, tree, selection, scan-preparation and export jobs. Reuse
  visible UI rows and cache prepared views; avoid AH lookups while browsing.
- Add `/cse dev dump`, `/cse dev catalog`, and `/cse dev perf` for opt-in profession
  diagnostics, catalog captures and timing/memory snapshots. Exports use WoW
  SavedVariables after reload or logout.
- Distinguish **Rank not listed** and **Variant not listed** from empty searches,
  unresolved variants and query failures. Keep exact-rank pricing and existing
  saved-cost break-even estimates.
- Keep development tests and documentation outside the installable addon, and
  include the required third-party data attribution and MIT license.

## Install and update

Extract `CraftSimEnhancer-v1.7.0-addon-only.zip` into `Interface/AddOns` so that
`CraftSimEnhancer` sits beside `CraftSim`. Replace the previous Enhancer folder
and reload or restart WoW. Settings and selections are retained.

After the 12.1.5 crafting quantity changes, rerun CraftSim Recipe Scan with
**Update Last Crafting Cost DB** enabled and recreate shopping lists. Current
quantities come from the game through CraftSim; saved costs and old plans need
refreshing.

## Compatibility and validation

Targets Retail interfaces 120100 and 120105. Automated integration passes with
CraftSim 27.0.7, the latest published release checked October 16, 2026, and with
its pinned unreleased development snapshot. Lua regression tests, syntax checks,
data reproduction checks and 11 Python generator/importer tests pass.

The user reports current in-game use is working. The full manual validation matrix
is not complete, so existing tested-version warnings remain. Batch budgets target
about 2 ms, with occasional longer GC/work slices; these are not FPS guarantees.

LibProfessionDB-derived static identifiers/names are MIT licensed, with required
attribution bundled in the addon. Its runtime code, Ace and LibStub are not shipped
as dependencies of this data import.
