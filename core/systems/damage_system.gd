class_name DamageSystem
extends RefCounted

## 唯一的傷害結算入口。任何塔、法術、英雄都不得自行計算傷害減免——
## 傷害計算一旦散落各處，數值平衡就無法推理，這是塔防最常見的技術債來源。
##
## 結算順序固定：
##   1. 依傷害類型取得減免比例
##   2. 套用減免
##   3. 扣血
##   4. 判定死亡

const PHYSICAL := &"physical"
const MAGIC := &"magic"
const TRUE_DAMAGE := &"true"

## 對敵人造成傷害，回傳實際造成的傷害值。
static func apply(enemy: Enemy, amount: float, damage_type: StringName) -> float:
	if not enemy.alive:
		return 0.0

	var reduction := 0.0
	match damage_type:
		PHYSICAL:
			reduction = enemy.armor
		MAGIC:
			reduction = enemy.magic_resist
		TRUE_DAMAGE:
			reduction = 0.0
		_:
			push_error("未知的傷害類型: %s" % damage_type)
			return 0.0

	# 減免比例必須夾限在 [0, 1]。敵人的 armor 與 magic_resist 是公開欄位，
	# 下個里程碑的破甲狀態效果會直接寫入這些欄位。若沒夾限，負值會變成傷害放大。
	reduction = clampf(reduction, 0.0, 1.0)

	var dealt := maxf(0.0, amount * (1.0 - reduction))
	enemy.hp -= dealt
	if enemy.hp <= 0.0:
		enemy.hp = 0.0
		enemy.alive = false
	return dealt
