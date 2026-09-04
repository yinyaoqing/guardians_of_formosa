class_name BattleSim
extends RefCounted

## 固定步長模擬迴圈。渲染幀率與邏輯 tick 解耦，好處是：
##  - 暫停與加速只是「本幀跑幾個 tick」，不必把 delta 乘上倍率（後者必然產生數值錯誤）
##  - 手機掉幀時邏輯不會變慢，戰鬥結果在不同效能裝置上一致

const TICK_RATE := 30
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 單幀最多執行的 tick 數。卡頓後若無上限地補跑積欠的 tick，
## 會讓下一幀更慢、積欠更多，形成死亡螺旋。真正積欠過多時丟棄積欠。
const MAX_TICKS_PER_FRAME := 8

var world: WorldState
var tick_count: int = 0
var speed_multiplier: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

func _init(p_world: WorldState = null) -> void:
	world = p_world if p_world != null else WorldState.new()
	world.projectile_system = ProjectileSystem.new(world)

## 推進模擬。frame_delta 為渲染幀的實際經過秒數。
## 回傳本幀實際執行的 tick 數。
func advance(frame_delta: float) -> int:
	if paused:
		# 排空佇列不受暫停阻擋:建造與賣出正是玩家暫停下來規劃時該做的事,
		# 佇列若在暫停時只進不出,恢復的那一刻就會一次套用整個積壓的佇列。
		# 其餘 tick 步驟(移動、戰鬥……)則照舊完全不跑。
		_apply_pending_intents()
		return 0
	_accumulator += frame_delta * speed_multiplier
	var ticks := 0
	while _accumulator >= TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_DELTA
		_tick()
		ticks += 1
	# 只在真的還積欠超過一個 tick 時才丟棄。「跑滿上限」不等於「積欠很多」——
	# 高速度倍率配低幀率會正好跑滿上限卻只剩極小零頭，那個零頭必須留給下一幀，
	# 否則模擬會悄悄跑得比設定的倍率慢。
	if ticks == MAX_TICKS_PER_FRAME and _accumulator > TICK_DELTA:
		_accumulator = 0.0
	return ticks

## 幀內進度 0.0 ~ 1.0，供表現層做渲染插值使用
func tick_progress() -> float:
	return clampf(_accumulator / TICK_DELTA, 0.0, 1.0)

func _tick() -> void:
	tick_count += 1
	_apply_pending_intents()
	world.status_system.tick(world.enemies, TICK_DELTA)
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	world.projectile_system.tick(TICK_DELTA)
	_tick_towers()
	_remove_dead()

## tick 的第一步。輸入發生在渲染幀上，模擬跑固定步長，兩者不對齊；
## 排隊到 tick 內套用，讓所有改變世界的事情都發生在明確的位置。
## 排第一是為了讓這一 tick 蓋好的塔這一 tick 就能開火，
## 賣掉的塔在能開火之前就消失——兩者都符合直覺且不需要特例。
## B1 只有一個去處,intent 的 kind 分派全交給 BuildSystem 自己做——
## 兩處各維護一份同樣的 kind 清單,日後加一種 kind 就得記得同步改兩處。
## 等之後的里程碑引入不屬於 BuildSystem 的 intent(法術、英雄……),
## 這裡才需要變成真正依 kind 分派到不同系統的路由器。
func _apply_pending_intents() -> void:
	for intent: GameIntent in world.pending_intents:
		BuildSystem.apply(world, intent)
	world.pending_intents.clear()

## 走到終點的敵人扣玩家一條命，並立刻移出戰場（避免重複扣血）
func _collect_leaked() -> void:
	for enemy: Enemy in world.enemies:
		if enemy.leaked and enemy.alive:
			enemy.alive = false
			world.lives -= 1

func _rebuild_grid() -> void:
	world.grid.clear()
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			world.grid.insert(enemy.id, enemy.position)

## 塔只負責發射，不再認識傷害結算。
## DamageSystem 的呼叫點因此收斂為兩處：投射物命中、DoT 結算，兩處都在系統層。
func _tick_towers() -> void:
	for tower: Tower in world.towers:
		tower.cooldown = maxf(0.0, tower.cooldown - TICK_DELTA)
		tower.target_id = TargetingSystem.find_first(tower, world.grid, world.enemies_by_id)
		if tower.target_id == 0 or tower.cooldown > 0.0:
			continue
		world.projectile_system.spawn(
			tower,
			tower.target_id,
			tower.projectile_speed,
			tower.splash_radius,
			tower.on_hit_effects
		)
		tower.cooldown = tower.fire_interval

## 死亡與洩漏的敵人移出集合，並在此處統一發放賞金。
## 傷害來源不只一處（塔、投射物、DoT），賞金邏輯若跟著複製會失去單一事實來源；
## 這裡本來就走訪所有死亡的敵人，且 leaked 旗標剛好能區分「被擊殺」與「走到終點」。
func _remove_dead() -> void:
	var survivors: Array[Enemy] = []
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			survivors.append(enemy)
			continue
		if not enemy.leaked:
			world.gold += enemy.bounty
		# 效果實例的歸還交給 StatusSystem——它是效果池的唯一擁有者。
		# 若這裡自己抓 world.effect_pool 來釋放，一旦有人用不同的池建構
		# StatusSystem（測試裡每一個都是這樣建的），兩邊帳目就會分家。
		world.status_system.release_all(enemy)
		world.enemies_by_id.erase(enemy.id)
	world.enemies = survivors
