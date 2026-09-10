# M1-B6 關卡地圖改 TileMap — 設計規格

> **2026-09-10 改號**：原編號 M1-B4 已由波次系統占用（`2026-09-06-m1b4-waves-design.md`，已在 main）。本文件改為 **M1-B6**。既有截圖檔名 `m1b4_*` 維持不變，那是實際存在的檔名。

- 日期：2026-09-09
- 狀態：**定案**（2026-09-09）。排入 M1 收尾（架構規格 §9 里程碑表 2026-09-09 新增列）；實作計畫 `docs/superpowers/plans/2026-09-09-m1b6-tilemap-map.md`
- 對應規格：`2026-09-04-tower-defense-architecture-design.md` §4、§9；`2026-09-04-visual-polish-pipeline.md` L1；`docs/art/A2x-shadow-puppet-experiment.md` §4
- 原型：`game/fx/pixel_demo.gd`（執行期組 TileSet、程序化地磚、擺件 y_sort、L1 陰影）

---

## 0. 為什麼

A2x §4 的實測：同一批單位放在 AI 整圖 `map_1_1` 上要找路徑，放在「平色地磚 + 高對比路徑」上一眼看出走向。**這是所有風格實驗裡可讀性提升最大的一項，而且與風格選擇無關**——不論皮影、扁平幾何或像素，地圖模組化都成立。

現況的問題不只是可讀性。整圖地圖意味著：改一條路徑就要重畫整張、`Path2D` 與畫面上的路是兩份互不知道的資料、擺件密度無法調、記憶體是一張 2048 上限的貼圖。

## 1. 範圍

**做**
- `TileMapLayer` 地面層：草地／沙洲路徑／水三種地形，程序化平色地磚（`art/scripts/make_tiles.py` 已有），每種 2–4 變體隨機
- 路徑由關卡資料驅動：`Path2D` 的曲線與路徑地磚**由同一份格座標折線**產生，不再各寫一份
- 擺件層：榕樹、竹叢、礁石、林投、聚落等 `Sprite2D`，y_sort，底下共用一張橢圓接觸陰影（精緻度規格 L1）
- 建塔點：沿路徑兩側的格子，由資料指定
- 潮汐（章節規格 1-1 機制）：水／沙洲兩種地磚的**格子集合**隨潮位切換——這比色溫 shader 更直接，且解掉美術聖經 §6 第 4 項「shader 或雙貼圖」的待決策：都不用，換格子

**不做**
- autotile 過渡磚（路徑邊緣有機化）：先用方格，過渡磚是人畫的工作，等風格與磚尺寸定案
- 多層地形（高低差）
- 地圖編輯器 UI：關卡資料手寫 JSON

## 2. 資料

`data/levels/level_01/map.json`（新增）：

```json
{
  "tile_px": 32,
  "cols": 60, "rows": 34,
  "path_waypoints": [[0, 4], [21, 4], [21, 9], [3, 9], [3, 18], [59, 18]],
  "path_width": 2,
  "water": {"rect": [46, 0, 60, 9]},
  "tide": {"low_extra_sand": [[46, 7], [47, 7], [46, 8], [47, 8], [48, 8], [49, 8]]},
  "props": [
    {"id": "prop_settlement", "cell": [40, 12], "shadow": false},
    {"id": "prop_banyan", "cell": [5, 1]}
  ],
  "build_slots": [[12, 7], [12, 14], [28, 15], [44, 15]]
}
```

- 路徑折線是**唯一真相**：`core` 由它算出 `Path2D` 曲線（格中心連線），`game` 由它鋪路徑地磚。兩者不可能漂開。
- `core/` 只讀 JSON 與算座標，不碰 `TileMapLayer`（硬規則 1）。
- 擺件 `id` 對應 `game/assets/chapter01/<id>.png`；`shadow: false` 給本身有底座的建物。

## 3. 執行期

```
BattleScene
 ├─ Ground   TileMapLayer   ← 由 map.json 鋪；潮位變化只 set_cell 水／沙洲的差集
 ├─ Props    Node2D(y_sort) ← 擺件 + 陰影
 ├─ Views    Node2D(y_sort) ← 單位、塔、投射物（現有）
 └─ HUD
```

TileSet 在執行期由圖集組成（`pixel_demo.gd` 的作法），不進 `.tres`（專案約定：資料一律 JSON）。圖集 `game/assets/chapter01/tiles.png` 由 `make_tiles.py` 產生並進 git。

## 4. 驗收

1. 關卡縮圖（螢幕縮到 1/4）仍能一眼看出路徑走向
2. 改 `path_waypoints` 一個點，`Path2D` 與地磚同時改變，敵人沿新路走
3. 潮位切換時，只有指定格子變化，其餘畫面不重繪
4. 擺件不落在路徑格與建塔格上（資料完整性測試）
5. 既有測試全綠；新增 `tests/test_level_map.gd` 守第 2、4 項

## 5. 與美術軌的關係

地磚顏色只用 `data/art_palette.json`；擺件走 A4 管線。地圖從此不再是 AI 資產，`map_1_1`／`map_tile_*` 三張整圖退役為參考圖（或留作過場背景）。

## 6. 待決策（已定，2026-09-09）

1. ~~磚尺寸 32 或 48~~ **32px**。路徑寬 2 格＝64px，單位跨路不溢出；60×34 格的地圖轉角可以較細。
2. ~~路徑格的視覺：卵石紋或素沙~~ **素沙（沙洲黃平色）**。扁平幾何風格下靠色對比讀路徑，紋理反而突兀；也最符合鹿耳門沙洲的實情。

實作上另外定了一件事：地面與擺件放 `CanvasLayer -10`、紙紋 shader 的描邊 pass 放 `-5`、單位留在根層、純紙紋 pass 與 HUD 同為 `1` 但先加入——描邊只看得到地圖，HUD 層序不用動。
