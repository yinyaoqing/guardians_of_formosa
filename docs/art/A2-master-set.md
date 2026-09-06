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
