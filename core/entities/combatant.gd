class_name Combatant
extends RefCounted

## 會被傷害結算打到的東西。Enemy 與 Soldier 的共同基底。
##
## 存在的唯一理由是讓 DamageSystem.apply() 維持「一個入口 + 靜態型別」。
## 若改成兩個函式（apply / apply_to_soldier），減免邏輯就有兩份，
## 而兩份數值規則漂移的那天不會有任何測試失敗——這正是硬規則 #2 要防的事。
##
## 這裡只放「傷害結算會讀寫的欄位」。速度、路徑、狀態效果都是 Enemy 專屬，
## 不上移；小兵不吃狀態效果，armor 在建立時寫一次就不再變動。

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true

var armor: float = 0.0          ## 物理減免比例，0.0 ~ 0.95
var magic_resist: float = 0.0   ## 魔法減免比例，0.0 ~ 0.95
