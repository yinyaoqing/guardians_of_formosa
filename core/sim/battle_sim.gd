class_name BattleSim
extends RefCounted

## 固定步長模擬迴圈。渲染幀率與邏輯 tick 解耦，好處是：
##  - 暫停與加速只是「本幀跑幾個 tick」，不必把 delta 乘上倍率（後者必然產生數值錯誤）
##  - 手機掉幀時邏輯不會變慢，戰鬥結果在不同效能裝置上一致

const TICK_RATE := 30
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 單幀最多執行的 tick 數。卡頓後若無上限地補跑積欠的 tick，
## 會讓下一幀更慢、積欠更多，形成死亡螺旋。超過上限就丟棄積欠。
const MAX_TICKS_PER_FRAME := 8

var tick_count: int = 0
var speed_multiplier: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

## 推進模擬。frame_delta 為渲染幀的實際經過秒數。
## 回傳本幀實際執行的 tick 數。
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	_accumulator += frame_delta * speed_multiplier
	var ticks := 0
	while _accumulator >= TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_DELTA
		_tick()
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0
	return ticks

func _tick() -> void:
	tick_count += 1
