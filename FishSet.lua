local name, Addon = ...

-- Global Variables --
Addon.FISH_SET = {}
local FISH_SET = Addon.FISH_SET

-- Init --
function InitDB()
  FishingStatsDB = FishingStatsDB or {}
  FishingStatsDB.fishCounts = FishingStatsDB.fishCounts or {}
  FishingStatsDB.prices = FishingStatsDB.prices or {}
  FishingStatsDB.earn = FishingStatsDB.earn or 0
  priceCache = FishingStatsDB.prices
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, addonName)
  if addonName == "FishingStats" then
    InitDB()
  end
end)

-- Func --

local Set = {}

function Set.add(set, v) set[v] = true  end
function Set.addList(set, list)
    for _, v in ipairs(list or {}) do set[v] = true end
end
function Set.addRange(set, startId, endId)
  for itemID = startId, endId do
    set[itemID] = true
  end
end

-- 11.0
-- Fish --
Set.addRange(FISH_SET, 220134, 220151)
Set.addList(FISH_SET, {222533, 225770, 225771, 217707, 220152, 226392})
-- Ore --
Set.addRange(FISH_SET, 210930, 210935)
-- Skin --
Set.addRange(FISH_SET, 212664, 212669)
-- 离骨碎片，蠕动样本
Set.addList(FISH_SET, {218337, 213611})

-- 12.0
Set.addRange(FISH_SET, 238365, 238384) 
-- Ore
Set.addRange(FISH_SET, 237359, 237364)

print("Fish set loaded")

function Addon.IsTrackedFish(itemID)
  return FISH_SET[itemID] == true
end

--- Load Fish Price ---

function Addon.PreloadFishPrices()
  if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
    print("Auctionator API not available. Price preload skipped.")
    return
  end

  for itemID in pairs(FISH_SET) do
    -- 只在未缓存时才查询
    if not priceCache[itemID] then
      local price = Auctionator.API.v1.GetAuctionPriceByItemID(name, itemID)
      if price then
        priceCache[itemID] = price
      end
    end
  end
  print("FishingStats: Fish price preload complete.")
end
