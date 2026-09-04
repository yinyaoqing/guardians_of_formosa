class_name Enemy
extends RefCounted

## 敵人的邏輯狀態。純資料，沒有行為——行為由 systems/ 下的各系統負責。

var id: int = 0
var enemy_id: StringName = &""

var hp: float = 0.0
var max_hp: float = 0.0
var speed: float = 0.0            ## 像素 / 秒
var armor: float = 0.0            ## 物理減免比例，0.0 ~ 0.95
var magic_resist: float = 0.0     ## 魔法減免比例，0.0 ~ 0.95
var bounty: int = 0               ## 擊殺獎勵金

var path_id: StringName = &""
var distance_along: float = 0.0   ## 沿路徑已行進距離
var position: Vector2 = Vector2.ZERO  ## 由 MovementSystem 每 tick 快取

var alive: bool = true
var leaked: bool = false          ## 已走到路徑終點，玩家扣血

## 攔截者的實體 id，0 表示未被攔截。M1 的士兵系統會用到。
var blocked_by: int = 0
