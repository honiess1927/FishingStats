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