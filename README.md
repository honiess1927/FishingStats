# 🎣 Fishing Stats

A lightweight World of Warcraft addon that tracks fish you catch and calculates their estimated auction value.

## ✨ Features

- 🐟 Tracks how many of each fish you've caught (currently supports The War Within fish only)
- 💰 Estimates total auction value based on Auctionator prices (You need to have Auctionator installed to get this)
- 🌍 Shows regional overview and per-region earnings breakdown based on your recorded catches
- 🧠 Automatically saves stats between sessions
- 🧭 Includes a minimap button for quick access

## 🔧 Slash Commands

- `/fs` — Toggle the main stats window
- `/fsr` — Reset all fish counts
- `/fsrp` — Clear cached prices and reload from Auctionator

## 📌 Notes

- Requires **Auctionator** to retrieve price data
- All data is saved via SavedVariables and persists through reloads or restarts
- Regional statistics start collecting from the version that introduced region tracking; older totals are not backfilled by region

## 🖼️ Region View

- `Overview` button: opens the region popup on the overview tab
- `Region` button: opens the details tab directly for your current zone/region
- Overview tab: shows total catches, total earn, and estimated hourly earn by region
- Details tab: lets you inspect the item-by-item breakdown for a selected region, including count, percentage, total earn, and estimated hourly earn

## 📋 Planned Features

- 🐟 Support for older fish and future expansions
- 🌐 Locale (multi-language) support
- ⚙️ Optional UI buttons for consumables and gear

## 💬 Feedback

Feel free to leave comments, suggestions, or bug reports on the CurseForge project page!

