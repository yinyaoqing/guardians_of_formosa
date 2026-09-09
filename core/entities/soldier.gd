class_name Soldier
extends Combatant

## 兵營派出的擋路兵。純資料，行為由 GarrisonSystem 與 MeleeSystem 負責。
##
## 崗位是一維的：小兵佔路徑上的一個距離值，不做自由移動。攔截判定因此是
## 一個數字比較而非幾何運算，且完全確定性——headless 測得到。

var id: int = 0
var barracks_id: int = 0          ## 產出它的兵營（Tower）id
var slot_index: int = 0           ## 在兵營的第幾個名額，重生時要放回同一格

var path_id: StringName = &""     ## 崗位所在的路徑
var post_distance: float = 0.0    ## 崗位在該路徑上的位置

## 崗位的世界座標。崗位不會移動，所以這是常數；存下來是因為表現層每幀要用，
## 每次由 PathData.position_at() 重算是白花的。
var position: Vector2 = Vector2.ZERO

var damage: float = 0.0
var damage_type: StringName = &"physical"
var attack_interval: float = 1.0
var cooldown: float = 0.0         ## 距離下次可攻擊的剩餘秒數

var engaged_enemy_id: int = 0     ## 0 表示未交戰
var regen_per_second: float = 0.0 ## 脫戰時每秒回血

## 把每一個欄位寫回出生狀態。
##
## 小兵走物件池，acquire() 拿到的是上一個死掉的小兵，欄位全是它上輩子的值。
## 少重設任何一個都會產生極難追的 bug——例如殘留的 engaged_enemy_id 會讓
## 剛重生的小兵「已經在跟一個早就死掉的敵人交戰」，於是它永遠不會接戰，
## 但畫面上它站得好好的。
func reset(p_max_hp: float, p_armor: float) -> void:
	max_hp = p_max_hp
	hp = p_max_hp
	alive = true
	armor = p_armor
	magic_resist = 0.0
	cooldown = 0.0
	engaged_enemy_id = 0
