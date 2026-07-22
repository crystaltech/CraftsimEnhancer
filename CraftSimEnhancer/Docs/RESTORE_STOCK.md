# Restoring stock CraftSim

The safest final operation is to replace the modified CraftSim directory with the current CurseForge package. Do not delete `CraftSimEnhancer/` when doing so.

If restoring file by file from the supplied `CraftSim_stock/` copy, restore these modified upstream files:

- `CraftSim.toc`
- `Init/Init.lua`
- `Modules/CraftQueue/CraftQueue.lua`
- `Modules/RecipeScan/RecipeScan.lua`
- `CHANGELOG.md`
- `Libs/LibDBIcon-1.0/LibDBIcon-1.0.toc`
- `Data/News.lua`
- `Data/SpecializationData/Midnight/Alchemy.lua`
- `Data/SpecializationData/Midnight/Inscription.lua`
- `Data/SpecializationData/Midnight/Tailoring.lua`

Remove these custom files/directories from the modified CraftSim copy after the Enhancer is installed and verified:

- `DB/auctionHouseScanDB.lua`
- `Data/GeneratedRecipes/`
- `Modules/AuctionHouseScan/`
- `Modules/VendorBuy/`

The following custom TOC lines disappear when the stock TOC is restored:

- `DB/auctionHouseScanDB.lua`
- every `Data/GeneratedRecipes/*.lua` line
- `Modules/AuctionHouseScan/AuctionHouseScan.lua`
- `Modules/VendorBuy/VendorBuy.lua`

`CraftSimDB.auctionHouseScanDB` may remain in SavedVariables. CraftSim Enhancer reads it once for migration and never deletes it. CraftSim's stock `priceOverrideDB` should remain because the scanner pushes prices into that upstream feature.

No source change must remain temporarily. If desired, keep the modified folder only as an offline backup until the in-game checklist passes; do not keep its custom files in the live `Interface/AddOns/CraftSim/` directory.

The final live layout is:

```text
Interface/AddOns/CraftSim/
Interface/AddOns/CraftSimEnhancer/
```

The first directory should be the unmodified CurseForge release. The second directory is independent and will not be overwritten when CurseForge updates CraftSim.
