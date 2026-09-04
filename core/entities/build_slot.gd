class_name BuildSlot
extends RefCounted

## 關卡上可以蓋塔的一個離散位置。
## 位置由場景中的 Marker2D 標示，載入時烘焙成本類別交給 core/——
## 與 Path2D → PathData 同一模式，core/ 不認得 Marker2D。

var id: int = 0                ## 由 WorldState.next_id() 配發，與其他實體共用號碼空間
var position: Vector2 = Vector2.ZERO
var occupied_by: int = 0       ## 塔的實體 id，0 表示空著
