extends Node2D

## 表現層的組裝點：
##  1. 從編輯器畫好的 Path2D 等距取樣出 PathData（core/ 不接觸 Curve2D）
##  2. 驅動 BattleSim
##  3. 依模擬狀態建立與更新 view

const PATH_SAMPLE_SPACING := 8.0
const MAIN_PATH_ID := &"main"
const SPAWN_INTERVAL := 1.5

const EnemyViewScript := preload("res://game/views/enemy_view.gd")
const TowerViewScript := preload("res://game/views/tower_view.gd")
const ProjectileViewScript := preload("res://game/views/projectile_view.gd")

## 置換用的投射物貼圖。之後應改為依 Projectile.projectile_id 從資料查表，
## 目前只有一種塔，寫成常數即可。
const PROJECTILE_SPRITE := "res://game/assets/placeholder_projectile.png"

@onready var _path_node: Path2D = $MainPath
@onready var _view_root: Node2D = $Views

var _registry := DataRegistry.new()
var _sim: BattleSim
var _enemy_views: Dictionary = {}       ## int -> EnemyView
var _tower_views: Dictionary = {}       ## int -> TowerView
var _projectile_views: Dictionary = {}  ## instance_id -> ProjectileView
var _spawn_timer: float = 0.0

func _ready() -> void:
	_registry.load_from_disk()

	var world := WorldState.new()
	world.configure_for_level(_registry, &"level_01")
	world.paths[MAIN_PATH_ID] = _bake_path(_path_node)

	_sim = BattleSim.new(world)
	_place_tower(&"archer_tower", Vector2(400, 200))

func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_spawn_enemy(&"orc_grunt")

	var ticks := _sim.advance(delta)
	if ticks > 0:
		_sync_views()
	_interpolate_views()

## 把編輯器畫的 Curve2D 等距取樣成點陣列。
## core/ 只認得點陣列，不認得 Curve2D——這個轉換就是分層的邊界。
func _bake_path(path_node: Path2D) -> PathData:
	var curve := path_node.curve
	var length := curve.get_baked_length()
	var sample_count := int(length / PATH_SAMPLE_SPACING) + 1
	var points := PackedVector2Array()
	for i in sample_count:
		points.append(curve.sample_baked(float(i) * PATH_SAMPLE_SPACING))
	return PathData.new(points, PATH_SAMPLE_SPACING)

func _spawn_enemy(enemy_id: StringName) -> void:
	var enemy := _registry.make_enemy(enemy_id, MAIN_PATH_ID)
	# 先把座標設到路徑起點再建 view。否則 view 會先出現在原點，
	# 等第一個 tick 才跳到路徑起點，看起來像瞬移。
	enemy.position = _sim.world.paths[MAIN_PATH_ID].position_at(0.0)
	_sim.world.add_enemy(enemy)

	var view := EnemyViewScript.new() as EnemyView
	view.setup(enemy.id, _registry.enemies[enemy_id]["sprite"], enemy.position)
	_view_root.add_child(view)
	_enemy_views[enemy.id] = view

func _place_tower(tower_id: StringName, tower_position: Vector2) -> void:
	var def: Dictionary = _registry.towers[tower_id]
	var level_def: Dictionary = def["levels"][0]

	var tower := Tower.new()
	tower.tower_id = tower_id
	tower.position = tower_position
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	var on_hit_effects: Array[StringName] = []
	for effect_id in level_def["on_hit_effects"]:
		on_hit_effects.append(StringName(effect_id))
	tower.on_hit_effects = on_hit_effects
	_sim.world.add_tower(tower)

	var view := TowerViewScript.new() as TowerView
	view.setup(tower.id, def["sprite"], tower_position)
	_view_root.add_child(view)
	_tower_views[tower.id] = view

## 每個邏輯 tick 後同步一次：推進插值目標、清掉已死亡的 view
func _sync_views() -> void:
	for enemy: Enemy in _sim.world.enemies:
		var view: EnemyView = _enemy_views.get(enemy.id)
		if view != null:
			view.on_tick(enemy.position)

	for view_id: int in _enemy_views.keys():
		if not _sim.world.enemies_by_id.has(view_id):
			var view: EnemyView = _enemy_views[view_id]
			view.queue_free()
			_enemy_views.erase(view_id)

	for tower: Tower in _sim.world.towers:
		if tower.target_id == 0:
			continue
		var target: Enemy = _sim.world.enemies_by_id.get(tower.target_id)
		if target != null:
			_tower_views[tower.id].aim_at(target.position)

	_sync_projectile_views()

## 投射物的生滅比敵人頻繁得多，且身分是 instance_id 而非實體 id。
## 新出現的建 view、已消失的釋放 view。
func _sync_projectile_views() -> void:
	var live: Dictionary = {}
	for projectile: Projectile in _sim.world.projectiles:
		live[projectile.instance_id] = true
		var view: ProjectileView = _projectile_views.get(projectile.instance_id)
		if view == null:
			# 生成當下的座標就是發射它的塔，從那裡開始插值才不會從原點滑進來
			view = ProjectileViewScript.new() as ProjectileView
			view.setup(projectile.instance_id, PROJECTILE_SPRITE, projectile.position)
			_view_root.add_child(view)
			_projectile_views[projectile.instance_id] = view
		else:
			view.on_tick(projectile.position)

	for view_id: int in _projectile_views.keys():
		if not live.has(view_id):
			var view: ProjectileView = _projectile_views[view_id]
			view.queue_free()
			_projectile_views.erase(view_id)

## 每個渲染幀插值一次，讓 30Hz 的邏輯看起來是 60fps 的平滑移動
func _interpolate_views() -> void:
	var alpha := _sim.tick_progress()
	for view: EnemyView in _enemy_views.values():
		view.interpolate(alpha)
	for view: ProjectileView in _projectile_views.values():
		view.interpolate(alpha)
