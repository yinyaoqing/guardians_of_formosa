# M0 戰鬥核心骨架 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 Godot 專案骨架與純邏輯戰鬥核心，讓一隻敵人沿路徑行進、一座塔偵測並擊殺它，且全部核心邏輯有單元測試覆蓋、CI 綠燈。

**Architecture:** 戰鬥邏輯寫成不依賴 SceneTree 的純 GDScript 類別（`RefCounted`），可在 headless 模式下直接單元測試；Node2D 表現層只讀取模擬狀態並做渲染插值。模擬以 30Hz 固定步長推進，與渲染幀率解耦。

**Tech Stack:** Godot 4.x（GL Compatibility 渲染器）、GDScript、GdUnit4 測試框架、GitHub Actions CI、Git LFS。

## Global Constraints

這些是專案級規則，**每個任務的要求都隱含包含本節**。出自 `docs/superpowers/specs/2026-09-04-tower-defense-architecture-design.md`。

- 只使用 Godot 4.x API。禁用 `KinematicBody2D`、`yield`、`export var` 等 Godot 3.x 寫法（Godot 4 用 `CharacterBody2D`、`await`、`@export`）。
- 只使用 GDScript，不引入 C#。
- `core/` 不得 import 任何 Node 或引擎場景類別。允許使用非 Node 的引擎類別（`FileAccess`、`DirAccess`、`JSON`、`Vector2`、`PackedVector2Array`）。
- 依賴方向單向：`game/`、`ui/`、`input/` 可讀 `core/`；`core/` 永不反向依賴。
- 傷害一律經過 `DamageSystem.apply()`，禁止在塔或任何其他程式碼中自行計算傷害。
- 實體之間一律以字串 id 互相引用，不存直接物件引用。
- 邏輯 tick 固定為 30Hz（`TICK_DELTA = 1.0 / 30.0`）。
- 所有遊戲資料以 JSON 定義，置於 `data/`，不使用 `.tres`。
- UI 與資料中只存 i18n key，不存字面文字。
- 戰鬥迴圈中禁止配置新物件（M0 尚無投射物，此規則自 M1 起實質生效）。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `project.godot` | Godot 專案設定：渲染器、視窗拉伸模式 |
| `.gitignore` / `.gitattributes` | 排除 `.godot/` 與 `art_src/`；行尾正規化；圖片音效走 LFS |
| `.godot-version` | 鎖定引擎版本，CI 讀取此檔 |
| `CLAUDE.md` | 專案硬規則，供 AI 協作時遵循 |
| `core/spatial/path_data.gd` | 等距取樣路徑，距離 → 座標查詢 |
| `core/spatial/uniform_grid.gd` | 均勻網格空間索引（broad phase） |
| `core/entities/enemy.gd` | 敵人邏輯狀態 |
| `core/entities/tower.gd` | 塔邏輯狀態 |
| `core/systems/movement_system.gd` | 沿路徑推進與洩漏判定 |
| `core/systems/targeting_system.gd` | 目標選擇（First 策略） |
| `core/systems/damage_system.gd` | 唯一的傷害結算入口 |
| `core/sim/world_state.gd` | 一場戰鬥的全部實體集合 |
| `core/sim/battle_sim.gd` | 固定步長 tick 迴圈，串接各系統 |
| `core/data/data_registry.gd` | JSON 載入與 id 查表 |
| `data/enemies/*.json`、`data/towers/*.json` | 資料定義 |
| `game/level/battle_scene.tscn` / `.gd` | 表現層組裝：Path2D 取樣、驅動模擬、生成 view |
| `game/views/enemy_view.gd` / `tower_view.gd` | 渲染插值 |
| `tests/core/*.gd` | 單元測試 |
| `tests/test_data_integrity.gd` | 資料完整性驗證 |
| `tests/test_core_purity.gd` | 自動化守衛：core/ 不得依賴 Node |
| `.github/workflows/tests.yml` | CI |

---

### Task 1: 專案骨架、版控設定與測試執行器

建立可執行的 Godot 專案與可運作的測試框架。此任務的驗收就是「一個最小測試能跑起來並通過」——若 GdUnit4 的 CLI 路徑或斷言 API 與本計畫所寫不同，此任務會立刻暴露，而不會變成後續任務的潛在錯誤。

**Files:**
- Create: `project.godot`（由 Godot 編輯器產生後修改）
- Create: `.gitignore`, `.gitattributes`, `.godot-version`, `CLAUDE.md`
- Create: `addons/gdUnit4/`（第三方，透過 AssetLib 安裝）
- Test: `tests/test_smoke.gd`

**Interfaces:**
- Consumes: 無
- Produces: 可執行的測試命令 `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests`

- [ ] **Step 1: 安裝 Godot 4.x 並鎖定版本**

前往 https://godotengine.org/download 下載目前的 **Godot 4.x 穩定版標準版**（不是 .NET 版——本專案不使用 C#）。解壓到固定位置，並把執行檔加入 PATH。

驗證安裝並把實際版本寫入版本鎖定檔：

```bash
godot --version
godot --version > .godot-version
cat .godot-version
```

Expected: 印出類似 `4.x.stable.official.<hash>` 的字串，且 `.godot-version` 內容相同。

- [ ] **Step 2: 建立 Godot 專案**

開啟 Godot 編輯器 → New Project → 路徑選 `c:/Users/yinya/git/guardians_of_formosa` → 專案名稱 `Guardians of Formosa` → **Renderer 選 `Compatibility`**（GL Compatibility 是中階 Android 上達成 60fps 最穩妥的選擇，且 2D 專案用不到 Forward+ 的功能）→ Create & Edit。

- [ ] **Step 3: 設定專案的視窗與拉伸模式**

在編輯器中 Project → Project Settings，設定以下項目（對應規格第 6.4 節的畫面適配策略）：

| 設定項 | 值 |
|---|---|
| Display → Window → Size → Viewport Width | `1920` |
| Display → Window → Size → Viewport Height | `1080` |
| Display → Window → Stretch → Mode | `canvas_items` |
| Display → Window → Stretch → Aspect | `expand` |

存檔後確認 `project.godot` 含有這些鍵：

```bash
grep -E "viewport_width|viewport_height|stretch/mode|stretch/aspect|rendering_method" project.godot
```

Expected: 五行都有輸出，`stretch/mode="canvas_items"`、`stretch/aspect="expand"`、`rendering_method="gl_compatibility"`。

- [ ] **Step 4: 建立 .gitignore**

```gitignore
# Godot 4 產生的匯入快取與暫存
.godot/
/android/
*.tmp
*.translation

# 匯出設定含本機路徑與金鑰，不進版控
export_presets.cfg

# AI 生成的原始美術素材不進 git（見規格 8.2）
# 以本地 + 雲端硬碟備份，只有裁切壓縮後的成品進 game/assets/
art_src/
```

- [ ] **Step 5: 建立 .gitattributes**

這一步同時解決行尾正規化與 LFS 設定。**必須在任何二進位資產進版控之前完成**，事後從 git 歷史清除 LFS 檔案成本極高。

```gitattributes
# 文字檔一律以 LF 儲存，避免 Windows 與 CI 之間的行尾差異
* text=auto eol=lf
*.gd text eol=lf
*.tscn text eol=lf
*.tres text eol=lf
*.json text eol=lf
*.md text eol=lf
*.cfg text eol=lf
*.godot text eol=lf

# 圖片與音效走 Git LFS
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.ogg filter=lfs diff=lfs merge=lfs -text
*.wav filter=lfs diff=lfs merge=lfs -text
```

- [ ] **Step 6: 初始化 Git LFS**

```bash
git lfs install --local
git lfs track
```

Expected: `git lfs track` 列出 `.gitattributes` 中的五條 LFS 規則。

- [ ] **Step 7: 建立目錄結構**

```bash
mkdir -p core/sim core/entities core/systems core/spatial core/data
mkdir -p data/enemies data/towers
mkdir -p game/views game/fx game/level game/assets
mkdir -p ui input platform
mkdir -p tests/core
mkdir -p .github/workflows
```

- [ ] **Step 8: 安裝 GdUnit4**

在 Godot 編輯器中：AssetLib 分頁 → 搜尋 `gdUnit4` → 選 **gdUnit4**（作者 MikeSchulze）→ Download → Install。安裝後 Project → Project Settings → Plugins → 勾選啟用 **gdUnit4**。重啟編輯器。

確認外掛已就位：

```bash
ls addons/gdUnit4/bin/GdUnitCmdTool.gd
```

Expected: 印出該路徑。若路徑不同（GdUnit4 版本差異），記下實際路徑，後續所有測試命令與 CI 設定都要改用實際路徑。

- [ ] **Step 9: 寫一個最小測試，確認框架與斷言 API 可用**

Create `tests/test_smoke.gd`:

```gdscript
extends GdUnitTestSuite

## 冒煙測試：確認 GdUnit4 已正確安裝，且本計畫使用的斷言 API 存在。
## 後續所有測試都只使用這裡驗證過的斷言形式。

func test_int_assertion() -> void:
	assert_int(2 + 2).is_equal(4)

func test_float_assertion() -> void:
	assert_float(0.1 + 0.2).is_equal_approx(0.3, 0.0001)

func test_bool_assertion() -> void:
	assert_bool(true).is_true()
	assert_bool(false).is_false()

func test_str_assertion() -> void:
	assert_str("hello world").contains("world")

func test_array_assertion() -> void:
	assert_array([1, 2, 3]).has_size(3)
	assert_array([1, 2, 3]).contains([2])

func test_comparison_assertions() -> void:
	assert_int(5).is_greater(3)
	assert_float(0.5).is_between(0.0, 1.0)

func test_custom_failure_message_api() -> void:
	# 後續的資料完整性測試大量使用 override_failure_message 指出是哪一筆資料出錯
	assert_bool(true).override_failure_message("這個訊息不該出現").is_true()
```

- [ ] **Step 10: 執行測試**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

Expected: 5 個測試全部通過，行程結束碼為 0。

若命令失敗或斷言 API 不存在，**現在就修正**：查閱 `addons/gdUnit4/README.md` 或 GdUnit4 官方文件確認該版本的 CLI 與斷言寫法，並把本計畫後續任務中的測試碼改成對應寫法。這是本任務的核心價值——把框架不確定性擋在第一關。

- [ ] **Step 11: 建立 CLAUDE.md**

```markdown
# Guardians of Formosa — AI 協作規則

完整架構設計見 `docs/superpowers/specs/2026-09-04-tower-defense-architecture-design.md`。

## 硬規則（違反即為 bug，不是風格問題）

1. **`core/` 不得 import 任何 Node 或引擎場景類別。** 允許 `FileAccess`、`DirAccess`、`JSON`、`Vector2` 等非 Node 類別。此規則由 `tests/test_core_purity.gd` 自動驗證。
2. **傷害一律經過 `DamageSystem.apply()`。** 禁止在塔、法術、英雄的程式碼中自行計算傷害減免。
3. **實體之間只用字串 id 互相引用**（如 `"enemy_id": "orc_grunt"`），不存直接物件引用。
4. **只使用 Godot 4.x API。** 禁用 `KinematicBody2D`（用 `CharacterBody2D`）、`yield`（用 `await`）、`export var`（用 `@export`）。
5. **戰鬥迴圈中禁止配置新物件**，投射物與特效一律走物件池。

## 其他約定

- 只用 GDScript，不引入 C#。
- 遊戲資料一律 JSON，置於 `data/`，不使用 `.tres`。
- UI 與資料中只存 i18n key，不存字面文字。
- 邏輯 tick 固定 30Hz。

## 測試

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

UI 與畫面不做自動化測試，人工驗收。
```

- [ ] **Step 12: 提交**

```bash
git add .gitignore .gitattributes .godot-version CLAUDE.md project.godot addons tests/test_smoke.gd
git commit -m "chore: 建立 Godot 專案骨架與 GdUnit4 測試環境"
```

---

### Task 2: PathData — 路徑取樣與距離查詢

**Files:**
- Create: `core/spatial/path_data.gd`
- Test: `tests/core/test_path_data.gd`

**Interfaces:**
- Consumes: 無
- Produces:
  - `PathData.new(points: PackedVector2Array, spacing: float) -> PathData`
  - `PathData.total_length() -> float`
  - `PathData.position_at(distance: float) -> Vector2`

`core/` 不接觸 `Curve2D`：等距取樣由 `game/level/` 完成（Task 10），把結果點陣列傳進來。這讓路徑邏輯可以用純陣列測試。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_path_data.gd`:

```gdscript
extends GdUnitTestSuite

## 一條水平直線路徑：(0,0) → (100,0) → (200,0)，取樣間距 100
func _make_straight_path() -> PathData:
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
	])
	return PathData.new(points, 100.0)

func test_total_length_is_spacing_times_segments() -> void:
	assert_float(_make_straight_path().total_length()).is_equal_approx(200.0, 0.001)

func test_position_at_start() -> void:
	var pos := _make_straight_path().position_at(0.0)
	assert_float(pos.x).is_equal_approx(0.0, 0.001)

func test_position_at_midpoint_interpolates() -> void:
	var pos := _make_straight_path().position_at(150.0)
	assert_float(pos.x).is_equal_approx(150.0, 0.001)

func test_position_before_start_clamps_to_first_point() -> void:
	var pos := _make_straight_path().position_at(-50.0)
	assert_float(pos.x).is_equal_approx(0.0, 0.001)

func test_position_beyond_end_clamps_to_last_point() -> void:
	var pos := _make_straight_path().position_at(999.0)
	assert_float(pos.x).is_equal_approx(200.0, 0.001)

func test_position_exactly_at_end_returns_last_point() -> void:
	var pos := _make_straight_path().position_at(200.0)
	assert_float(pos.x).is_equal_approx(200.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_path_data.gd
```

Expected: FAIL，錯誤訊息指出識別字 `PathData` 未定義。

- [ ] **Step 3: 寫最小實作**

Create `core/spatial/path_data.gd`:

```gdscript
class_name PathData
extends RefCounted

## 等距取樣後的路徑。敵人只持有「沿路徑已行進距離」，
## 由本類別換算成座標。因為取樣是等距的，換算是 O(1)。
##
## 取樣工作由 game/level/ 從 Curve2D 完成後傳入，core/ 不接觸引擎的曲線類別。

var _points: PackedVector2Array
var _spacing: float
var _total_length: float

func _init(points: PackedVector2Array, spacing: float) -> void:
	assert(points.size() >= 2, "PathData 至少需要兩個取樣點")
	assert(spacing > 0.0, "取樣間距必須為正數")
	_points = points
	_spacing = spacing
	_total_length = spacing * float(points.size() - 1)

func total_length() -> float:
	return _total_length

## 回傳沿路徑行進 distance 後的座標。超出兩端時夾在端點。
func position_at(distance: float) -> Vector2:
	if distance <= 0.0:
		return _points[0]
	if distance >= _total_length:
		return _points[_points.size() - 1]
	var exact := distance / _spacing
	var index := int(exact)
	var t := exact - float(index)
	return _points[index].lerp(_points[index + 1], t)
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_path_data.gd
```

Expected: 6 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/spatial/path_data.gd tests/core/test_path_data.gd
git commit -m "feat(core): 新增 PathData 等距取樣路徑"
```

---

### Task 3: BattleSim — 固定步長 tick 迴圈

**Files:**
- Create: `core/sim/battle_sim.gd`
- Test: `tests/core/test_battle_sim.gd`

**Interfaces:**
- Consumes: 無
- Produces:
  - `BattleSim.TICK_RATE: int = 30`、`BattleSim.TICK_DELTA: float`
  - `BattleSim.new() -> BattleSim`
  - `BattleSim.advance(frame_delta: float) -> int`（回傳本幀實際執行的 tick 數）
  - `BattleSim.tick_count: int`、`BattleSim.speed_multiplier: float`、`BattleSim.paused: bool`

本任務只建立 tick 迴圈本身，不串接任何系統。Task 8 才把 world 與各系統掛進 `_tick()`。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_battle_sim.gd`:

```gdscript
extends GdUnitTestSuite

const FRAME_60FPS := 1.0 / 60.0

func test_one_second_of_60fps_frames_produces_30_ticks() -> void:
	var sim := BattleSim.new()
	for i in 60:
		sim.advance(FRAME_60FPS)
	assert_int(sim.tick_count).is_equal(30)

func test_paused_sim_does_not_tick() -> void:
	var sim := BattleSim.new()
	sim.paused = true
	var ticks := sim.advance(FRAME_60FPS * 10.0)
	assert_int(ticks).is_equal(0)
	assert_int(sim.tick_count).is_equal(0)

func test_double_speed_doubles_tick_count() -> void:
	var sim := BattleSim.new()
	sim.speed_multiplier = 2.0
	for i in 60:
		sim.advance(FRAME_60FPS)
	assert_int(sim.tick_count).is_equal(60)

func test_partial_frames_accumulate_without_loss() -> void:
	# 每幀不足一個 tick，但累積滿了就該觸發
	var sim := BattleSim.new()
	var ticks_first := sim.advance(0.01)
	assert_int(ticks_first).is_equal(0)
	sim.advance(0.01)
	sim.advance(0.01)
	sim.advance(0.01)
	# 累積 0.04 秒 > TICK_DELTA (0.0333)，應已跑過一次
	assert_int(sim.tick_count).is_equal(1)

func test_huge_frame_delta_is_capped_and_backlog_discarded() -> void:
	# 防死亡螺旋：卡頓一整秒後不該試圖補跑 30 個 tick
	var sim := BattleSim.new()
	var ticks := sim.advance(1.0)
	assert_int(ticks).is_equal(BattleSim.MAX_TICKS_PER_FRAME)
	# 積欠已被丟棄，下一個正常幀不該爆量
	var next_ticks := sim.advance(FRAME_60FPS)
	assert_int(next_ticks).is_equal(0)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_battle_sim.gd
```

Expected: FAIL，識別字 `BattleSim` 未定義。

- [ ] **Step 3: 寫最小實作**

Create `core/sim/battle_sim.gd`:

```gdscript
class_name BattleSim
extends RefCounted

## 固定步長模擬迴圈。渲染幀率與邏輯 tick 解耦，好處是：
##  - 暫停與加速只是「本幀跑幾個 tick」，不必把 delta 乘上倍率（後者必然產生數值錯誤）
##  - 手機掉幀時邏輯不會變慢，戰鬥結果在不同效能裝置上一致

const TICK_RATE := 30
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 單幀最多執行的 tick 數。卡頓後若無上限地補跑積欠的 tick，
## 會讓下一幀更慢、積欠更多，形成死亡螺旋。超過上限就丟棄積欠。
const MAX_TICKS_PER_FRAME := 8

var tick_count: int = 0
var speed_multiplier: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

## 推進模擬。frame_delta 為渲染幀的實際經過秒數。
## 回傳本幀實際執行的 tick 數。
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	_accumulator += frame_delta * speed_multiplier
	var ticks := 0
	while _accumulator >= TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_DELTA
		_tick()
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0
	return ticks

func _tick() -> void:
	tick_count += 1
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_battle_sim.gd
```

Expected: 5 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/sim/battle_sim.gd tests/core/test_battle_sim.gd
git commit -m "feat(core): 新增 BattleSim 固定步長 tick 迴圈"
```

---

### Task 4: Enemy 實體與 MovementSystem

**Files:**
- Create: `core/entities/enemy.gd`
- Create: `core/systems/movement_system.gd`
- Test: `tests/core/test_movement_system.gd`

**Interfaces:**
- Consumes: `PathData`（Task 2）
- Produces:
  - `Enemy.new() -> Enemy`，欄位：`id: int`、`enemy_id: StringName`、`hp: float`、`max_hp: float`、`speed: float`、`armor: float`、`magic_resist: float`、`bounty: int`、`path_id: StringName`、`distance_along: float`、`position: Vector2`、`alive: bool`、`leaked: bool`、`blocked_by: int`
  - `MovementSystem.tick(enemies: Array, paths: Dictionary, delta: float) -> void`

`position` 由 MovementSystem 每 tick 更新並快取，讓 TargetingSystem（Task 6）不必重複換算。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_movement_system.gd`:

```gdscript
extends GdUnitTestSuite

const PATH_ID := &"main"

func _make_paths() -> Dictionary:
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
	])
	return {PATH_ID: PathData.new(points, 100.0)}

func _make_enemy() -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.speed = 50.0
	enemy.path_id = PATH_ID
	return enemy

func test_enemy_advances_by_speed_times_delta() -> void:
	var enemy := _make_enemy()
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(50.0, 0.001)

func test_position_is_cached_after_tick() -> void:
	var enemy := _make_enemy()
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.position.x).is_equal_approx(50.0, 0.001)

func test_enemy_reaching_path_end_is_marked_leaked() -> void:
	var enemy := _make_enemy()
	enemy.distance_along = 190.0
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_bool(enemy.leaked).is_true()
	assert_float(enemy.distance_along).is_equal_approx(200.0, 0.001)

func test_leaked_enemy_does_not_advance_further() -> void:
	var enemy := _make_enemy()
	enemy.leaked = true
	enemy.distance_along = 200.0
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(200.0, 0.001)

func test_dead_enemy_does_not_advance() -> void:
	var enemy := _make_enemy()
	enemy.alive = false
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)

func test_blocked_enemy_does_not_advance() -> void:
	# 攔截機制不是重新尋路，而是停止推進 distance_along
	var enemy := _make_enemy()
	enemy.blocked_by = 42
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_movement_system.gd
```

Expected: FAIL，識別字 `Enemy` 未定義。

- [ ] **Step 3: 寫 Enemy**

Create `core/entities/enemy.gd`:

```gdscript
class_name Enemy
extends RefCounted

## 敵人的邏輯狀態。純資料，沒有行為——行為由 systems/ 下的各系統負責。

var id: int = 0
var enemy_id: StringName = &""

var hp: float = 0.0
var max_hp: float = 0.0
var speed: float = 0.0            ## 像素 / 秒
var armor: float = 0.0            ## 物理減免比例，0.0 ~ 0.95
var magic_resist: float = 0.0     ## 魔法減免比例，0.0 ~ 0.95
var bounty: int = 0               ## 擊殺獎勵金

var path_id: StringName = &""
var distance_along: float = 0.0   ## 沿路徑已行進距離
var position: Vector2 = Vector2.ZERO  ## 由 MovementSystem 每 tick 快取

var alive: bool = true
var leaked: bool = false          ## 已走到路徑終點，玩家扣血

## 攔截者的實體 id，0 表示未被攔截。M1 的士兵系統會用到。
var blocked_by: int = 0
```

- [ ] **Step 4: 寫 MovementSystem**

Create `core/systems/movement_system.gd`:

```gdscript
class_name MovementSystem
extends RefCounted

## 沿固定路徑推進敵人。不做尋路——路徑在編輯器畫好並烘焙成等距點陣列，
## 敵人只需要累加「已行進距離」。

static func tick(enemies: Array, paths: Dictionary, delta: float) -> void:
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.leaked:
			continue
		if enemy.blocked_by != 0:
			continue
		var path: PathData = paths[enemy.path_id]
		enemy.distance_along += enemy.speed * delta
		if enemy.distance_along >= path.total_length():
			enemy.distance_along = path.total_length()
			enemy.leaked = true
		enemy.position = path.position_at(enemy.distance_along)
```

- [ ] **Step 5: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_movement_system.gd
```

Expected: 6 個測試全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add core/entities/enemy.gd core/systems/movement_system.gd tests/core/test_movement_system.gd
git commit -m "feat(core): 新增 Enemy 實體與 MovementSystem"
```

---

### Task 5: UniformGrid 空間索引

**Files:**
- Create: `core/spatial/uniform_grid.gd`
- Test: `tests/core/test_uniform_grid.gd`

**Interfaces:**
- Consumes: 無
- Produces:
  - `UniformGrid.CELL_SIZE: float = 64.0`
  - `UniformGrid.new() -> UniformGrid`
  - `UniformGrid.clear() -> void`
  - `UniformGrid.insert(entity_id: int, position: Vector2) -> void`
  - `UniformGrid.query_radius(center: Vector2, radius: float) -> Array[int]`

`query_radius` 是 **broad phase**：回傳的是「可能在範圍內」的候選 id，呼叫端必須自行做精確距離判定。這個分工要在註解裡寫清楚，否則會被誤用。

**實作陷阱**：格子的容器必須用 `Array[int]` 而非 `PackedInt32Array`。GDScript 的 `Packed*Array` 是值型別，`_cells[key].append(x)` 會修改暫存副本而非字典裡的陣列，且不會報錯——這是會靜默失敗的那種 bug。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_uniform_grid.gd`:

```gdscript
extends GdUnitTestSuite

func test_empty_grid_returns_no_candidates() -> void:
	var grid := UniformGrid.new()
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).has_size(0)

func test_inserted_entity_is_found_in_range() -> void:
	var grid := UniformGrid.new()
	grid.insert(7, Vector2(10, 10))
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).contains([7])

func test_multiple_entities_in_same_cell_are_all_returned() -> void:
	# 驗證值型別陷阱：同格多筆資料不得互相覆蓋
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(10, 10))
	grid.insert(2, Vector2(20, 20))
	grid.insert(3, Vector2(30, 30))
	assert_array(grid.query_radius(Vector2(20, 20), 50.0)).has_size(3)

func test_entity_far_outside_radius_is_not_returned() -> void:
	var grid := UniformGrid.new()
	grid.insert(7, Vector2(1000, 1000))
	assert_array(grid.query_radius(Vector2.ZERO, 50.0)).has_size(0)

func test_query_spans_multiple_cells() -> void:
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(-100, 0))
	grid.insert(2, Vector2(100, 0))
	assert_array(grid.query_radius(Vector2.ZERO, 150.0)).has_size(2)

func test_clear_removes_all_entities() -> void:
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(10, 10))
	grid.clear()
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).has_size(0)

func test_negative_coordinates_are_handled() -> void:
	# floori 對負數的行為與 int() 截斷不同，必須用 floori
	var grid := UniformGrid.new()
	grid.insert(5, Vector2(-10, -10))
	assert_array(grid.query_radius(Vector2(-10, -10), 10.0)).contains([5])
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_uniform_grid.gd
```

Expected: FAIL，識別字 `UniformGrid` 未定義。

- [ ] **Step 3: 寫最小實作**

Create `core/spatial/uniform_grid.gd`:

```gdscript
class_name UniformGrid
extends RefCounted

## 均勻網格空間索引。100+ 敵人配 20+ 座塔時，逐幀暴力比對是 O(n²)，
## 手機承受不了。改為把敵人索引進固定格子，塔只查詢射程覆蓋到的格子。
##
## 每 tick 整個重建（clear + 逐筆 insert）比維護增量更新簡單，且效能足夠。

const CELL_SIZE := 64.0

## Vector2i -> Array[int]
## 必須用 Array 而非 PackedInt32Array：後者是值型別，
## _cells[key].append() 會修改暫存副本而非字典裡的陣列，且不會報錯。
var _cells: Dictionary = {}

func clear() -> void:
	_cells.clear()

func insert(entity_id: int, position: Vector2) -> void:
	var key := _cell_of(position)
	if not _cells.has(key):
		var bucket: Array[int] = []
		_cells[key] = bucket
	var existing: Array[int] = _cells[key]
	existing.append(entity_id)

## Broad phase：回傳「可能」落在半徑內的候選 id。
## 呼叫端必須自行做精確距離判定——本方法只保證不漏，不保證不多。
func query_radius(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var min_cell := _cell_of(center - Vector2(radius, radius))
	var max_cell := _cell_of(center + Vector2(radius, radius))
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(x, y)
			if _cells.has(key):
				var bucket: Array[int] = _cells[key]
				result.append_array(bucket)
	return result

func _cell_of(position: Vector2) -> Vector2i:
	# 用 floori 而非 int()：int() 對負數是向零截斷，會讓 -10 與 10 落在同格
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_uniform_grid.gd
```

Expected: 7 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/spatial/uniform_grid.gd tests/core/test_uniform_grid.gd
git commit -m "feat(core): 新增 UniformGrid 空間索引"
```

---

### Task 6: Tower 實體與 TargetingSystem

**Files:**
- Create: `core/entities/tower.gd`
- Create: `core/systems/targeting_system.gd`
- Test: `tests/core/test_targeting_system.gd`

**Interfaces:**
- Consumes: `Enemy`（Task 4）、`UniformGrid`（Task 5）
- Produces:
  - `Tower.new() -> Tower`，欄位：`id: int`、`tower_id: StringName`、`position: Vector2`、`level: int`、`damage: float`、`damage_type: StringName`、`attack_range: float`、`fire_interval: float`、`cooldown: float`、`target_id: int`
  - `TargetingSystem.find_first(tower: Tower, grid: UniformGrid, enemies_by_id: Dictionary) -> int`（回傳敵人 id，找不到回傳 0）

欄位名用 `attack_range` 而非 `range`：`range` 是 GDScript 內建函式名，當成成員變數會在類別內遮蔽它。

First 策略之所以便宜，是因為敵人沿路徑走，「最前面」就是 `distance_along` 最大者——不需要任何幾何運算。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_targeting_system.gd`:

```gdscript
extends GdUnitTestSuite

func _make_tower() -> Tower:
	var tower := Tower.new()
	tower.id = 100
	tower.tower_id = &"archer_tower"
	tower.position = Vector2.ZERO
	tower.attack_range = 200.0
	tower.damage = 10.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = 1.0
	return tower

func _make_enemy(id: int, pos: Vector2, distance_along: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = id
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.position = pos
	enemy.distance_along = distance_along
	return enemy

## 把敵人陣列灌進 grid 與 id 查表，回傳 [grid, enemies_by_id]
func _index(enemies: Array) -> Array:
	var grid := UniformGrid.new()
	var by_id: Dictionary = {}
	for enemy: Enemy in enemies:
		grid.insert(enemy.id, enemy.position)
		by_id[enemy.id] = enemy
	return [grid, by_id]

func test_no_enemies_returns_zero() -> void:
	var indexed := _index([])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(0)

func test_single_enemy_in_range_is_selected() -> void:
	var indexed := _index([_make_enemy(1, Vector2(50, 0), 50.0)])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(1)

func test_enemy_outside_range_is_not_selected() -> void:
	# 落在 grid 查詢的方形範圍內，但超出圓形射程——驗證精確距離判定有做
	var indexed := _index([_make_enemy(1, Vector2(190, 190), 50.0)])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(0)

func test_first_strategy_picks_furthest_along_path() -> void:
	var indexed := _index([
		_make_enemy(1, Vector2(50, 0), 50.0),
		_make_enemy(2, Vector2(100, 0), 120.0),
		_make_enemy(3, Vector2(80, 0), 90.0),
	])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)

func test_dead_enemy_is_skipped() -> void:
	var dead := _make_enemy(1, Vector2(100, 0), 150.0)
	dead.alive = false
	var alive := _make_enemy(2, Vector2(50, 0), 50.0)
	var indexed := _index([dead, alive])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)

func test_leaked_enemy_is_skipped() -> void:
	var leaked := _make_enemy(1, Vector2(100, 0), 150.0)
	leaked.leaked = true
	var normal := _make_enemy(2, Vector2(50, 0), 50.0)
	var indexed := _index([leaked, normal])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_targeting_system.gd
```

Expected: FAIL，識別字 `Tower` 未定義。

- [ ] **Step 3: 寫 Tower**

Create `core/entities/tower.gd`:

```gdscript
class_name Tower
extends RefCounted

## 塔的邏輯狀態。純資料，行為由 systems/ 負責。
## 特別注意：射程欄位叫 attack_range 而非 range——range 是 GDScript 內建函式。

var id: int = 0
var tower_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var level: int = 1

var damage: float = 0.0
var damage_type: StringName = &"physical"
var attack_range: float = 0.0
var fire_interval: float = 1.0    ## 兩次攻擊的間隔秒數

var cooldown: float = 0.0         ## 距離下次可攻擊的剩餘秒數
var target_id: int = 0            ## 當前鎖定的敵人 id，0 表示無目標
```

- [ ] **Step 4: 寫 TargetingSystem**

Create `core/systems/targeting_system.gd`:

```gdscript
class_name TargetingSystem
extends RefCounted

## 目標選擇。First 策略（射程內最接近終點者）在塔防裡特別便宜：
## 敵人沿固定路徑走，「最前面」就是 distance_along 最大者，不需要幾何運算。

## 回傳射程內 distance_along 最大的敵人 id，找不到時回傳 0。
static func find_first(tower: Tower, grid: UniformGrid, enemies_by_id: Dictionary) -> int:
	var candidates := grid.query_radius(tower.position, tower.attack_range)
	var best_id := 0
	var best_distance := -1.0
	var range_squared := tower.attack_range * tower.attack_range
	for candidate_id in candidates:
		var enemy: Enemy = enemies_by_id[candidate_id]
		if not enemy.alive or enemy.leaked:
			continue
		# grid 只做 broad phase，這裡補上精確的圓形射程判定
		if tower.position.distance_squared_to(enemy.position) > range_squared:
			continue
		if enemy.distance_along > best_distance:
			best_distance = enemy.distance_along
			best_id = enemy.id
	return best_id
```

- [ ] **Step 5: 執行測試確認通過**

測試引用了 `DamageSystem.PHYSICAL`，該常數在 Task 7 才建立。先把測試中的 `DamageSystem.PHYSICAL` 暫時改為 `&"physical"`，執行測試：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_targeting_system.gd
```

Expected: 6 個測試全部 PASS。Task 7 完成後再改回 `DamageSystem.PHYSICAL`。

- [ ] **Step 6: 提交**

```bash
git add core/entities/tower.gd core/systems/targeting_system.gd tests/core/test_targeting_system.gd
git commit -m "feat(core): 新增 Tower 實體與 TargetingSystem First 策略"
```

---

### Task 7: DamageSystem

**Files:**
- Create: `core/systems/damage_system.gd`
- Modify: `tests/core/test_targeting_system.gd`（把暫用的 `&"physical"` 改回 `DamageSystem.PHYSICAL`）
- Test: `tests/core/test_damage_system.gd`

**Interfaces:**
- Consumes: `Enemy`（Task 4）
- Produces:
  - `DamageSystem.PHYSICAL: StringName`、`DamageSystem.MAGIC: StringName`、`DamageSystem.TRUE_DAMAGE: StringName`
  - `DamageSystem.apply(enemy: Enemy, amount: float, damage_type: StringName) -> float`（回傳實際造成的傷害）

這是**唯一的傷害結算入口**。塔防的技術債幾乎都長在傷害計算散落各處，所以這條規則寫進 CLAUDE.md 並由 code review 把關。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_damage_system.gd`:

```gdscript
extends GdUnitTestSuite

func _make_enemy(armor: float, magic_resist: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.armor = armor
	enemy.magic_resist = magic_resist
	return enemy

func test_physical_damage_is_reduced_by_armor() -> void:
	var enemy := _make_enemy(0.5, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(50.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(50.0, 0.001)

func test_magic_damage_ignores_armor_and_uses_magic_resist() -> void:
	var enemy := _make_enemy(0.9, 0.25)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.MAGIC)
	assert_float(dealt).is_equal_approx(75.0, 0.001)

func test_true_damage_ignores_all_reduction() -> void:
	var enemy := _make_enemy(0.9, 0.9)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.TRUE_DAMAGE)
	assert_float(dealt).is_equal_approx(100.0, 0.001)

func test_lethal_damage_marks_enemy_dead_and_clamps_hp_to_zero() -> void:
	var enemy := _make_enemy(0.0, 0.0)
	DamageSystem.apply(enemy, 250.0, DamageSystem.PHYSICAL)
	assert_bool(enemy.alive).is_false()
	assert_float(enemy.hp).is_equal_approx(0.0, 0.001)

func test_damage_to_dead_enemy_deals_nothing() -> void:
	var enemy := _make_enemy(0.0, 0.0)
	enemy.alive = false
	var dealt := DamageSystem.apply(enemy, 50.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(0.0, 0.001)

func test_full_armor_reduction_deals_no_damage_but_does_not_heal() -> void:
	var enemy := _make_enemy(1.0, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(0.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_damage_system.gd
```

Expected: FAIL，識別字 `DamageSystem` 未定義。

- [ ] **Step 3: 寫最小實作**

Create `core/systems/damage_system.gd`:

```gdscript
class_name DamageSystem
extends RefCounted

## 唯一的傷害結算入口。任何塔、法術、英雄都不得自行計算傷害減免——
## 傷害計算一旦散落各處，數值平衡就無法推理，這是塔防最常見的技術債來源。
##
## 結算順序固定：
##   1. 依傷害類型取得減免比例
##   2. 套用減免
##   3. 扣血
##   4. 判定死亡

const PHYSICAL := &"physical"
const MAGIC := &"magic"
const TRUE_DAMAGE := &"true"

## 對敵人造成傷害，回傳實際造成的傷害值。
static func apply(enemy: Enemy, amount: float, damage_type: StringName) -> float:
	if not enemy.alive:
		return 0.0

	var reduction := 0.0
	match damage_type:
		PHYSICAL:
			reduction = enemy.armor
		MAGIC:
			reduction = enemy.magic_resist
		TRUE_DAMAGE:
			reduction = 0.0
		_:
			push_error("未知的傷害類型: %s" % damage_type)
			return 0.0

	var dealt := maxf(0.0, amount * (1.0 - reduction))
	enemy.hp -= dealt
	if enemy.hp <= 0.0:
		enemy.hp = 0.0
		enemy.alive = false
	return dealt
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_damage_system.gd
```

Expected: 6 個測試全部 PASS。

- [ ] **Step 5: 把 TargetingSystem 測試改回具名常數**

在 `tests/core/test_targeting_system.gd` 的 `_make_tower()` 中，把：

```gdscript
	tower.damage_type = &"physical"
```

改回：

```gdscript
	tower.damage_type = DamageSystem.PHYSICAL
```

- [ ] **Step 6: 執行全部測試**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

Expected: 全部通過。

- [ ] **Step 7: 提交**

```bash
git add core/systems/damage_system.gd tests/core/test_damage_system.gd tests/core/test_targeting_system.gd
git commit -m "feat(core): 新增 DamageSystem 統一傷害結算"
```

---

### Task 8: WorldState 與 BattleSim 串接

把各系統接進 tick 迴圈，形成完整的戰鬥模擬：敵人前進 → 重建空間索引 → 塔選目標 → 冷卻到期則開火 → 結算傷害與獎勵金。

**Files:**
- Create: `core/sim/world_state.gd`
- Modify: `core/sim/battle_sim.gd`
- Test: `tests/core/test_battle_integration.gd`

**Interfaces:**
- Consumes: `Enemy`、`Tower`、`PathData`、`UniformGrid`、`MovementSystem`、`TargetingSystem`、`DamageSystem`
- Produces:
  - `WorldState.new() -> WorldState`，欄位：`enemies: Array[Enemy]`、`towers: Array[Tower]`、`paths: Dictionary`、`gold: int`、`lives: int`、`grid: UniformGrid`、`enemies_by_id: Dictionary`
  - `WorldState.add_enemy(enemy: Enemy) -> void`、`WorldState.add_tower(tower: Tower) -> void`
  - `BattleSim.new(world: WorldState) -> BattleSim`（建構子簽章變更）
  - `BattleSim.world: WorldState`

- [ ] **Step 1: 寫 WorldState**

Create `core/sim/world_state.gd`:

```gdscript
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
```

- [ ] **Step 2: 寫失敗的整合測試**

Create `tests/core/test_battle_integration.gd`:

```gdscript
extends GdUnitTestSuite

const FRAME_60FPS := 1.0 / 60.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
		Vector2(300, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 100.0)
	world.gold = 0
	world.lives = 20
	return world

func _add_enemy(world: WorldState, hp: float, speed: float, bounty: int) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.speed = speed
	enemy.bounty = bounty
	enemy.path_id = PATH_ID
	world.add_enemy(enemy)
	return enemy

func _add_tower(world: WorldState, pos: Vector2, damage: float, fire_interval: float) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.attack_range = 150.0
	tower.damage = damage
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = fire_interval
	world.add_tower(tower)
	return tower

## 推進模擬指定秒數
func _run(sim: BattleSim, seconds: float) -> void:
	var frames := int(seconds / FRAME_60FPS)
	for i in frames:
		sim.advance(FRAME_60FPS)

func test_tower_kills_enemy_in_range() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 30.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_bool(enemy.alive).is_false()

func test_killing_enemy_awards_bounty_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 10.0, 0.0, 7)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 3.0)
	assert_int(world.gold).is_equal(7)

func test_enemy_reaching_end_costs_a_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_int(world.lives).is_equal(19)

func test_leaked_enemy_only_costs_one_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 5.0)
	assert_int(world.lives).is_equal(19)

func test_tower_out_of_range_does_not_damage() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 100.0, 0.0, 5)
	enemy.position = Vector2(0, 0)
	_add_tower(world, Vector2(1000, 1000), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)

func test_fire_interval_limits_shots() -> void:
	# 1 秒內、射速 0.5 秒一發，最多打 2 發 = 20 傷害
	var world := _make_world()
	var enemy := _add_enemy(world, 1000.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 1.0)
	assert_float(enemy.hp).is_between(970.0, 990.0)
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_battle_integration.gd
```

Expected: FAIL，`BattleSim.new()` 不接受參數。

- [ ] **Step 4: 改寫 BattleSim 串接各系統**

Replace `core/sim/battle_sim.gd` 全部內容:

```gdscript
class_name BattleSim
extends RefCounted

## 固定步長模擬迴圈。渲染幀率與邏輯 tick 解耦，好處是：
##  - 暫停與加速只是「本幀跑幾個 tick」，不必把 delta 乘上倍率（後者必然產生數值錯誤）
##  - 手機掉幀時邏輯不會變慢，戰鬥結果在不同效能裝置上一致

const TICK_RATE := 30
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 單幀最多執行的 tick 數。卡頓後若無上限地補跑積欠的 tick，
## 會讓下一幀更慢、積欠更多，形成死亡螺旋。超過上限就丟棄積欠。
const MAX_TICKS_PER_FRAME := 8

var world: WorldState
var tick_count: int = 0
var speed_multiplier: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

func _init(p_world: WorldState = null) -> void:
	world = p_world if p_world != null else WorldState.new()

## 推進模擬。frame_delta 為渲染幀的實際經過秒數。
## 回傳本幀實際執行的 tick 數。
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	_accumulator += frame_delta * speed_multiplier
	var ticks := 0
	while _accumulator >= TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_DELTA
		_tick()
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0
	return ticks

func _tick() -> void:
	tick_count += 1
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	_tick_towers()
	_remove_dead()

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

func _tick_towers() -> void:
	for tower: Tower in world.towers:
		tower.cooldown = maxf(0.0, tower.cooldown - TICK_DELTA)
		tower.target_id = TargetingSystem.find_first(tower, world.grid, world.enemies_by_id)
		if tower.target_id == 0 or tower.cooldown > 0.0:
			continue
		var target: Enemy = world.enemies_by_id[tower.target_id]
		DamageSystem.apply(target, tower.damage, tower.damage_type)
		tower.cooldown = tower.fire_interval
		if not target.alive and not target.leaked:
			world.gold += target.bounty

## 死亡與洩漏的敵人移出集合。M0 直接移除；M1 會改成先播死亡動畫再移除。
func _remove_dead() -> void:
	var survivors: Array[Enemy] = []
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			survivors.append(enemy)
		else:
			world.enemies_by_id.erase(enemy.id)
	world.enemies = survivors
```

- [ ] **Step 5: 修正 Task 3 的 BattleSim 測試**

`tests/core/test_battle_sim.gd` 中的 `BattleSim.new()` 現在會建立空的 `WorldState`，測試仍應通過。執行確認：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/core/test_battle_sim.gd
```

Expected: 5 個測試全部 PASS。若失敗，檢查 `_init` 的預設參數是否正確。

- [ ] **Step 6: 執行整合測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

Expected: 全部測試 PASS。

- [ ] **Step 7: 提交**

```bash
git add core/sim/world_state.gd core/sim/battle_sim.gd tests/core/test_battle_integration.gd
git commit -m "feat(core): 串接 WorldState 與各系統至 BattleSim tick 迴圈"
```

---

### Task 9: DataRegistry 與資料完整性測試

**Files:**
- Create: `core/data/data_registry.gd`
- Create: `data/enemies/orc_grunt.json`
- Create: `data/towers/archer_tower.json`
- Modify: `project.godot`（匯出時包含 JSON）
- Test: `tests/test_data_integrity.gd`

**Interfaces:**
- Consumes: 無
- Produces:
  - `DataRegistry.new() -> DataRegistry`
  - `DataRegistry.load_from_disk(root: String = "res://data") -> void`
  - `DataRegistry.enemies: Dictionary`（StringName -> Dictionary）
  - `DataRegistry.towers: Dictionary`（StringName -> Dictionary）
  - `DataRegistry.make_enemy(enemy_id: StringName, path_id: StringName) -> Enemy`

- [ ] **Step 1: 建立敵人資料**

Create `data/enemies/orc_grunt.json`:

```json
{
  "id": "orc_grunt",
  "name_key": "enemy.orc_grunt.name",
  "hp": 120.0,
  "speed": 45.0,
  "armor": 0.2,
  "magic_resist": 0.0,
  "bounty": 6,
  "sprite": "res://game/assets/placeholder_enemy.png",
  "frame_count": 8
}
```

- [ ] **Step 2: 建立塔資料**

Create `data/towers/archer_tower.json`:

```json
{
  "id": "archer_tower",
  "name_key": "tower.archer_tower.name",
  "damage_type": "physical",
  "levels": [
    {"cost": 70,  "damage": 9.0,  "attack_range": 180.0, "fire_interval": 0.8},
    {"cost": 130, "damage": 14.0, "attack_range": 190.0, "fire_interval": 0.75},
    {"cost": 220, "damage": 22.0, "attack_range": 200.0, "fire_interval": 0.7}
  ],
  "sprite": "res://game/assets/placeholder_tower.png"
}
```

- [ ] **Step 3: 寫失敗的完整性測試**

Create `tests/test_data_integrity.gd`:

```gdscript
extends GdUnitTestSuite

## 把資料錯誤變成測試失敗，而不是執行到那一關才黑屏。
## 這條防線在 AI 協作下投報率極高：改完數值跑測試就知道有沒有改壞。

var _registry: DataRegistry

func before_test() -> void:
	_registry = DataRegistry.new()
	_registry.load_from_disk()

func test_at_least_one_enemy_is_loaded() -> void:
	assert_int(_registry.enemies.size()).is_greater(0)

func test_at_least_one_tower_is_loaded() -> void:
	assert_int(_registry.towers.size()).is_greater(0)

func test_every_enemy_has_required_fields() -> void:
	var required := ["id", "name_key", "hp", "speed", "armor", "magic_resist", "bounty", "sprite"]
	for enemy_id: StringName in _registry.enemies:
		var def: Dictionary = _registry.enemies[enemy_id]
		for field: String in required:
			assert_bool(def.has(field)).override_failure_message(
				"敵人 %s 缺少必填欄位 %s" % [enemy_id, field]
			).is_true()

func test_every_enemy_has_sane_numbers() -> void:
	for enemy_id: StringName in _registry.enemies:
		var def: Dictionary = _registry.enemies[enemy_id]
		assert_float(def["hp"]).override_failure_message(
			"敵人 %s 的 hp 必須為正" % enemy_id
		).is_greater(0.0)
		assert_float(def["speed"]).override_failure_message(
			"敵人 %s 的 speed 必須為正" % enemy_id
		).is_greater(0.0)
		assert_float(def["armor"]).is_between(0.0, 0.95)
		assert_float(def["magic_resist"]).is_between(0.0, 0.95)

func test_every_tower_level_has_required_fields() -> void:
	var required := ["cost", "damage", "attack_range", "fire_interval"]
	for tower_id: StringName in _registry.towers:
		var def: Dictionary = _registry.towers[tower_id]
		assert_bool(def.has("levels")).is_true()
		for level_def: Dictionary in def["levels"]:
			for field: String in required:
				assert_bool(level_def.has(field)).override_failure_message(
					"塔 %s 的某個等級缺少欄位 %s" % [tower_id, field]
				).is_true()

func test_tower_upgrade_costs_increase() -> void:
	for tower_id: StringName in _registry.towers:
		var levels: Array = _registry.towers[tower_id]["levels"]
		for i in range(1, levels.size()):
			assert_int(levels[i]["cost"]).override_failure_message(
				"塔 %s 第 %d 級的造價必須高於前一級" % [tower_id, i + 1]
			).is_greater(levels[i - 1]["cost"])

func test_tower_damage_types_are_known() -> void:
	var known := [DamageSystem.PHYSICAL, DamageSystem.MAGIC, DamageSystem.TRUE_DAMAGE]
	for tower_id: StringName in _registry.towers:
		var damage_type := StringName(_registry.towers[tower_id]["damage_type"])
		assert_bool(known.has(damage_type)).override_failure_message(
			"塔 %s 的傷害類型 %s 不是已知類型" % [tower_id, damage_type]
		).is_true()

func test_every_referenced_sprite_path_exists() -> void:
	for enemy_id: StringName in _registry.enemies:
		var path: String = _registry.enemies[enemy_id]["sprite"]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"敵人 %s 引用的貼圖不存在: %s" % [enemy_id, path]
		).is_true()
	for tower_id: StringName in _registry.towers:
		var path: String = _registry.towers[tower_id]["sprite"]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"塔 %s 引用的貼圖不存在: %s" % [tower_id, path]
		).is_true()
```

- [ ] **Step 4: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_data_integrity.gd
```

Expected: FAIL，識別字 `DataRegistry` 未定義。

- [ ] **Step 5: 寫 DataRegistry**

Create `core/data/data_registry.gd`:

```gdscript
class_name DataRegistry
extends RefCounted

## JSON 資料載入與 id 查表。
## 使用 FileAccess / DirAccess / JSON——這些是引擎類別但不是 Node，
## 因此不違反「core/ 不依賴 Node」的規則。

var enemies: Dictionary = {}   ## StringName -> Dictionary
var towers: Dictionary = {}    ## StringName -> Dictionary

func load_from_disk(root: String = "res://data") -> void:
	enemies = _load_dir(root.path_join("enemies"))
	towers = _load_dir(root.path_join("towers"))

## 依 id 建出一個 Enemy 實體。id 引用失敗時直接報錯——
## 靜默回傳 null 會讓錯誤在很遠的地方才炸開。
func make_enemy(enemy_id: StringName, path_id: StringName) -> Enemy:
	assert(enemies.has(enemy_id), "找不到敵人定義: %s" % enemy_id)
	var def: Dictionary = enemies[enemy_id]
	var enemy := Enemy.new()
	enemy.enemy_id = enemy_id
	enemy.hp = def["hp"]
	enemy.max_hp = def["hp"]
	enemy.speed = def["speed"]
	enemy.armor = def["armor"]
	enemy.magic_resist = def["magic_resist"]
	enemy.bounty = def["bounty"]
	enemy.path_id = path_id
	return enemy

func _load_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	assert(dir != null, "找不到資料目錄: %s" % dir_path)
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var full_path := dir_path.path_join(file_name)
		var text := FileAccess.get_file_as_string(full_path)
		var parsed: Variant = JSON.parse_string(text)
		assert(parsed is Dictionary, "JSON 格式錯誤: %s" % full_path)
		var def: Dictionary = parsed
		assert(def.has("id"), "資料檔缺少 id 欄位: %s" % full_path)
		result[StringName(def["id"])] = def
	return result
```

- [ ] **Step 6: 建立置換貼圖**

完整性測試要求引用的貼圖真的存在。用 Godot 編輯器建立兩張最小的置換圖：

在編輯器中新增一個 Sprite2D，或直接用任意繪圖工具產生兩張 64×64 的純色 PNG，存為：
- `game/assets/placeholder_enemy.png`（紅色方塊）
- `game/assets/placeholder_tower.png`（藍色方塊）

存檔後讓 Godot 匯入它們（編輯器會自動掃描）。確認：

```bash
ls game/assets/placeholder_enemy.png game/assets/placeholder_tower.png
ls game/assets/*.png.import
```

Expected: 兩張 PNG 與對應的 `.import` 檔都存在。

注意：這兩張 PNG 會走 Git LFS（Task 1 的 `.gitattributes` 已設定）。

- [ ] **Step 7: 設定匯出時包含 JSON**

Godot 預設不會把 `.json` 打包進匯出檔。在 Project → Export → Resources 分頁，於「Filters to export non-resource files/folders」欄位填入：

```
*.json
```

此設定寫在 `export_presets.cfg`，該檔不進版控（含本機路徑），所以**要在 README 記下這一步**，換機時需重設。

Create `README.md`:

```markdown
# Guardians of Formosa

塔防遊戲。架構設計見 `docs/superpowers/specs/`，實作計畫見 `docs/superpowers/plans/`。

## 環境需求

- Godot 4.x 標準版（非 .NET 版），版本見 `.godot-version`
- Git LFS

## 執行測試

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

## 換機或重建匯出設定時的必要步驟

`export_presets.cfg` 不進版控（含本機路徑），重建匯出設定時必須手動補上：

- Project → Export → Resources → **Filters to export non-resource files/folders** 填 `*.json`
  （否則 `data/` 下的 JSON 不會被打包，遊戲在匯出版本會找不到資料）
```

- [ ] **Step 8: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

Expected: 全部測試 PASS，包含 8 個資料完整性測試。

- [ ] **Step 9: 提交**

```bash
git add core/data/data_registry.gd data/ game/assets/ tests/test_data_integrity.gd README.md project.godot
git commit -m "feat(core): 新增 DataRegistry JSON 載入與資料完整性測試"
```

---

### Task 10: core 純淨度守衛測試

把「`core/` 不得依賴 Node」從一條靠自律的規則，變成一條會失敗的測試。這是整份架構最容易被侵蝕的規則，而侵蝕之後可測試性就沒了。

**Files:**
- Create: `tests/test_core_purity.gd`

**Interfaces:**
- Consumes: 無
- Produces: 無（純守衛測試）

- [ ] **Step 1: 寫守衛測試**

Create `tests/test_core_purity.gd`:

```gdscript
extends GdUnitTestSuite

## 自動化驗證 CLAUDE.md 硬規則 #1：core/ 不得依賴 Node 或場景。
## 這條規則一旦破壞，core/ 就無法在 headless 下單元測試，
## 整個分層架構的價值就消失了——所以用測試把它釘死。

const CORE_ROOT := "res://core"

## 出現這些字串即代表 core/ 碰到了 Node 或場景系統
const FORBIDDEN_PATTERNS := [
	"extends Node",
	"extends Node2D",
	"extends CanvasItem",
	"extends Control",
	"extends Resource",
	".tscn",
	"get_tree()",
	"get_node(",
	"add_child(",
	"queue_free(",
]

func test_core_scripts_do_not_depend_on_nodes() -> void:
	var scripts := _collect_gd_files(CORE_ROOT)
	assert_int(scripts.size()).override_failure_message(
		"在 %s 底下找不到任何 .gd 檔，守衛測試形同虛設" % CORE_ROOT
	).is_greater(0)

	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for pattern: String in FORBIDDEN_PATTERNS:
			assert_bool(source.contains(pattern)).override_failure_message(
				"%s 含有被禁止的 Node 依賴 '%s'。core/ 必須是純邏輯，見 CLAUDE.md 規則 #1。" % [path, pattern]
			).is_false()

func _collect_gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(root.path_join(file_name))
	for sub_dir in dir.get_directories():
		found.append_array(_collect_gd_files(root.path_join(sub_dir)))
	return found
```

- [ ] **Step 2: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_core_purity.gd
```

Expected: PASS。目前 `core/` 下的所有類別都是 `extends RefCounted`。

- [ ] **Step 3: 驗證守衛測試真的會抓到違規**

暫時在 `core/entities/enemy.gd` 開頭加一行註解 `# .tscn`，重跑測試：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_core_purity.gd
```

Expected: FAIL，錯誤訊息指出 `res://core/entities/enemy.gd 含有被禁止的 Node 依賴 '.tscn'`。

確認後**把那行註解刪掉**，重跑確認回到 PASS。這一步驗證的是守衛本身有效——一個永遠通過的守衛測試比沒有更糟。

- [ ] **Step 4: 提交**

```bash
git add tests/test_core_purity.gd
git commit -m "test: 新增 core 純淨度守衛測試"
```

---

### Task 11: 表現層 — BattleScene 與渲染插值

把模擬結果畫出來。這是 M0 唯一人工驗收的任務——依規格第 8.1 節，UI 與畫面不做自動化測試。

**Files:**
- Create: `game/views/enemy_view.gd`
- Create: `game/views/tower_view.gd`
- Create: `game/level/battle_scene.gd`
- Create: `game/level/battle_scene.tscn`
- Modify: `project.godot`（設定主場景）

**Interfaces:**
- Consumes: `BattleSim`、`WorldState`、`DataRegistry`、`PathData`、`Enemy`、`Tower`
- Produces: 可執行的遊戲場景

**渲染插值的必要性**：邏輯跑 30Hz、畫面跑 60fps，若直接把 `enemy.position` 指給 Sprite，敵人會以 30Hz 跳動。做法是記住上一個 tick 與這一個 tick 的座標，依幀內進度插值。

- [ ] **Step 1: 寫 EnemyView**

Create `game/views/enemy_view.gd`:

```gdscript
class_name EnemyView
extends Sprite2D

## 敵人的視覺表現。只讀模擬狀態，不寫回——資料流是單向的。
##
## 邏輯 30Hz、畫面 60fps，直接套用座標會看到跳動，
## 所以記住前後兩個 tick 的座標，依幀內進度插值。

var enemy_id: int = 0

var _previous_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO

func setup(p_enemy_id: int, sprite_path: String, start_position: Vector2) -> void:
	enemy_id = p_enemy_id
	texture = load(sprite_path)
	_previous_position = start_position
	_target_position = start_position
	position = start_position

## 每個邏輯 tick 呼叫一次，推進插值的目標點
func on_tick(new_position: Vector2) -> void:
	_previous_position = _target_position
	_target_position = new_position

## 每個渲染幀呼叫一次。alpha 為距離下個 tick 的進度 0.0 ~ 1.0
func interpolate(alpha: float) -> void:
	position = _previous_position.lerp(_target_position, alpha)
```

- [ ] **Step 2: 寫 TowerView**

Create `game/views/tower_view.gd`:

```gdscript
class_name TowerView
extends Sprite2D

## 塔的視覺表現。塔不移動，所以不需要插值；
## M0 只做「有目標時轉向目標」，開火特效留到 M1 的投射物系統。

var tower_id: int = 0

func setup(p_tower_id: int, sprite_path: String, tower_position: Vector2) -> void:
	tower_id = p_tower_id
	texture = load(sprite_path)
	position = tower_position

func aim_at(target_position: Vector2) -> void:
	rotation = (target_position - position).angle()
```

- [ ] **Step 3: 寫 BattleScene 腳本**

Create `game/level/battle_scene.gd`:

```gdscript
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

@onready var _path_node: Path2D = $MainPath
@onready var _view_root: Node2D = $Views

var _registry := DataRegistry.new()
var _sim: BattleSim
var _enemy_views: Dictionary = {}   ## int -> EnemyView
var _tower_views: Dictionary = {}   ## int -> TowerView
var _spawn_timer: float = 0.0

func _ready() -> void:
	_registry.load_from_disk()

	var world := WorldState.new()
	world.paths[MAIN_PATH_ID] = _bake_path(_path_node)
	world.gold = 200
	world.lives = 20

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

## 每個渲染幀插值一次，讓 30Hz 的邏輯看起來是 60fps 的平滑移動
func _interpolate_views() -> void:
	var alpha := _sim.tick_progress()
	for view: EnemyView in _enemy_views.values():
		view.interpolate(alpha)
```

- [ ] **Step 4: 為 BattleSim 補上 tick_progress()**

`_interpolate_views()` 需要知道「距離下個 tick 還有多少進度」。在 `core/sim/battle_sim.gd` 的 `advance()` 之後加入：

```gdscript
## 幀內進度 0.0 ~ 1.0，供表現層做渲染插值使用
func tick_progress() -> float:
	return clampf(_accumulator / TICK_DELTA, 0.0, 1.0)
```

- [ ] **Step 5: 建立場景**

在 Godot 編輯器中：

1. Scene → New Scene → 選 2D Scene，根節點改名為 `BattleScene`
2. 把 `game/level/battle_scene.gd` 附加到根節點
3. 新增子節點 `Path2D`，改名為 `MainPath`
4. 選中 `MainPath`，用工具列的曲線工具在畫面上畫一條由左到右、帶幾個轉折的路徑
5. 新增子節點 `Node2D`，改名為 `Views`
6. 存檔為 `game/level/battle_scene.tscn`
7. Project → Project Settings → Application → Run → Main Scene 設為 `res://game/level/battle_scene.tscn`

- [ ] **Step 6: 人工驗收**

在編輯器中按 F5 執行，確認以下四項：

1. 紅色方塊（敵人）每 1.5 秒生成一次，沿著你畫的路徑平滑移動——**不是每秒 30 次的跳動**
2. 藍色方塊（塔）在有敵人進入射程時轉向該敵人
3. 敵人被打到血量歸零時消失
4. 走到路徑終點的敵人消失

若敵人移動有明顯頓挫，代表插值沒生效：檢查 `_interpolate_views()` 是否每幀都被呼叫，以及 `on_tick()` 是否只在 `ticks > 0` 時呼叫。

- [ ] **Step 7: 提交**

```bash
git add game/ core/sim/battle_sim.gd project.godot
git commit -m "feat(game): 新增 BattleScene 表現層與渲染插值"
```

---

### Task 12: GitHub Actions CI

**Files:**
- Create: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: `.godot-version`（Task 1）
- Produces: 每次 push 自動執行 headless 測試

- [ ] **Step 1: 確認 .godot-version 的內容格式**

CI 需要純版本號（如 `4.4.1`），而 `godot --version` 輸出的是 `4.4.1.stable.official.<hash>`。先確認實際內容：

```bash
cat .godot-version
```

把檔案內容改成純版本號，例如：

```bash
echo "4.4.1" > .godot-version
cat .godot-version
```

（把 `4.4.1` 換成你 Step 1 實際安裝的版本號。）

- [ ] **Step 2: 建立 CI 設定**

Create `.github/workflows/tests.yml`:

```yaml
name: tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  gdunit4:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - name: 讀取鎖定的 Godot 版本
        id: godot
        run: echo "version=$(cat .godot-version)" >> "$GITHUB_OUTPUT"

      - name: 執行 GdUnit4 測試
        uses: MikeSchulze/gdUnit4-action@v1
        with:
          godot-version: ${{ steps.godot.outputs.version }}
          paths: res://tests
```

- [ ] **Step 3: 提交並推送**

```bash
git add .github/workflows/tests.yml .godot-version
git commit -m "ci: 新增 GitHub Actions headless 測試"
git push -u origin main
```

- [ ] **Step 4: 確認 CI 綠燈**

```bash
gh run watch
```

Expected: workflow 成功，所有測試通過。

若 `MikeSchulze/gdUnit4-action` 的輸入參數名稱與此處不同（版本差異），查閱該 action 的 README 修正 `with:` 區塊的鍵名。若該 action 不可用，退路是自行安裝 Godot 後直接跑 CLI：

```yaml
      - name: 下載 Godot
        run: |
          VERSION=$(cat .godot-version)
          wget -q "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip"
          unzip -q "Godot_v${VERSION}-stable_linux.x86_64.zip"
          chmod +x "Godot_v${VERSION}-stable_linux.x86_64"
          echo "GODOT_BIN=$PWD/Godot_v${VERSION}-stable_linux.x86_64" >> "$GITHUB_ENV"

      - name: 匯入專案資源
        run: $GODOT_BIN --headless --path . --import

      - name: 執行測試
        run: $GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

- [ ] **Step 5: M0 完成驗收**

確認以下全部成立：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
git status --short
```

- 全部測試 PASS
- 工作目錄乾淨
- CI 綠燈
- F5 執行遊戲，敵人平滑沿路徑移動、被塔擊殺、走到終點時扣命

---

## M0 完成後的下一步

M0 交付的是骨架與可驗證的核心。M1 垂直切片包含四個獨立子系統，**各自需要獨立的實作計畫**：

| 子計畫 | 範圍 | 依賴 |
|---|---|---|
| M1-A 投射物與物件池 | 三種攻擊型態、物件池、狀態效果系統（減速／暈眩／DoT／破甲）、StatusSystem | M0 |
| M1-B 輸入抽象與 HUD | GameIntent 層、觸控與鍵鼠翻譯器、環形建塔選單、HUD、安全區適配 | M0 |
| M1-C 英雄與法術 | 英雄實體、移動與技能、法術施放、士兵攔截機制（`blocked_by`） | M1-A |
| M1-D 波次與關卡結算 | WaveSystem timeline、提前召喚、勝敗判定、星等評分、存檔（`PlatformServices` 介面 + `LocalPlatform`） | M1-B |

建議順序為 A → B → C → D。A 與 B 可平行進行（互不依賴）。

**M1 開工前的前置條件**（見規格第 11 節）：美術風格與 AI 生成流程必須定案，因為 M1 需要產出 4 敵人 + 1 Boss + 1 英雄 + 3 塔的實際美術。
