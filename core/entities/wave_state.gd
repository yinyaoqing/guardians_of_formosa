class_name WaveState
extends RefCounted

## 波次的執行期狀態。只有 WaveSystem 讀寫。
##
## 不攤平到 WorldState 的欄位裡，是因為這些狀態彼此只有一起看才有意義，
## 而 WorldState 已經夠長了。

## 正在倒數或正在生成的那一波。等於 waves.size() 表示全部生成完畢。
var next_wave_index: int = 0

## 距離該波開始的秒數。只在 spawning 為 false 時有意義。
var countdown: float = 0.0

var spawning: bool = false

## 生成中的群組，每筆是 {enemy_id, path_id, remaining, interval, timer}。
## 每波開始時配置一次——一波約十幾秒才發生一次，不是戰鬥迴圈的高頻配置。
var active_groups: Array[Dictionary] = []
