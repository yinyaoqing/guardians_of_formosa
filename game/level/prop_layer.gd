class_name PropLayer
extends Node2D

## 擺件層：樹、聚落、礁石等由 map.json 指定格子，y_sort 讓站在後面的被前面的蓋住。
## 每個擺件底下一張共用的橢圓接觸陰影（精緻度規格 L1）——沒有它單位與擺件都像貼紙。
## 擺件貼圖來自 game/assets/chapter01/<id>.png，走 A4 管線，本層不處理美術。

var _shadow: Texture2D


func _ready() -> void:
	y_sort_enabled = true


func setup(map: LevelMap, asset_dir: String, shadow: Texture2D) -> void:
	_shadow = shadow
	for p in map.props():
		var tex: Texture2D = load(asset_dir.path_join("%s.png" % p["id"]))
		var foot := map.cell_center(p["cell"]) + Vector2(0, map.tile_px * 0.5)
		if p["shadow"]:
			_add_shadow(foot, tex.get_width() * 0.9)
		var s := Sprite2D.new()
		s.texture = tex
		s.position = foot
		s.offset = Vector2(0, -tex.get_height() * 0.5)
		add_child(s)


func _add_shadow(foot: Vector2, width: float) -> void:
	var s := Sprite2D.new()
	s.texture = _shadow
	s.position = foot
	s.scale = Vector2.ONE * (width / _shadow.get_width())
	s.z_index = -1
	add_child(s)
