# 🎣 Fishing Stats

A lightweight World of Warcraft addon that tracks the fish (and other fishing loot) you catch, estimates their auction value, and breaks earnings down by zone and by day.

## ✨ Features

- 🐟 Tracks how many of each fish/item you've caught while fishing (currently covers The War Within fish, ore, and skinning loot — see `FishSet.lua`)
- 💰 Estimates item value using **Auctionator** and/or **TSM (TradeSkillMaster)** as price sources, with a configurable primary source and fallback secondary source
- 🔄 Automatically clears the cached price table and reloads prices whenever the Auction House closes, so values stay current
- 🌍 Regional overview and per-region breakdown of catches, total earnings, and estimated hourly earnings
- 📅 Daily earnings log, broken down by date
- 🎣 Displays your current fishing skill (base + gear/buff bonus)
- 🧰 Quick-use buff buttons on the main panel for a configurable set of fishing consumables (lures, etc.), with stack counts
- 🧭 Minimap button for quick access
- 🧠 All stats and settings are saved via SavedVariables and persist across sessions

## 🔧 Slash Commands

- `/fs` — Toggle the main stats window
- `/fsr` — Reset all fish counts, total earnings, and the price cache
- `/fsrp` — Clear cached prices and reload from the configured price source(s)
- `/fsconfig` — Open the FishingStats settings panel (Interface → AddOns → FishingStats)

## 🖱️ Minimap Button

- **Left-click** — Toggle the main stats window
- **Right-click** — Reset all fish counts (same as `/fsr`)

## ⚙️ Price Sources

Price data comes from **Auctionator** and/or **TSM**, configured in the settings panel (`/fsconfig`):

- **Primary Price Source** — tried first
- **Secondary Price Source (fallback)** — used if the primary has no price for an item
- Either can be set to `None`; sources that aren't loaded are marked accordingly in the dropdown

Prices are cached per item and automatically refreshed when the Auction House closes.

## 🖼️ Main Panel

The main panel (`/fs`) shows total fishing skill, hourly earnings for your current zone, total earnings, and a sorted breakdown of everything caught. Three buttons open the region window on a specific tab:

- **Overview** — opens the region popup on the Overview tab
- **Region** — opens the Details tab pre-selected to your current zone
- **Daily** — opens the Daily Earn tab

## 🌍 Region Window

A single window with three tabs:

- **Overview** — total catches, total earnings, and estimated hourly earnings per region
- **Details** — item-by-item breakdown for a selected region (count, percentage, total earn, estimated hourly earn), with a button to clear the saved data for that region
- **Daily Earn** — catches and total earnings grouped by date
- **Refresh Price** — button to clear the price cache and reload (same as `/fsrp`)

## 📌 Notes

- Requires **Auctionator** and/or **TSM** for price data; without at least one, earnings show as 0
- Regional and daily statistics start collecting from the version that introduced them; older totals are not backfilled
- Estimated hourly earnings are extrapolated from a fixed catches-per-hour target, not a live rate

## 📋 Planned Features

- 🐟 Support for older fish and future expansions
- 🌐 Locale (multi-language) support
- ⚙️ Additional configuration for the buff button loadout

## 💬 Feedback

Feel free to leave comments, suggestions, or bug reports on the CurseForge project page!
