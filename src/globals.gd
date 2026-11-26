extends Node

enum GYRO { HANDHOLD, DESKTOP, ACCEL }

const settings_path = "user://preferences.json"
@onready var current_level_info: Dictionary
@onready var bg_brightness := .5
@onready var gyro_type := GYRO.HANDHOLD		## HANDHOLD, DESKTOP, or ACCEL
@onready var note_speed := 4.				## 1.0 ~ 8.0
@onready var offset := 0					## Unit: ms
@onready var render_timing := 4.			## Unit: beat (hence bpm irrelevant). default: 1 full bar under 4/4 time signature
@onready var render_pool := 128				## Unit: number count


func _ready() -> void:
	load_config()

func load_config(path: String = settings_path) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not read preferences: %s" % error_string(FileAccess.get_open_error()))
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("Invalid preferences JSON; keeping current settings.")
		return
	var data: Dictionary = json.data
	# JSON numbers may be floats. Reject invalid fields individually so older
	# configurations can omit keys without losing their valid settings.
	if _valid_number(data.get("gyro_type"), GYRO.HANDHOLD, GYRO.ACCEL, true):
		gyro_type = int(data.gyro_type)
	if _valid_number(data.get("note_speed"), 1.0, 8.0):
		note_speed = float(data.note_speed)
	if _valid_number(data.get("offset"), -2000, 2000, true):
		offset = int(data.offset)
	if _valid_number(data.get("render_timing"), 0.0, INF) and data.render_timing > 0:
		render_timing = float(data.render_timing)
	if _valid_number(data.get("render_pool"), 1, 2147483647, true):
		render_pool = int(data.render_pool)


func _valid_number(value: Variant, minimum: float, maximum: float, integer: bool = false) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum \
		and (not integer or value == floor(value))


func save_config(path: String = settings_path) -> Error:
	# WRITE creates the file on first use as well as replacing an existing file.
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_error = FileAccess.get_open_error()
		push_warning("Could not save preferences: %s" % error_string(open_error))
		return open_error
	file.store_string(JSON.stringify({
		"gyro_type": gyro_type,
		"note_speed": note_speed,
		"offset": offset,
		"render_timing": render_timing,
		"render_pool": render_pool,
	}, "\t"))
	file.flush()
	var write_error = file.get_error()
	if write_error != OK:
		push_warning("Could not write preferences: %s" % error_string(write_error))
	return write_error
