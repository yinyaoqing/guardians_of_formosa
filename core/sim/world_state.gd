class_name WorldState
extends RefCounted

## 一場戰鬥的全部實體與資源。純資料容器，不含模擬邏輯。

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var paths: Dictionary = {}          ## StringName -> PathData

var gold: int = 0
var lives: int = 20

## 每 tick 由 BattleSim 重建的查詢結構
var grid := UniformGrid.new()
var enemies_by_id: Dictionary = {}  ## int -> Enemy

var _next_entity_id: int = 1

func add_enemy(enemy: Enemy) -> void:
	if enemy.id == 0:
		enemy.id = _next_entity_id
		_next_entity_id += 1
	enemies.append(enemy)
	enemies_by_id[enemy.id] = enemy

func add_tower(tower: Tower) -> void:
	if tower.id == 0:
		tower.id = _next_entity_id
		_next_entity_id += 1
	towers.append(tower)
