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

## 對一個 Combatant 造成傷害，回傳實際造成的傷害值。
##
## 參數型別是 Combatant 而非 Enemy：敵人砍小兵與塔打敵人必須走同一個入口，
## 否則減免邏輯就有兩份。
static func apply(target: Combatant, amount: float, damage_type: StringName) -> float:
	if not target.alive:
		return 0.0

	var reduction := 0.0
	match damage_type:
		PHYSICAL:
			reduction = target.armor
		MAGIC:
			reduction = target.magic_resist
		TRUE_DAMAGE:
			reduction = 0.0
		_:
			push_error("未知的傷害類型: %s" % damage_type)
			return 0.0

	# 減免比例必須夾限在 [0, 1]。armor 與 magic_resist 是公開欄位，
	# 破甲狀態效果會直接寫入它們。若沒夾限，負值會變成傷害放大。
	reduction = clampf(reduction, 0.0, 1.0)

	var dealt := maxf(0.0, amount * (1.0 - reduction))
	target.hp -= dealt
	if target.hp <= 0.0:
		target.hp = 0.0
		target.alive = false
	return dealt
