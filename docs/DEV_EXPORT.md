# Developer profession export

Profession dump available in **1.6.2-rc3**; catalog mode added in **1.6.2-rc4**. The commands are opt-in and do not change prices, shopping lists, or normal addon settings.

```text
/cse dev dump
/cse dev catalog
/cse dev perf
/cse dev status
/cse dev cancel
/cse dev clear
```

Use **`/cse dev catalog`** when you have not learned the profession or its expansion. In 1.7.0 it queries the **10,621 numeric recipe IDs** in Recon's current database across all supported professions and eras. No profession window is required, and changing or closing a profession window does not cancel catalog mode. It saves a separate `catalog` capture for the current character and preserves profession captures. Wait for the completion message, then `/reload` to save to disk.

Catalog mode asks the client for live data by recipe ID. Some APIs may return only partial data or no data for unlearned recipes; unavailable schematics and incomplete recipe records remain explicit. The completion message reports both recipe IDs attempted and valid schematics returned. Raw live fields and fields named `generatedProfession`/`generatedRecipeName` retain separate provenance. A missing live result is never filled in with generated data and presented as confirmed live data. The generated-data snapshot is included for comparison.

This covers recipes already in Recon's database. It does not discover unknown new recipes outside that list. Sixteen generated transform entries without numeric spell IDs are included in the generated snapshot but cannot be queried as live recipe IDs. The profession-window dump remains useful for discovering additional recipe IDs and learned-state information that the client exposes there.

Open your own profession window and let its recipes load. Select the desired expansion view and clear search/recipe filters where possible. Run `/cse dev dump` and keep the same profession open until the completion message. Work is split across frames. Switching or closing professions cancels the pending capture and preserves previously completed captures.

The command captures the profession's recipe list plus Recon's generated recipe IDs for that profession, including unlearned recipes when the client supplies them. It saves live recipe information, known/unlearned state, profession and category information, output quantities and rank links, required/optional/finishing reagent slots and their quantities/ranked alternatives, item details, generated item metadata, and saved CraftSim crafting costs. Foreign/stale recipe entries, API errors, missing schematics, and uncached item data remain identifiable. If item data is uncached, wait a few seconds and repeat the dump.

It also snapshots the Enhancer settings/vendor plan, compatibility warnings and module states, current Recon prices and missing results, CraftSim price overrides where present, generated recipe/category data, and up to 200 recent debug messages. Enable `/cse debug` before reproducing an issue if you want debug messages included; existing errors from BugSack/BugGrabber still need to be reported separately.

Captures are keyed by character and base/child profession. Repeat for each profession and character you want to inspect. If an expansion selection changes what the client returns, dump that expansion too. Repeating the same character/profession view replaces that capture; other captures remain. This is a snapshot of data exposed by the client, not a complete dump of every profession in the game, every recipe variant, or your entire account's crafting history.

After the completion message, run `/reload` or log out normally. WoW writes both saved-variable tables to:

```text
_retail_/WTF/Account/<account>/SavedVariables/CraftSimEnhancer.lua
```

The diagnostics are under **`CraftSimEnhancerDevDB`**; your regular settings remain under `CraftSimEnhancerDB`. The file includes character identifiers and addon settings used for diagnosis. WoW addons cannot write an arbitrary log file directly; SavedVariables supplies the disk export. A crash or forced exit before saving can lose the latest capture.

`/cse dev status` reports running progress or the number of saved captures. `/cse dev cancel` stops pending work. `/cse dev clear` removes only developer exports and buffered debug messages; follow with `/reload` to persist the removal. Large captures can make the SavedVariables file larger, so clear them when no longer needed.

Use the [in-game checklist](../Tests/MANUAL_12_1_5.md) alongside the export.

`/cse dev perf` reports catalog counts, preparation timing, cache hits, row pool sizes, and an explicit addon memory snapshot when supported. It does not start continuous profiling. Capture it before and after opening Recon, changing expansion views, and selecting recipes. Timings describe addon preparation, not total frame time or server response latency.

Recipe collection and final snapshot copying yield between batches. A snapshot publishes only when finished; cancelling during collection or finalization preserves completed captures. A full catalog export can take time and create a large SavedVariables file. Use it for diagnosis, then clear it when no longer needed.
