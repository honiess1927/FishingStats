--[[
  FishingStats.lua
  Pure Lua fishing stats addon
--]]

-- ------------- Configuration -------------
local name, Addon = ...
local FISH_SPELL_ID = 131474                       -- Base fishing skill spell ID

local isFishing = false

-- ------------- UI -------------
-- Main panel
local frame = CreateFrame("Frame", "FishingStatsFrame", UIParent, "BackdropTemplate")
frame:SetSize(150, 300)
frame:SetPoint("CENTER")
frame:SetBackdrop({
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true, tileSize = 32, edgeSize = 32,
  insets   = { left=10, right=10, top=10, bottom=10 },
})
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

-- Static FontString rows used to display totals
local maxLines = 15
local lineHeight = 16
local lines = {}
for i = 1, maxLines do
  local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, - (20 + (i-1)*lineHeight))
  fs:SetText("Hello")    -- Initial placeholder
  lines[i] = fs
end

-- Create buttons
-- ... after the frame has been created ...
------------------------------------------------------------
-- Swappable buff item list
------------------------------------------------------------
local buffItemIDs = {117405, 133755, 88535, 241148}
local MAX_COL = 4              -- Up to 4 buttons per row
local BTN_SIZE = 28
local BTN_PADDING = 4
local FormatCoins
local FormatGoldOnlyCoins
  
  -------- REFRESH PANEL -----
local function RefreshPanel()
  local fishCounts = FishingStatsDB.fishCounts
  local currentRegionName = Addon.GetCurrentFishingRegion()
  local currentRegionMetrics = Addon.GetRegionDetailData(currentRegionName)
  -- Clear previous content
  for i = 1, maxLines do
    lines[i]:SetText("")
  end

  -- Header
  lines[1]:SetText(" Fishing Stats (Total)")
  local total, max, bonus = Addon.GetFishingSkillBonus()
  lines[2]:SetText(string.format("Fishing Skill: %d (+%d)", total, bonus))

  lines[3]:SetText(string.format("%s Hourly: %s", currentRegionMetrics.regionName, FormatGoldOnlyCoins(currentRegionMetrics.estimatedHourlyEarn)))
  lines[4]:SetText(string.format("Total Earn: %s", GetCoinTextureString(FishingStatsDB.earn)))



  -- Populate rows
  local row = 5
  -- Sort by count
  local sortedFish = {}
  local totalCount = 0
  for name, count in pairs(fishCounts) do
    table.insert(sortedFish, {name = name, count = count})
    totalCount = totalCount + count
  end
  table.sort(sortedFish, function(a, b) return a.count > b.count end)
  for _, fish in ipairs(sortedFish) do
    if row > maxLines then break end
    lines[row]:SetText( string.format("%-20s  × %3d    %d%%", fish.name, fish.count, fish.count / totalCount * 100) )
    row = row + 1
  end

  -- Show an empty-state message if needed
  if row == 5 then
    lines[5]:SetText("|cffff0000No data yet|r")
  end

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
regionFrame:SetBackdrop({
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true, tileSize = 32, edgeSize = 32,
  insets   = { left=10, right=10, top=10, bottom=10 },
})
regionFrame:EnableMouse(true)
regionFrame:SetMovable(true)
regionFrame:RegisterForDrag("LeftButton")
regionFrame:SetScript("OnDragStart", regionFrame.StartMoving)
regionFrame:SetScript("OnDragStop", regionFrame.StopMovingOrSizing)
regionFrame:Hide()
regionFrame.activeTab = "overview"
regionFrame.selectedRegion = nil

table.insert(UISpecialFrames, "FishingStatsRegionFrame")

regionFrame.title = regionFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
regionFrame.title:SetPoint("TOP", regionFrame, "TOP", 0, -18)
regionFrame.title:SetText("Region Earnings")

regionFrame.closeButton = CreateFrame("Button", nil, regionFrame, "UIPanelCloseButton")
regionFrame.closeButton:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", -5, -5)

regionFrame.overviewTab = CreateFrame("Button", nil, regionFrame, "UIPanelButtonTemplate")
regionFrame.overviewTab:SetSize(110, 24)
regionFrame.overviewTab:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", 18, -48)
regionFrame.overviewTab:SetText("Overview")

regionFrame.detailsTab = CreateFrame("Button", nil, regionFrame, "UIPanelButtonTemplate")
regionFrame.detailsTab:SetSize(110, 24)
regionFrame.detailsTab:SetPoint("LEFT", regionFrame.overviewTab, "RIGHT", 8, 0)
regionFrame.detailsTab:SetText("Details")

regionFrame.refreshPriceButton = CreateFrame("Button", nil, regionFrame, "UIPanelButtonTemplate")
regionFrame.refreshPriceButton:SetSize(100, 24)
regionFrame.refreshPriceButton:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", -34, -48)
regionFrame.refreshPriceButton:SetText("Refresh Price")

regionFrame.overviewContent = CreateFrame("Frame", nil, regionFrame)
regionFrame.overviewContent:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", 18, -82)
regionFrame.overviewContent:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", -18, 18)

regionFrame.detailsContent = CreateFrame("Frame", nil, regionFrame)
regionFrame.detailsContent:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", 18, -82)
regionFrame.detailsContent:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", -18, 18)
regionFrame.regionOptions = {}

regionFrame.overviewHeaders = {}
local overviewHeaderConfig = {
  { key = "region", text = "Region", x = 0 },
  { key = "count", text = "Catches", x = 120 },
  { key = "total", text = "Total Earn", x = 200 },
  { key = "hourly", text = "Hourly Earn", x = 325 },
}

for _, column in ipairs(overviewHeaderConfig) do
  local header = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", column.x, 0)
  header:SetText(column.text)
  regionFrame.overviewHeaders[column.key] = header
end

regionFrame.overviewRows = {}
for i = 1, 12 do
  local row = {}
  row.region = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.region:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", 0, -(20 + (i - 1) * 22))
  row.count = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.count:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", 120, -(20 + (i - 1) * 22))
  row.total = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.total:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", 200, -(20 + (i - 1) * 22))
  row.hourly = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.hourly:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", 325, -(20 + (i - 1) * 22))
  regionFrame.overviewRows[i] = row
end

regionFrame.overviewEmptyText = regionFrame.overviewContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
regionFrame.overviewEmptyText:SetPoint("TOPLEFT", regionFrame.overviewContent, "TOPLEFT", 0, -28)
regionFrame.overviewEmptyText:SetText("No regional data recorded yet.")

regionFrame.detailsTitle = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
regionFrame.detailsTitle:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, 0)
regionFrame.detailsTitle:SetText("Region Details")

regionFrame.dropdownLabel = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
regionFrame.dropdownLabel:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -28)
regionFrame.dropdownLabel:SetText("Select Region")

regionFrame.dropdown = CreateFrame("Frame", "FishingStatsRegionDropdown", regionFrame.detailsContent, "UIDropDownMenuTemplate")
regionFrame.dropdown:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", -16, -42)

regionFrame.clearRegionButton = CreateFrame("Button", nil, regionFrame.detailsContent, "UIPanelButtonTemplate")
regionFrame.clearRegionButton:SetSize(100, 22)
regionFrame.clearRegionButton:SetPoint("TOPRIGHT", regionFrame.detailsContent, "TOPRIGHT", -6, -34)
regionFrame.clearRegionButton:SetText("Clear Region")

regionFrame.detailsSummary = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
regionFrame.detailsSummary:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -78)
regionFrame.detailsSummary:SetJustifyH("LEFT")

regionFrame.detailsHeaders = {}
local detailsHeaderConfig = {
  { key = "item", text = "Item", x = 0 },
  { key = "count", text = "Count", x = 100 },
  { key = "percent", text = "%", x = 150 },
  { key = "total", text = "Total Earn", x = 220 },
  { key = "hourly", text = "Hourly Earn", x = 305 },
}

for _, column in ipairs(detailsHeaderConfig) do
  local header = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", column.x, -98)
  header:SetText(column.text)
  regionFrame.detailsHeaders[column.key] = header
end

regionFrame.detailsScrollFrame = CreateFrame("ScrollFrame", "FishingStatsRegionDetailsScrollFrame", regionFrame.detailsContent, "UIPanelScrollFrameTemplate")
regionFrame.detailsScrollFrame:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -116)
regionFrame.detailsScrollFrame:SetPoint("BOTTOMRIGHT", regionFrame.detailsContent, "BOTTOMRIGHT", -28, 6)

regionFrame.detailsScrollChild = CreateFrame("Frame", nil, regionFrame.detailsScrollFrame)
regionFrame.detailsScrollChild:SetSize(430, 1)
regionFrame.detailsScrollFrame:SetScrollChild(regionFrame.detailsScrollChild)

regionFrame.detailRows = {}

local function EnsureDetailRows(count)
  for i = #regionFrame.detailRows + 1, count do
    local row = {}
    local yOffset = -((i - 1) * 20)
    row.item = regionFrame.detailsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.item:SetPoint("TOPLEFT", regionFrame.detailsScrollChild, "TOPLEFT", 0, yOffset)
    row.count = regionFrame.detailsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.count:SetPoint("TOPLEFT", regionFrame.detailsScrollChild, "TOPLEFT", 100, yOffset)
    row.percent = regionFrame.detailsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.percent:SetPoint("TOPLEFT", regionFrame.detailsScrollChild, "TOPLEFT", 150, yOffset)
    row.total = regionFrame.detailsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.total:SetPoint("TOPLEFT", regionFrame.detailsScrollChild, "TOPLEFT", 220, yOffset)
    row.hourly = regionFrame.detailsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.hourly:SetPoint("TOPLEFT", regionFrame.detailsScrollChild, "TOPLEFT", 305, yOffset)
    regionFrame.detailRows[i] = row
  end
end

regionFrame.detailsEmptyText = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
regionFrame.detailsEmptyText:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -78)
regionFrame.detailsEmptyText:SetText("No regional data recorded yet.")

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

  if tabName == "overview" then
    regionFrame.overviewContent:Show()
    regionFrame.detailsContent:Hide()
    regionFrame.overviewTab:Disable()
    regionFrame.detailsTab:Enable()
  else
    regionFrame.overviewContent:Hide()
    regionFrame.detailsContent:Show()
    regionFrame.overviewTab:Enable()
    regionFrame.detailsTab:Disable()
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

  for _, row in ipairs(regionFrame.overviewRows) do
    row.region:SetText("")
    row.count:SetText("")
    row.total:SetText("")
    row.hourly:SetText("")
  end

  if #overviewData == 0 then
    regionFrame.overviewEmptyText:Show()
    return
  end

  regionFrame.overviewEmptyText:Hide()

  for i, entry in ipairs(overviewData) do
    local row = regionFrame.overviewRows[i]
    if not row then
      break
    end

    row.region:SetText(entry.regionName)
    row.count:SetText(tostring(entry.totalCount))
    row.total:SetText(FormatCoins(entry.totalEarn))
    row.hourly:SetText(FormatCoins(entry.estimatedHourlyEarn))
  end
end

RefreshRegionDetails = function()
  local selectedRegion = regionFrame.selectedRegion

  for _, row in ipairs(regionFrame.detailRows) do
    row.item:SetText("")
    row.count:SetText("")
    row.percent:SetText("")
    row.total:SetText("")
    row.hourly:SetText("")
  end
  regionFrame.detailsScrollFrame:SetVerticalScroll(0)

  if not selectedRegion then
    regionFrame.detailsEmptyText:Show()
    regionFrame.detailsSummary:Hide()
    regionFrame.detailsScrollFrame:Hide()
    regionFrame.detailsTitle:SetText("Region Details")
    regionFrame.clearRegionButton:Disable()
    return
  end

  local metrics = Addon.GetRegionDetailData(selectedRegion)
  if not metrics or metrics.totalCount == 0 then
    regionFrame.detailsEmptyText:Show()
    regionFrame.detailsSummary:Hide()
    regionFrame.detailsScrollFrame:Hide()
    regionFrame.detailsTitle:SetText(selectedRegion)
    regionFrame.clearRegionButton:Disable()
    return
  end

  regionFrame.detailsEmptyText:Hide()
  regionFrame.detailsSummary:Show()
  regionFrame.detailsScrollFrame:Show()
  regionFrame.detailsTitle:SetText(metrics.regionName)
  regionFrame.clearRegionButton:Enable()
  regionFrame.detailsSummary:SetText(string.format(
    "Catches: %d   Item Types: %d   Total Earn: %s   Hourly Earn: %s",
    metrics.totalCount,
    #(metrics.items or {}),
    FormatCoins(metrics.totalEarn),
    FormatCoins(metrics.estimatedHourlyEarn)
  ))

  EnsureDetailRows(#(metrics.items or {}))
  regionFrame.detailsScrollChild:SetHeight(math.max(1, #(metrics.items or {}) * 20))

  for i, entry in ipairs(metrics.items or {}) do
    local row = regionFrame.detailRows[i]

    row.item:SetText(entry.itemName)
    row.count:SetText(tostring(entry.count))
    row.percent:SetText(string.format("%.1f%%", entry.catchPercent))
    row.total:SetText(FormatCoins(entry.totalEarn))
    row.hourly:SetText(FormatCoins(entry.estimatedHourlyEarn))
  end
end

RefreshRegionWindow = function()
  RefreshRegionOverview()
  RefreshRegionDetails()
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

------------------------------------------------------------
-- Daily Earnings window
------------------------------------------------------------
local dailyFrame = CreateFrame("Frame", "FishingStatsDailyFrame", UIParent, "BackdropTemplate")
dailyFrame:SetSize(380, 360)
dailyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
dailyFrame:SetBackdrop({
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true, tileSize = 32, edgeSize = 32,
  insets   = { left=10, right=10, top=10, bottom=10 },
})
dailyFrame:EnableMouse(true)
dailyFrame:SetMovable(true)
dailyFrame:RegisterForDrag("LeftButton")
dailyFrame:SetScript("OnDragStart", dailyFrame.StartMoving)
dailyFrame:SetScript("OnDragStop", dailyFrame.StopMovingOrSizing)
dailyFrame:Hide()

table.insert(UISpecialFrames, "FishingStatsDailyFrame")

dailyFrame.title = dailyFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
dailyFrame.title:SetPoint("TOP", dailyFrame, "TOP", 0, -18)
dailyFrame.title:SetText("Daily Earnings")

dailyFrame.closeButton = CreateFrame("Button", nil, dailyFrame, "UIPanelCloseButton")
dailyFrame.closeButton:SetPoint("TOPRIGHT", dailyFrame, "TOPRIGHT", -5, -5)

local dailyContent = CreateFrame("Frame", nil, dailyFrame)
dailyContent:SetPoint("TOPLEFT",     dailyFrame, "TOPLEFT",     18, -48)
dailyContent:SetPoint("BOTTOMRIGHT", dailyFrame, "BOTTOMRIGHT", -18, 18)

local dailyHeaderConfig = {
  { key = "date",  text = "Date",       x = 0   },
  { key = "count", text = "Catches",    x = 140  },
  { key = "earn",  text = "Total Earn", x = 210 },
}
dailyFrame.dailyHeaders = {}
for _, col in ipairs(dailyHeaderConfig) do
  local h = dailyContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  h:SetPoint("TOPLEFT", dailyContent, "TOPLEFT", col.x, 0)
  h:SetText(col.text)
  dailyFrame.dailyHeaders[col.key] = h
end

dailyFrame.scrollFrame = CreateFrame("ScrollFrame", "FishingStatsDailyScrollFrame", dailyContent, "UIPanelScrollFrameTemplate")
dailyFrame.scrollFrame:SetPoint("TOPLEFT",     dailyContent, "TOPLEFT",     0,   -20)
dailyFrame.scrollFrame:SetPoint("BOTTOMRIGHT", dailyContent, "BOTTOMRIGHT", -28,  6)

dailyFrame.scrollChild = CreateFrame("Frame", nil, dailyFrame.scrollFrame)
dailyFrame.scrollChild:SetSize(310, 1)
dailyFrame.scrollFrame:SetScrollChild(dailyFrame.scrollChild)

dailyFrame.rows = {}

local function EnsureDailyRows(count)
  for i = #dailyFrame.rows + 1, count do
    local yOffset = -((i - 1) * 20)
    local row = {}
    row.date  = dailyFrame.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.date:SetPoint("TOPLEFT", dailyFrame.scrollChild, "TOPLEFT", 0, yOffset)
    row.count = dailyFrame.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.count:SetPoint("TOPLEFT", dailyFrame.scrollChild, "TOPLEFT", 140, yOffset)
    row.earn  = dailyFrame.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.earn:SetPoint("TOPLEFT", dailyFrame.scrollChild, "TOPLEFT", 210, yOffset)
    dailyFrame.rows[i] = row
  end
end

dailyFrame.emptyText = dailyContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
dailyFrame.emptyText:SetPoint("TOPLEFT", dailyContent, "TOPLEFT", 0, -28)
dailyFrame.emptyText:SetText("No daily data recorded yet.")

local function RefreshDailyWindow()
  local data = Addon.GetDailyEarnData()

  for _, row in ipairs(dailyFrame.rows) do
    row.date:SetText("")
    row.count:SetText("")
    row.earn:SetText("")
  end
  dailyFrame.scrollFrame:SetVerticalScroll(0)

  if #data == 0 then
    dailyFrame.emptyText:Show()
    dailyFrame.scrollFrame:Hide()
    return
  end

  dailyFrame.emptyText:Hide()
  dailyFrame.scrollFrame:Show()

  EnsureDailyRows(#data)
  dailyFrame.scrollChild:SetHeight(math.max(1, #data * 20))

  for i, entry in ipairs(data) do
    local row = dailyFrame.rows[i]
    row.date:SetText(entry.dateKey)
    row.count:SetText(tostring(entry.totalCount))
    row.earn:SetText(FormatCoins(entry.totalEarn))
  end
end

local dailyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
dailyButton:SetSize(72, 24)
dailyButton:SetPoint("TOPLEFT", currentRegionButton, "BOTTOMLEFT", 0, -6)
dailyButton:SetText("Daily")
dailyButton:SetScript("OnClick", function()
  if dailyFrame:IsShown() then
    dailyFrame:Hide()
  else
    RefreshDailyWindow()
    dailyFrame:Show()
  end
end)


-- ------------- Event handling -------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("LOOT_OPENED")

frame:SetScript("OnEvent", function(self, event, ...)
  local fishCounts = FishingStatsDB.fishCounts  
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "FishingStats" then
      BuildSettingsPanel()
      print("🎣 FishingStats loaded. Click the minimap fishing icon to view stats.")
    end

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" and spellID == FISH_SPELL_ID then
      isFishing = true

    elseif event == "LOOT_OPENED" and isFishing then
      -- This branch is unreachable because event is already UNIT_SPELLCAST_SUCCEEDED
    end

  elseif event == "LOOT_OPENED" and isFishing then
    local regionName = Addon.GetCurrentFishingRegion()
    local n = GetNumLootItems()
    for i = 1, n do
      local icon, name, quantity, _, quality = GetLootSlotInfo(i)
      local link = GetLootSlotLink(i)
      if link then
        local id = tonumber(link:match("item:(%d+):"))
        local name
        if Addon.IsTrackedFish(id) then
          name = GetItemInfo(link)
        else
          if quality == 0 then
              name = "垃圾"
          else
              name = "杂项"
          end
        end
        if name then
          -- Misc and junk count as 1; everything else uses the loot quantity
          local count = quantity
          if (name == "杂项" or name == "垃圾") then
            count = 1
          end
          fishCounts[name] = (fishCounts[name] or 0) + count
          local price = GetCachedItemPrice(id)
          local totalPrice = price * quantity
          print("Caught: " .. name .. "; Total: " .. fishCounts[name] .. " Value: " .. GetCoinTextureString(totalPrice))
          FishingStatsDB.earn = FishingStatsDB.earn + totalPrice
          Addon.RecordRegionCatch(regionName, id, name, count, totalPrice)
          Addon.RecordDailyEarn(count, totalPrice)
          if regionFrame:IsShown() then
            RefreshRegionWindow()
          end
          RefreshPanel()
        end
        if id == 220152 then
          if name then
            useBtn:SetAttribute("item", name)
            -- Simulate one click to trigger the secure action
            useBtn:Click()
            print("Auto-used:", name)
          end
        end
      end
    end
    isFishing = false
  end
end)

------------------------------------------------------------
-- Buff button creation
------------------------------------------------------------
frame.buffButtons = {}

for idx, itemID in ipairs(buffItemIDs) do
  --------------------------------------------------------
  -- Position: row and column
  --------------------------------------------------------
  local row = math.floor((idx-1) / MAX_COL)    -- 0,1,2…
  local col = (idx-1) % MAX_COL                -- 0 ~ 3
  local x = 10 + col * (BTN_SIZE + BTN_PADDING)
  local y = 10 + row * (BTN_SIZE + BTN_PADDING)

  --------------------------------------------------------
  -- SecureActionButton
  --------------------------------------------------------
  local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
  local btn = CreateFrame("Button",
                          "FishingStatsBuffBtn"..itemID,
                          frame,
                          "SecureActionButtonTemplate")
  btn:SetSize(BTN_SIZE, BTN_SIZE)
  btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)

  name = name or tostring(itemID)
  btn:SetAttribute("type", "item")
  btn:SetAttribute("item", name)
  btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

  --------------------------------------------------------
  -- Background icon
  --------------------------------------------------------
  btn.icon = btn:CreateTexture(nil, "BACKGROUND")
  btn.icon:SetAllPoints(btn)
  if icon then btn.icon:SetTexture(icon) end

  --------------------------------------------------------
  -- Bottom-right count text
  --------------------------------------------------------
  btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
  btn.count:SetText("")           -- Hidden by default

  --------------------------------------------------------
  -- Tooltip
  --------------------------------------------------------
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)

  frame.buffButtons[itemID] = btn
end

-- Refresh counts: show numbers only when quantity > 1
------------------------------------------------------------
local function RefreshBuffCounts()
  for itemID, btn in pairs(frame.buffButtons) do
    local qty = GetItemCount(itemID, true)
    if qty and qty > 1 then
      btn.count:SetText(qty)
      btn.count:Show()
    else
      btn.count:Hide()
    end
  end
end

-- Event-driven refresh
------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")   -- Batch refresh after bag changes
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", RefreshBuffCounts)


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
