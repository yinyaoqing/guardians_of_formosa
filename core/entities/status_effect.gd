class_name StatusEffect
extends RefCounted

## 狀態效果的「執行期實例」，不是 JSON 定義本身。
## 實例走物件池：施加時取出、到期時歸還，避免戰鬥迴圈中配置新物件。

const KIND_SLOW := &"slow"
const KIND_STUN := &"stun"
const KIND_DOT := &"dot"
const KIND_ARMOR_BREAK := &"armor_break"

## 施加者的 tower_id（塔的「種類」，不是個別那座塔）。
## 堆疊規則以此判定「同來源刷新」或「不同來源並存」。
var source: StringName = &""

var kind: StringName = &""
var magnitude: float = 0.0
var damage_type: StringName = &""   ## 僅 KIND_DOT 使用
var remaining: float = 0.0          ## 剩餘秒數

func reset() -> void:
	source = &""
	kind = &""
	magnitude = 0.0
	damage_type = &""
	remaining = 0.0
