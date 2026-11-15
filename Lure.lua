--[[
  Lure.lua
  Maintains a general macro ("FS Lure") that always uses the highest-priority
  fishing lure currently available (in bags or equipped). The macro body is
  rewritten whenever bags or equipment change, so the same macro can sit on an
  action bar permanently.
--]]

local _, Addon = ...

-- Priority order: first available wins.
local LURE_PRIORITY = {
  262651, -- 尖刺钉螺
  262650, -- 扭动的蠕行虫
  117405, -- 纳特的饮酒帽 (head item, usually equipped)
}

-- All lures (including the hat) are applied to the fishing pole: after /use
-- the client asks for a target item, so the macro follows up with /use on
-- the pole slot.
local FISHING_POLE_SLOT = 28 -- profession tool slot holding the fishing pole

local MACRO_NAME = "FS Lure"
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- with #showtooltip the icon follows the item

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local IsEquippedItem = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem

local function HasItem(itemID)
  return (GetItemCount(itemID) or 0) > 0 or (IsEquippedItem and IsEquippedItem(itemID))
end

local function GetBestLure()
  for _, itemID in ipairs(LURE_PRIORITY) do
    if HasItem(itemID) then
      return itemID
    end
  end
end

local function BuildMacroBody()
  -- With nothing available, still point at the lowest-priority item so the
  -- button shows a sensible icon/tooltip instead of an empty macro.
  local itemID = GetBestLure() or LURE_PRIORITY[#LURE_PRIORITY]
  return "#showtooltip\n/use item:" .. itemID .. "\n/use " .. FISHING_POLE_SLOT
end

local pendingUpdate = false
local eventFrame = CreateFrame("Frame")

-- Updates the macro body if the macro exists. Macros can't be edited in
-- combat, so the update is deferred until combat ends.
local function UpdateLureMacro()
  if InCombatLockdown() then
    pendingUpdate = true
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end

  local index = GetMacroIndexByName(MACRO_NAME)
  if index == 0 then return end

  local body = BuildMacroBody()
  if GetMacroBody(index) ~= body then
    EditMacro(index, MACRO_NAME, MACRO_ICON, body)
  end
end

-- Creates the macro if needed. Returns its index, or nil on failure.
local function EnsureLureMacro()
  local index = GetMacroIndexByName(MACRO_NAME)
  if index ~= 0 then
    UpdateLureMacro()
    return index
  end

  if InCombatLockdown() then
    print("FishingStats: can't create the lure macro in combat.")
    return nil
  end

  local maxGeneral = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS)
    or MAX_ACCOUNT_MACROS or 120
  local numGeneral = GetNumMacros()
  if numGeneral >= maxGeneral then
    print("FishingStats: no free general macro slot for the lure macro.")
    return nil
  end

  index = CreateMacro(MACRO_NAME, MACRO_ICON, BuildMacroBody(), nil)
  return index
end

-- Puts the lure macro on the cursor so it can be dropped on an action bar.
function Addon.PickupLureMacro()
  local index = EnsureLureMacro()
  if index then
    PickupMacro(index)
  end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_ENABLED" then
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if not pendingUpdate then return end
    pendingUpdate = false
  end
  UpdateLureMacro()
end)
