# Implementation Plan: Multi-Datasource Price Support

## Goals

1. Support **TradeSkillMaster (TSM)** as an alternative price datasource alongside Auctionator.
2. Expose a **primary / secondary source** preference that is configured through the **native WoW Settings UI** (Interface → AddOns → FishingStats panel), not a custom standalone panel.
3. Use **`DBMinBuyout`** (not `dbmarket`) when querying TSM prices.
4. Default: Primary = `Auctionator`, Secondary = `TSM`.

---

## TSM Price API

TSM exposes a public Lua API. The call to resolve a price source for one item is:

```lua
TSM_API.GetCustomPriceValue("DBMinBuyout", "i:" .. itemID)
-- returns: price in copper (number), or nil if unavailable
```

`"i:12345"` is the canonical TSM item string. `DBMinBuyout` is the per-realm minimum buyout recorded by TSM's scanner.

---

## Files Changed

| File | Summary |
|---|---|
| `FishSet.lua` | Extend `InitDB`, add `Addon.GetItemPriceFromSource`, `Addon.GetItemPrice`, update `GetCurrentItemPrice` and `PreloadFishPrices` |
| `FishingStats.lua` | Update `GetCachedItemPrice`; add WoW Settings panel, dropdowns, and `/fsconfig` slash command |
| `FishingStats.toc` | Add `TradeSkillMaster` to `## OptionalDeps` |

---

## Phase 1 — Config Storage (`FishSet.lua` → `InitDB`)

Extend the database initialiser to persist user preferences:

```lua
FishingStatsDB.config = FishingStatsDB.config or {}
FishingStatsDB.config.primarySource   = FishingStatsDB.config.primarySource   or "Auctionator"
FishingStatsDB.config.secondarySource = FishingStatsDB.config.secondarySource or "TSM"
```

Valid source strings: `"Auctionator"`, `"TSM"`, `"None"`.

---

## Phase 2 — Datasource Abstraction (`FishSet.lua`)

### 2a. `Addon.GetItemPriceFromSource(source, itemID)`

Centralised, side-effect-free price query:

```lua
function Addon.GetItemPriceFromSource(source, itemID)
  if not itemID then return nil end

  if source == "Auctionator" then
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
      return Auctionator.API.v1.GetAuctionPriceByItemID("FishingStats", itemID)
    end

  elseif source == "TSM" then
    if TSM_API then
      local itemString = "i:" .. itemID
      return TSM_API.GetCustomPriceValue("DBMinBuyout", itemString)
    end
  end

  return nil
end
```

### 2b. `Addon.GetItemPrice(itemID)` — primary → secondary fallback

```lua
function Addon.GetItemPrice(itemID)
  if not itemID then return 0 end

  local cfg = FishingStatsDB.config or {}
  local primary   = cfg.primarySource   or "Auctionator"
  local secondary = cfg.secondarySource or "TSM"

  local price = Addon.GetItemPriceFromSource(primary, itemID)
  if (not price or price == 0) and secondary ~= "None" and secondary ~= primary then
    price = Addon.GetItemPriceFromSource(secondary, itemID)
  end

  return price or 0
end
```

### 2c. Replace `GetCurrentItemPrice` (private, in `FishSet.lua`)

The old function queried Auctionator directly. Replace its body to delegate:

```lua
local function GetCurrentItemPrice(itemID)
  if not itemID then return 0 end
  if priceCache[itemID] then return priceCache[itemID] end
  local price = Addon.GetItemPrice(itemID)
  if price and price > 0 then
    priceCache[itemID] = price
  end
  return price or 0
end
```

### 2d. Update `Addon.PreloadFishPrices`

Remove the hard Auctionator availability guard; use `Addon.GetItemPrice` instead:

```lua
function Addon.PreloadFishPrices()
  local cfg = FishingStatsDB.config or {}
  local primary   = cfg.primarySource   or "Auctionator"
  local secondary = cfg.secondarySource or "TSM"
  local primaryOk   = (primary   ~= "None") and Addon.GetItemPriceFromSource(primary,   220134) ~= nil
  -- (probe with any known itemID just to test availability; result discarded)

  if primary == "None" and secondary == "None" then
    print("FishingStats: No price source configured. Prices will be unavailable.")
    return
  end

  for itemID in pairs(FISH_SET) do
    if not priceCache[itemID] then
      local price = Addon.GetItemPrice(itemID)
      if price and price > 0 then
        priceCache[itemID] = price
      end
    end
  end
  print("FishingStats: Price preload complete.")
end
```

---

## Phase 3 — Update `GetCachedItemPrice` (`FishingStats.lua`)

The duplicate price-fetch function in `FishingStats.lua` must also delegate to `Addon.GetItemPrice`:

```lua
local function GetCachedItemPrice(itemID)
  if not itemID then return 0 end
  if priceCache[itemID] then return priceCache[itemID] end
  local price = Addon.GetItemPrice(itemID)
  if price and price > 0 then
    priceCache[itemID] = price
  end
  return price or 0
end
```

---

## Phase 4 — WoW Settings Panel (`FishingStats.lua`)

Use the retail Settings API (`Settings.RegisterCanvasLayoutCategory`) so the config appears under **Interface → AddOns → FishingStats**, with no separate floating window.

### 4a. Source list constants

```lua
local PRICE_SOURCES = { "Auctionator", "TSM", "None" }
```

### 4b. Build canvas frame with two `UIDropDownMenu` controls

```lua
local function BuildSettingsPanel()
  local panel = CreateFrame("Frame")
  panel.name = "FishingStats"

  -- Title
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("FishingStats — Price Sources")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetText("Choose which auction-data addons are used for item price lookups.\nPrimary is tried first; Secondary is the fallback.")

  -- Helper: create a labelled dropdown
  local function MakeDropdown(parent, label, yOffset, getter, setter)
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 16, yOffset)
    lbl:SetText(label)

    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 12, yOffset - 22)
    UIDropDownMenu_SetWidth(dd, 180)
    UIDropDownMenu_Initialize(dd, function(_, level)
      for _, src in ipairs(PRICE_SOURCES) do
        local available = (src == "None")
          or (src == "Auctionator" and Auctionator and Auctionator.API)
          or (src == "TSM"         and TSM_API ~= nil)
        local info = UIDropDownMenu_CreateInfo()
        info.text    = available and src or (src .. " |cffff4444(not loaded)|r")
        info.checked = getter() == src
        info.func    = function()
          setter(src)
          UIDropDownMenu_SetText(dd, src)
          -- Wipe cache so next query uses new source
          wipe(FishingStatsDB.prices)
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    UIDropDownMenu_SetText(dd, getter())
    return dd
  end

  local primaryDD = MakeDropdown(
    panel, "Primary Price Source:", -72,
    function() return FishingStatsDB.config and FishingStatsDB.config.primarySource or "Auctionator" end,
    function(v) FishingStatsDB.config.primarySource = v end
  )

  local secondaryDD = MakeDropdown(
    panel, "Secondary Price Source (fallback):", -140,
    function() return FishingStatsDB.config and FishingStatsDB.config.secondarySource or "TSM" end,
    function(v) FishingStatsDB.config.secondarySource = v end
  )

  -- Register with WoW Settings
  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)

  -- Store references for `/fsconfig` command
  Addon.settingsCategory = category
end
```

### 4c. Call `BuildSettingsPanel()` at addon load time

Inside the `ADDON_LOADED` handler in `FishingStats.lua`, after `InitDB`:

```lua
if addon == "FishingStats" then
  BuildSettingsPanel()
  print("🎣 FishingStats loaded. Click the minimap fishing icon to view stats.")
end
```

### 4d. `/fsconfig` slash command — opens the Settings panel to the FishingStats page

```lua
SLASH_FS_CONFIG1 = "/fsconfig"
SlashCmdList["FS_CONFIG"] = function()
  Settings.OpenToCategory(Addon.settingsCategory:GetID())
end
```

---

## Phase 5 — TOC update (`FishingStats.toc`)

```
## OptionalDeps: Auctionator, TradeSkillMaster
```

---

## Sequence Diagram

```
LOOT_OPENED
  └─ GetCachedItemPrice(itemID)         [FishingStats.lua]
       └─ Addon.GetItemPrice(itemID)    [FishSet.lua]
            ├─ GetItemPriceFromSource(primary, itemID)
            │    ├─ Auctionator.API.v1.GetAuctionPriceByItemID(...)
            │    └─ TSM_API.GetCustomPriceValue("DBMinBuyout", "i:"..id)
            └─ if 0/nil → GetItemPriceFromSource(secondary, itemID)
```

---

## Notes & Constraints

- `TSM_API` is the global exposed by TradeSkillMaster 4+. It may not exist when TSM is not loaded; all access is guarded.
- `DBMinBuyout` reflects the **minimum buyout** price recorded by TSM's AH scanner — the most conservative/liquid price signal.
- Changing the source in Settings wipes `priceCache` immediately; the user should then use the existing "Refresh Price" button (or `/fsrp`) to repopulate.
- `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` are available from WoW 10.0 onwards (retail only). This matches the `## Interface: 120001` target.
