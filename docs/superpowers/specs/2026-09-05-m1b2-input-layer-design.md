# M1-B2：輸入抽象層 — 設計規格

- 日期：2026-09-05
- 狀態：已確認，待轉為實作計畫
- 上層規格：`2026-09-04-tower-defense-architecture-design.md`（§6 輸入抽象與 UI 適配）
- 前置：M1-B1 已完成（`main` 的 `c8c4bd1`），測試 165/165

## 1. 範圍

B2 交付**原始事件 → `GameIntent`** 的翻譯層。B1 已建好建塔系統與意圖佇列，但至今沒有任何東西產生 intent——`battle_scene` 靠一行過渡程式碼在開場自動送出一筆建造。

### 1.1 已確認的決定

| 決定 | 選擇 | 理由 |
|---|---|---|
| 交付範圍 | **鍵鼠路線完整可玩，觸控只做選取與取消** | 環形建塔選單要 B3 才存在；沒有選單，觸控真的無法選「哪一種塔」 |
| 分層 | **裝置翻譯器 → 互動狀態機 → intent** | 互動文法只存在一處，加手把時只需再寫一個薄翻譯器 |
| 暫停與倍速 | **走 intent 佇列** | 回放會忠實重現「玩家何時加速、何時暫停」，而那是實戰節奏的一部分 |

### 1.2 不在 B2 範圍

環形建塔選單、HUD、射程圈、安全區適配（皆 B3）；長按查看資訊（B3）；手把（M4）；法術與英雄的 intent（M1-C，對應系統尚不存在）。

## 2. 分層

```
原始 InputEvent
   ↓  裝置翻譯器（純函式，可測）
InputAction（裝置無關）
   ↓  InteractionController（純邏輯，可測）
GameIntent → world.queue_intent()
```

翻譯器**只認得裝置、不認得遊戲規則**；控制器**只認得遊戲規則、不認得裝置**。這條界線是 M4 加手把時只需再寫一個薄翻譯器的原因。

### 2.1 翻譯器是純函式，不是 Node

```gdscript
static func translate(event: InputEvent, world_position: Vector2) -> InputAction
```

螢幕座標換算成世界座標的工作留在場景做（它需要 viewport），結果當參數傳入。因此 **`input/` 整層沒有 Node、整層可 headless 測試**，「按鍵 X 應產生動作 Y」也成為可測的斷言。

不可測的只剩 `battle_scene` 中約十餘行的事件轉發與座標換算。

### 2.2 選取狀態只有一個欄位

```gdscript
var selected_slot_id: int = 0   ## 0 表示未選取
```

**選取的對象永遠是建塔點，不是塔。** 所有塔都蓋在建塔點上、與其同座標，所以「選中一座塔」等同「選中一個被占用的建塔點」。占用與否決定哪些操作合法。

狀態機因此只有一個變數，不需要「選中的是塔還是空位」這種分支。

### 2.3 控制器只過濾結構，不過濾金錢

控制器只判斷**結構上做不做得到**：有沒有選取、占用狀態對不對。符合就發 intent。

**金錢夠不夠一律不看**——那是 `BuildSystem` 的權威（B1 規格 §6）。錢不夠時 intent 照發，由 `core/` 靜默拒絕，那正是 B1 訂下的「時機類拒絕」。控制器若自己再判斷一次，就有了第二個事實來源，而兩者漂移的那天不會有任何測試失敗。

B3 的 HUD 可另外預測金錢把按鈕變灰**作為視覺回饋**，但那是回饋，不是權威。

### 2.4 命中判定用線性掃描

點擊座標找半徑內最近的建塔點，沒有就是取消選取。建塔點數量是個位數，不需動用 `UniformGrid`（它裝的是敵人，且每 tick 重建）。

**命中半徑定為 48 像素。** 依據是架構規格 §6.4 的「觸控目標尺寸統一以 ≥44pt 設計，PC 上不縮小」——命中半徑必須至少涵蓋那個尺寸，否則觸控時會出現「看得到卻點不到」。取 48 是留一點餘裕。

半徑內有多個建塔點時取最近者。示範關卡的四個建塔點相距數百像素，不會發生，但規則要明確以免日後關卡把建塔點放近時行為未定義。

## 3. 互動文法

### 3.1 裝置無關的動作

```gdscript
class_name InputAction
extends RefCounted

const SELECT_AT := &"select_at"        ## 在某個世界座標點選
const CHOOSE_TOWER := &"choose_tower"  ## 選第 n 種本關可用的塔
const SELL := &"sell"
const UPGRADE := &"upgrade"
const CANCEL := &"cancel"
const TOGGLE_PAUSE := &"toggle_pause"
const CYCLE_SPEED := &"cycle_speed"

var kind: StringName = &""
var world_position: Vector2 = Vector2.ZERO  ## SELECT_AT 用
var index: int = 0                          ## CHOOSE_TOWER 用，1 起算
```

### 3.2 轉移表

| 動作 | 未選取 | 選中空位 | 選中有塔 |
|---|---|---|---|
| `SELECT_AT` 命中建塔點 | 選中它 | 改選 | 改選 |
| `SELECT_AT` 沒命中 | — | 取消選取 | 取消選取 |
| `CHOOSE_TOWER(n)` | — | **發 build** | — |
| `SELL` | — | — | **發 sell** |
| `UPGRADE` | — | — | **發 upgrade** |
| `CANCEL` | — | 取消選取 | 取消選取 |
| `TOGGLE_PAUSE` | **發 intent** | **發 intent** | **發 intent** |
| `CYCLE_SPEED` | **發 intent** | **發 intent** | **發 intent** |

「—」是靜默忽略，不是錯誤——沿用 B1 的分野。`n` 超出本關可用塔種數量時同樣靜默忽略（按了「3」但本關只有一種塔，是正常的使用者行為）。

**重複點選同一個建塔點是冪等的，不是切換。** 再點一次已選中的建塔點，它維持選中。若做成切換，連點兩下就會莫名其妙地取消選取，而連點在觸控上很常見。要取消選取只有兩條路：點空白處，或 `CANCEL`。

**發出 intent 後選取狀態不變。** 建造的 intent 在下一 tick 套用，建塔點自然從「空」變成「有塔」，可用操作也就從建造變成賣出與升級，不需要額外邏輯。

連按兩次建造會排兩筆 intent，第二筆套用時因「建塔點已占用」被靜默拒絕——B1 已處理該競態。

### 3.3 暫停與倍速的 intent 不帶數值

```
KIND_TOGGLE_PAUSE   無 payload
KIND_CYCLE_SPEED    無 payload
```

**intent 表達玩家動作，不是結果值。** `paused` 與 `speed_multiplier` 住在 `BattleSim` 上，而控制器只拿得到 `WorldState`；若 intent 要帶「切到 2 倍速」這種結果值，控制器就得持有 sim 的參照，那條依賴不值得為一個數字建立。

由 `BattleSim` 自己算下一段速度（`1.0 → 2.0 → 4.0 → 1.0`），既避開該依賴，回放時重現的也是「玩家按了切換」而非「速度變成 2」，更貼近事實。

4 倍速配低幀率會觸發單幀 tick 上限；該路徑在 M1-A 已修過並有測試守著（積欠不足一個 tick 時不丟棄零頭），此處不需再處理。

### 3.4 BattleSim 成為真正的路由器

B1 的最終修正把 kind 分派收攏進 `BuildSystem`，並在 `BattleSim` 留下註解：「等之後的里程碑引入不屬於 `BuildSystem` 的 intent，這裡才需要變成真正依 kind 分派到不同系統的路由器。」

暫停與倍速正是那種 intent——它們改的是模擬控制參數而非世界狀態，不該進 `BuildSystem`。B2 因此把 `_apply_pending_intents` 改成路由器：建造類轉給 `BuildSystem`，控制類自己處理。

**這是會靜默漏掉某個 kind 的改動**，測試要求見 §5.2。

## 4. 翻譯器

### 4.1 B2 不寫觸控翻譯器

Godot 預設開啟 `emulate_mouse_from_touch`，觸控裝置上一次點擊**同時**產生 `InputEventScreenTouch` 與模擬的 `InputEventMouseButton`。兩個翻譯器都跑的話，一次點擊會變成兩個 `SELECT_AT`。

而 B2 的觸控範圍只有點選與取消——正好是模擬滑鼠事件已涵蓋的。**現在寫觸控翻譯器等於寫死碼。**

真正需要它的是長按與環形選單的手勢，皆在 B3。B2 只出 `mouse_keyboard_input.gd`；觸控目前靠模擬事件運作，專屬翻譯器留待 B3。

### 4.2 按鍵走 InputMap

在 `project.godot` 定義動作，翻譯器只問 `event.is_action_pressed("gof_select")`。重新綁定不用改程式；M4 加手把時只是替同一個動作多綁一個按鈕，**翻譯器一行都不用動**。

前綴 `gof_` 避開 Godot 內建的 `ui_*`。

| 動作 | 綁定 |
|---|---|
| `gof_select` | 滑鼠左鍵 |
| `gof_cancel` | 滑鼠右鍵、Esc |
| `gof_choose_tower_1` / `_2` / `_3` | 1 / 2 / 3 |
| `gof_sell` | S |
| `gof_upgrade` | U |
| `gof_toggle_pause` | 空白鍵 |
| `gof_cycle_speed` | F |

三個 `choose_tower` 動作對應「本關第 n 種可用塔」，不是特定塔種——換關卡不用改綁定。

### 4.3 座標換算

關卡整幅入鏡、無鏡頭平移（架構規格 §6.3），世界座標與螢幕座標只差一個畫布變換：

```gdscript
var world_pos := get_viewport().get_canvas_transform().affine_inverse() * event.position
```

此行留在 `battle_scene`，因為它需要 viewport。

## 5. 測試策略

| | 測法 |
|---|---|
| `InteractionController` 的文法 | 單元測試，直接餵 `InputAction` |
| `MouseKeyboardInput.translate` | 單元測試，直接餵 `InputEvent` |
| `BattleSim` 的路由 | 單元測試 |
| 事件轉發、座標換算、置換標記 | 人工驗收 |

### 5.1 三處必須刻意設計成有鑑別力

本專案反覆出現「測試通過了它宣稱要排除的實作」。B2 有三個明顯的坑：

**建造測試要用第二個建塔點與第二種塔。** 若用第一個與第一種，一個寫死 `build_slots[0].id` 與 `available_towers[0]` 的實作會照樣通過。

**倍速測試要驗到循環回頭。** 只測 `1x → 2x` 的話，「每次乘二」的實作也會通過；要測到 `4x → 1x` 才能釘住循環。

**路由重構要有回歸守衛。** 必須有測試斷言建造類 intent 在重構後仍然到得了 `BuildSystem`。

### 5.2 其餘覆蓋

控制器：命中與未命中的選取、超出範圍的 `CHOOSE_TOWER`、在空位上按賣出、在有塔的位置上按建造、未選取時按賣出與升級、控制類動作不需要選取。

翻譯器：每個綁定的動作各一；未綁定的按鍵回傳 `null`；`CHOOSE_TOWER` 的 index 測試要用 2 而非 1，否則寫死 1 的實作會通過。

## 6. 表現層：兩件必要的雜務

### 6.1 建塔點需要置換標記

`Marker2D` 不畫任何東西。B2 交付「點選建塔點」，但玩家看不到建塔點在哪，也看不到自己選中了什麼——人工驗收會變成對著記憶中的座標盲按。

B2 因此包含最低限度的表現：**建塔點畫一個置換標記，選中時換色**。用程式產生的純色貼圖，不需要美術。

**此為置換品，列入 B3 的替換清單**，處理方式同 B1 那行過渡程式碼。

### 6.2 刪掉 B1 的過渡自動建塔

B1 在 `battle_scene` 留了一行「開場自動建一座塔」，當時標為 B3 的刪除清單。B2 之後玩家自己就能建塔，**該行現在即可刪除**，不必等 B3。

## 7. 人工驗收

跑 `godot --path .`：

1. 四個建塔點以置換標記顯示在畫面上
2. 點擊其中一個 → 標記變色
3. 按 `1` → 該位置蓋出塔，金幣減少
4. 點擊已有塔的建塔點，按 `U` → 升級；按 `S` → 塔消失、金幣回一部分
5. 點空白處 → 選取解除
6. 空白鍵 → 敵人與投射物停住，再按恢復
7. `F` → 速度在 1x / 2x / 4x 間循環

第 6 項要留意一個 B1 的已知現象：**暫停中建造或賣出，畫面不會更新**，要到恢復才看得到。那是 `battle_scene` 只在 `ticks > 0` 時同步 view 造成的，B1 規格 §2.2 已記錄，屬 B3 處理。B2 不修，但驗收時勿誤判為 bug。

## 8. 檔案結構

```
input/input_action.gd              新增
input/interaction_controller.gd    新增
input/mouse_keyboard_input.gd      新增
core/entities/game_intent.gd       修改：新增兩個控制類 kind
core/sim/battle_sim.gd             修改：路由器、暫停與倍速的處理
project.godot                      修改：InputMap 動作定義
game/assets/placeholder_slot.png   新增：建塔點的置換標記（程式產生的純色圖）
game/views/build_slot_view.gd      新增：建塔點的視覺，選中時換色
game/level/battle_scene.gd         修改：事件轉發、座標換算、建塔點 view、刪除過渡建塔
tests/input/test_interaction_controller.gd   新增
tests/input/test_mouse_keyboard_input.gd     新增
tests/core/test_tick_order.gd      修改：控制類 intent 與路由回歸守衛
```

`BuildSystem`、`WorldState`、`MovementSystem`、`TargetingSystem`、`DamageSystem`、`ProjectileSystem`、`StatusSystem` 一律不動。

## 9. 待後續決策事項

- 觸控專屬翻譯器與長按查看資訊（B3）
- 暫停中的 view 同步（B3）
- 手把翻譯器與建塔點跳選（M4）
- 選取狀態是否需要暴露給 B3 的 HUD，以何種形式（B3 時決定）
