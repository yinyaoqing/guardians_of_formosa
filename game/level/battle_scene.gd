extends Node2D

## 表現層的組裝點：
##  1. 從編輯器畫好的 Path2D 等距取樣出 PathData（core/ 不接觸 Curve2D）
##  2. 驅動 BattleSim
##  3. 依模擬狀態建立與更新 view

const PATH_SAMPLE_SPACING := 8.0
const MAIN_PATH_ID := &"main"
const SPAWN_INTERVAL := 1.5
const LEVEL_ID := &"level_01"

const EnemyViewScript := preload("res://game/views/enemy_view.gd")
const TowerViewScript := preload("res://game/views/tower_view.gd")
const ProjectileViewScript := preload("res://game/views/projectile_view.gd")
const BuildSlotViewScript := preload("res://game/views/build_slot_view.gd")

## 置換用的投射物貼圖。之後應改為依 Projectile.projectile_id 從資料查表，
## 目前只有一種塔，寫成常數即可。
const PROJECTILE_SPRITE := "res://game/assets/placeholder_projectile.png"

## 建塔點的美術。空位時顯示，蓋了塔就隱藏——塔就站在同一個座標上。
const SLOT_SPRITE := "res://game/assets/chapter01/prop_buildsite.png"

const BattleHudScene := preload("res://ui/battle_hud.tscn")
const BuildMenuScene := preload("res://ui/build_menu.tscn")
const RangeCircleScript := preload("res://game/views/range_circle.gd")

@onready var _path_node: Path2D = $MainPath
@onready var _view_root: Node2D = $Views
@onready var _build_slots_root: Node2D = $BuildSlots

var _registry := DataRegistry.new()
var _sim: BattleSim
var _enemy_views: Dictionary = {}       ## int -> EnemyView
var _tower_views: Dictionary = {}       ## int -> TowerView
var _projectile_views: Dictionary = {}  ## instance_id -> ProjectileView
var _slot_views: Dictionary = {}        ## slot_id -> BuildSlotView
var _controller := InteractionController.new()
var _hud: BattleHud = null

## 每座塔上次畫出來的等級。升級換圖靠它偵測，與 HUD 只在值變動時才寫 Label
## 是同一個手法——每幀無條件重載一張 128px 的圖是白燒的。
var _shown_tower_levels: Dictionary = {}   ## tower id -> int
var _spawn_timer: float = 0.0

var _build_menu: BuildMenu = null
var _range_circle: RangeCircle = null

## 選單目前畫的是哪一批選項。重算與重建按鈕只在這個簽章變動時做——
## 每幀重建按鈕是白燒的配置，而 gold 一變（每次擊殺）買得起與否就可能翻轉。
var _menu_signature: Array = []
var _menu_options: Array[Dictionary] = []

func _ready() -> void:
	_registry.load_from_disk()

	var world := WorldState.new()
	world.configure_for_level(_registry, LEVEL_ID)
	world.paths[MAIN_PATH_ID] = _bake_path(_path_node)

	_sim = BattleSim.new(world)
	_bake_build_slots(world)
	InputBindings.install()

	_hud = BattleHudScene.instantiate() as BattleHud
	add_child(_hud)
	_hud.setup(world, _sim, StringName(_registry.levels[LEVEL_ID]["name_key"]))
	_hud.pause_pressed.connect(_on_hud_pause_pressed)
	_hud.speed_pressed.connect(_on_hud_speed_pressed)

	_build_menu = BuildMenuScene.instantiate() as BuildMenu
	add_child(_build_menu)
	_build_menu.option_chosen.connect(_on_menu_option_chosen)
	_build_menu.option_hovered.connect(_on_menu_option_hovered)
	_build_menu.option_unhovered.connect(_on_menu_option_unhovered)

	_range_circle = RangeCircleScript.new() as RangeCircle
	_view_root.add_child(_range_circle)

func _process(delta: float) -> void:
	# 暫停時 advance 回傳 0，但佇列仍會被排空（建造與賣出正是玩家暫停下來規劃時
	# 要做的事）。只看 ticks 的話，暫停中蓋的塔要到恢復才出現在畫面上。
	var had_intents := not _sim.world.pending_intents.is_empty()
	var ticks := _sim.advance(delta)

	# 生怪計時器走模擬時間而非渲染時間：暫停時 advance() 回傳 0 個 tick，
	# 計時器因此完全不動；4 倍速下 ticks 對應的模擬時間也是 4 倍，生怪
	# 頻率才會跟著倍率一起變快，而不是被渲染幀率牽著走。
	# 生怪邏輯目前留在場景層是暫時的，等到波次系統子里程碑會搬進 tick 裡。
	_spawn_timer -= float(ticks) * BattleSim.TICK_DELTA
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_spawn_enemy(&"orc_grunt")

	if ticks > 0 or had_intents:
		_sync_views()
	_interpolate_views()
	_update_slot_views()

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

## 把場景中的 Marker2D 烘焙成 BuildSlot 交給 core/。
## core/ 不認得 Marker2D，與 Path2D → PathData 是同一個分層邊界。
func _bake_build_slots(world: WorldState) -> void:
	for marker in _build_slots_root.get_children():
		var slot := BuildSlot.new()
		slot.position = marker.position
		world.add_build_slot(slot)

		var view := BuildSlotViewScript.new() as BuildSlotView
		view.setup(slot.id, SLOT_SPRITE, slot.position)
		_view_root.add_child(view)
		_slot_views[slot.id] = view

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
		if not _tower_views.has(tower.id):
			var view := TowerViewScript.new() as TowerView
			view.setup(tower.id, _tower_sprite_for(tower), tower.position)
			_view_root.add_child(view)
			_tower_views[tower.id] = view
			_shown_tower_levels[tower.id] = tower.level
		elif _shown_tower_levels.get(tower.id, 0) != tower.level:
			_shown_tower_levels[tower.id] = tower.level
			(_tower_views[tower.id] as TowerView).set_sprite(_tower_sprite_for(tower))

	for view_id: int in _tower_views.keys():
		if _find_tower_view_owner(view_id) == null:
			var view: TowerView = _tower_views[view_id]
			view.queue_free()
			_tower_views.erase(view_id)
			_shown_tower_levels.erase(view_id)

	for tower: Tower in _sim.world.towers:
		if tower.target_id == 0:
			continue
		var target: Enemy = _sim.world.enemies_by_id.get(tower.target_id)
		if target != null:
			_tower_views[tower.id].aim_at(target.position)

	_sync_projectile_views()

## 賣塔之後對應的 view 要跟著消失。塔的數量少，線性搜尋即可。
func _find_tower_view_owner(view_id: int) -> Tower:
	for tower: Tower in _sim.world.towers:
		if tower.id == view_id:
			return tower
	return null

## 塔的等級自 1 起算，對應 levels 陣列的索引 level - 1——與 BuildSystem 一致。
func _tower_sprite_for(tower: Tower) -> String:
	var levels: Array = _registry.towers[tower.tower_id]["levels"]
	return levels[tower.level - 1]["sprite"]

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

## 每幀更新選取提示、佔用狀態與選單。建塔點是個位數，直接全部設定即可。
func _update_slot_views() -> void:
	for view: BuildSlotView in _slot_views.values():
		view.set_selected(view.slot_id == _controller.selected_slot_id)
		var slot: BuildSlot = _sim.world.build_slots_by_id.get(view.slot_id)
		view.set_occupied(slot != null and slot.occupied_by != 0)
	_update_build_menu()

## 選單是選取狀態的純函數：選取變了就開、關、移動。控制器裡沒有任何選單狀態，
## 所以「點空白處關閉選單」是免費的——select_at 命中不到建塔點時本來就會清成 0。
func _update_build_menu() -> void:
	var signature := _current_menu_signature()
	if signature == _menu_signature:
		return
	_menu_signature = signature

	var slot_id := _controller.selected_slot_id
	_menu_options = BuildMenuOptions.for_slot(_sim.world, slot_id)
	if _menu_options.is_empty():
		_build_menu.hide_menu()
		_range_circle.hide_circle()
		return

	var slot: BuildSlot = _sim.world.build_slots_by_id.get(slot_id)
	_build_menu.show_options(_menu_options, slot.position)
	_show_range_for_selection(slot)

## 選單只在這幾個值變動時重算。gold 在裡面，因為買得起與否會隨擊殺翻轉。
func _current_menu_signature() -> Array:
	var slot_id := _controller.selected_slot_id
	var occupied := 0
	var level := 0
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(slot_id)
	if slot != null:
		occupied = slot.occupied_by
		var tower := _find_tower_view_owner(occupied)
		if tower != null:
			level = tower.level
	return [slot_id, _sim.world.gold, occupied, level]

## 把原始事件翻成裝置無關的動作，交給控制器。
## 螢幕座標換算成世界座標需要 viewport，所以這一步留在場景。
## 關卡整幅入鏡、無鏡頭平移，因此只差一個畫布變換。
func _unhandled_input(event: InputEvent) -> void:
	var world_position: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position \
		if event is InputEventMouse else Vector2.ZERO
	var action := MouseKeyboardInput.translate(event, world_position)
	if action == null:
		return
	_controller.handle(action, _sim.world)
	get_viewport().set_input_as_handled()

## HUD 的按鈕與鍵盤走同一條路：翻成 InputAction 餵給控制器，而不是直接改 sim。
## B2 已經有測試守著「動作 → 意圖 → 路由器」那條路；另開一條的話那條路上
## 一條測試都沒有，而兩條路遲早會漂移。
func _on_hud_pause_pressed() -> void:
	_controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), _sim.world)

func _on_hud_speed_pressed() -> void:
	_controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), _sim.world)

## 選中有塔的建塔點時顯示現有射程；空位不顯示，要滑過某一瓣才預覽。
func _show_range_for_selection(slot: BuildSlot) -> void:
	if slot.occupied_by == 0:
		_range_circle.hide_circle()
		return
	var tower := _find_tower_view_owner(slot.occupied_by)
	if tower == null:
		_range_circle.hide_circle()
		return
	_range_circle.show_at(tower.position, tower.attack_range)

## 選單的按鈕與鍵盤走同一條路：翻成 InputAction 餵給控制器。
## B2 已經有測試守著「動作 → 意圖 → 路由器」那條路。
func _on_menu_option_chosen(option_index: int) -> void:
	if option_index < 0 or option_index >= _menu_options.size():
		return
	var option: Dictionary = _menu_options[option_index]
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			_controller.handle(InputAction.choose_tower(int(option["choice_index"])), _sim.world)
		BuildMenuOptions.KIND_UPGRADE:
			_controller.handle(InputAction.simple(InputAction.UPGRADE), _sim.world)
		BuildMenuOptions.KIND_SELL:
			_controller.handle(InputAction.simple(InputAction.SELL), _sim.world)

## 滑過某一瓣時預覽那個選擇會帶來的射程。觸控沒有 hover，依已定案的觸控模型
## 點下去就建、不預覽——射程圈預覽是滑鼠獨有的額外好處。
func _on_menu_option_hovered(option_index: int) -> void:
	if option_index < 0 or option_index >= _menu_options.size():
		return
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(_controller.selected_slot_id)
	if slot == null:
		return
	var option: Dictionary = _menu_options[option_index]
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			var levels: Array = _registry.towers[StringName(option["tower_id"])]["levels"]
			_range_circle.show_at(slot.position, float(levels[0]["attack_range"]))
		BuildMenuOptions.KIND_UPGRADE:
			var tower := _find_tower_view_owner(slot.occupied_by)
			if tower == null:
				return
			var next_levels: Array = _registry.towers[tower.tower_id]["levels"]
			_range_circle.show_at(tower.position, float(next_levels[tower.level]["attack_range"]))
		_:
			pass

func _on_menu_option_unhovered() -> void:
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(_controller.selected_slot_id)
	if slot == null:
		_range_circle.hide_circle()
		return
	_show_range_for_selection(slot)
