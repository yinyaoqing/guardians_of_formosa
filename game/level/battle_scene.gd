extends Node2D

## 表現層的組裝點：
##  1. 從 map.json 的折線等距取樣出 PathData（core/ 不接觸 Curve2D，也不再需要 Path2D）
##  2. 驅動 BattleSim
##  3. 依模擬狀態建立與更新 view

## 取樣間距同時決定小兵崗位的精度：BuildSystem._assign_post() 掃過 world.paths 的
## 所有取樣點取最近者。改這個值會連帶改變崗位落點（M1-B5 規格 §5.3）。
const PATH_SAMPLE_SPACING := 8.0
const MAIN_PATH_ID := &"main"
const LEVEL_ID := &"level_01"

const EnemyViewScript := preload("res://game/views/enemy_view.gd")
const TowerViewScript := preload("res://game/views/tower_view.gd")
const ProjectileViewScript := preload("res://game/views/projectile_view.gd")
const BuildSlotViewScript := preload("res://game/views/build_slot_view.gd")
const SoldierViewScript := preload("res://game/views/soldier_view.gd")

## 置換用的投射物貼圖。之後應改為依 Projectile.projectile_id 從資料查表，
## 目前銃樓與獵寮共用同一張，寫成常數即可。
const PROJECTILE_SPRITE := "res://game/assets/placeholder_projectile.png"

## 建塔點的美術。空位時顯示，蓋了塔就隱藏——塔就站在同一個座標上。
const SLOT_SPRITE := "res://game/assets/chapter01/prop_buildsite.png"

const TILES_ATLAS := "res://game/assets/chapter01/tiles.png"
const SHADOW_ELLIPSE := "res://game/assets/chapter01/shadow_ellipse.png"
const PROP_ASSET_DIR := "res://game/assets/chapter01"

const BattleHudScene := preload("res://ui/battle_hud.tscn")
const BuildMenuScene := preload("res://ui/build_menu.tscn")
const ResultPanelScene := preload("res://ui/result_panel.tscn")
const RangeCircleScript := preload("res://game/views/range_circle.gd")

@onready var _view_root: Node2D = $Views

var _registry := DataRegistry.new()
var _sim: BattleSim
var _level_map: LevelMap
var _ground: GroundLayer
var _props: PropLayer
var _enemy_views: Dictionary = {}       ## int -> EnemyView
var _tower_views: Dictionary = {}       ## int -> TowerView
var _projectile_views: Dictionary = {}  ## instance_id -> ProjectileView
var _slot_views: Dictionary = {}        ## slot_id -> BuildSlotView
var _soldier_views: Dictionary = {}     ## int -> SoldierView
var _controller := InteractionController.new()
var _hud: BattleHud = null

## 每座塔上次畫出來的等級。升級換圖靠它偵測，與 HUD 只在值變動時才寫 Label
## 是同一個手法——每幀無條件重載一張 128px 的圖是白燒的。
var _shown_tower_levels: Dictionary = {}   ## tower id -> int

var _build_menu: BuildMenu = null
var _range_circle: RangeCircle = null
var _result_panel: ResultPanel = null
var _result_shown: bool = false

## 上一次同步 view 時的平民數。用來換算「這一批消失的敵人裡有幾個是走到終點的」，
## 見 _release_vanished_enemy_views()。
var _shown_civilians: int = 0

## 選單目前畫的是哪一批選項。拆成結構與金錢兩個簽章，理由見 _update_build_menu()。
var _menu_structural_signature: Array = []
var _menu_gold: int = -1
var _menu_options: Array[Dictionary] = []

func _ready() -> void:
	_registry.load_from_disk()

	var meta: Dictionary = _registry.levels[LEVEL_ID]
	assert(meta.has("map"), "關卡 %s 沒有 map.json" % LEVEL_ID)
	_level_map = LevelMap.new(meta["map"])

	# 地面與擺件放在 CanvasLayer -10：一定在單位（根層，layer 0）之下，
	# 而且描邊 pass（layer -5）只看得到它們、看不到單位。
	var ground_layers := CanvasLayer.new()
	ground_layers.name = "GroundLayers"
	ground_layers.layer = -10
	add_child(ground_layers)
	_ground = GroundLayer.new()
	_ground.setup(_level_map, load(TILES_ATLAS))
	ground_layers.add_child(_ground)
	_props = PropLayer.new()
	_props.setup(_level_map, PROP_ASSET_DIR, load(SHADOW_ELLIPSE))
	ground_layers.add_child(_props)

	var world := WorldState.new()
	world.configure_for_level(_registry, LEVEL_ID)
	# 路徑必須在任何塔被建造之前填好：BuildSystem._assign_post() 在建塔當下
	# 掃過 world.paths 取最近的取樣點當小兵崗位（M1-B5 規格 §5.3）。
	world.paths[MAIN_PATH_ID] = PathData.new(_level_map.sample_path(PATH_SAMPLE_SPACING), PATH_SAMPLE_SPACING)
	_shown_civilians = world.civilians_remaining

	_sim = BattleSim.new(world)
	_bake_build_slots(world)
	InputBindings.install()

	# 紙紋 pass 與 HUD 同在 CanvasLayer 1，靠加入順序決定上下：這行必須在 HUD 之前。
	PaperOverlay.attach(self)

	_hud = BattleHudScene.instantiate() as BattleHud
	add_child(_hud)
	_hud.setup(world, _sim, StringName(_registry.levels[LEVEL_ID]["name_key"]))
	_hud.pause_pressed.connect(_on_hud_pause_pressed)
	_hud.speed_pressed.connect(_on_hud_speed_pressed)
	_hud.call_wave_pressed.connect(_on_hud_call_wave_pressed)

	_build_menu = BuildMenuScene.instantiate() as BuildMenu
	add_child(_build_menu)
	_build_menu.option_chosen.connect(_on_menu_option_chosen)
	_build_menu.option_hovered.connect(_on_menu_option_hovered)
	_build_menu.option_unhovered.connect(_on_menu_option_unhovered)

	_range_circle = RangeCircleScript.new() as RangeCircle
	_view_root.add_child(_range_circle)

	_result_panel = ResultPanelScene.instantiate() as ResultPanel
	add_child(_result_panel)
	_result_panel.restart_pressed.connect(_on_restart_pressed)

func _process(delta: float) -> void:
	# 暫停時 advance 回傳 0，但佇列仍會被排空（建造與賣出正是玩家暫停下來規劃時
	# 要做的事）。只看 ticks 的話，暫停中蓋的塔要到恢復才出現在畫面上。
	var had_intents := not _sim.world.pending_intents.is_empty()
	var ticks := _sim.advance(delta)

	if ticks > 0 or had_intents:
		_sync_views()
	_interpolate_views()
	# 通關後停止更新選取提示與建造選單：advance() 已經回傳 0、_apply_pending_intents()
	# 不會再跑，這裡若繼續呼叫，點擊建塔點排出的意圖就會卡在 pending_intents 裡
	# 永遠沒有人清空，had_intents 因此永遠是 true，_sync_views() 也會跟著永遠執行。
	if not _sim.world.battle_finished:
		_update_slot_views()
	_update_result_panel()

## 建塔點由 map.json 指定格子，LevelMap 換算成像素座標交給 core/。
## core/ 不認得格子與貼圖，與 LevelMap → PathData 是同一個分層邊界。
##
## 場景裡不再有 Marker2D：建塔點與路徑同出於 map.json 這一份真相，
## 兩套並存的話 BuildSystem 不知道哪一組才算數。
func _bake_build_slots(world: WorldState) -> void:
	for pos in _level_map.build_slot_positions():
		var slot := BuildSlot.new()
		slot.position = pos
		world.add_build_slot(slot)

		var view := BuildSlotViewScript.new() as BuildSlotView
		view.setup(slot.id, SLOT_SPRITE, slot.position)
		_view_root.add_child(view)
		_slot_views[slot.id] = view

## 每個邏輯 tick 後同步一次：推進插值目標、清掉已死亡的 view
func _sync_views() -> void:
	for enemy: Enemy in _sim.world.enemies:
		var view: EnemyView = _enemy_views.get(enemy.id)
		if view == null:
			# 生成搬進 tick 之後，建立 view 的責任跟著移到這裡。
			# 先用敵人當下的座標建，才不會從畫面原點滑進來。
			view = EnemyViewScript.new() as EnemyView
			var def: Dictionary = _registry.enemies[enemy.enemy_id]
			# puppet 是分件行走的拆件資料；沒有這個鍵的敵人退回整張圖，view 自己處理。
			view.setup(enemy.id, def["sprite"], enemy.position, def.get("puppet", ""))
			_view_root.add_child(view)
			_enemy_views[enemy.id] = view
		else:
			view.on_tick(enemy.position, enemy.hp / maxf(enemy.max_hp, 1.0))

	_release_vanished_enemy_views()

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

	_sync_soldier_views()
	_sync_projectile_views()

## 敵人從模擬消失有兩種原因：被擊殺（倒下淡出）、走到終點（直接消失）。
## 模擬不回頭告訴 view 是哪一種，而 leaked 旗標在同一個 tick 內就被
## _collect_leaked() 與 _remove_dead() 用掉了，表現層看不到它。
##
## 用座標距離去猜會與 core 的判定不同步（core 判的是 distance_along >=
## total_length()，不是像素距離）。改成向 core 要一個精確的**數量**：
## 每個走到終點的敵人正好讓 civilians_remaining 少一，所以這一批消失的
## view 裡，走到終點的恰好有「平民數的減少量」個。哪幾個則以「離路徑終點
## 多近」排序決定——同一批裡同時有擊殺與洩漏時，最靠近終點的那個就是洩漏的。
## 數量永遠正確；只有「同一次同步內兩者並存」時才依賴這個排序。
func _release_vanished_enemy_views() -> void:
	var vanished: Array[int] = []
	for view_id: int in _enemy_views.keys():
		if not _sim.world.enemies_by_id.has(view_id):
			vanished.append(view_id)
	if vanished.is_empty():
		return

	var leaked_count := maxi(0, _shown_civilians - _sim.world.civilians_remaining)
	_shown_civilians = _sim.world.civilians_remaining

	if leaked_count > 0 and vanished.size() > 1:
		var path_end: Vector2 = _sim.world.paths[MAIN_PATH_ID].position_at(INF)
		vanished.sort_custom(func(a: int, b: int) -> bool:
			return (_enemy_views[a] as EnemyView).position.distance_squared_to(path_end) 				< (_enemy_views[b] as EnemyView).position.distance_squared_to(path_end))

	for i in vanished.size():
		var view: EnemyView = _enemy_views[vanished[i]]
		if i < leaked_count:
			view.queue_free()
		else:
			view.play_death()
		_enemy_views.erase(vanished[i])

## 小兵的崗位固定不動，所以沒有插值，只有血量在變。
func _sync_soldier_views() -> void:
	for soldier: Soldier in _sim.world.soldiers:
		var view: SoldierView = _soldier_views.get(soldier.id)
		if view == null:
			view = SoldierViewScript.new() as SoldierView
			view.setup(soldier.id, soldier.position, soldier.slot_index)
			_view_root.add_child(view)
			_soldier_views[soldier.id] = view
		view.on_tick(soldier.hp / maxf(1.0, soldier.max_hp))

	for view_id: int in _soldier_views.keys():
		if not _sim.world.soldiers_by_id.has(view_id):
			var view: SoldierView = _soldier_views[view_id]
			view.queue_free()
			_soldier_views.erase(view_id)

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
			_play_tower_fire(projectile)
		else:
			view.on_tick(projectile.position)

	for view_id: int in _projectile_views.keys():
		if not live.has(view_id):
			var view: ProjectileView = _projectile_views[view_id]
			view.queue_free()
			_projectile_views.erase(view_id)

## 投射物只記得塔種不記得是哪一座（source_tower_id 是 StringName），
## 但它生成在發射它的塔的座標上——用座標找回那座塔，播後座與槍口閃光。
const FIRE_MATCH_PX := 12.0

func _play_tower_fire(projectile: Projectile) -> void:
	var target: Enemy = _sim.world.enemies_by_id.get(projectile.target_id)
	if target == null:
		return
	for tower: Tower in _sim.world.towers:
		if tower.position.distance_to(projectile.position) <= FIRE_MATCH_PX:
			var view: TowerView = _tower_views.get(tower.id)
			if view != null:
				view.play_fire(target.position)
			return

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
##
## 簽章拆成兩半，因為它們的變動頻率與該做的事完全不同：
##  - 結構簽章 [slot_id, occupied, level]：決定「有哪些選項存在」，只在選取、
##    建造、升級、賣出時變。變了才值得 show_options() 重建按鈕。
##  - gold：只決定「已存在的選項買不買得起」，orc_grunt 每 1.5 秒死一隻就變一次。
##    合在一起會導致戰鬥中每秒重建一次按鈕——玩家按著滑鼠不放時按鈕被
##    queue_free() 掉，pressed 永遠不會發出；hover 中的射程圈預覽也會被
##    重建後跟著跑的 _show_range_for_selection 打回目前等級，一秒閃一次。
## 只有 gold 變、結構沒變時，改成重算選項後原地更新既有按鈕的變暗顯示。
func _update_build_menu() -> void:
	var slot_id := _controller.selected_slot_id
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(slot_id)
	var structural := _current_menu_structural_signature(slot_id, slot)
	var gold := _sim.world.gold

	if structural == _menu_structural_signature:
		if gold != _menu_gold:
			_menu_gold = gold
			# 選單沒開（空選項）就沒有按鈕可更新，重算也是白工。
			if not _menu_options.is_empty():
				_menu_options = BuildMenuOptions.for_slot(_sim.world, slot_id)
				_build_menu.update_affordability(_menu_options)
		return

	_menu_structural_signature = structural
	_menu_gold = gold
	_menu_options = BuildMenuOptions.for_slot(_sim.world, slot_id)
	if _menu_options.is_empty():
		_build_menu.hide_menu()
		_range_circle.hide_circle()
		return

	# show_options 絕對不能一幀內被叫兩次：_clear() 的 queue_free() 是延後生效，
	# 兩次呼叫之間舊按鈕還掛著、還連著 signal，發出的會是對不上新陣列的舊索引。
	# 這個函式一幀只會進到這裡一次（結構簽章已經改過了），所以這個前提仍然成立。
	#
	# slot.position 是世界座標，這裡直接當成 BuildMenu（CanvasLayer）底下的
	# Control 座標用。今天成立是因為場景根在原點、沒有 Camera2D、
	# stretch mode 對兩者的縮放相同；哪天鏡頭一動，這裡要跟著換成螢幕座標。
	_build_menu.show_options(_menu_options, slot.position)
	_show_range_for_selection(slot)

func _current_menu_structural_signature(slot_id: int, slot: BuildSlot) -> Array:
	var occupied := 0
	var level := 0
	if slot != null:
		occupied = slot.occupied_by
		var tower := _find_tower_view_owner(occupied)
		if tower != null:
			level = tower.level
	return [slot_id, occupied, level]

## 把原始事件翻成裝置無關的動作，交給控制器。
## 螢幕座標換算成世界座標需要 viewport，所以這一步留在場景。
## 關卡整幅入鏡、無鏡頭平移，因此只差一個畫布變換。
##
## 通關後直接不理會輸入：advance() 已經回傳 0，選取與建造再也沒有意義，
## 讓 _controller 繼續處理只會把意圖排進一個永遠沒人清空的佇列。
## 結算面板自己的按鈕不受影響——Button 是 Control，會在 GUI 事件階段
## 先吃掉點擊、直接呼叫它自己的 pressed，事件根本不會落到這裡的
## _unhandled_input；只有沒被任何 Control 接住的事件才會走到這裡。
func _unhandled_input(event: InputEvent) -> void:
	if _sim.world.battle_finished:
		return
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
## HUD 的按鈕走 GUI 事件階段，Button 會就地消費掉點擊並發 signal——**完全不經過
## _unhandled_input**，所以那裡的通關檢查擋不到它們。通關後 advance() 回傳 0、
## 佇列不再被排空，這三顆若不各自擋一次，每按一下就往永遠不會清空的佇列塞一筆。
func _hud_input_accepted() -> bool:
	return not _sim.world.battle_finished

func _on_hud_pause_pressed() -> void:
	if not _hud_input_accepted():
		return
	_controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), _sim.world)

func _on_hud_speed_pressed() -> void:
	if not _hud_input_accepted():
		return
	_controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), _sim.world)

func _on_hud_call_wave_pressed() -> void:
	if not _hud_input_accepted():
		return
	_controller.handle(InputAction.simple(InputAction.CALL_NEXT_WAVE), _sim.world)

## 通關時把結算面板叫出來。只叫一次——面板不是每幀重畫的東西。
##
## 星等規則住在 core/systems/result_system.gd，這裡只負責讀 WorldState 顯示——
## 門檻與起始平民數都經由 configure_for_level() 注入，不再直接讀 registry。
func _update_result_panel() -> void:
	if _result_shown or not _sim.world.battle_finished:
		return
	_result_shown = true

	# 通關後就不再更新選單與射程圈了（見 _process 的說明），所以要在這裡收一次，
	# 否則最後一隻敵人剛好在選單開著時死掉，那個選單會凍在結算面板旁邊直到重來。
	_build_menu.hide_menu()
	_range_circle.hide_circle()

	var stars := ResultSystem.star_count(_sim.world)
	_result_panel.show_result(stars, _sim.world.waves.size(), _sim.world.civilians_remaining, _sim.world.starting_civilians)

func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

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
			# 兵營的等級資料沒有 attack_range 鍵，這是 BuildSystem 分派兩種塔的
			# 同一個 schema 差異（_apply_shooter_stats / _apply_barracks_stats）。
			# .get(..., 0.0) 讓兵營回傳 0.0，show_at() 本來就會因此隱藏射程圈——
			# 兵營本來就沒有射程，不該畫圈。
			_range_circle.show_at(slot.position, float(levels[0].get("attack_range", 0.0)))
		BuildMenuOptions.KIND_UPGRADE:
			var tower := _find_tower_view_owner(slot.occupied_by)
			if tower == null:
				return
			var next_levels: Array = _registry.towers[tower.tower_id]["levels"]
			# 同上：兵營沒有 attack_range 鍵。
			_range_circle.show_at(tower.position, float(next_levels[tower.level].get("attack_range", 0.0)))
		_:
			pass

func _on_menu_option_unhovered() -> void:
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(_controller.selected_slot_id)
	if slot == null:
		_range_circle.hide_circle()
		return
	_show_range_for_selection(slot)
