extends Node

enum GYRO { HANDHOLD, DESKTOP, ACCEL }

const settings_path := "user://preferences.json"
@onready var gyro_type := GYRO.HANDHOLD		## HANDHOLD, DESKTOP, or ACCEL
@onready var note_speed := 4.				## 1.0 ~ 8.0
@onready var render_timing := 4.			## Unit: beat (hence bpm irrelevant). default: 1 full bar under 4/4 time signature
@onready var render_pool := 128				## Unit: number count

func get_next_angle(prev: Vector3, delta: Vector3) -> Vector3:
	# use .z to get the angle
	match gyro_type:
		GYRO.HANDHOLD, GYRO.DESKTOP:
			return prev + delta
		GYRO.ACCEL:
			return prev + delta / 3
		_:
			return Vector3.ZERO

func _ready() -> void:
	load_config()

func load_config() -> void:
	if FileAccess.file_exists(settings_path):
		var content = FileAccess.open(settings_path, FileAccess.READ).get_as_text()
		var data = JSON.parse_string(content)
		gyro_type = data.gyro_type
		note_speed = data.note_speed
		render_timing = data.render_timing
		render_pool = data.render_pool
