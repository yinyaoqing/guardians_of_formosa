class_name Combatant
extends RefCounted

## 會被傷害結算打到的東西。Enemy 與 Soldier 的共同基底。
##
## 存在的唯一理由是讓 DamageSystem.apply() 維持「一個入口 + 靜態型別」。
## 若改成兩個函式（apply / apply_to_soldier），減免邏輯就有兩份，
## 而兩份數值規則漂移的那天不會有任何測試失敗——這正是硬規則 #2 要防的事。
##
## 這裡只放「傷害結算會讀寫的欄位」。速度、路徑、狀態效果都是 Enemy 專屬，不上移。
##
## armor / magic_resist 的生命週期由子類別決定，基底不保證任何重算路徑：
## Enemy 的是衍生值，StatusSystem 每 tick 由 base_armor / base_magic_resist 重算
## 覆寫；Soldier 的是常數，只在 reset() 寫一次。因此任何會寫入 armor /
## magic_resist 的機制（破甲、強化）在套用到新的 Combatant 子類之前，必須先
## 確認該子類有重算路徑——沒有 base_* + reset_derived_stats() 的子類，寫進去的
## 減益是永久的，不會自然消退。

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true

var armor: float = 0.0          ## 物理減免比例，0.0 ~ 0.95
var magic_resist: float = 0.0   ## 魔法減免比例，0.0 ~ 0.95
