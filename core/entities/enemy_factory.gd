class_name EnemyFactory
extends RefCounted

## 從敵人定義造出 Enemy。這是全專案唯一造敵人的地方。
##
## B4 之前只有 DataRegistry.make_enemy 一條路，但波次系統住在 core/、只拿得到
## 注入 WorldState 的 enemy_defs，不認得 registry。兩邊各寫一份就是第二個事實
## 來源，而這次兩邊都在 core/、沒有分層守衛擋著，所以可以真的收攏成一份。

static func from_def(def: Dictionary, enemy_id: StringName, path_id: StringName) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = enemy_id
	enemy.hp = def["hp"]
	enemy.max_hp = def["hp"]
	enemy.base_speed = def["speed"]
	enemy.base_armor = def["armor"]
	enemy.base_magic_resist = def["magic_resist"]
	enemy.reset_derived_stats()
	enemy.bounty = int(def["bounty"])
	enemy.path_id = path_id
	return enemy
