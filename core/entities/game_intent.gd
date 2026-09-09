class_name GameIntent
extends RefCounted

## 玩家意圖。輸入層產生，排入 WorldState 的佇列，由 BattleSim 在 tick 第一步套用。
##
## 排隊而非立即套用，是為了讓所有改變世界的事情都發生在 tick 內的明確位置——
## 既有整套 tick 順序測試都建立在這條不變式上。代價是最多一個 tick 的延遲。
##
## 不做池化：intent 由人手驅動，每秒最多數個，與每秒數十個生滅的投射物
## 不是同一個量級。沿用「只池化 churn 最高的」原則。

const KIND_BUILD := &"build"
const KIND_SELL := &"sell"
const KIND_UPGRADE := &"upgrade"

## 控制類：改的是模擬本身的參數，不是世界狀態，由 BattleSim 直接處理。
## 刻意不帶數值——intent 表達玩家動作而非結果值，回放時重現的才是
## 「玩家按了切換」而不是「速度變成 2」。
const KIND_TOGGLE_PAUSE := &"toggle_pause"
const KIND_CYCLE_SPEED := &"cycle_speed"
const KIND_CALL_NEXT_WAVE := &"call_next_wave"

var kind: StringName = &""
var slot_id: int = 0            ## KIND_BUILD 用
var tower_id: StringName = &""  ## KIND_BUILD 用，要蓋哪一種
var entity_id: int = 0          ## KIND_SELL / KIND_UPGRADE 用，動哪一座

static func build(p_slot_id: int, p_tower_id: StringName) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_BUILD
	intent.slot_id = p_slot_id
	intent.tower_id = p_tower_id
	return intent

static func sell(p_entity_id: int) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_SELL
	intent.entity_id = p_entity_id
	return intent

static func upgrade(p_entity_id: int) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_UPGRADE
	intent.entity_id = p_entity_id
	return intent

static func toggle_pause() -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_TOGGLE_PAUSE
	return intent

static func cycle_speed() -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_CYCLE_SPEED
	return intent

static func call_next_wave() -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_CALL_NEXT_WAVE
	return intent
