extends Control

func _ready():
	gyro_button.offset_right = viewport.x * .125
	gyro_button.offset_left = -gyro_button.offset_right
	speed_label.custom_minimum_size = Vector2(viewport.x * .25, 0)
	gyro_button.offset_top = viewport.y * .1
	speed_ctrls.offset_top = viewport.y * .3
	back_button.pressed.connect(_on_back_button_pressed)
	gyro_button.item_selected.connect(_on_gyro_selected)
	for item in speed_ctrls.get_children():
		if item is Button:
			item.pressed.connect(_on_speed_buttons_pressed.bind(item.name))
	read_settings()
	show_panel()

@onready var viewport := get_viewport_rect().size
@onready var back_button := $BackButton
@onready var gyro_button := $GyroButton
@onready var speed_ctrls := $SpeedControls
@onready var speed_label := $SpeedControls/Speed

## Returns formatted string with size set
func set_font_size(str: String, size: int) -> String:
	return "[font_size=%d]%s[/font_size]" % [size, str]

## Get settings from Globals. Used as an update fn
func read_settings():
	speed_label.text = set_font_size(str(Globals.note_speed), 24)
	gyro_button.selected = Globals.gyro_type

## Store settings to .cfg file
func save_settings():
	pass

func show_panel():
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1, .3)

## Encountering logical difficulties here...
func hide_panel():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, .3)

func _on_gyro_selected(type_id: int):
	Globals.gyro_type = type_id
	read_settings()
	save_settings()
	
func _on_speed_buttons_pressed(name: String):
	var val: float
	match name:
		"sss":	val = -1.
		"ss":	val = -.1
		"s":	val = -.01
		"f":	val = .01
		"ff":	val = .1
		"fff":	val = 1.
	Globals.note_speed = clampf(Globals.note_speed + val, 1, 8)
	read_settings()

func _on_back_button_pressed():
	#hide_panel()
	get_tree().paused = false
	queue_free()
