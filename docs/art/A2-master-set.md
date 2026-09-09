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
