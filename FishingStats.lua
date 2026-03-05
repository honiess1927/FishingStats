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
local buffItemIDs = {117405, 221790, 88535}
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
          fishCounts[name] = (fishCounts[name] or 0) + (name == "杂项" or name == "垃圾" and 1 or quantity)
          local price = priceCache[id] or Auctionator.API.v1.GetAuctionPriceByItemID(name, id) or 0
          local totalPrice = price * quantity
          print("钓到：" .. name .. "；累计：" .. fishCounts[name] .. " 价值: " .. GetCoinTextureString(totalPrice))
          FishingStatsDB.earn = FishingStatsDB.earn + totalPrice
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

