# 1.7.0 catalog and performance validation

This release adds an offline cross-expansion catalog. In-game validation remains
pending; no tested-version marker was advanced. Follow [the manual checklist](MANUAL_12_1_5.md).

## Coverage and provenance

- Verified CSE 12.1.5 baseline: 1,030 records, including 347 decor recipes.
- Added records: 9,607; combined: 10,637, with 10,621 numeric recipe IDs and 16 named transforms.
- Added item metadata: 7,930; combined: 9,867 rows.
- Nine crafting professions, Classic through Midnight. This expands CSE's catalog;
  it does not change CraftSim's support for simulating older profession mechanics.
- 2,426 imports are catalog-only: 1,733 lack a resolved live crafted item,
  686 require unresolved output bonus/quality variants, and 7 lack an unambiguous
  live profession category. They are visible but disabled for scanning.
- 7,181 imports have resolved current outputs and required reagents. Bound outputs
  and vendor materials still obey normal AH exclusions; this count is not a count
  of auctionable products. Required material quality ranks are retained.

IDs/names come from LibProfessionDB / ProfessionDB v1.9.1's Retail snapshot
12.1.0.69933. Scan relationships/categories/metadata are resolved from matching
Wago.Tools client 12.1.5.70391 tables. Existing verified CSE data takes priority.
See the shipped [attribution](../CraftSimEnhancer/THIRD_PARTY_NOTICES.md) and
[MIT license](../CraftSimEnhancer/ThirdPartyLicenses/LibProfessionDB-LICENSE.txt).
The importer parses data tables without executing upstream code and writes a
manifest with library and CSV SHA-256 hashes. No library installation, runtime
library code, Ace, LibStub, network downloads, or CSV parsing is required in WoW.

Generated scan relationships identify items. CraftSim's live schematics remain
responsible for crafting quantities and costs. The expanded catalog does not
supply guessed lumber prices or stale recipe quantities to CraftSim.

## Behavior and performance protections

Recon groups Profession → Expansion → Category → Recipe. The expansion dropdown
is a view filter: selections in other views still scan. Bulk selection affects
the visible view. Shared reagents retain ownership across professions/expansions;
individual item overrides take precedence. Legacy migration considers only the
verified baseline, so imported recipes never become selected by sharing an item.
Recipe selections drive current scan targets even if saved target keys predate a
reagent change.

The runtime builds a compact index once, caches item ownership, caps prepared
view caches at four branches, caches selected target counts and tree entries,
and updates affected targets when a recipe/individual selection changes. Large
target preparation, sorting, tree construction, counts, and export snapshots use
cooperative batches targeting 2 ms. Obsolete jobs cancel when views change or the
AH closes. Browsing uses shipped metadata rather than AH item queries. Scans
prepare only selected recipes and sources of positive individual overrides.
Scrolling allocates viewport rows plus two spare rows and reuses those frames.
There is no new continuous catalog polling/OnUpdate loop. Developer exports and
memory profiling are explicit commands only.

A full catalog still consumes memory for its static tables and requested indexes.
Large bulk selection/migration and GC can add synchronous work; the budget is not
a hard frame-time limit. The Lua test process measured about 63–65 MiB of total heap
after multiple fixtures, four cached views and an all-profession view; this is
not isolated WoW addon memory. Use `/cse dev perf` in game for the actual addon
snapshot. Export data also increases SavedVariables size until cleared.

## Automated evidence

`Tests/test_catalog.lua` loads production data as well as fixtures and checks
baseline precedence, source/metadata invariants, all-expansion ownership,
selection preservation, migration, override precedence, stale target caches,
cancellation, four-view cache eviction, warm-cache reuse and zero AH item-info
calls during browsing. A 10,000-entry scrolling fixture allocates 12 rows for a
240-pixel viewport. All nine professions produce 10,014 unique browsing targets.

Local plain-Lua runs built the cold recipe index in approximately 8–11 ms.
Most cooperative slices were near 2 ms, with observed GC/work spikes around
6–11 ms. These are developer-machine measurements and do not establish WoW FPS
or engine/API costs. In-game visual scrolling, actual frame impact, AH replies,
merchant transactions, and unlearned-profession API coverage need manual checks.

The addon Lua regression suite, syntax checks, CraftSim 27.0.7 source integration,
11 Python generator/importer tests, baseline semantic reproduction and imported
Lua byte-for-byte reproduction all passed before packaging this release.
The package was also checked against its TOC and the on-disk addon files.

## rc2 availability checks

Added RecipeAvailability.lua with a per-character session cache and Learned /
Unlearned / Unchecked states. The availability dropdown filters both browsing
views; its independent Scan learned recipes only toggle filters source recipes
before generating scan targets. Defaults preserve previous browsing/scanning.
Unlearned rows are dimmed but selectable, and availability is labeled on rows.
Unchecked records include unavailable API data and named transforms without IDs.

Own-profession context requires ready data and explicit rejection of linked,
guild and NPC contexts. Every observed recipe must match its returned ID and
base profession, with an explicit boolean learned field. Missing entries do not
imply unlearned. Updates publish after completion only, reject switched contexts,
and cancel on close/source changes. New-learn events cancel older observations.
Initial/open/source-change observations refresh confirmed state; routine list
updates retry unchecked IDs and reuse confirmed state. Timers coalesce bursts,
work yields in the existing 2 ms job runner, and scrolling reads cached state.
The cache resets each login to avoid retaining stale learned data across sessions.

Tests/test_recipe_availability.lua covers missing/error/mismatched/foreign data,
explicit false, character isolation, linked/guild/NPC rejection, unloaded/closed
contexts, unavailable APIs, deferred/atomic publication, batching, cancellation,
context switching, event coalescing, warm-cache API avoidance, forced refresh,
learning during an older refresh, and profession removal without invalidation on
ordinary rank updates. Catalog integration tests cover both item-view filtering
and scan restrictions, positive overrides, unchecked sources, shared materials,
and preserving choices when hiding or excluding a recipe. In-game refresh/event
behavior and menu/label layout remain pending manual validation.
