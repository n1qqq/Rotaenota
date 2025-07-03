extends Control

func _ready():
	# 加载设置
	load_settings()

func load_settings():
	# 从配置文件加载设置
	pass

func save_settings():
	# 保存设置到配置文件
	pass

func _on_GyroToggle_toggled(button_pressed):
	# 切换陀螺仪启用状态
	pass
	save_settings()

func _on_Back_pressed():
	# 返回上一界面
	get_tree().change_scene("res://scn/level_select.tscn")
