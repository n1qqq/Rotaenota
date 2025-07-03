extends Node2D

@onready var gyroscope = $GyroscopeAgent

func _ready():
	
	setup_game_area()

func setup_game_area():
	# 设置游戏区域和判定线等
	pass

func setup_pack(pack: Dictionary):
	pass

func _process(delta):
	while gyroscope.calibrating():
		return
	match Globals.gyro_type:
		Globals.GYRO.HANDHOLD, Globals.GYRO.DESKTOP:
			var gyro = Input.get_gyroscope()
			handle_gyro_input(gyro)
		Globals.GYRO.ACCEL:
			var accel = Input.get_accelerometer()
			handle_accel_input(accel)

func handle_gyro_input(gyro_data):
	pass

func handle_accel_input(gyro_data):
	pass

func _input(event):
	# 处理触摸输入
	if event is InputEventScreenTouch:
		handle_touch_input(event)

func handle_touch_input(touch_event):
	# 处理触摸事件
	pass

func _on_Back_pressed():
	# 返回关卡选择界面
	get_tree().change_scene("res://scenes/level_select.tscn")
