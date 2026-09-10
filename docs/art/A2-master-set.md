# A2　母本集驗收紀錄

- 日期：2026-09-06
- 對應計畫：`docs/superpowers/plans/2026-09-06-a2-golden-master-set.md`

---

## 光源基線

L2 驗收：全遊戲光源固定自左上方。量尺實作於 `art/scripts/check_lighting.py`（`lighting_bias()`）。

指令：

```
python art/scripts/check_lighting.py --stage flux2
```

輸出（33 個資產、每個 2 張、共 66 張，`stage_flux2`）：

```
  tower_musket_t1        h=-0.025  d=-0.010
  tower_musket_t1        h=-0.005  d=+0.016
  tower_musket_t2        h=+0.004  d=+0.070
  tower_musket_t2        h=+0.013  d=+0.115
  tower_musket_t3        h=+0.024  d=+0.110
  tower_musket_t3        h=+0.035  d=+0.102
  tower_hunter_t1        h=-0.048  d=-0.049
  tower_hunter_t1        h=-0.000  d=+0.012
  tower_hunter_t2        h=-0.014  d=+0.040
  tower_hunter_t2        h=+0.005  d=+0.030
  tower_hunter_t3        h=+0.029  d=+0.061
  tower_hunter_t3        h=+0.017  d=+0.011
  tower_fence_t1         h=+0.016  d=+0.029
  tower_fence_t1         h=-0.023  d=-0.003
  tower_fence_t2         h=-0.005  d=+0.007
  tower_fence_t2         h=-0.003  d=+0.027
  tower_fence_t3         h=-0.008  d=+0.032
  tower_fence_t3         h=+0.052  d=+0.055
  enemy_musketeer        h=-0.002  d=+0.002
  enemy_musketeer        h=+0.031  d=+0.062
  enemy_rattan           h=-0.002  d=+0.021
  enemy_rattan           h=-0.019  d=+0.060
  enemy_archer           h=-0.039  d=-0.046
  enemy_archer           h=+0.019  d=+0.017
  enemy_ironman          h=+0.023  d=-0.007
  enemy_ironman          h=+0.042  d=+0.023
  enemy_sapper           h=+0.002  d=+0.021
  enemy_sapper           h=-0.010  d=+0.035
  enemy_warjunk          h=+0.022  d=+0.128
  enemy_warjunk          h=+0.017  d=+0.121
  boss_chenze            h=+0.001  d=+0.063
  boss_chenze            h=+0.028  d=+0.111
  civilian_family        h=-0.001  d=+0.057
  civilian_family        h=-0.011  d=+0.043
  civilian_slave         h=+0.005  d=-0.136
  civilian_slave         h=+0.027  d=-0.099
  voc_gunner             h=-0.035  d=+0.012
  voc_gunner             h=-0.009  d=+0.096
  voc_coyett             h=+0.002  d=+0.036
  voc_coyett             h=+0.005  d=+0.028
  siraya_elder           h=-0.014  d=-0.022
  siraya_elder           h=+0.042  d=+0.073
  siraya_woman           h=+0.011  d=-0.003
  siraya_woman           h=-0.013  d=-0.000
  map_1_1                h=+0.041  d=+0.042
  map_1_1                h=-0.021  d=-0.037
  map_tile_sandbar       h=-0.246  d=-0.191
  map_tile_sandbar       h=-0.016  d=-0.112
  map_tile_town          h=+0.015  d=-0.011
  map_tile_town          h=+0.005  d=-0.098
  prop_buildsite         h=+0.011  d=+0.079
  prop_buildsite         h=-0.001  d=+0.022
  prop_settlement        h=+0.067  d=+0.017
  prop_settlement        h=+0.081  d=+0.031
  icon_silver            h=+0.017  d=+0.111
  icon_silver            h=+0.007  d=+0.047
  icon_civilian          h=-0.009  d=-0.012
  icon_civilian          h=+0.006  d=-0.005
  icon_tide              h=+0.020  d=+0.081
  icon_tide              h=-0.004  d=+0.061
  icon_tower_musket      h=+0.008  d=+0.034
  icon_tower_musket      h=+0.018  d=+0.061
  icon_tower_hunter      h=+0.013  d=+0.025
  icon_tower_hunter      h=-0.008  d=-0.017
  icon_tower_fence       h=+0.013  d=+0.017
  icon_tower_fence       h=+0.012  d=+0.007

=== 光源方向不一致 18/66（diagonal 應為正，代表左上較亮）
  tower_musket_t1 / tower_musket_t1_flux2_00001_.png  diagonal=-0.010
  tower_hunter_t1 / tower_hunter_t1_flux2_00001_.png  diagonal=-0.049
  tower_fence_t1 / tower_fence_t1_flux2_00002_.png  diagonal=-0.003
  enemy_archer / enemy_archer_flux2_00001_.png  diagonal=-0.046
  enemy_ironman / enemy_ironman_flux2_00001_.png  diagonal=-0.007
  civilian_slave / civilian_slave_flux2_00001_.png  diagonal=-0.136
  civilian_slave / civilian_slave_flux2_00002_.png  diagonal=-0.099
  siraya_elder / siraya_elder_flux2_00001_.png  diagonal=-0.022
  siraya_woman / siraya_woman_flux2_00001_.png  diagonal=-0.003
  siraya_woman / siraya_woman_flux2_00002_.png  diagonal=-0.000
  map_1_1 / map_1_1_flux2_00002_.png  diagonal=-0.037
  map_tile_sandbar / map_tile_sandbar_flux2_00001_.png  diagonal=-0.191
  map_tile_sandbar / map_tile_sandbar_flux2_00002_.png  diagonal=-0.112
  map_tile_town / map_tile_town_flux2_00001_.png  diagonal=-0.011
  map_tile_town / map_tile_town_flux2_00002_.png  diagonal=-0.098
  icon_civilian / icon_civilian_flux2_00001_.png  diagonal=-0.012
  icon_civilian / icon_civilian_flux2_00002_.png  diagonal=-0.005
  icon_tower_hunter / icon_tower_hunter_flux2_00002_.png  diagonal=-0.017
```

離開碼 1（18/66 不一致）。此步驟不預期全過，只記錄現況分佈；`map_tile_sandbar` 偏差最大（-0.191、-0.112），其餘多在 ±0.05 內屬邊界值。是否重生成留待後續任務判斷。

---

## 第二批：扁平幾何無五官（2026-09-09）

風格定案後（美術聖經 §1.1 修訂註記）整批重出、人工挑選、過閘門、替換 `game/assets/chapter01/`。

### 挑選

- 工具：`select_masters.py`（帶編號印樣、`--pick id=n --stage s`、`--apply`），選擇記在 `art/manifest/master_set.json`（stage + 檔名 + 日期）。人工挑選透過 Claude Code Artifact 表單（radio 單選，選擇即時存 db）。
- 四輪：第一輪 20/33；第二輪（13 個補跑 4 張新 seed）+6；第三輪 +6（三個用 `refine.py` 拿「最理想但一處不對」的候選只改一處：標槍位置、弓弦、配劍；四個依回饋改 prompt：一手刀一手盾、藤牌自然藤色與織紋、持盾不露手、通條直立）；第四輪 +1（藤牌兵握刀）。
- 來源分佈：`stage_flat` 27、`stage_ref`（史料參考圖 + Klein 編輯）2（鐵人軍、大熕船）、`stage_fix`（Klein 針對性修圖）4（鏢手、弓箭手、陳澤未採、藤牌兵）。
- 兩個反覆的教訓：**否定句無效**（圖示「NO frame」12 張 8 張有底板）；**「一手一物」要寫成左右手各持什麼**，否則模型把盾與刀畫在同一側或漏掉一把。

### 管線

`postprocess.py --stage flat --outline-width 1`（`master_set.json` 優先）。描邊 1px vs 2px 並排實測：扁平風格下 2px 過重，取 1px。量化 RGB + 鐵灰選擇性 + 硃砂暗（A2x §9.3）。

### 三道閘門

| 檢查 | 結果 |
|---|---|
| 色票（`postprocess --verify-only`） | 33/33 通過 |
| 剪影（`silhouette.py --master --cat unit`，門檻 0.93） | 17 個單位，1 對超標：`enemy_musketeer ↔ voc_coyett` 0.933（擦線，與第一批相同） |
| 光源（`check_lighting.py --master`） | diagonal ≤ 0 的 10/33；扣掉將退役的兩張地圖後，其餘 8 張都在 ±0.09 內。**扁平風格的光是垂直分光線（左亮右暗），diagonal 這個量尺量的是左上對右下，對這個風格不再是對的指標**——horizontal 那欄 33 張裡只有 5 張為負且都在 −0.03 內（地圖除外）。L2 的量尺應改以 horizontal 為主，待改 |

### 進 `game/assets`

33 張替換 `game/assets/chapter01/`，`godot --headless --import` 後全套測試通過。踩到一個坑：`03_processed/` 裡還留著實驗期的 `xp_*` 產出，`cp *.png` 一起帶進去讓 7 個測試失敗——`postprocess --out` 的正式輸出目錄應該只放清單資產，或搬進 `game/assets` 時以清單過濾。

---

# 第三批：對話肖像與過場大圖（2026-09-10）

A2 閘門要求「連續三批風格穩定」。第一批＝A1 的 FLUX.2 全量，第二批＝扁平幾何 33 張母本，
第三批就是這裡的敘事層產出。**同一套 `shared.style` 字串、同一份色票、同一條無五官條款**，
只換 framing 與尺寸——三份清單（`chapter01_assets`／`chapter01_portraits`／`chapter01_cutscenes`）
的風格區塊逐字相同，這是刻意的：批次差要能歸因到 framing 而不是風格描述漂移。

## 肖像六張

| 項目 | 內容 |
|---|---|
| 清單 | `art/manifest/chapter01_portraits.json`，framing＝胸像、深色石板底、768×768 |
| 挑選 | 一輪定案 6/6（表單 radio，記入 `master_set.json`，stage 全為 `flat`） |
| 後處理 | `postprocess.py --stage flat --outline-width 1`，`SIZE_BY_CAT["portrait"] = 256` |
| 色票閘門 | 6/6 通過（`--verify-only`） |
| 尺寸上限 | `data/art_limits.json` 加 `"portrait_": 256`；`test_art_limits` 通過 |
| 印樣 | `art_src/contact/portraits_processed.png` |

**批次差**：與 33 張母本並排看不出差異。臉一律留空，鬍鬚、髮髻、笠盔、白領這些身分標記都在——
與單位圖的處理方式一致。揆一的髮鬚被畫成榕蔭綠，是色票內的合法選色，不是漂移。

## 過場大圖三張

| 項目 | 內容 |
|---|---|
| 清單 | `art/manifest/chapter01_cutscenes.json`，framing＝16:9 全景、1024×576 |
| 工作流 | `a2x_flux2_multiref.api.json`——**Klein 多參考圖編輯**，每張餵 3 張母本原圖 |
| 候選 | 3 張各 2 張（`stage_cutscene`），印樣 `art_src/contact/cutscenes_candidates.png` |
| 挑選 | 進行中 |
| 尺寸上限 | `data/art_limits.json` 加 `"cs_": 1024` |

**這一批最有價值的實測**：多參考圖編輯在「三個角色同框」的情境下仍然成立。授杖那張餵了
揆一肖像、頭目肖像、銃樓火繩槍手三張母本，出來的圖裡黑袍白領、髮髻與肩布、闊邊帽與火繩槍
各自跟著自己的參考圖走，prompt 一個字都沒有描述服裝。登陸那張的中式硬帆扇形與陳澤的明盔
同理。A2x §8 的結論「內容靠圖、風格靠字」從單一角色推廣到多角色場景，**這是 A3 決定不訓
LoRA 的最後一塊依據**。

無五官條款在 1024px 下仍守住：六張候選放大檢查，臉全部是單一色塊（`cutscenes_faces.png`）。

## A2 閘門結論

| 閘門 | 狀態 |
|---|---|
| 連續三批風格穩定 | **達成**——三批共 42 個資產、7 個類別，並排看不出批次差 |
| 色票 | 33/33 + 6/6 通過；過場不受色票約束（滿版場景，與 `scene` 同處理） |
| 剪影 | 單位類 1 對擦線（musketeer ↔ coyett 0.933），肖像與過場不適用此量尺 |
| 光源 | diagonal 量尺對垂直分光線的扁平風格不適用，已記在第二批；改量 horizontal 待做 |

**A3 風格 LoRA：不做。** 美術聖經 §8 的條件是「第三批仍有漂移才訓」，三批沒有漂移，
而一致性的實際承擔者是扁平幾何風格本身與 Klein 參考圖編輯。這條決定已同步進精緻度規格 §2。

