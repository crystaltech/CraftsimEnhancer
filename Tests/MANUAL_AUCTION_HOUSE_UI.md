# Auction House UI smoke test

Use this short checklist after installing a development build:

1. Open **CSE Recon** with one profession selected and confirm **Products + reagents** is the first scan-scope option.
2. Confirm both panes use a readable medium-charcoal Blizzard rock texture, with a subtle two-pixel metallic center divider and a recessed list whose top/left inner shadow and bottom/right bevel remain restrained.
3. Switch between the persistent **Recipes** and **Individual items** Blizzard top tabs; the active tab should connect visually to the content, the tab borders must not overlap, and neither label should change.
4. Confirm the compact selection summary reconciles recipe selection with the price-target tooltip details.
5. In **Recipes**, verify `+`/`-` only expands/collapses, the checkbox changes a group, and clicking a recipe row changes that recipe.
6. Confirm the summary and gold-text **Select all**, **Clear all**, and correct **Expand all**/**Collapse all** actions fit on one compact row and share the same visual weight.
7. In **Individual items**, enter a search and confirm the bulk actions become **Select matches** and **Clear matches**.
8. Start a scan and confirm the slim progress bar advances while selection controls are disabled.
9. Open **Unpriced items**, click **Skip future**, and confirm the row changes to disabled **Skipped** without changing another recipe's shared targets.
10. Resize or use both standard and small Auctionator tabs and confirm no labels overlap or clip.
