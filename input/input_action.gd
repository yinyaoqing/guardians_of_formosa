class_name InputAction
extends RefCounted

## 裝置無關的玩家動作。翻譯器把原始 InputEvent 轉成本型別，
## InteractionController 再把動作序列翻成 GameIntent。
##
## 這一層存在的理由是把「互動文法」與「裝置」分開：文法只寫一次，
## M4 加手把時只需再寫一個薄翻譯器，文法一行都不用動。

const SELECT_AT := &"select_at"        ## 在某個世界座標點選
const CHOOSE_TOWER := &"choose_tower"  ## 選第 n 種本關可用的塔
const SELL := &"sell"
const UPGRADE := &"upgrade"
const CANCEL := &"cancel"
const TOGGLE_PAUSE := &"toggle_pause"
const CYCLE_SPEED := &"cycle_speed"

var kind: StringName = &""
var world_position: Vector2 = Vector2.ZERO  ## SELECT_AT 用
var index: int = 0                          ## CHOOSE_TOWER 用，1 起算

static func select_at(p_world_position: Vector2) -> InputAction:
	var action := InputAction.new()
	action.kind = SELECT_AT
	action.world_position = p_world_position
	return action

static func choose_tower(p_index: int) -> InputAction:
	var action := InputAction.new()
	action.kind = CHOOSE_TOWER
	action.index = p_index
	return action

## 不帶 payload 的動作
static func simple(p_kind: StringName) -> InputAction:
	var action := InputAction.new()
	action.kind = p_kind
	return action
