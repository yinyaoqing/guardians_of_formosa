class_name WorldState
extends RefCounted

## 一場戰鬥的全部實體與資源。純資料容器，不含模擬邏輯。

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var paths: Dictionary = {}          ## StringName -> PathData

## 狀態效果的 JSON 定義，由表現層在載入關卡時自 DataRegistry 灌入。
## core/ 不自行讀檔，維持可在無檔案系統的情況下被測試。
var effect_defs: Dictionary = {}   ## StringName -> Dictionary

var gold: int = 0
var lives: int = 20

## 每 tick 由 BattleSim 重建的查詢結構
var grid := UniformGrid.new()
var enemies_by_id: Dictionary = {}  ## int -> Enemy

const EFFECT_POOL_CAPACITY := 64

## 狀態效果實例池與其系統。實例走池化，避免戰鬥迴圈中配置新物件。
var effect_pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), EFFECT_POOL_CAPACITY)
var status_system := StatusSystem.new(effect_pool)

const PROJECTILE_POOL_CAPACITY := 128

var projectiles: Array[Projectile] = []
var projectile_pool := ObjectPool.new(func() -> Projectile: return Projectile.new(), PROJECTILE_POOL_CAPACITY)
var projectile_system: ProjectileSystem = null   ## 由 BattleSim 於建構時注入

var _next_entity_id: int = 1

func add_enemy(enemy: Enemy) -> void:
	if enemy.id == 0:
		enemy.id = next_id()
	enemies.append(enemy)
	enemies_by_id[enemy.id] = enemy

func add_tower(tower: Tower) -> void:
	if tower.id == 0:
		tower.id = next_id()
	towers.append(tower)

## 配發一個全新的實體 id。敵人、塔、投射物共用同一個遞增計數器，
## 確保 id 在型別之間也不重複。
func next_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id
