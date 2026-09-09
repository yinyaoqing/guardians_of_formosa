class_name PaperOverlay
extends Node

## 「紙上的戲」兩層後處理（A2x §2.4）：
##   layer -5  描邊 + 紙紋——此時 screen texture 只畫了 GroundLayers（-10），地圖收成線稿
##   layer  1  只有紙紋——蓋住單位讓它們也躺在紙上；與 HUD 同層但先加入，HUD 仍在最上
## 單位在根層（0），輪廓已由 postprocess.py 加好，不再吃 Sobel。
## M2 要量它在中階 Android 的幀率；ENABLED 是總開關。

const SHADER := preload("res://game/fx/paper_ink.gdshader")
const ENABLED := true

var _ink: ShaderMaterial
var _paper: ShaderMaterial


## 必須在 HUD／BuildMenu 加入 host 之前呼叫，否則紙紋會蓋在 UI 上。
static func attach(host: Node) -> PaperOverlay:
	var o := PaperOverlay.new()
	o.name = "PaperOverlay"
	host.add_child(o)
	o._ink = o._layer(-5, false)
	o._paper = o._layer(1, true)
	o.set_enabled(ENABLED)
	return o


func _layer(index: int, paper_only: bool) -> ShaderMaterial:
	var layer := CanvasLayer.new()
	layer.layer = index
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	if paper_only:
		mat.set_shader_parameter("ink_strength", 0.0)
		mat.set_shader_parameter("paper_tint", 0.10)
		mat.set_shader_parameter("vignette", 0.0)
	else:
		# 地磚的碎點（草地的翠綠／曝曬沙點）在預設門檻下每一顆都被抓成墨點，畫面髒；
		# 提高門檻只讓路徑邊、水岸、擺件輪廓這種強邊緣出線。
		mat.set_shader_parameter("ink_threshold", 0.32)
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)
	return mat


func set_enabled(on: bool) -> void:
	_ink.set_shader_parameter("enabled", on)
	_paper.set_shader_parameter("enabled", on)
