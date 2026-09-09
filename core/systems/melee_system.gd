class_name MeleeSystem
extends RefCounted

## 交戰的建立與雙方互砍。
##
## 這個系統不認得兵營：小兵從哪來、什麼時候補、回多少血都是 GarrisonSystem
## 的事。這裡只問「誰站在哪、誰在打誰」。
##
## 解除交戰不在這裡——實體離開世界的唯一地點是 BattleSim._remove_dead()，
## 解綁也放在那裡，才不會有兩個地方各自清一半。

## 攔截窗口的半寬（像素）。
##
## 銃卒速度 45 px/s，一個 tick 走 1.5 px，所以 48 px 寬的窗口相當於 32 個
## tick 的通過時間。倍速是「一幀跑多個 tick」而非放大 delta，每個 tick 的
## 位移恆為 1.5 px，因此 4 倍速下也不會有敵人在單一 tick 內跳過整個窗口。
const ENGAGE_WINDOW := 24.0

static func tick(world: WorldState, delta: float) -> void:
	_engage(world)
	_trade_damage(world, delta)

## 讓每個閒著的小兵找一個對象。
##
## 複雜度是 O(小兵 × 敵人)。M1 的上限約 12 個小兵配 30 隻敵人 = 360 次比較，
## 遠低於塔的目標選擇（那個才需要 UniformGrid）。不配置任何物件。
static func _engage(world: WorldState) -> void:
	for soldier: Soldier in world.soldiers:
		if not soldier.alive or soldier.engaged_enemy_id != 0:
			continue
		var best: Enemy = null
		for enemy: Enemy in world.enemies:
			if not enemy.alive or enemy.leaked or enemy.blocked_by != 0:
				continue
			if enemy.path_id != soldier.path_id:
				continue
			if absf(enemy.distance_along - soldier.post_distance) > ENGAGE_WINDOW:
				continue
			# 窗口內有多個時擋最前面的，與 TargetingSystem.find_first 一致
			if best == null or enemy.distance_along > best.distance_along:
				best = enemy
		if best == null:
			continue
		soldier.engaged_enemy_id = best.id
		best.blocked_by = soldier.id

## 交戰雙方各自照自己的間隔出手。兩邊都走 DamageSystem——近戰若自己算傷害，
## 減免規則就有第二份（硬規則 #2）。
##
## 冷卻歸零用 <= 0.0 判斷、不用容差，是為了跟 _tick_towers 的既有寫法一致
## （見 battle_sim.gd）。代價是連續相減的浮點殘值會讓實際攻擊間隔比設定值
## 多吃約一個 tick（1/30 秒，約 3.3%）——塔已經在付這個代價，近戰跟著付，
## 兩邊的冷卻語意就不會因為各自選了不同的判斷方式而悄悄分家。
static func _trade_damage(world: WorldState, delta: float) -> void:
	for soldier: Soldier in world.soldiers:
		if not soldier.alive or soldier.engaged_enemy_id == 0:
			continue
		var enemy: Enemy = world.enemies_by_id.get(soldier.engaged_enemy_id)
		if enemy == null or not enemy.alive:
			continue

		soldier.cooldown = maxf(0.0, soldier.cooldown - delta)
		if soldier.cooldown <= 0.0:
			DamageSystem.apply(enemy, soldier.damage, soldier.damage_type)
			soldier.cooldown = soldier.attack_interval

		# 敵人照樣還手，即使它剛剛被打死——這一 tick 兩邊同歸於盡是合理結果。
		# 但小兵若已經死了就不再挨打，否則屍體會被重複結算。
		if not soldier.alive:
			continue
		enemy.melee_cooldown = maxf(0.0, enemy.melee_cooldown - delta)
		if enemy.melee_cooldown <= 0.0:
			DamageSystem.apply(soldier, enemy.melee_damage, DamageSystem.PHYSICAL)
			enemy.melee_cooldown = enemy.melee_interval
