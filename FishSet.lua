local name, Addon = ...

-- Global Variables --
Addon.FISH_SET = {}
local FISH_SET = Addon.FISH_SET
local HOURLY_CATCH_TARGET = 300

local function NormalizeRegionName(regionName)
  if type(regionName) ~= "string" then
    return "Unknown Region"
  end

  local normalized = regionName
  if strtrim then
    normalized = strtrim(normalized)
  end

  if normalized == "" then
    return "Unknown Region"
  end

  return normalized
end

local function IsZeroHourlyItem(itemName)
  return itemName == "杂项" or itemName == "垃圾"
end

local function GetCurrentItemPrice(itemID)
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

local function SortRegionItems(items)
  table.sort(items, function(a, b)
    if a.estimatedHourlyEarn ~= b.estimatedHourlyEarn then
      return a.estimatedHourlyEarn > b.estimatedHourlyEarn
    end

    if a.count ~= b.count then
      return a.count > b.count
    end

    return a.itemName < b.itemName
  end)
end

local function SortRegions(regions)
  table.sort(regions, function(a, b)
    if a.estimatedHourlyEarn ~= b.estimatedHourlyEarn then
      return a.estimatedHourlyEarn > b.estimatedHourlyEarn
    end

    if a.totalEarn ~= b.totalEarn then
      return a.totalEarn > b.totalEarn
    end

    return a.regionName < b.regionName
  end)
end

-- Init --
function InitDB()
  FishingStatsDB = FishingStatsDB or {}
  FishingStatsDB.fishCounts = FishingStatsDB.fishCounts or {}
  FishingStatsDB.prices = FishingStatsDB.prices or {}
  FishingStatsDB.earn = FishingStatsDB.earn or 0
  FishingStatsDB.regionStats = FishingStatsDB.regionStats or {}
  FishingStatsDB.meta = FishingStatsDB.meta or {}
  FishingStatsDB.meta.dataVersion = 2
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

function Addon.GetCurrentFishingRegion()
  local regionName = nil

  if GetRealZoneText then
    regionName = GetRealZoneText()
  end

  if NormalizeRegionName(regionName) == "Unknown Region" and GetZoneText then
    regionName = GetZoneText()
  end

  return NormalizeRegionName(regionName)
end

function Addon.EnsureRegionStats(regionName)
  local resolvedRegionName = NormalizeRegionName(regionName)
  local regionStats = FishingStatsDB.regionStats[resolvedRegionName]

  if not regionStats then
    regionStats = {
      regionName = resolvedRegionName,
      totalCount = 0,
      totalEarn = 0,
      fishCounts = {},
    }
    FishingStatsDB.regionStats[resolvedRegionName] = regionStats
  end

  regionStats.regionName = regionStats.regionName or resolvedRegionName
  regionStats.totalCount = regionStats.totalCount or 0
  regionStats.totalEarn = regionStats.totalEarn or 0
  regionStats.fishCounts = regionStats.fishCounts or {}

  return regionStats, resolvedRegionName
end

function Addon.RecordRegionCatch(regionName, itemID, itemName, count, totalEarn)
  if not itemName then
    return
  end

  local safeCount = count or 0
  local safeEarn = totalEarn or 0
  local regionStats = Addon.EnsureRegionStats(regionName)
  local itemStats = regionStats.fishCounts[itemName]

  if not itemStats then
    itemStats = {
      itemID = itemID,
      count = 0,
      totalEarn = 0,
    }
    regionStats.fishCounts[itemName] = itemStats
  end

  if itemID and not itemStats.itemID then
    itemStats.itemID = itemID
  end

  itemStats.count = (itemStats.count or 0) + safeCount
  itemStats.totalEarn = (itemStats.totalEarn or 0) + safeEarn
  regionStats.totalCount = (regionStats.totalCount or 0) + safeCount
  regionStats.totalEarn = (regionStats.totalEarn or 0) + safeEarn
end

function Addon.DeleteRegionStats(regionName)
  local resolvedRegionName = NormalizeRegionName(regionName)

  if not FishingStatsDB.regionStats[resolvedRegionName] then
    return false
  end

  FishingStatsDB.regionStats[resolvedRegionName] = nil
  return true
end

function Addon.GetRegionMetrics(regionName)
  local resolvedRegionName = NormalizeRegionName(regionName)
  local regionStats = FishingStatsDB.regionStats[resolvedRegionName]

  if not regionStats then
    return {
      regionName = resolvedRegionName,
      totalCount = 0,
      totalEarn = 0,
      estimatedHourlyEarn = 0,
      items = {},
    }
  end

  local totalCount = regionStats.totalCount or 0
  local totalEarn = regionStats.totalEarn or 0
  local estimatedHourlyEarn = 0
  local items = {}

  for itemName, itemStats in pairs(regionStats.fishCounts or {}) do
    local itemCount = itemStats.count or 0
    local itemTotalEarn = itemStats.totalEarn or 0
    local itemCatchPercent = 0
    local itemHourlyEarn = 0
    local itemHourlyValue = 0

    if totalCount > 0 then
      itemCatchPercent = itemCount / totalCount * 100
      if not IsZeroHourlyItem(itemName) then
        itemHourlyValue = GetCurrentItemPrice(itemStats.itemID) * itemCount
        itemHourlyEarn = itemHourlyValue / totalCount * HOURLY_CATCH_TARGET
      end
    end

    estimatedHourlyEarn = estimatedHourlyEarn + itemHourlyEarn

    table.insert(items, {
      itemID = itemStats.itemID,
      itemName = itemName,
      count = itemCount,
      totalEarn = itemTotalEarn,
      catchPercent = itemCatchPercent,
      estimatedHourlyEarn = itemHourlyEarn,
    })
  end

  SortRegionItems(items)

  return {
    regionName = regionStats.regionName or resolvedRegionName,
    totalCount = totalCount,
    totalEarn = totalEarn,
    estimatedHourlyEarn = estimatedHourlyEarn,
    items = items,
  }
end

function Addon.GetRegionOverviewData()
  local overview = {}

  for regionName in pairs(FishingStatsDB.regionStats or {}) do
    local metrics = Addon.GetRegionMetrics(regionName)
    table.insert(overview, {
      regionName = metrics.regionName,
      totalCount = metrics.totalCount,
      totalEarn = metrics.totalEarn,
      estimatedHourlyEarn = metrics.estimatedHourlyEarn,
    })
  end

  SortRegions(overview)
  return overview
end

function Addon.GetRegionDetailData(regionName)
  return Addon.GetRegionMetrics(regionName)
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
