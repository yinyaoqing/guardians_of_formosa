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

## 兩段式重生契約的「生命與戰鬥狀態」那一段——只覆蓋這裡。
##
## 小兵走物件池，acquire() 拿到的是上一個死掉的小兵，欄位全是它上輩子的值。
## 讓小兵重新可用需要兩段合作，兩段加起來才覆蓋全部欄位：
##
##   1. 這個函式：max_hp、hp、alive、armor、magic_resist、cooldown、
##      engaged_enemy_id——會被 DamageSystem 讀寫、決定「這隻小兵現在死活
##      如何、能不能打」的欄位。
##   2. 呼叫端（GarrisonSystem._spawn()）：id（設 0 讓 add_soldier 配發新
##      的）、barracks_id、slot_index、path_id、post_distance、position、
##      damage、damage_type、attack_interval、regen_per_second——身分、
##      崗位與數值，這個函式完全不碰。
##
## 這個分工是刻意的，不要把它合併成一個函式：GarrisonSystem 在 acquire()
## 之後一定會重新指派崗位與數值，由呼叫端負責這些欄位不會漏——但生命與
## 戰鬥狀態不會有別的地方去設，漏掉哪一個都得靠這個函式補上。
##
## 忘記覆蓋的欄位會產生極難追的 bug，因為畫面看起來完全正常。例如殘留的
## engaged_enemy_id 會讓剛重生的小兵「已經在跟一個早就死掉的敵人交戰」，
## 於是它永遠不會接戰新目標，但它站在崗位上、動畫也在播，肉眼看不出問題。
## 而若呼叫端漏掉 path_id / post_distance / position（本函式刻意不覆蓋的
## 欄位），重生的小兵會用上輩子的位置去攔截敵人——同樣要等到某條路徑漏防
## 才會被發現。
func reset(p_max_hp: float, p_armor: float) -> void:
	max_hp = p_max_hp
	hp = p_max_hp
	alive = true
	armor = p_armor
	magic_resist = 0.0
	cooldown = 0.0
	engaged_enemy_id = 0
