# M1-B3a：UI 基礎與 HUD — 設計規格

- 日期：2026-09-05
- 狀態：定案
- 上游規格：`2026-09-04-tower-defense-architecture-design.md` §6、`2026-09-05-m1b2-input-layer-design.md`

---

## 1. 範圍

B3 原本是一個里程碑，涵蓋 HUD、環形建塔選單、射程圈與觸控手勢。攤開之後那是兩件風險完全不同的事綁在同一個驗收點上，故拆為兩段：

| | 內容 | 交付物 |
|---|---|---|
| **B3a**（本規格） | i18n 管線、中文字型、`ui/` 層與安全區、HUD、Space 撞鍵修正、暫停中的 view 同步 | 看得到金幣變動、按得到暫停鈕 |
| **B3b** | 環形建塔選單、射程圈、長按查看資訊、置換標記替換，順帶補足三種塔 | 用 UI 建塔，而不是快捷鍵 |

B3a 先做，因為 B3b 的每一顆按鈕都要顯示文字與造價，而文字要有地方來。

### 1.1 已確認的決定

- i18n 走 Godot 內建翻譯 + CSV
- 兩個語系：zh-TW 與 en，兩者都要完整
- 中文字型：台北黑體
- HUD 內容：金幣、生命、關卡名、暫停鈕、速度鈕
- HUD 版面：全部靠上，浮在戰場上方，不佔用戰場空間
- Space 從內建 `ui_accept` 與 `ui_select` 移除；Esc 維持原樣

### 1.2 不在 B3a 範圍

環形建塔選單、射程圈、觸控長按、塔的資訊面板、勝敗結算、波次系統、設定畫面、語系切換 UI、字型子集化。

---

## 2. 分層

新增 `ui/` 層。它按定義就是 Node 滿載的，所以**沒有**類似 `core/` 的純度規則。取而代之的是一條方向規則：

> `ui/` 可以**讀** `WorldState` 與 `BattleSim` 來顯示；不得直接呼叫 `core/` 的系統，不得寫入 `WorldState`，也不得自己排隊意圖。它要讓事情發生，只能發 signal。

### 2.1 UI 與鍵盤走同一套文法

暫停按鈕與空白鍵最後產生的是**同一個** `InputAction.simple(TOGGLE_PAUSE)`。

流向是：`BattleHud` 發 signal → `battle_scene` 翻成 `InputAction` → `InteractionController.handle()` → 意圖佇列 → `BattleSim`。

這樣做的理由不是整齊，是**測試覆蓋**。B2 已經有測試守著「`TOGGLE_PAUSE` 動作會排出 `toggle_pause` 意圖」與「路由器會把它交給 `BattleSim`」。若 HUD 另開一條路直接改 `sim.paused`，那條路上一條測試都沒有，而且兩條路遲早會漂移。

順帶的好處是 `BattleHud` 完全不認得輸入層——它只認得 `WorldState`、`BattleSim` 與自己的 signal，可以單獨存在。

### 2.2 這條規則要用測試守住

沿用 `tests/test_core_purity.gd` 的原始碼掃描手法：`ui/` 底下的 `.gd` 不得出現 `BuildSystem`、`queue_intent(`、`InputAction`。

理由與 `core/` 純度測試相同——**在 AI 協作下，只有能自動驗證的架構規則才不會腐化。** 這條規則違反起來毫不費力（`sim.paused = not sim.paused` 一行就好，而且會動），所以更需要測試盯著。

### 2.3 誰持有 InteractionController

仍然是 `battle_scene`。B2 已經讓它在 `_unhandled_input` 裡把動作餵給控制器，HUD 的 signal 只是同一個入口的第二個來源。**動作進入控制器的地方全專案只有一處。**

---

## 3. i18n

### 3.1 機制

`i18n/strings.csv`，三欄：

```
keys,zh_TW,en
hud.gold_format,金幣 %d,Gold %d
```

Godot 匯入時產生 `strings.zh_TW.translation` 與 `strings.en.translation`。這兩個檔**不進版控**——`.gitignore` 已有 `*.translation`，它們是匯入產物，`--import` 會重建。

`project.godot` 的 `internationalization/locale/translations` 登記兩者。程式端用 `tr()`，Control 用 `auto_translate_mode`（注意：`auto_translate` 已棄用，Godot 4.7.2 的現行屬性是 `auto_translate_mode`）。

### 3.2 為什麼 CSV 不算違反「一律 JSON」

CLAUDE.md 說「遊戲資料一律 JSON，置於 `data/`」。翻譯放在 `i18n/` 而非 `data/`，因為**它不是遊戲資料，是資產**——跟字型、貼圖同一類，由引擎的匯入管線處理。

自製 JSON 載入器可以做到字面上的一致，代價是要自己實作語系回退、每個 Label 都得手動接（`auto_translate_mode` 用不了），而且放棄整條 gettext 工具鏈——M4 上架接 Steam 的翻譯流程時會很痛。那個成本是持續的，換到的只有規則的字面一致。

CSV → PO 之後可以遷移，等 M3 內容量大、真的需要翻譯者註解與複數形時再說。

### 3.3 格式字串本身要進翻譯檔

**禁止用字串串接組出顯示文字。**

```gdscript
tr("hud.gold_format") % gold        # 對
tr("hud.gold") + " " + str(gold)    # 錯
```

理由是語序會變。`金幣 %d` 與 `Gold %d` 剛好同序，但下一個語言不會，而串接寫法要到那時候才會爆，屆時每一處都要改。

### 3.4 B3a 的全部文字

| key | zh-TW | en |
|---|---|---|
| `hud.gold_format` | `金幣 %d` | `Gold %d` |
| `hud.lives_format` | `生命 %d` | `Lives %d` |
| `hud.speed_format` | `%d 倍速` | `%dx` |
| `hud.pause` | `暫停` | `Pause` |
| `hud.resume` | `繼續` | `Resume` |
| `level.level_01.name` | `熱蘭遮` | `Zeelandia` |

最後一個已經存在於 `data/levels/level_01/meta.json` 的 `name_key`。它是 B3a 裡唯一**顯示在畫面上**的資料層 key——其餘五個都是寫在 UI 裡的 key。沒有它，資料層那條路徑要到 B3b 才第一次被走到。

**更正**（實作時發現）：`data/` 底下實際有 **7 個** `name_key`，不是 1 個——一個關卡、一個敵人、一個塔、四個狀態效果。既有的 `tests/test_data_integrity.gd` 早就要求這些實體都必須有 `name_key`，所以 CSV 必須全部涵蓋，否則完整性測試會失敗。B3a 因此實際有 12 個 key：

| 額外的 key | zh-TW | en |
|---|---|---|
| `enemy.orc_grunt.name` | `獸人步兵` | `Orc Grunt` |
| `tower.archer_tower.name` | `弓箭塔` | `Archer Tower` |
| `status.chill.name` | `寒冰` | `Chill` |
| `status.poison.name` | `中毒` | `Poison` |
| `status.stun_shock.name` | `暈眩` | `Stun` |
| `status.sunder.name` | `破甲` | `Sunder` |

這六個目前都不顯示在畫面上（要到 B3b 的塔資訊與環形選單才會），但完整性測試要求它們存在。`獸人步兵` 是灰盒佔位——那隻敵人本身就是 M0 骨架留下的佔位，不是 1661 年的內容。

### 3.5 字型：這是會讓驗收整片豆腐的前提

**Godot 4 的預設字型不含中日韓字符。** 實測 `ThemeDB.fallback_font` 是 Open Sans SemiBold，`has_char("熱")` 與 `has_char("遮")` 都是 `false`。不處理的話畫面上是一排方框。

採用**台北黑體**（Taipei Sans TC Beta，翰字鑄造 JT Foundry，基於思源黑體調整為教育部標準字形，SIL Open Font License）。選它而非 Noto Sans TC 的理由：題材是台灣史，字形依台灣標準而非日本標準，專有名詞（熱蘭遮、西拉雅）不會出現異體字。

- 字型檔放 `game/assets/fonts/`，格式 TTF
- `.gitattributes` 目前只把 png/jpg/webp/ogg/wav 導進 LFS，**沒有 ttf/otf**，要補
- 設為預設 theme font（`project.godot` 的 `gui/theme/custom_font`），不逐個 Control 設

#### 取得方式是一個人工前置步驟

字型由專案擁有者親自從官方下載頁取得：<https://sites.google.com/view/jtfoundry/zh-tw/downloads>

**這一步刻意不自動化。** 官方發布掛在該頁的 Google Drive 連結後面，抓不到穩定的直接 URL；GitHub 上好抓的都是第三方再包裝，其中一個甚至把授權標成 MIT。字型要隨商業遊戲散布上 Steam，**來源鏈必須指得出來**，所以由擁有者從發行方直接取得，而不是從鏡像。

授權已於該頁確認，原文為：

> 台北黑體亦基於 SIL Open Font License 1.1 授權為免費、公開的字型製品。

商用允許，衍生自 Noto Sans CJK。注意官網**首頁**的「免費試用版」按鈕標籤與 `© 2019 JT Foundry All rights reserved` 頁尾具誤導性，實際條款在下載頁。

實作計畫的第一個任務會讀取實際檔名並據此設定 `project.godot`——檔名不預先假定。

**字型子集化列入 M2。** 完整 CJK 字型是 10–20MB，而 B3a 只用到六句話。M2 本來就是記憶體閘門，一併處理；現在做是過早最佳化，而且子集要等文字內容穩定才有意義。

### 3.6 語系怎麼驗

實測目前 `TranslationServer.get_locale()` 就是 `zh_TW`（跟隨作業系統），所以直接跑起來看到的是中文。

英文靠**測試**驗：測試裡 `TranslationServer.set_locale("en")`、取 `tr(key)`、斷言、然後**還原 locale**。不還原的話會汙染同一個行程裡的其他測試套件——與 `InputMap` 是同一類全域狀態陷阱，B2 已經踩過一次。

人工驗收因此只需確認中文渲染正常，不需要切語系。

---

## 4. HUD

### 4.1 結構

```
BattleHud (CanvasLayer)
└ Root (MarginContainer)          ← 安全區邊距套在這裡
  └ Top (HBoxContainer，錨定上緣)
    ├ GoldLabel
    ├ LivesLabel
    ├ (彈性空白)
    ├ LevelNameLabel
    ├ (彈性空白)
    ├ PauseButton
    └ SpeedButton
```

版面寫在 `ui/battle_hud.tscn`，邏輯寫在 `ui/battle_hud.gd`。**用 `.tscn` 而非純程式建**，因為專案擁有者有編輯器、之後會想自己調版面。代價是初次的錨點值是盲寫的，第一次人工驗收就是版面錯誤現形的地方。

### 4.2 HUD 浮在戰場上，不佔空間

關卡整幅入鏡（架構規格 §6.3），HUD 疊在上方。畫面頂部是關卡設計時最容易避開路徑的區域，所以疊加的代價最低，而換到的是戰場拿到完整畫面。

### 4.3 安全區

邊距套在 `Root` 這個 `MarginContainer` 上，值取自 `DisplayServer.get_display_safe_area()`。桌面上安全區等於整個畫面，邊距為 0，所以這段程式在 PC 上是無作用的——但它必須現在就寫，因為手機上瀏海會直接吃掉金幣數字，而那要到 M2 實機測試才看得到。

### 4.4 觸控目標尺寸

架構規格 §6.4 訂 ≥44pt，且 PC 上不縮小。

換算：44pt ≈ 7mm；手機橫向畫面高約 65mm，對應 1080 個設計單位。7 / 65 × 1080 ≈ **112 設計單位**。按鈕的 `custom_minimum_size` 訂 **120×120**，留一點餘裕。

實體尺寸留到 M2 實機驗證——這個換算建立在「手機橫向高約 65mm」這個假設上，而那個假設沒有被量過。

### 4.5 資料流：輪詢，但只在變動時寫入

`BattleHud.setup(world: WorldState, sim: BattleSim)` 拿到唯讀參照。每個渲染幀讀 `world.gold`、`world.lives`、`sim.paused`、`sim.speed_multiplier`。

`core/` 是純 `RefCounted`，沒有 signal 可以訂閱，所以輪詢不是選擇而是唯一解。

**但只在值改變時才寫 `Label.text`。** 每個值各自快取上一次的結果。否則每秒 60 次的 `tr()`、`%` 格式化與 `text` 指派全是白燒的字串配置——這與「戰鬥迴圈中禁止配置新物件」是同一個考量，只是換到表現層。

### 4.6 速度鈕沿用循環語意

速度鈕發的是 `CYCLE_SPEED`，跟 `F` 鍵同一條路，順序 1 → 2 → 4 → 1。

**這與架構規格 §6.1 的意圖表列的 `SetGameSpeed(x)` 不同**，是 B2 的刻意決定：意圖表達玩家動作而非結果值，回放時重現的才是「玩家按了切換」而非「速度變成 2」。此處記下這個分歧，避免日後被當成漏做。

代價是觸控上要從 4x 回到 2x 得繞一圈。若之後證實難用，改法是新增 `SetGameSpeed` 意圖並讓 HUD 顯示三顆按鈕；屆時鍵盤的循環鍵可以並存。

---

## 5. Space 從內建 UI 動作移除

### 5.1 問題

Godot 4.7.2 的內建動作實測內容：

```
ui_accept:  Enter, KP Enter, Space
ui_select:  Space, Joy(3)
ui_cancel:  Escape
```

B2 把 `gof_toggle_pause` 綁 Space。今天場景裡沒有任何 `Control`，所以看不出問題。**B3a 加上 HUD 之後，玩家第一次點到暫停鈕就會讓它取得焦點，此後 Space 會去觸發那顆已聚焦的按鈕、被 `_gui_input` 吃掉，永遠到不了 `_unhandled_input`。暫停從此失效，而且毫無線索。**

### 5.2 解法

`InputBindings.install()` 裡把 Space 從 `ui_accept` 與 `ui_select` 移除，**保留 Enter 與 KP Enter**。

`install()` 已經是所有綁定的唯一入口、已經冪等、已經有測試——這個修正放在那裡不需要任何新機制。

實作細節：**內建動作存的是 `keycode`，而 `gof_*` 存的是 `physical_keycode`**，判斷時兩個欄位都要看，否則會漏掉。

### 5.3 為什麼不是別的解法

**不用 `focus_mode = FOCUS_NONE`。** 那是一條「每加一顆按鈕都要記得」的紀律規則，沒有測試抓得到漏掉的那一顆，而這正是 AI 協作下最會腐化的東西。更關鍵的是它會毀掉 HUD 的鍵盤與手把導航，而 M4 要上 Steam Deck。拔 Space 保留 Enter，按鈕照樣可聚焦、可導航、可用 Enter 觸發。

**不把暫停搬到 `_input()`。** 那會讓遊戲永遠贏在 UI 之前。對話框開著時 Esc 應該關對話框，未來的重新綁定介面裡 Space 也會被遊戲吃掉。那是拿一個罕見 bug 換一個永久的優先權倒置。

**不把暫停改綁 P。** 繞開而非解決，下一個人加綁定時同樣的坑會再開一次。

### 5.4 Esc 不動

`ui_cancel` 只有 Escape，而且 `Button` 與 `LineEdit` 都不消費它——只有 `AcceptDialog` / `ConfirmationDialog` / `Popup` 這類會。那些開著的時候，要的正是 Esc 關對話框而非清掉建塔點選取，而 exclusive popup 本來就會在 `_unhandled_input` 之前攔截。優先權自動就是對的。

**配套約束（B3a 不實作，但要寫進規格）：日後加入的第一個模態對話框，開啟時必須一併暫停模擬。** 這樣「Esc 關了對話框」與「Esc 清了選取」永遠不會在同一個時刻都成立。B3a 沒有對話框，所以這條現在無從違反。

---

## 6. 補掉 B1 遺留的暫停同步

`battle_scene._process` 目前只在 `ticks > 0` 時同步 view，所以暫停中建造或賣出的塔，畫面要等到恢復才更新。B1 規格已記錄，標為 B3 處理。

改法：

```gdscript
var had_intents := not _sim.world.pending_intents.is_empty()
var ticks := _sim.advance(delta)
if ticks > 0 or had_intents:
	_sync_views()
```

精準且便宜，完全不動非暫停的路徑。B3a 做這個修正的理由是它的暫停鈕讓暫停從「只有鍵盤玩家會碰到」變成一等操作。

---

## 7. 測試策略

### 7.1 自動化

| 測試 | 抓什麼 |
|---|---|
| **i18n 完整性** | 掃 `ui/` 的 `tr("...")` 字面與 `data/` 所有 JSON 的 `name_key`；每個 key 在 CSV 都要存在，**且 zh_TW 與 en 兩欄都非空** |
| **兩個語系真的都解析得到** | `set_locale("en")` 後 `tr(key)` 回傳的不是 key 本身，且與 zh_TW 不同；測試結束**必須還原 locale** |
| **`ui/` 分層守衛** | `ui/` 的 `.gd` 不得出現 `BuildSystem`、`queue_intent(`、`InputAction` |
| **Space 已移除** | `install()` 後 `ui_accept` 沒有 Space、**但仍有 Enter**；`ui_select` 沒有 Space；重複 `install()` 冪等 |

i18n 完整性測試是這四條裡價值最高的。「加了 key 忘了補英文」不是可能發生，是必然發生，而且不會有任何執行期錯誤——英文語系下就只是顯示出 key 本身。

「仍有 Enter」那條是刻意設計的：一個把 `ui_accept` 整個清空的實作會通過「沒有 Space」的斷言，但會靜默打壞 HUD 的鍵盤觸發與 M4 的手把導航。

### 7.2 人工驗收

UI 與畫面不做自動化（CLAUDE.md）。跑 `godot --path .`：

1. HUD 出現在畫面上緣，中文正常顯示，**不是豆腐框**
2. 建塔 → 金幣減少；賣塔 → 金幣回一部分；擊殺 → 金幣增加；漏怪 → 生命減少
3. 按暫停鈕 → 效果與空白鍵完全相同
4. **點過暫停鈕之後再按空白鍵，暫停仍然有效**（這是 §5 修正的直接驗收）
5. 速度鈕循環 1x → 2x → 4x → 1x，且鈕上顯示當前倍速
6. 關卡名顯示為「熱蘭遮」
7. **暫停中建造或賣出，畫面立刻更新**（§6 的驗收）
8. HUD 不遮擋建塔點與路徑

---

## 8. 檔案結構

```
i18n/strings.csv                        新增
game/assets/fonts/<台北黑體 Regular>.ttf   人工放入（走 LFS，檔名於 Task 1 讀取）
ui/battle_hud.tscn                      新增
ui/battle_hud.gd                        新增
input/input_bindings.gd                 修改：移除內建動作的 Space
game/level/battle_scene.gd              修改：掛載 HUD、接 signal、暫停同步修正
project.godot                           修改：語系登記、預設字型
.gitattributes                          修改：ttf/otf 進 LFS
tests/test_i18n.gd                      新增
tests/test_ui_layer.gd                  新增
tests/input/test_mouse_keyboard_input.gd 修改：Space 已移除的四條
```

`core/` 一律不動。B3a 沒有任何 `core/` 的改動——這是它是表現層里程碑的證據。

---

## 9. 待後續決策事項

- 環形建塔選單、射程圈、長按查看資訊、置換標記替換（B3b）
- 補足三種塔（B3b，純 JSON：`chill` 狀態效果與 `splash_radius` 都已存在且系統已支援）
- 勝敗結算與波次系統（獨立子里程碑）
- 敵人生成移入 tick（同上）
- 字型子集化（M2，記憶體閘門）
- 觸控目標的實體尺寸驗證（M2 實機）
- 語系切換 UI 與設定畫面（M4）
- 手把翻譯器與建塔點跳選（M4）
- `translate()` 目前只看 `is_action_pressed`、完全丟棄放開事件，B3b 的長按手勢需要改它的簽名
- `tests/test_core_purity.gd` 的原始碼文字檢查可被「註解掉的呼叫」騙過；修法是比對前濾掉以 `#` 開頭的行

### 最終全分支審查留下的事項

- **兩條新守衛在合理的 B3b 未來下會誤報。** `test_the_two_locales_actually_differ` 會拒絕一組正當相同的譯文（專有名詞，或 `VS` 這種純符號字串）；`ui/` 守衛的寫入偵測若 `ui/` 重構到沒有任何腳本持有 `WorldState` / `BattleSim` 型別的參照就會失敗。兩者的失敗訊息都自帶說明，但便宜的預防是各自旁邊放一個有註解的例外清單常數——**讓下一個人是加一筆而不是把守衛刪掉**，守衛就是這樣死的。
- **`tr("key", "context")` 會被 `tr()` 掃描靜默跳過**，正則要求引號後緊接 `)`。今天沒有用到，第一次需要 context 參數時才會咬人。
- **`ui/` 的寫入偵測穿不過集合成員。** `_world.build_slots[0].occupied_by = 5` 在 `[` 處就不匹配。`pending_intents` 已加入字串清單擋住現實中最可能的那一半，索引穿透仍未涵蓋。
- **`test_core_purity.gd` 的三條原始碼守衛都是整檔 `contains()`**，所以被註解掉的呼叫同樣算通過。它們證明的是「那段文字存在」，不是「那段程式會執行」。這是該檔既有的性質，不單獨修改。
- **Bold 字重已提交但無人引用**（21MB，`project.godot` 只設了 Regular）。刻意作為 B3b 的準備，但若檔案有問題不會有任何東西說話，要到 B3b 真的用它才會發現。
- **`_apply_safe_area()` 只在 `_ready()` 跑一次**，沒有處理 `NOTIFICATION_WM_SIZE_CHANGED`。手機開啟後旋轉、或視窗拖到不同縮放的螢幕，都會維持啟動當下的邊距。列入 M2 實機清單。
