class_name StatusSystem
extends RefCounted

## 狀態效果的施加、堆疊、到期與衍生數值重算。
##
## 堆疊規則（架構規格 §4.3）：同來源刷新持續時間，不同來源取最強。
## 「來源」定義為施加者的 tower_id，也就是塔的「種類」而非個別那座塔——
## 三座同型冰霜塔打同一隻敵人是互相刷新，不疊三層。這是唯一不會讓多塔堆疊失控的定義。
##
## 來源只決定「刷新或新增」；強度只在重算衍生值時取各 kind 的最大值。
## 兩件事分開後規則就沒有歧義。

var _pool: ObjectPool

func _init(effect_pool: ObjectPool) -> void:
	_pool = effect_pool

## 對敵人施加一個效果。effect_def 為 DataRegistry 載入的 JSON 字典。
func apply(enemy: Enemy, effect_def: Dictionary, source: StringName) -> void:
	if not enemy.alive:
		return

	var kind := StringName(effect_def["kind"])
	var duration: float = effect_def["duration"]
	var magnitude: float = effect_def.get("magnitude", 0.0)
	var damage_type := StringName(effect_def.get("damage_type", ""))

	var existing := _find(enemy, kind, source)
	if existing != null:
		existing.remaining = maxf(existing.remaining, duration)
		existing.magnitude = magnitude
		existing.damage_type = damage_type
		return

	var effect: StatusEffect = _pool.acquire()
	effect.reset()
	effect.kind = kind
	effect.source = source
	effect.magnitude = magnitude
	effect.damage_type = damage_type
	effect.remaining = duration
	enemy.active_effects.append(effect)

## 依生效中的效果重算敵人的衍生數值。
## 每種 kind 取最強的一個，只套用一次——不相加。相加會讓多塔堆疊迅速失控。
func recompute(enemy: Enemy) -> void:
	enemy.reset_derived_stats()

	var strongest_slow := 0.0
	var strongest_armor_break := 0.0
	var has_stun := false

	for effect: StatusEffect in enemy.active_effects:
		match effect.kind:
			StatusEffect.KIND_SLOW:
				strongest_slow = maxf(strongest_slow, effect.magnitude)
			StatusEffect.KIND_STUN:
				has_stun = true
			StatusEffect.KIND_ARMOR_BREAK:
				strongest_armor_break = maxf(strongest_armor_break, effect.magnitude)
			StatusEffect.KIND_DOT:
				pass   # DoT 不影響衍生數值，在 tick 中結算傷害

	if has_stun:
		enemy.speed = 0.0
		enemy.stunned = true
	else:
		enemy.speed = enemy.base_speed * (1.0 - strongest_slow)

	enemy.armor = maxf(0.0, enemy.base_armor - strongest_armor_break)

## 歸還敵人身上所有生效中的效果。敵人離場時呼叫，否則池會逐漸耗盡。
## 由 StatusSystem 負責是因為它是效果實例的唯一擁有者——若呼叫端各自持有池的參照，
## 兩份帳就會分家，一邊洩漏、一邊重複釋放。
func release_all(enemy: Enemy) -> void:
	for effect: StatusEffect in enemy.active_effects:
		_pool.release(effect)
	enemy.active_effects.clear()

func _find(enemy: Enemy, kind: StringName, source: StringName) -> StatusEffect:
	for effect: StatusEffect in enemy.active_effects:
		if effect.kind == kind and effect.source == source:
			return effect
	return null

## 每個邏輯 tick 呼叫一次，且必須排在 tick 迴圈的最前面——
## 否則後續所有系統讀到的都是上一 tick 的衍生值。
func tick(enemies: Array, delta: float) -> void:
	for enemy: Enemy in enemies:
		if not enemy.alive:
			continue
		_expire(enemy, delta)
		recompute(enemy)
		_apply_damage_over_time(enemy, delta)

## 推進剩餘時間，把到期的效果移出並歸還池中。
## 由後往前走訪，這樣原地移除不會跳過元素。
func _expire(enemy: Enemy, delta: float) -> void:
	for i in range(enemy.active_effects.size() - 1, -1, -1):
		var effect: StatusEffect = enemy.active_effects[i]
		effect.remaining -= delta
		if effect.remaining <= 0.0:
			enemy.active_effects.remove_at(i)
			_pool.release(effect)

## magnitude 是每秒傷害，因此乘上 delta。
## 一律經過 DamageSystem——這是硬規則第 2 條，DoT 不例外。
func _apply_damage_over_time(enemy: Enemy, delta: float) -> void:
	for effect: StatusEffect in enemy.active_effects:
		if effect.kind != StatusEffect.KIND_DOT:
			continue
		DamageSystem.apply(enemy, effect.magnitude * delta, effect.damage_type)
		if not enemy.alive:
			return
