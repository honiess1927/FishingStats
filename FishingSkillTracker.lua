-- FishingSkillTracker.lua
local _, Addon = ...

--- 返回三值：总钓鱼技能，基础专业等级，装备+Buff 加成
function Addon.GetFishingSkillBonus()
  -- 1. 专业基础等级
  local baseSkill = 0
  local _, _, _, fishingProf = GetProfessions()
  if fishingProf then
    baseSkill = select(3, GetProfessionInfo(fishingProf)) or 0
    maxSkill = select(4, GetProfessionInfo(fishingProf)) or 0
    bonus = select(8, GetProfessionInfo(fishingProf)) or 0
  end

  return baseSkill + bonus, maxSkill, bonus
end
