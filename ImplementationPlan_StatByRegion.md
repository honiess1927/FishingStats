# Implementation Plan: Region-Based Hourly Earnings

## Goal

Add a new region statistics workflow to FishingStats so the player can:

1. Open a new region stats window from the existing main panel.
2. View an overview of estimated hourly earnings by region.
3. Switch to a details tab.
4. Select a region from a dropdown and inspect fish/item breakdown, percentage share, and estimated hourly earnings.

The hourly estimate is based on a fixed throughput of **300 catches per hour**.

## Current State Summary

The addon currently tracks only global totals:

- `FishingStatsDB.fishCounts`: item name -> count
- `FishingStatsDB.prices`: item ID -> auction price cache
- `FishingStatsDB.earn`: total accumulated value

The current loot flow in `FishingStats.lua` updates totals when `LOOT_OPENED` fires after a successful fishing cast. There is no region-aware storage, no region inference, and no UI container for tabbed detail views.

This means the feature is not a pure UI addition. It requires a data model extension so future catches are attributed to the player’s current region at the time loot is processed.

## Recommended Scope

Implement the feature in two layers:

1. **Data capture layer**
   Record each fishing result against a resolved region key.
2. **Presentation layer**
   Add a button, popup window, overview tab, details tab, and region dropdown.

Do not attempt to backfill historical region data from existing totals. Existing global totals have no region metadata, so they cannot be partitioned accurately.

## Functional Requirements Mapping

### Requirement 1: Button on the right side of the main panel

Add a button anchored to the right edge of `FishingStatsFrame`.

Recommended label:

- `Regions`

Responsibilities:

- Visible whenever the main panel is shown.
- Opens the region statistics popup.
- Refreshes the popup before showing it.

### Requirement 2: Open a new popup window

Create a separate movable frame, for example `FishingStatsRegionFrame`, instead of overloading the current compact main panel.

Recommended properties:

- Width around `420-520`
- Height around `620-820`
- Same backdrop style as the main panel for visual consistency
- Close button in the top-right corner
- Hidden by default

### Requirement 3: Overview page of estimated hourly earnings by region

The overview tab should list all tracked regions with:

- Region name
- Total catch count in that region
- Total catch value in that region
- Estimated hourly earnings: use the same item-level calculation logic as the details tab as described below.

Guardrails:

- If `regionTotalCatchCount == 0`, the rigion should be hidden.
- Sort regions descending by estimated hourly earnings.

### Requirement 4: Details tab with dropdown by region

The details tab should contain:

- A dropdown listing all regions with `regionTotalCatchCount > 0`
- A scrollable or bounded list of catches/items for the selected region

For each item in the selected region, display:

- Item name
- Count
- Percentage of regional total catches
- Estimated earn contribution

Recommended formula per item:

- `itemValueTotal = itemCount * itemUnitPrice`
- `itemCatchPercent = itemCount / regionTotalCatchCount * 100`
- `itemHourlyEarn = (itemCount / regionTotalCatchCount) * 300 * itemUnitPrice`

Equivalent simplified formula:

- `itemHourlyEarn = itemValueTotal / regionTotalCatchCount * 300`

This makes the item-level hourly contributions sum to the region hourly estimate shown on the overview tab.

## Data Model Changes

### New SavedVariables structure

Extend `FishingStatsDB` with region-specific storage.

Recommended shape:

```lua
FishingStatsDB.regionStats = {
  [regionKey] = {
    regionName = "Hallowfall",
    totalCount = 0,
    totalEarn = 0,
    fishCounts = {
      [itemName] = {
        itemID = 220141,
        count = 0,
        totalEarn = 0,
      },
    },
  },
}
```

Optional but useful:

```lua
FishingStatsDB.meta = {
  dataVersion = 2,
}
```

Why this structure works:

- Region overview becomes cheap to compute.
- Details view does not need to reconstruct totals from global state.
- Overview and details can share the same precomputed per-item regional metrics.
- Item-level earnings remain stable even if future Auctionator prices change, because `totalEarn` is stored at capture time.

### Region key strategy

Use a stable internal key and store a display name.

Recommended approach:

- `regionKey = GetRealZoneText()` if available and non-empty
- Fallback to `GetZoneText()`
- Final fallback: `"Unknown Region"`

If subzones are important later, the plan can be extended to include both zone and subzone, but for this requirement the top-level zone is the safer default because it maps better to the idea of a region.

### Migration

Update initialization in `FishSet.lua` so the addon creates missing region storage safely on load.

Important constraint:

- Existing `fishCounts` and `earn` data should remain untouched.
- Region data starts empty for existing users.
- No attempt should be made to redistribute historical totals into regions.

User-facing note to include in documentation or release notes:

- Region statistics begin collecting after this version is installed.

## Data Capture Design

### Where to capture region

Hook the new logic into the existing `LOOT_OPENED` branch in `FishingStats.lua`, because that is where fish/item counts and earnings are already finalized.

Recommended flow during loot processing:

1. Resolve current region name.
2. Resolve `itemID`, `itemName`, `quantity`, and price.
3. Update existing global totals exactly as before.
4. Update region totals using the same resolved values.

### New helper functions

Add small helper functions to avoid duplicating logic:

```lua
Addon.GetCurrentFishingRegion()
Addon.EnsureRegionStats(regionName)
Addon.RecordRegionCatch(regionName, itemID, itemName, count, totalEarn)
Addon.GetRegionMetrics(regionName)
Addon.GetRegionOverviewData()
Addon.GetRegionDetailData(regionName)
```

Responsibilities:

- `GetCurrentFishingRegion()` returns the best available region name.
- `EnsureRegionStats()` creates table scaffolding if absent.
- `RecordRegionCatch()` updates count and earn totals for region and item.
- `GetRegionMetrics(regionName)` builds the normalized per-item metrics for one region, including percentage and hourly earn.
- `GetRegionOverviewData()` returns sorted region rows for the overview tab by aggregating each region's item metrics.
- `GetRegionDetailData(regionName)` returns the same per-item metrics and region totals for the details tab.

### Counting rules

The current addon treats `杂项` and `垃圾` differently by forcing count to `1` instead of loot quantity. Region tracking should follow the exact same counting rule so regional totals stay consistent with existing aggregate totals.

### Pricing rules

The current implementation already derives `totalPrice` from Auctionator price times `quantity`. Region storage should persist that computed value directly.

Recommended behavior when no price is available:

- Record the catch count.
- Record earnings as `0`.

This ensures the catch distribution remains accurate even when pricing is incomplete.

## UI Design

### New popup frame

Add a new region window in `FishingStats.lua` unless you choose to split UI concerns into a new file.

Recommended child elements:

- Title text: `Region Earnings`
- Close button
- Two tab buttons: `Overview`, `Details`
- One content container for each tab

Recommended implementation approach:

- Use two child frames and show/hide them when tabs change.
- Keep the tab state on the frame, for example `regionFrame.activeTab`.

### Overview tab

Use a static list of `FontString` rows first. This is consistent with the current addon style and keeps scope controlled.

Data source rule:

- Do not calculate overview hourly earnings in a separate UI-only formula path.
- Build the overview rows from the same region metrics used by the details tab so the numbers stay identical.

Recommended columns:

- Region
- Catches
- Total Earn
- Hourly Earn

If row count may exceed visible space:

- Either cap to top N regions initially
- Or add a simple `ScrollFrame`

For a first implementation, a capped list is acceptable if documented, but a scrollable list is preferable.

### Details tab

Use WoW’s standard dropdown pattern:

- `UIDropDownMenuTemplate`

Below the dropdown, display item rows for the selected region.

Recommended columns:

- Item
- Count
- %
- Hourly Earn

Optional extra column if space allows:

- Total Earn

Recommended behavior:

- Default select the first available region sorted by hourly earnings.
- If no region data exists, show a message such as `No regional data recorded yet.`

## File-Level Implementation Plan

### 1. `FishSet.lua`

Purpose:

- Extend DB initialization.
- Add data helpers that are not directly tied to UI rendering.

Planned changes:

1. Initialize `FishingStatsDB.regionStats`.
2. Optionally initialize `FishingStatsDB.meta.dataVersion`.
3. Add helper methods for region resolution and region stat updates.
4. Add a shared region metrics builder used by both overview and detail rendering.
5. Add helper methods for overview/detail data retrieval.

Why here:

- This file already owns DB initialization and shared addon functions.
- It is the cleanest place for data-layer helpers.

### 2. `FishingStats.lua`

Purpose:

- Wire the new data capture into the loot event.
- Build the new UI button and popup window.
- Render overview and detail data.

Planned changes:

1. Add a `Regions` button to the existing main frame’s right side.
2. Create `FishingStatsRegionFrame`.
3. Add tab buttons and content containers.
4. Add refresh functions:
   - `RefreshRegionOverview()`
   - `RefreshRegionDetails(selectedRegion)`
   - `RefreshRegionWindow()`
5. Ensure `RefreshRegionOverview()` consumes the same shared region metrics as `RefreshRegionDetails(selectedRegion)`.
6. During `LOOT_OPENED`, call `Addon.RecordRegionCatch(...)` alongside the existing total updates.

### 3. `FishingStats.toc`

Purpose:

- Only needed if UI/data helpers are split into new files.

Planned change:

- Add any newly created Lua file to the load order.

If all work stays inside the current files, no `.toc` change is required.

### 4. `README.md`

Purpose:

- Document user-visible behavior.

Planned changes:

1. Add the new region earnings feature to the feature list.
2. Mention that region stats are collected from the moment this version is installed.
3. Optionally add a slash command later if a direct open action is introduced.

## Suggested Implementation Sequence

### Phase 1: Data foundation

1. Extend DB initialization.
2. Implement region resolution helper.
3. Implement region record/update helper.
4. Implement a shared region metrics builder.
5. Implement overview/detail query helpers on top of that builder.

Deliverable:

- Region data tables populate correctly during gameplay.

### Phase 2: Event integration

1. Update the fishing loot handler.
2. Record region stats in the same branch that updates global stats.
3. Verify no regressions to total counts and total earnings.

Deliverable:

- Every new fishing catch updates both global and regional stats.

### Phase 3: Popup UI shell

1. Add the right-side button.
2. Create the popup frame.
3. Add close button and tabs.
4. Add empty-state messaging.

Deliverable:

- User can open and navigate the new window.

### Phase 4: Overview rendering

1. Build the region summary rows.
2. Source each region's hourly earn from the same per-item metrics used in details.
3. Sort data.
4. Format currency and counts.

Deliverable:

- Overview tab shows estimated hourly earnings by region.

### Phase 5: Details rendering

1. Add dropdown.
2. Populate region options.
3. Render per-item rows for the selected region.
4. Calculate percentages and hourly contributions.

Deliverable:

- Details tab meets the full requirement.

### Phase 6: Validation and polish

1. Test regions with missing prices.
2. Test first-run and upgraded SavedVariables.
3. Test frame open/close and tab switching.
4. Test with no regional data.
5. Confirm formatting fits common UI scale settings.

Deliverable:

- Feature is stable and usable in normal play.

## Edge Cases and Risks

### 1. Historical data cannot be regionalized

Risk:

- Existing totals do not contain zone metadata.

Decision:

- Start region tracking only for future catches.

### 2. Zone name may be unavailable briefly

Risk:

- In rare loading transitions, zone APIs may return an empty string.

Mitigation:

- Use fallback chain and store under `Unknown Region` when necessary.

### 3. Auctionator prices may be missing

Risk:

- Hourly earnings may underreport value.

Mitigation:

- Preserve catch counts even when value is zero.
- Keep price cache preload behavior unchanged.

### 4. UI row count may exceed visible space

Risk:

- Regions or items may overflow a static frame.

Mitigation:

- Prefer a simple scroll frame if time allows.
- Otherwise explicitly limit visible rows and show top entries first.

### 5. Region name collisions across expansions

Risk:

- Two maps could theoretically share a display name.

Mitigation:

- Accept display-name keys for now unless this becomes a real issue.
- If needed later, migrate to map ID plus display name.

## Acceptance Criteria

The feature should be considered complete when all of the following are true:

1. The main panel has a right-side button that opens a new region stats popup.
2. The popup has an overview tab and a details tab.
3. The overview tab lists regional hourly earnings based on 300 catches per hour.
4. The overview tab uses the same underlying region/item calculation logic as the details tab.
5. The details tab includes a dropdown for region selection.
6. The details tab shows item type, count, percentage, and estimated earn for the selected region.
7. New catches update both global stats and regional stats without breaking existing behavior.
8. Existing users can upgrade without SavedVariables errors.
9. Empty-state handling works when no regional data exists yet.

## Recommended Nice-to-Haves

These are not required for the first pass but would improve maintainability:

1. Extract region UI into a dedicated file such as `RegionStats.lua`.
2. Add a slash command like `/fsregion` to open the popup directly.
3. Add a tooltip to the `Regions` button.
4. Add a small note in the popup clarifying that hourly estimates use current price cache and 300 catches per hour.
5. Store `itemID` consistently for all tracked entries to support future icon rendering.

## Recommended Next Action

Implement the data model and capture path first, then build the popup UI on top of real region data. That ordering reduces rework and makes the UI immediately testable with live catches.