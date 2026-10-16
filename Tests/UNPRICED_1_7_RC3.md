# rc3 unpriced-report classification

The October 16, 2026 user report from 1.7.0-rc2 shows 475 processed targets,
330 priced targets, and 145 unpriced targets grouped into 47 items. All report
entries are product targets; none reports a timeout or throttling failure.

42 items / 120 unpriced targets have populated broad-search buyout rows with
zero matches for the requested quality rank. For example, Bright Linen Alchemy
Apron targets levels 180 and 199, while its returned rows show 186, 192 and 206.
Those entries previously said “No auctions,” which concealed the other-rank
listings. The evidence supports an absent requested rank under the scanner's
current classification; the report alone cannot prove every inferred rank map.

Five items / 25 targets returned zero buyout rows:

- Evercore Binding (245342)
- Evercore Gear Weight (245344)
- Evercore Reconnaissance (244753)
- Evercore Zoomshroud (244751)
- Farstrider Clampers (244713)

Those searches returned item-specific events and complete-result flags. Cached
empty results received confirmation retries. No positive auction price can be
inferred from these responses. Their cached 12.1.5 ItemSparse entries are bind on
equip, so this report does not justify adding a bind-on-pickup exclusion.

rc3 changes reporting, keeping the existing exact-rank matching and saved-cost
estimate rules. Classified but absent ranks become “Rank not listed”; ordinary
level variants become “Variant not listed.” Empty buyout searches remain
“No auctions,” unresolved ranks remain “Variant not recognized,” and explicit
query errors take precedence. The absent-rank message retains confirmed-absence
semantics so Push Overrides can use the established cost-based estimate and
better-rank cap. It does not substitute another rank's auction price.

Tests/test_auction_house_scan.lua reproduces populated other-rank rows, unmatched
ordinary levels, unresolved classification, empty results and query failures.
It verifies unmatched rows never become auction prices, absent ranks remain
estimate-eligible, and unresolved ranks remain ineligible. The Lua regression
suite, syntax checks and CraftSim 27.0.7 integration passed before packaging.
In-game confirmation of the new labels remains pending.
