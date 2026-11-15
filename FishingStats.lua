--[[
  FishingStats.lua
  Pure Lua fishing stats addon
--]]

-- ------------- Configuration -------------
local name, Addon = ...

-- The global item APIs were deprecated in favor of C_Item and removed in newer
-- clients; prefer C_Item and fall back to the old globals if present.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetCoinTextureString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
  or GetCoinTextureString or GetMoneyString

-- ------------- Debug logging -------------
-- Toggle with /fsdebug. Prints go out with a [FS-DEBUG] prefix so they're easy to
-- spot/filter in chat while we track down the catch-detection issue.
local debugEnabled = false
local function DebugPrint(...)
  if not debugEnabled then return end
  print("|cff33ff99[FS-DEBUG]|r", ...)
end

-- ------------- UI -------------
-- Main panel
-- Flat, ElvUI-like backdrop used when ElvUI isn't installed. When ElvUI is
-- loaded, ApplyElvUISkin() (bottom of this file) re-skins with ElvUI's own template.
local FLAT_BACKDROP = {
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
}
local function ApplyFlatBackdrop(f)
  f:SetBackdrop(FLAT_BACKDROP)
  f:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
  f:SetBackdropBorderColor(0, 0, 0, 1)
end

local frame = CreateFrame("Frame", "FishingStatsFrame", UIParent, "BackdropTemplate")
frame:SetSize(160, 300)
frame:SetPoint("CENTER")
ApplyFlatBackdrop(frame)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

-- Layout (top to bottom):
--   Title "Fishing Stats" + current region subtitle
--   ── separator ──
--   3 label/value rows: Skill / Hourly / Total
--   ── separator ──
--   Scrollable catch list: name | count | percent
local PAD = 10
local lineHeight = 16
local LABEL_COLOR = { 0.6, 0.6, 0.6 }

local function AddSeparator(yOffset)
  local sep = frame:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(1, 1, 1, 0.12)
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, yOffset)
  sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, yOffset)
  return sep
end

-- Title
frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
frame.title:SetText("Fishing Stats")

frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
frame.subtitle:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
frame.subtitle:SetJustifyH("LEFT")
frame.subtitle:SetWordWrap(false)
frame.subtitle:SetTextColor(unpack(LABEL_COLOR))

AddSeparator(-44)

-- Key stats: label on the left (grey, small), value right-aligned (white)
local function AddStatRow(label, yOffset)
  local lbl = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, yOffset - 2)
  lbl:SetTextColor(unpack(LABEL_COLOR))
  lbl:SetText(label)

  local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, yOffset)
  value:SetJustifyH("RIGHT")
  return value
end

frame.skillValue  = AddStatRow("Skill",  -52)
frame.hourlyValue = AddStatRow("Hourly", -70)
frame.totalValue  = AddStatRow("Total",  -88)

AddSeparator(-108)

-- Scrollable catch list (mouse wheel or scroll bar)
local fishScrollFrame = CreateFrame("ScrollFrame", "FishingStatsFishScrollFrame", frame, "UIPanelScrollFrameTemplate")
fishScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -114)
fishScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, PAD)

local fishScrollChild = CreateFrame("Frame", nil, fishScrollFrame)
fishScrollChild:SetSize(1, 1)
fishScrollFrame:SetScrollChild(fishScrollChild)
fishScrollFrame:SetScript("OnSizeChanged", function(self, width)
  fishScrollChild:SetWidth(width)
end)

local PCT_WIDTH = 30
local COUNT_WIDTH = 24
local fishRows = {}
local function GetFishRow(i)
  local row = fishRows[i]
  if row then return row end
  row = {}
  local y = -((i - 1) * lineHeight)

  row.pct = fishScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.pct:SetPoint("TOPRIGHT", fishScrollChild, "TOPRIGHT", 0, y - 2)
  row.pct:SetWidth(PCT_WIDTH)
  row.pct:SetJustifyH("RIGHT")
  row.pct:SetTextColor(unpack(LABEL_COLOR))

  row.count = fishScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.count:SetPoint("TOPRIGHT", row.pct, "TOPLEFT", 0, 2)
  row.count:SetWidth(COUNT_WIDTH)
  row.count:SetJustifyH("RIGHT")

  row.name = fishScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.name:SetPoint("TOPLEFT", fishScrollChild, "TOPLEFT", 0, y)
  row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  fishRows[i] = row
  return row
end

local FormatCoins
local FormatGoldOnlyCoins

-------- REFRESH PANEL -----
local function RefreshPanel()
  local fishCounts = FishingStatsDB.fishCounts
  local currentRegionName = Addon.GetCurrentFishingRegion()
  local currentRegionMetrics = Addon.GetRegionDetailData(currentRegionName)

  -- Header
  local total, _, bonus = Addon.GetFishingSkillBonus()
  frame.subtitle:SetText(currentRegionMetrics.regionName)
  frame.skillValue:SetText(string.format("%d |cff999999(+%d)|r", total, bonus))
  frame.hourlyValue:SetText(FormatGoldOnlyCoins(currentRegionMetrics.estimatedHourlyEarn))
  frame.totalValue:SetText(GetCoinTextureString(FishingStatsDB.earn))

  -- Clear previous list content
  for _, r in ipairs(fishRows) do
    r.name:SetText("")
    r.count:SetText("")
    r.pct:SetText("")
  end

  -- Sort by count
  local sortedFish = {}
  local totalCount = 0
  for name, count in pairs(fishCounts) do
    table.insert(sortedFish, {name = name, count = count})
    totalCount = totalCount + count
  end
  table.sort(sortedFish, function(a, b) return a.count > b.count end)

  local rowCount = #sortedFish
  for i, fish in ipairs(sortedFish) do
    local r = GetFishRow(i)
    r.name:SetText(fish.name)
    r.count:SetText(fish.count)
    r.pct:SetText(string.format("%d%%", fish.count / totalCount * 100))
  end

  -- Empty state
  if rowCount == 0 then
    local r = GetFishRow(1)
    r.name:SetText("|cff808080No data yet|r")
    rowCount = 1
  end

  fishScrollChild:SetSize(math.max(1, fishScrollFrame:GetWidth()), math.max(1, rowCount * lineHeight))

  frame:Show()
end


local function showhide()
  if frame:IsShown() then
    frame:Hide()
  else
    -- Refresh content
    RefreshPanel()
    Addon.PreloadFishPrices()
    frame:Show()
  end
end

-- Minimap button
local btn = CreateFrame("Button", "FishingStatsMinimapButton", Minimap, "SecureActionButtonTemplate")
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM")
btn:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -10, -10)
btn:SetNormalTexture("Interface\\Icons\\inv_fishingpole_02")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnClick", function(_, mouseButton)
  if mouseButton == "RightButton" then
    SlashCmdList["FS_RELOADCOUNTS"]()
  else
    showhide()
  end
end)


-- Create the secure use button once
local useBtn = CreateFrame("Button", "FishingStatsUseButton", UIParent, "SecureActionButtonTemplate")
useBtn:SetAttribute("type", "item")

FormatCoins = function(value)
  local amount = math.floor((value or 0) + 0.5)
  return GetCoinTextureString(amount)
end

FormatGoldOnlyCoins = function(value)
  local amount = math.max(0, math.floor((value or 0) + 0.5))
  local gold = math.floor(amount / 10000)
  return GetCoinTextureString(gold * 10000)
end

local function GetCachedItemPrice(itemID)
  if not itemID then return 0 end
  if priceCache[itemID] then return priceCache[itemID] end
  local price = Addon.GetItemPrice(itemID)
  if price and price > 0 then
    priceCache[itemID] = price
  end
  return price or 0
end

local regionFrame = CreateFrame("Frame", "FishingStatsRegionFrame", UIParent, "BackdropTemplate")
regionFrame:SetSize(500, 420)
regionFrame:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
ApplyFlatBackdrop(regionFrame)
regionFrame:EnableMouse(true)
regionFrame:SetMovable(true)
regionFrame:RegisterForDrag("LeftButton")
regionFrame:SetScript("OnDragStart", regionFrame.StartMoving)
regionFrame:SetScript("OnDragStop", regionFrame.StopMovingOrSizing)
regionFrame:Hide()
regionFrame.activeTab = "overview"
regionFrame.selectedRegion = nil

table.insert(UISpecialFrames, "FishingStatsRegionFrame")

local REGION_PAD = 16

-- Header: title, close button, tab row, separator
regionFrame.title = regionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
regionFrame.title:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", REGION_PAD, -14)
regionFrame.title:SetText("Region Earnings")

regionFrame.closeButton = CreateFrame("Button", nil, regionFrame, "UIPanelCloseButton")
regionFrame.closeButton:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", -4, -4)

local function CreateTabButton(text, width)
  local b = CreateFrame("Button", nil, regionFrame, "UIPanelButtonTemplate")
  b:SetSize(width or 90, 22)
  b:SetText(text)
  return b
end

regionFrame.overviewTab = CreateTabButton("Overview")
regionFrame.overviewTab:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", REGION_PAD, -42)

regionFrame.detailsTab = CreateTabButton("Details")
regionFrame.detailsTab:SetPoint("LEFT", regionFrame.overviewTab, "RIGHT", 4, 0)

regionFrame.dailyTab = CreateTabButton("Daily Earn")
regionFrame.dailyTab:SetPoint("LEFT", regionFrame.detailsTab, "RIGHT", 4, 0)

regionFrame.refreshPriceButton = CreateTabButton("Refresh Price", 100)
regionFrame.refreshPriceButton:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", -REGION_PAD, -42)

local function AddHLine(parent, yOffset, leftInset, rightInset)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.12)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", leftInset or 0, yOffset)
  line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightInset or 0), yOffset)
  return line
end

AddHLine(regionFrame, -72, REGION_PAD, REGION_PAD)

local function CreateContent()
  local c = CreateFrame("Frame", nil, regionFrame)
  c:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", REGION_PAD, -82)
  c:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", -REGION_PAD, 14)
  return c
end

regionFrame.overviewContent = CreateContent()
regionFrame.detailsContent = CreateContent()
regionFrame.dailyContent = CreateContent()

regionFrame.regionOptions = {}

------------------------------------------------------------
-- Generic scrollable table: grey header row + separator, zebra-striped rows,
-- first column left-aligned, numeric columns right-aligned.
-- Column spec: { key, text, x = left edge, width } for left-aligned columns,
--              { key, text, right = right edge } for right-aligned columns.
------------------------------------------------------------
local ROW_HEIGHT = 20

local function CreateDataTable(parent, scrollName, columns, topOffset, emptyText)
  local t = { columns = columns, rows = {} }

  for _, col in ipairs(columns) do
    local h = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    h:SetTextColor(unpack(LABEL_COLOR))
    if col.right then
      h:SetPoint("TOPRIGHT", parent, "TOPLEFT", col.right, topOffset)
    else
      h:SetPoint("TOPLEFT", parent, "TOPLEFT", col.x, topOffset)
    end
    h:SetText(col.text)
  end
  AddHLine(parent, topOffset - 15)

  t.scroll = CreateFrame("ScrollFrame", scrollName, parent, "UIPanelScrollFrameTemplate")
  t.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topOffset - 20)
  t.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 0)

  t.child = CreateFrame("Frame", nil, t.scroll)
  t.child:SetSize(1, 1)
  t.scroll:SetScrollChild(t.child)
  t.scroll:SetScript("OnSizeChanged", function(_, width) t.child:SetWidth(width) end)

  t.empty = parent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  t.empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, topOffset - 28)
  t.empty:SetText(emptyText)

  return t
end

local function GetTableRow(t, i)
  local row = t.rows[i]
  if row then return row end

  row = {}
  local top = -((i - 1) * ROW_HEIGHT)
  local mid = top - ROW_HEIGHT / 2

  if i % 2 == 0 then
    row.stripe = t.child:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetColorTexture(1, 1, 1, 0.04)
    row.stripe:SetHeight(ROW_HEIGHT)
    row.stripe:SetPoint("TOPLEFT", t.child, "TOPLEFT", 0, top)
    row.stripe:SetPoint("TOPRIGHT", t.child, "TOPRIGHT", 0, top)
  end

  for _, col in ipairs(t.columns) do
    local fs = t.child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetWordWrap(false)
    if col.right then
      fs:SetPoint("RIGHT", t.child, "TOPLEFT", col.right, mid)
      fs:SetJustifyH("RIGHT")
    else
      fs:SetPoint("LEFT", t.child, "TOPLEFT", col.x, mid)
      fs:SetWidth(col.width)
      fs:SetJustifyH("LEFT")
    end
    if col.dim then fs:SetTextColor(unpack(LABEL_COLOR)) end
    row[col.key] = fs
  end

  t.rows[i] = row
  return row
end

-- fillRow(row, entry) sets the text of each column for one data entry.
local function FillDataTable(t, data, fillRow)
  for _, row in ipairs(t.rows) do
    for _, col in ipairs(t.columns) do
      row[col.key]:SetText("")
    end
    if row.stripe then row.stripe:Hide() end
  end
  t.scroll:SetVerticalScroll(0)

  if #data == 0 then
    t.empty:Show()
    t.scroll:Hide()
    return
  end

  t.empty:Hide()
  t.scroll:Show()
  for i, entry in ipairs(data) do
    local row = GetTableRow(t, i)
    if row.stripe then row.stripe:Show() end
    fillRow(row, entry)
  end
  t.child:SetSize(math.max(1, t.scroll:GetWidth()), #data * ROW_HEIGHT)
end

------------------------------------------------------------
-- Overview tab
------------------------------------------------------------
regionFrame.overviewTable = CreateDataTable(regionFrame.overviewContent, "FishingStatsOverviewScrollFrame", {
  { key = "region", text = "Region",      x = 4, width = 150 },
  { key = "count",  text = "Catches",     right = 220 },
  { key = "total",  text = "Total Earn",  right = 330 },
  { key = "hourly", text = "Hourly Earn", right = 438 },
}, 0, "No regional data recorded yet.")

------------------------------------------------------------
-- Details tab: region dropdown + clear button, 4 stat blocks, item table
------------------------------------------------------------
regionFrame.dropdown = CreateFrame("Frame", "FishingStatsRegionDropdown", regionFrame.detailsContent, "UIDropDownMenuTemplate")
regionFrame.dropdown:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", -16, 4)

regionFrame.clearRegionButton = CreateFrame("Button", nil, regionFrame.detailsContent, "UIPanelButtonTemplate")
regionFrame.clearRegionButton:SetSize(100, 22)
regionFrame.clearRegionButton:SetPoint("TOPRIGHT", regionFrame.detailsContent, "TOPRIGHT", 0, -2)
regionFrame.clearRegionButton:SetText("Clear Region")

regionFrame.detailStats = {}
local detailStatConfig = {
  { key = "count",  text = "Catches" },
  { key = "types",  text = "Item Types" },
  { key = "total",  text = "Total Earn" },
  { key = "hourly", text = "Hourly Earn" },
}
for i, stat in ipairs(detailStatConfig) do
  local x = 4 + (i - 1) * 117
  local lbl = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  lbl:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", x, -38)
  lbl:SetTextColor(unpack(LABEL_COLOR))
  lbl:SetText(stat.text)

  local value = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -3)
  regionFrame.detailStats[stat.key] = value
end

regionFrame.detailsTable = CreateDataTable(regionFrame.detailsContent, "FishingStatsRegionDetailsScrollFrame", {
  { key = "item",    text = "Item",        x = 4, width = 130 },
  { key = "count",   text = "Count",       right = 180 },
  { key = "percent", text = "%",           right = 230, dim = true },
  { key = "total",   text = "Total Earn",  right = 334 },
  { key = "hourly",  text = "Hourly Earn", right = 438 },
}, -80, "No regional data recorded yet.")

------------------------------------------------------------
-- Daily tab
------------------------------------------------------------
regionFrame.dailyTable = CreateDataTable(regionFrame.dailyContent, "FishingStatsDailyScrollFrame", {
  { key = "date",  text = "Date",       x = 4, width = 140 },
  { key = "count", text = "Catches",    right = 300 },
  { key = "earn",  text = "Total Earn", right = 438 },
}, 0, "No daily data recorded yet.")

-- Scroll frames (for the ElvUI skin)
regionFrame.overviewScrollFrame = regionFrame.overviewTable.scroll
regionFrame.detailsScrollFrame = regionFrame.detailsTable.scroll
regionFrame.dailyScrollFrame = regionFrame.dailyTable.scroll

local function SetSelectedRegion(regionName)
  regionFrame.selectedRegion = regionName
  UIDropDownMenu_SetText(regionFrame.dropdown, regionName or "Select Region")
end

local function SyncRegionOptions(overviewData)
  local selectedRegionIsValid = false

  wipe(regionFrame.regionOptions)
  for _, entry in ipairs(overviewData) do
    table.insert(regionFrame.regionOptions, entry.regionName)
    if entry.regionName == regionFrame.selectedRegion then
      selectedRegionIsValid = true
    end
  end

  if regionFrame.selectedRegion and not selectedRegionIsValid then
    table.insert(regionFrame.regionOptions, 1, regionFrame.selectedRegion)
    selectedRegionIsValid = true
  end

  return selectedRegionIsValid
end

local RefreshRegionDetails
local RefreshRegionWindow

StaticPopupDialogs["FISHINGSTATS_CONFIRM_CLEAR_REGION"] = {
  text = "Clear all saved data for %s?",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function(_, data)
    if not data or not data.regionName then
      return
    end

    Addon.DeleteRegionStats(data.regionName)
    RefreshPanel()
    if regionFrame:IsShown() then
      RefreshRegionWindow()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = STATICPOPUP_NUMDIALOGS,
}

UIDropDownMenu_SetWidth(regionFrame.dropdown, 180)
UIDropDownMenu_Initialize(regionFrame.dropdown, function(self, level)
  for _, regionName in ipairs(regionFrame.regionOptions) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = "   " .. regionName
    info.checked = regionName == regionFrame.selectedRegion
    info.func = function()
      SetSelectedRegion(regionName)
      RefreshRegionDetails()
    end
    UIDropDownMenu_AddButton(info, level)
  end
end)

local function SetRegionTab(tabName)
  regionFrame.activeTab = tabName

  regionFrame.overviewContent:SetShown(tabName == "overview")
  regionFrame.detailsContent:SetShown(tabName == "details")
  regionFrame.dailyContent:SetShown(tabName == "daily")

  local tabs = {
    overview = regionFrame.overviewTab,
    details  = regionFrame.detailsTab,
    daily    = regionFrame.dailyTab,
  }
  for key, tab in pairs(tabs) do
    local active = key == tabName
    if regionFrame.elvSkinned then
      -- ElvUI style: keep tabs clickable and mark the active one with the
      -- ElvUI accent (value) color border instead of a greyed-out button.
      tab:SetEnabled(true)
      if active then
        tab:SetBackdropBorderColor(unpack(regionFrame.elvAccentColor))
      else
        tab:SetBackdropBorderColor(unpack(regionFrame.elvBorderColor))
      end
    else
      tab:SetEnabled(not active)
    end
  end
end

local function RefreshRegionOverview()
  local overviewData = Addon.GetRegionOverviewData()
  local selectedRegionIsValid = SyncRegionOptions(overviewData)

  if not selectedRegionIsValid then
    SetSelectedRegion(overviewData[1] and overviewData[1].regionName or nil)
  else
    SetSelectedRegion(regionFrame.selectedRegion)
  end

  FillDataTable(regionFrame.overviewTable, overviewData, function(row, entry)
    row.region:SetText(entry.regionName)
    row.count:SetText(tostring(entry.totalCount))
    row.total:SetText(FormatCoins(entry.totalEarn))
    row.hourly:SetText(FormatCoins(entry.estimatedHourlyEarn))
  end)
end

local function SetDetailStats(count, types, total, hourly)
  regionFrame.detailStats.count:SetText(count)
  regionFrame.detailStats.types:SetText(types)
  regionFrame.detailStats.total:SetText(total)
  regionFrame.detailStats.hourly:SetText(hourly)
end

RefreshRegionDetails = function()
  local selectedRegion = regionFrame.selectedRegion
  local metrics = selectedRegion and Addon.GetRegionDetailData(selectedRegion)
  local items = (metrics and metrics.totalCount > 0 and metrics.items) or {}

  if #items == 0 then
    SetDetailStats("-", "-", "-", "-")
    regionFrame.clearRegionButton:Disable()
  else
    SetDetailStats(
      tostring(metrics.totalCount),
      tostring(#items),
      FormatCoins(metrics.totalEarn),
      FormatCoins(metrics.estimatedHourlyEarn)
    )
    regionFrame.clearRegionButton:Enable()
  end

  FillDataTable(regionFrame.detailsTable, items, function(row, entry)
    row.item:SetText(entry.itemName)
    row.count:SetText(tostring(entry.count))
    row.percent:SetText(string.format("%.1f%%", entry.catchPercent))
    row.total:SetText(FormatCoins(entry.totalEarn))
    row.hourly:SetText(FormatCoins(entry.estimatedHourlyEarn))
  end)
end

local function RefreshDailyContent()
  FillDataTable(regionFrame.dailyTable, Addon.GetDailyEarnData(), function(row, entry)
    row.date:SetText(entry.dateKey)
    row.count:SetText(tostring(entry.totalCount))
    row.earn:SetText(FormatCoins(entry.totalEarn))
  end)
end

RefreshRegionWindow = function()
  RefreshRegionOverview()
  RefreshRegionDetails()
  RefreshDailyContent()
  SetRegionTab(regionFrame.activeTab or "overview")
end
Addon.RefreshRegionWindow = RefreshRegionWindow

local function ShowRegionOverviewWindow()
  regionFrame.activeTab = "overview"
  RefreshRegionWindow()
  regionFrame:Show()
end

local function ShowCurrentRegionWindow()
  local currentRegion = Addon.GetCurrentFishingRegion()
  SetSelectedRegion(currentRegion)
  regionFrame.activeTab = "details"
  RefreshRegionWindow()
  regionFrame:Show()
end

regionFrame.overviewTab:SetScript("OnClick", function()
  SetRegionTab("overview")
end)

regionFrame.detailsTab:SetScript("OnClick", function()
  RefreshRegionDetails()
  SetRegionTab("details")
end)

regionFrame.dailyTab:SetScript("OnClick", function()
  RefreshDailyContent()
  SetRegionTab("daily")
end)

regionFrame.refreshPriceButton:SetScript("OnClick", function()
  SlashCmdList["FS_RELOADPRICES"]()
end)

regionFrame.clearRegionButton:SetScript("OnClick", function()
  if not regionFrame.selectedRegion then
    return
  end

  StaticPopup_Show("FISHINGSTATS_CONFIRM_CLEAR_REGION", regionFrame.selectedRegion, nil, {
    regionName = regionFrame.selectedRegion,
  })
end)

SetRegionTab("overview")

local overviewButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
overviewButton:SetSize(72, 24)
overviewButton:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, -2)
overviewButton:SetText("Overview")
overviewButton:SetScript("OnClick", ShowRegionOverviewWindow)

local currentRegionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
currentRegionButton:SetSize(72, 24)
currentRegionButton:SetPoint("TOPLEFT", overviewButton, "BOTTOMLEFT", 0, -6)
currentRegionButton:SetText("Region")
currentRegionButton:SetScript("OnClick", ShowCurrentRegionWindow)

local dailyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
dailyButton:SetSize(72, 24)
dailyButton:SetPoint("TOPLEFT", currentRegionButton, "BOTTOMLEFT", 0, -6)
dailyButton:SetText("Daily")
dailyButton:SetScript("OnClick", function()
  regionFrame.activeTab = "daily"
  RefreshRegionWindow()
  regionFrame:Show()
end)

-- Lure macro: click or drag to put the auto-lure macro on the cursor, then
-- drop it on an action bar (see Lure.lua).
local lureButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
lureButton:SetSize(72, 24)
lureButton:SetPoint("TOPLEFT", dailyButton, "BOTTOMLEFT", 0, -6)
lureButton:SetText("Lure")
lureButton:RegisterForDrag("LeftButton")
lureButton:SetScript("OnClick", Addon.PickupLureMacro)
lureButton:SetScript("OnDragStart", Addon.PickupLureMacro)
lureButton:HookScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Lure Macro")
  GameTooltip:AddLine("Drag (or click) to place it on an action bar.", 1, 1, 1)
  GameTooltip:AddLine("Uses the best lure you have:", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("尖刺钉螺 > 扭动的蠕行虫 > 纳特的饮酒帽", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
lureButton:HookScript("OnLeave", GameTooltip_Hide)


-- Records one caught item (fish, ore, junk, misc...) from a fishing catch.
-- `link` is a full item hyperlink so GetItemInfo works even before the item is
-- otherwise cached.
local function RecordFishCatch(regionName, id, link, quantity)
  local itemName
  if Addon.IsTrackedFish(id) then
    itemName = GetItemInfo(link)
  else
    local quality = select(3, GetItemInfo(link))
    itemName = (quality == 0) and "垃圾" or "杂项"
  end
  if not itemName then
    return
  end

  local fishCounts = FishingStatsDB.fishCounts
  -- Misc and junk count as 1; everything else uses the loot quantity
  local count = quantity
  if (itemName == "杂项" or itemName == "垃圾") then
    count = 1
  end
  fishCounts[itemName] = (fishCounts[itemName] or 0) + count
  local price = GetCachedItemPrice(id)
  local totalPrice = price * quantity
  print("Caught: " .. itemName .. "; Total: " .. fishCounts[itemName] .. " Value: " .. GetCoinTextureString(totalPrice))
  FishingStatsDB.earn = FishingStatsDB.earn + totalPrice
  Addon.RecordRegionCatch(regionName, id, itemName, count, totalPrice)
  Addon.RecordDailyEarn(count, totalPrice)
  if regionFrame:IsShown() then
    RefreshRegionWindow()
  end
  RefreshPanel()

  if id == 220152 then
    useBtn:SetAttribute("item", itemName)
    -- Simulate one click to trigger the secure action
    useBtn:Click()
    print("Auto-used:", itemName)
  end
end

-- ------------- Event handling -------------
frame:RegisterEvent("ADDON_LOADED")
-- Loot addons like SpeedyAutoLoot register for both LOOT_READY and LOOT_OPENED and
-- handle whichever fires (see its OnInit) because the client doesn't reliably fire
-- LOOT_OPENED for a quick single-item catch - LOOT_READY is the one that always
-- fires. We do the same, with lootSessionHandled/LOOT_CLOSED guarding against
-- double-processing the same loot session if both events do fire.
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")

local lootSessionHandled = false

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "FishingStats" then
      BuildSettingsPanel()
      print("🎣 FishingStats loaded. Click the minimap fishing icon to view stats.")
    end

  elseif event == "LOOT_CLOSED" then
    lootSessionHandled = false

  elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
    if lootSessionHandled then
      return
    end

    local numItems = GetNumLootItems()
    if numItems == 0 then
      -- Loot data isn't ready yet on this particular event; wait for the next one.
      return
    end

    local fishingLoot = IsFishingLoot and IsFishingLoot()
    DebugPrint(event, "IsFishingLoot=" .. tostring(fishingLoot), "numItems=" .. tostring(numItems))
    lootSessionHandled = true

    if not fishingLoot then
      return
    end

    local regionName = Addon.GetCurrentFishingRegion()
    for i = 1, numItems do
      local link = GetLootSlotLink(i)
      local _, _, quantity = GetLootSlotInfo(i)
      if link then
        local id = tonumber(link:match("item:(%d+):"))
        if id then
          RecordFishCatch(regionName, id, link, quantity)
        end
      end
    end
  end
end)


-- Define the /fs command
SLASH_FS1 = "/fs"

SlashCmdList["FS"] = function(msg)
  -- Ignore any text after /fs and just toggle the panel
  showhide()
end

SLASH_FS_RELOADPRICES1 = "/fsrp"
SlashCmdList["FS_RELOADPRICES"] = function()
  wipe(FishingStatsDB.prices)
  Addon.PreloadFishPrices()
  RefreshPanel()
  if regionFrame:IsShown() then
    RefreshRegionWindow()
  end
end

SLASH_FS_RELOADCOUNTS1 = "/fsr"
SlashCmdList["FS_RELOADCOUNTS"] = function()
  wipe(FishingStatsDB.fishCounts)
  FishingStatsDB.earn = 0
  wipe(FishingStatsDB.prices)
  Addon.PreloadFishPrices()
  RefreshPanel()
end

SLASH_FS_CONFIG1 = "/fsconfig"
SlashCmdList["FS_CONFIG"] = function()
  if Addon.settingsCategory then
    Settings.OpenToCategory(Addon.settingsCategory:GetID())
  end
end

SLASH_FS_DEBUG1 = "/fsdebug"
SlashCmdList["FS_DEBUG"] = function()
  debugEnabled = not debugEnabled
  print("FishingStats debug logging:", debugEnabled and "|cff33ff99ON|r" or "|cffff4444OFF|r")
end

------------------------------------------------------------
-- WoW Settings panel (Interface → AddOns → FishingStats)
------------------------------------------------------------
local PRICE_SOURCES = { "Auctionator", "TSM", "None" }

function BuildSettingsPanel()
  local panel = CreateFrame("Frame")
  panel.name = "FishingStats"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("FishingStats — Price Sources")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetText("Choose which auction-data addons provide item prices.\nPrimary is tried first; Secondary is the fallback.")

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
          or (src == "Auctionator" and Auctionator and Auctionator.API ~= nil)
          or (src == "TSM"         and TSM_API ~= nil)
        local info = UIDropDownMenu_CreateInfo()
        info.text    = available and src or (src .. " |cffff4444(not loaded)|r")
        info.checked = getter() == src
        info.func    = function()
          setter(src)
          UIDropDownMenu_SetText(dd, src)
          wipe(FishingStatsDB.prices)
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    UIDropDownMenu_SetText(dd, getter())
    return dd
  end

  MakeDropdown(
    panel, "Primary Price Source:", -72,
    function() return (FishingStatsDB.config or {}).primarySource or "Auctionator" end,
    function(v) FishingStatsDB.config.primarySource = v end
  )

  MakeDropdown(
    panel, "Secondary Price Source (fallback):", -140,
    function() return (FishingStatsDB.config or {}).secondarySource or "TSM" end,
    function(v) FishingStatsDB.config.secondarySource = v end
  )

  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  Addon.settingsCategory = category
end

------------------------------------------------------------
-- ElvUI skin
-- If ElvUI is loaded, re-skin our frames with ElvUI's own skin API so they
-- follow the user's ElvUI theme (colors, border style, pixel mode).
-- Without ElvUI the flat backdrop from ApplyFlatBackdrop() is kept.
------------------------------------------------------------
local function ApplyElvUISkin()
  if regionFrame.elvSkinned or not ElvUI then return end
  local E = unpack(ElvUI)
  local S = E and E.Skins
  if not (S and E.media and E.media.rgbvaluecolor and S.HandleButton) then return end

  local function HandleScrollFrame(sf)
    local bar = sf.ScrollBar or (sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    if bar then S:HandleScrollBar(bar) end
  end

  -- Windows
  frame:SetTemplate("Transparent")
  regionFrame:SetTemplate("Transparent")
  frame.title:SetTextColor(unpack(E.media.rgbvaluecolor))
  regionFrame.title:SetTextColor(unpack(E.media.rgbvaluecolor))
  S:HandleCloseButton(regionFrame.closeButton)

  -- Buttons
  for _, b in ipairs({
    regionFrame.overviewTab, regionFrame.detailsTab, regionFrame.dailyTab,
    regionFrame.refreshPriceButton, regionFrame.clearRegionButton,
    overviewButton, currentRegionButton, dailyButton, lureButton,
  }) do
    S:HandleButton(b)
  end

  -- Dropdown & scroll bars
  S:HandleDropDownBox(regionFrame.dropdown, 200, nil, true)
  HandleScrollFrame(fishScrollFrame)
  HandleScrollFrame(regionFrame.overviewScrollFrame)
  HandleScrollFrame(regionFrame.detailsScrollFrame)
  HandleScrollFrame(regionFrame.dailyScrollFrame)

  -- Active-tab highlight (see SetRegionTab). ElvUI resets the border color
  -- on mouse leave, so re-apply our highlight after its OnLeave hook.
  regionFrame.elvAccentColor = { unpack(E.media.rgbvaluecolor) }
  regionFrame.elvBorderColor = { unpack(E.media.bordercolor) }
  regionFrame.elvSkinned = true
  for _, tab in ipairs({ regionFrame.overviewTab, regionFrame.detailsTab, regionFrame.dailyTab }) do
    tab:HookScript("OnLeave", function() SetRegionTab(regionFrame.activeTab) end)
  end
  SetRegionTab(regionFrame.activeTab or "overview")
end

local skinFrame = CreateFrame("Frame")
skinFrame:RegisterEvent("PLAYER_LOGIN")
skinFrame:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  -- Wait one frame so ElvUI has finished its own PLAYER_LOGIN initialization.
  C_Timer.After(0, function()
    local ok, err = pcall(ApplyElvUISkin)
    if not ok then DebugPrint("ElvUI skin failed:", err) end
  end)
end)
