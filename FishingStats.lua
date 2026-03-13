--[[
  FishingStats.lua
  Pure Lua 版钓鱼统计插件
--]]

-- ------------- 配置区 -------------
local name, Addon = ...
local FISH_SPELL_ID = 131474                       -- 普通钓鱼技能 ID

local isFishing = false

-- ------------- UI 部分 -------------
-- 主面板
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

-- 2) 静态 FontString 列表，用来显示总计
local maxLines = 15
local lineHeight = 16
local lines = {}
for i = 1, maxLines do
  local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, - (20 + (i-1)*lineHeight))
  fs:SetText("Hello")    -- 初始为空
  lines[i] = fs
end

-- 创建按钮
-- … 在 frame 已创建之后 …
------------------------------------------------------------
-- 可换 Buff 物品清单
------------------------------------------------------------
local buffItemIDs = {117405, 133755, 88535, 241148}
local MAX_COL = 4              -- 每行最多 4 个
local BTN_SIZE = 28
local BTN_PADDING = 4
  
  -------- REFRESH PANEL -----
local function RefreshPanel()
  local fishCounts = FishingStatsDB.fishCounts
  -- 清空旧内容
  for i = 1, maxLines do
    lines[i]:SetText("")
  end

  -- 写入标题
  lines[1]:SetText(" 钓鱼统计（总计）")
  local total, max, bonus = Addon.GetFishingSkillBonus()
  lines[2]:SetText(string.format("钓鱼技能：%d（+%d）", total, bonus))
  
  lines[3]:SetText(GetCoinTextureString(FishingStatsDB.earn))



  -- 按行写入数据
  local row = 4
  -- 按数量排序
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

  -- 如果没有数据，提示一条
  if row == 2 then
    lines[2]:SetText("|cffff0000尚无数据|r")
  end

  frame:Show()
end


local function showhide()
  if frame:IsShown() then
    frame:Hide()
  else
    -- 刷新内容
    RefreshPanel()
    Addon.PreloadFishPrices()
    frame:Show()
  end
end

-- 小地图按钮
local btn = CreateFrame("Button", "FishingStatsMinimapButton", Minimap, "SecureActionButtonTemplate")
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM")
btn:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -10, -10)
btn:SetNormalTexture("Interface\\Icons\\inv_fishingpole_02")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:SetScript("OnClick", showhide)


-- ① 创建 Secure Button（只需做一次）
local useBtn = CreateFrame("Button", "FishingStatsUseButton", UIParent, "SecureActionButtonTemplate")
useBtn:SetAttribute("type", "item")

local function FormatCoins(value)
  local amount = math.floor((value or 0) + 0.5)
  return GetCoinTextureString(amount)
end

local function GetCachedItemPrice(itemID)
  if not itemID then
    return 0
  end

  if priceCache[itemID] then
    return priceCache[itemID]
  end

  if Auctionator and Auctionator.API and Auctionator.API.v1 then
    local price = Auctionator.API.v1.GetAuctionPriceByItemID(name, itemID)
    if price then
      priceCache[itemID] = price
      return price
    end
  end

  return 0
end

local function LogRegionCatch(regionName, itemName)
  local metrics = Addon.GetRegionDetailData(regionName)
  local itemMetrics = nil

  for _, entry in ipairs(metrics.items or {}) do
    if entry.itemName == itemName then
      itemMetrics = entry
      break
    end
  end

  print("[FishingStats][Region] 区域：" .. metrics.regionName .. "；区域累计：" .. metrics.totalCount .. "；区域总收益：" .. FormatCoins(metrics.totalEarn) .. "；区域时薪：" .. FormatCoins(metrics.estimatedHourlyEarn))

  if itemMetrics then
    print(string.format("[FishingStats][Region] 条目：%s；数量：%d；占比：%.1f%%；条目总收益：%s；条目时薪：%s", itemMetrics.itemName, itemMetrics.count, itemMetrics.catchPercent, FormatCoins(itemMetrics.totalEarn), FormatCoins(itemMetrics.estimatedHourlyEarn)))
  end
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

regionFrame.detailsSummary = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
regionFrame.detailsSummary:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -78)
regionFrame.detailsSummary:SetJustifyH("LEFT")

regionFrame.detailsHeaders = {}
local detailsHeaderConfig = {
  { key = "item", text = "Item", x = 0 },
  { key = "count", text = "Count", x = 120 },
  { key = "percent", text = "%", x = 205 },
  { key = "total", text = "Total Earn", x = 260 },
  { key = "hourly", text = "Hourly Earn", x = 345 },
}

for _, column in ipairs(detailsHeaderConfig) do
  local header = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", column.x, -98)
  header:SetText(column.text)
  regionFrame.detailsHeaders[column.key] = header
end

regionFrame.detailRows = {}
for i = 1, 10 do
  local row = {}
  local yOffset = -(120 + (i - 1) * 20)
  row.item = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.item:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, yOffset)
  row.count = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.count:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 120, yOffset)
  row.percent = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.percent:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 205, yOffset)
  row.total = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.total:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 260, yOffset)
  row.hourly = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.hourly:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 345, yOffset)
  regionFrame.detailRows[i] = row
end

regionFrame.detailsEmptyText = regionFrame.detailsContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
regionFrame.detailsEmptyText:SetPoint("TOPLEFT", regionFrame.detailsContent, "TOPLEFT", 0, -78)
regionFrame.detailsEmptyText:SetText("No regional data recorded yet.")

local function SetSelectedRegion(regionName)
  regionFrame.selectedRegion = regionName
  UIDropDownMenu_SetText(regionFrame.dropdown, regionName or "Select Region")
end

local RefreshRegionDetails

UIDropDownMenu_SetWidth(regionFrame.dropdown, 180)
UIDropDownMenu_Initialize(regionFrame.dropdown, function(self, level)
  for _, regionName in ipairs(regionFrame.regionOptions) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = regionName
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
  local selectedRegionIsValid = false

  wipe(regionFrame.regionOptions)
  for _, entry in ipairs(overviewData) do
    table.insert(regionFrame.regionOptions, entry.regionName)
    if entry.regionName == regionFrame.selectedRegion then
      selectedRegionIsValid = true
    end
  end

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

  if not selectedRegion then
    regionFrame.detailsEmptyText:Show()
    regionFrame.detailsSummary:Hide()
    return
  end

  local metrics = Addon.GetRegionDetailData(selectedRegion)
  if not metrics or metrics.totalCount == 0 then
    regionFrame.detailsEmptyText:Show()
    regionFrame.detailsSummary:Hide()
    return
  end

  regionFrame.detailsEmptyText:Hide()
  regionFrame.detailsSummary:Show()
  regionFrame.detailsSummary:SetText(string.format(
    "Region: %s   Catches: %d   Item Types: %d   Total Earn: %s   Hourly Earn: %s",
    metrics.regionName,
    metrics.totalCount,
    #(metrics.items or {}),
    FormatCoins(metrics.totalEarn),
    FormatCoins(metrics.estimatedHourlyEarn)
  ))

  for i, entry in ipairs(metrics.items or {}) do
    local row = regionFrame.detailRows[i]
    if not row then
      break
    end

    row.item:SetText(entry.itemName)
    row.count:SetText(tostring(entry.count))
    row.percent:SetText(string.format("%.1f%%", entry.catchPercent))
    row.total:SetText(FormatCoins(entry.totalEarn))
    row.hourly:SetText(FormatCoins(entry.estimatedHourlyEarn))
  end
end

local function RefreshRegionWindow()
  RefreshRegionOverview()
  RefreshRegionDetails()
  SetRegionTab(regionFrame.activeTab or "overview")
end

local function ShowRegionWindow()
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

SetRegionTab("overview")

local regionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
regionButton:SetSize(72, 24)
regionButton:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -18)
regionButton:SetText("Regions")
regionButton:SetScript("OnClick", ShowRegionWindow)


-- ------------- 事件处理 -------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("LOOT_OPENED")

frame:SetScript("OnEvent", function(self, event, ...)
  local fishCounts = FishingStatsDB.fishCounts  
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "FishingStats" then
      print("🎣 FishingStats 已加载，点击小地图钓鱼图标查看统计。")
    end

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" and spellID == FISH_SPELL_ID then
      isFishing = true

    elseif event == "LOOT_OPENED" and isFishing then
      -- 这段不会走到，因为 event 已经是 UNIT_SPELLCAST_SUCCEEDED
    end

  elseif event == "LOOT_OPENED" and isFishing then
    local regionName = Addon.GetCurrentFishingRegion()
    print("[FishingStats][Region] 本次钓鱼区域：" .. regionName)
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
          -- 如果是 杂项 或者垃圾，count 累加 1， 否则累加 quantity    
          local count = quantity
          if (name == "杂项" or name == "垃圾") then
            count = 1
          end
          fishCounts[name] = (fishCounts[name] or 0) + count
          local price = GetCachedItemPrice(id)
          local totalPrice = price * quantity
          print("钓到：" .. name .. "；累计：" .. fishCounts[name] .. " 价值: " .. GetCoinTextureString(totalPrice))
          FishingStatsDB.earn = FishingStatsDB.earn + totalPrice
          Addon.RecordRegionCatch(regionName, id, name, count, totalPrice)
          LogRegionCatch(regionName, name)
          if regionFrame:IsShown() then
            RefreshRegionWindow()
          end
          RefreshPanel()
        end
        if id == 220152 then
          if name then
            useBtn:SetAttribute("item", name)
            -- 下面这行模拟一次点击，触发 secure action
            useBtn:Click()
            print("自动使用：", name)
          end
        end
      end
    end
    isFishing = false
  end
end)

------------------------------------------------------------
-- 按钮创建
------------------------------------------------------------
frame.buffButtons = {}

for idx, itemID in ipairs(buffItemIDs) do
  --------------------------------------------------------
  -- 位置信息：行、列
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
  -- 背景图标
  --------------------------------------------------------
  btn.icon = btn:CreateTexture(nil, "BACKGROUND")
  btn.icon:SetAllPoints(btn)
  if icon then btn.icon:SetTexture(icon) end

  --------------------------------------------------------
  -- 右下角数量文字
  --------------------------------------------------------
  btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
  btn.count:SetText("")           -- 默认隐藏

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

------------------------------------------------------------
-- 刷新数量：>1 时显示数字，否则隐藏
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

------------------------------------------------------------
-- 事件驱动刷新
------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")   -- 背包变动后批量刷新
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", RefreshBuffCounts)


-- 定义 /fs 命令
SLASH_FS1 = "/fs"

SlashCmdList["FS"] = function(msg)
  -- msg 是 /fs 后面可能带的文本参数，这里我们忽略它，直接切换面板
  showhide()
end

SLASH_FS_RELOADPRICES1 = "/fsrp"
SlashCmdList["FS_RELOADPRICES"] = function()
  wipe(FishingStatsDB.prices)
  Addon.PreloadFishPrices()
end

SLASH_FS_RELOADCOUNTS1 = "/fsr"
SlashCmdList["FS_RELOADCOUNTS"] = function()
  wipe(FishingStatsDB.fishCounts)
  FishingStatsDB.earn = 0
  wipe(FishingStatsDB.prices)
  Addon.PreloadFishPrices()
  RefreshPanel()
end

