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

func _find(enemy: Enemy, kind: StringName, source: StringName) -> StatusEffect:
	for effect: StatusEffect in enemy.active_effects:
		if effect.kind == kind and effect.source == source:
			return effect
	return null
