# Guardians of Formosa

塔防遊戲。架構設計見 `docs/superpowers/specs/`，實作計畫見 `docs/superpowers/plans/`。

## 環境需求

- Godot 4.x 標準版（非 .NET 版），版本見 `.godot-version`
- Git LFS

## 執行測試

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

## 換機或重建匯出設定時的必要步驟

`export_presets.cfg` 不進版控（含本機路徑），重建匯出設定時必須手動補上：

- Project → Export → Resources → **Filters to export non-resource files/folders** 填 `*.json`
  （否則 `data/` 下的 JSON 不會被打包，遊戲在匯出版本會找不到資料）
