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
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

UI 與畫面不做自動化測試，人工驗收。
