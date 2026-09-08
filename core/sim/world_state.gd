class_name WorldState
extends RefCounted

## 一場戰鬥的全部實體與資源。純資料容器，不含模擬邏輯。

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var paths: Dictionary = {}          ## StringName -> PathData

## 狀態效果的 JSON 定義，由表現層在載入關卡時自 DataRegistry 灌入。
## core/ 不自行讀檔，維持可在無檔案系統的情況下被測試。
var effect_defs: Dictionary = {}   ## StringName -> Dictionary

## 塔的 JSON 定義與本關可用的塔種，同樣由 configure_for_level 注入。
var tower_defs: Dictionary = {}              ## StringName -> Dictionary
## 波次系統從這裡造敵人。core/ 不讀檔，所以定義由 configure_for_level 注入，
## 與 tower_defs、effect_defs 同一個模式。
var enemy_defs: Dictionary = {}               ## StringName -> Dictionary
var waves: Array = []                         ## 每筆是一波的定義
var call_bonus_per_second: int = 0
var wave_state := WaveState.new()

## 所有波次都生成完畢，且場上沒有活著的敵人。
##
## 這一關沒有「輸」——第一章規格 §0.2 決定三排除強制失敗關卡，所以這是唯一
## 的結束條件，成立即通關，差別只在救到多少平民。
var battle_finished: bool = false
var available_towers: Array[StringName] = []
var sell_refund_ratio: float = 0.0

var gold: int = 0

## 待撤離的平民數。漏過去一隻敵人就少救一個。
##
## 歸零**不是失敗**——第一章規格 §0.2 決定三明文排除強制失敗關卡：
## 撐過波次即通關，差別在救到多少人。所以這個數字夾在 0，且不觸發任何事。
var civilians_remaining: int = 20

## 平民撤離數的原始總量，供 ResultSystem.star_count() 算第二顆星用。
## civilians_remaining 會隨戰局遞減，星等規則需要的是「總共要救幾個」，
## 兩者不是同一個數字，所以另開一個欄位，不是把 civilians_remaining 覆用。
var starting_civilians: int = 0

## 拿到第二顆星所需的平民撤離門檻。規格是「≥ 門檻」，判定邏輯在
## core/systems/result_system.gd，這裡只負責從關卡資料注入。
var star_civilian_threshold: int = 0

## 每 tick 由 BattleSim 重建的查詢結構
var grid := UniformGrid.new()
var enemies_by_id: Dictionary = {}  ## int -> Enemy

var build_slots: Array[BuildSlot] = []
var build_slots_by_id: Dictionary = {}   ## int -> BuildSlot

## 待處理的玩家意圖。BattleSim 於 tick 第一步排空並套用。
var pending_intents: Array[GameIntent] = []

const EFFECT_POOL_CAPACITY := 64

## 狀態效果實例池與其系統。實例走池化，避免戰鬥迴圈中配置新物件。
var effect_pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), EFFECT_POOL_CAPACITY)
var status_system := StatusSystem.new(effect_pool)

const PROJECTILE_POOL_CAPACITY := 128

var projectiles: Array[Projectile] = []
var projectile_pool := ObjectPool.new(func() -> Projectile: return Projectile.new(), PROJECTILE_POOL_CAPACITY)
var projectile_system: ProjectileSystem = null   ## 由 BattleSim 於建構時注入

var _next_entity_id: int = 1

## 依關卡把整個世界配置好：資料定義、可用塔種、起始資源。
## core/ 不讀檔，所以定義由呼叫端自 DataRegistry 取得後傳入。
##
## 一次呼叫涵蓋全部，是為了讓「忘了接線」只會發生一次，而不是每加一項注入
## 就多一個要記得的地方。M1-A 的最終 review 正是抓到漏接 effect_defs，
## 導致命中狀態效果在實際遊戲中完全失效，而所有測試照樣通過。
func configure_for_level(registry: DataRegistry, level_id: StringName) -> void:
	assert(registry.levels.has(level_id), "找不到關卡定義: %s" % level_id)
	var meta: Dictionary = registry.levels[level_id]

	effect_defs = registry.status_effects
	tower_defs = registry.towers
	enemy_defs = registry.enemies

	var towers_for_level: Array[StringName] = []
	for tower_id in meta["available_towers"]:
		towers_for_level.append(StringName(tower_id))
	available_towers = towers_for_level

	sell_refund_ratio = meta["sell_refund_ratio"]
	gold = int(meta["starting_gold"])
	civilians_remaining = int(meta["starting_civilians"])
	starting_civilians = int(meta["starting_civilians"])
	star_civilian_threshold = int(meta["star_civilian_threshold"])

	waves = meta.get("waves", [])
	call_bonus_per_second = int(meta.get("call_bonus_per_second", 0))
	reset_wave_state()

func add_enemy(enemy: Enemy) -> void:
	if enemy.id == 0:
		enemy.id = next_id()
	enemies.append(enemy)
	enemies_by_id[enemy.id] = enemy

func add_tower(tower: Tower) -> void:
	if tower.id == 0:
		tower.id = next_id()
	towers.append(tower)

func add_build_slot(slot: BuildSlot) -> void:
	if slot.id == 0:
		slot.id = next_id()
	build_slots.append(slot)
	build_slots_by_id[slot.id] = slot

func queue_intent(intent: GameIntent) -> void:
	pending_intents.append(intent)

## 配發一個全新的實體 id。敵人、塔、投射物共用同一個遞增計數器，
## 確保 id 在型別之間也不重複。
func next_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id

## 把波次狀態重設到第一波的倒數。configure_for_level 之後、以及測試裡
## 直接指定 waves 之後都要呼叫，否則倒數是 0、第一波會立刻開始。
func reset_wave_state() -> void:
	wave_state = WaveState.new()
	if not waves.is_empty():
		wave_state.countdown = float(waves[0]["delay"])
