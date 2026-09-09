class_name ResultSystem
extends RefCounted

## 通關結算的星等規則。純函式，只讀 WorldState，不改動任何狀態——
## 星等只在戰鬥結束後算一次，不屬於 tick 迴圈。
##
## 這是本里程碑唯一一條活在 core/ 之外的遊戲規則（原本在 battle_scene.gd
## 裡直接讀 registry），搬進來的理由：第三顆星（未失去聚落建物）要看的
## 聚落建物數量本來就得住在 core/，星等規則不能一半在 core/、一半在 game/。
##
## 第一章規格 §4.6：
##   ★   撐過所有波次——呼叫這個函式的前提是 world.battle_finished 成立，
##       所以第一顆星恆定拿到，這裡不需要另外判斷。
##   ★★  平民撤離數達到門檻，用 >=（規格原文「≥ 門檻」，不是「> 門檻」）。
##   ★★★ 未失去聚落建物——聚落建物尚未實作，沒有東西可以「沒有失去」，
##       這顆星恆為未達成。等聚落建物真的加進遊戲，這裡要換成讀那個計數，
##       而不是刪掉這一段。
static func star_count(world: WorldState) -> int:
	var stars := 1
	if world.civilians_remaining >= world.star_civilian_threshold:
		stars = 2
	return stars
