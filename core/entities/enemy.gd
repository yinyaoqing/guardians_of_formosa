class_name Enemy
extends Combatant

## 敵人的邏輯狀態。純資料，沒有行為——行為由 systems/ 下的各系統負責。

var id: int = 0
var enemy_id: StringName = &""

var bounty: int = 0               ## 擊殺獎勵金

var path_id: StringName = &""
var distance_along: float = 0.0   ## 沿路徑已行進距離
var position: Vector2 = Vector2.ZERO  ## 由 MovementSystem 每 tick 快取

var leaked: bool = false          ## 已走到路徑終點，玩家扣血

## 攔截者的實體 id，0 表示未被攔截。M1 的士兵系統會用到。
var blocked_by: int = 0

## 基礎數值：資料載入時填入，之後永不寫入。
## 狀態效果只改衍生值，基礎值必須保持乾淨，否則效果到期後無法還原。
var base_speed: float = 0.0            ## 像素 / 秒
var base_armor: float = 0.0            ## 物理減免比例，0.0 ~ 0.95
var base_magic_resist: float = 0.0     ## 魔法減免比例，0.0 ~ 0.95

## 衍生數值：每 tick 由 StatusSystem 依 active_effects 重算並覆寫。
## 除 StatusSystem 外，任何程式碼都不得寫入這些欄位。
## armor 與 magic_resist 雖然宣告在 Combatant，語意上同屬本區塊——
## 基底類別只知道「有這個欄位」，不知道它每 tick 會被重算。
var speed: float = 0.0
var stunned: bool = false              ## 純供表現層顯示暈眩圖示

## 生效中的狀態效果。實例來自物件池，由 StatusSystem 管理生滅。
var active_effects: Array[StatusEffect] = []

## 把基礎值複製到衍生值。資料載入後呼叫一次，
## 之後每 tick 由 StatusSystem 在重算開頭呼叫。
func reset_derived_stats() -> void:
	speed = base_speed
	armor = base_armor
	magic_resist = base_magic_resist
	stunned = false
