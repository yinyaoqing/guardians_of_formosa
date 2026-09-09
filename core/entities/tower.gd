class_name Tower
extends RefCounted

## 塔的邏輯狀態。純資料，行為由 systems/ 負責。
## 特別注意：射程欄位叫 attack_range 而非 range——range 是 GDScript 內建函式。

## 塔的種類。用顯式欄位而非「兵營把 damage 填 0」——後者要靠讀者推理，
## 且 damage 為 0 的射擊塔是合法的資料錯誤，兩者就分不出來。
const KIND_SHOOTER := &"shooter"
const KIND_BARRACKS := &"barracks"

var kind: StringName = KIND_SHOOTER

var id: int = 0
var tower_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var level: int = 1

var damage: float = 0.0
var damage_type: StringName = &"physical"
var attack_range: float = 0.0
var fire_interval: float = 1.0    ## 兩次攻擊的間隔秒數

var cooldown: float = 0.0         ## 距離下次可攻擊的剩餘秒數
var target_id: int = 0            ## 當前鎖定的敵人 id，0 表示無目標

## 像素 / 秒。預設 0 是為了讓忘記從 data 複製速度的漏搬運立刻現形
##（投射物卡住不動，看得出來問題）；若預設值為 600 則會巧合地「正常」工作。
var projectile_speed: float = 0.0
var splash_radius: float = 0.0          ## 0 表示單體
var on_hit_effects: Array[StringName] = []

## ---- 以下僅 kind == KIND_BARRACKS 時有意義 ----

## 每個名額目前的小兵 id，0 表示空著；與 respawn_timers 同索引。
## 長度固定為該級的兵數，建造與升級時各重設一次，tick 內只寫既有元素——
## 硬規則 #5 禁止在戰鬥迴圈中配置新物件。
var soldier_ids: PackedInt32Array = PackedInt32Array()
var respawn_timers: PackedFloat32Array = PackedFloat32Array()

var soldier_hp: float = 0.0
var soldier_damage: float = 0.0
var soldier_attack_interval: float = 1.0
var soldier_armor: float = 0.0
var respawn_time: float = 0.0
var regen_per_second: float = 0.0

## 崗位。建造當下算一次，之後不再變動——連潮汐開出新路徑時也不變，
## 理由與後續處理見設計規格 §5.3。
var post_path_id: StringName = &""
var post_distance: float = 0.0
var post_position: Vector2 = Vector2.ZERO
