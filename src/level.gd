extends Control

@onready var chart_parser = preload("res://src/chart_parser.gd")
const GyroInitializer = preload("res://src/gyroscope_initializer.gd")
const GyroAgent = preload("res://src/gyroscope_agent.gd")
var gyro_initializer: Node
var gyro_agent: Node
var motion_ready := false
var _motion_status: Label
var _retry_calibration: Button
var _application_focused := true
var _level_loaded := false
@onready var bg = $Aspect2/Background
@onready var notes_container = $Notes
@onready var start_timestamp: int
@onready var prev_timestamp: int
@onready var bpm: float
@onready var chart_data: Dictionary
@onready var metas: Array[Dictionary] = []	## Meta info. Flipped to avoid frequent revision of indeces
@onready var notes: Array[Dictionary] = []	## Note info. Flipped to avoid frequent revision of indeces
@onready var lines: Array[Dictionary] = []	## Line info. Flipped to avoid frequent revision of indeces
@onready var music: AudioStream
@onready var music_playback

func _ready():
	if !setup():
		var lbl = RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = get_viewport_rect().size
		lbl.clip_contents = false
		lbl.text = "[font_size=30][u]Could not launch %s. Please check resource files.[/u][/font_size]" % \
					Globals.current_level_info.get("config", {}).get("title", "level")
		add_child(lbl)
		await get_tree().create_timer(2).timeout
		get_tree().change_scene_to_file("res://scn/level_select.tscn")
		return
	
	initialize_chart_data()
	_level_loaded = true
	_setup_motion_controls()
	start_motion_calibration()


func _setup_motion_controls() -> void:
	var controls := VBoxContainer.new()
	controls.position = Vector2(16, 16)
	add_child(controls)
	_motion_status = Label.new()
	controls.add_child(_motion_status)
	_retry_calibration = Button.new()
	_retry_calibration.text = "Recalibrate"
	_retry_calibration.pressed.connect(start_motion_calibration)
	controls.add_child(_retry_calibration)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_Back_pressed)
	controls.add_child(back)


func _clear_motion_nodes() -> void:
	motion_ready = false
	for node in [gyro_initializer, gyro_agent]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	gyro_initializer = null
	gyro_agent = null


func start_motion_calibration() -> void:
	if not _level_loaded or not _application_focused or get_tree().paused:
		return
	_clear_motion_nodes()
	_motion_status.text = "Hold still for calibration (2 seconds)."
	_retry_calibration.disabled = true
	gyro_initializer = GyroInitializer.new()
	gyro_initializer.mode = Globals.gyro_type
	gyro_initializer.completed.connect(_on_motion_calibrated)
	gyro_initializer.failed.connect(_on_motion_calibration_failed)
	add_child(gyro_initializer)


func _on_motion_calibrated(gravity: Vector3, bias: Vector3) -> void:
	# Construct the scripted node only after calibration has completed.
	var input_mode: int = gyro_initializer.mode
	remove_child(gyro_initializer)
	gyro_initializer.queue_free()
	gyro_initializer = null
	gyro_agent = GyroAgent.new()
	if not gyro_agent.configure(input_mode, gravity, bias):
		gyro_agent.free()
		gyro_agent = null
		_on_motion_calibration_failed("Unsupported calibration pose. Please retry.")
		return
	gyro_agent.process_physics_priority = -10
	add_child(gyro_agent)
	motion_ready = true
	_motion_status.text = "Calibration complete."
	_retry_calibration.disabled = false


func _on_motion_calibration_failed(reason: String) -> void:
	_clear_motion_nodes()
	_motion_status.text = reason
	_retry_calibration.disabled = false


func _notification(what: int) -> void:
	if not _level_loaded:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused = false
		_clear_motion_nodes()
	elif what == NOTIFICATION_PAUSED:
		_clear_motion_nodes()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_focused = true
		call_deferred("start_motion_calibration")
	elif what == NOTIFICATION_UNPAUSED:
		call_deferred("start_motion_calibration")

func setup() -> bool:
	if not Globals.current_level_info.has("config") or not Globals.current_level_info.has("path"):
		return false
	# Jacket
	var jacket_path = Globals.current_level_info.path + Globals.current_level_info.config.jacket
	if FileAccess.file_exists(jacket_path):
		bg.texture = ImageTexture.create_from_image(Image.load_from_file(jacket_path))
	else:
		bg.texture = preload("res://res/Journey_with_You_jacket.webp")
	bg.modulate = Color(Globals.bg_brightness, Globals.bg_brightness, Globals.bg_brightness)
	# Validation
	var prereq = [
		Globals.current_level_info.path + Globals.current_level_info.config.chart, 
		Globals.current_level_info.path + Globals.current_level_info.config.song
	]
	for file in prereq:
		if !FileAccess.file_exists(file):
			push_error("Directory for chart or music is invalid.")
			return false
	# Chart
	var data := FileAccess.open(prereq[0], FileAccess.READ).get_as_text()
	chart_data = chart_parser.parse_chart(data)
	# Music
	if prereq[1].to_lower().ends_with("mp3"):
		music = AudioStreamMP3.load_from_file(prereq[1])
	elif prereq[1].to_lower().ends_with("ogg"):
		music = AudioStreamOggVorbis.load_from_file(prereq[1])
	elif prereq[1].to_lower().ends_with("wav"):
		music = AudioStreamWAV.load_from_file(prereq[1])
	else:
		push_error("Unsupported audio format (We support mp3, wav, and ogg vorbis).")
		return false
	return true

func _physics_process(_delta: float) -> void:
	if motion_ready and is_instance_valid(gyro_agent) and not gyro_agent.is_calibrated:
		start_motion_calibration()

## Unwraps chart_data into METAS and NOTES, do respective calculations, then flip the arrays back-to-front.
func initialize_chart_data() -> void:
	metas.clear()
	notes.clear()
	lines.clear()
	for meta in chart_data.metadata:
		metas.append(meta)
	for note in chart_data.notes:
		notes.append(note)
	for line in chart_data.lines:
		lines.append(line)
	metas.reverse()
	notes.reverse()
	lines.reverse()
	chart_data = {}

func _input(event):
	# 处理触摸输入
	if event is InputEventScreenTouch:
		handle_touch_input(event)

func handle_touch_input(touch_event):
	# 处理触摸事件
	pass

func _on_Back_pressed():
	get_tree().change_scene_to_file("res://scn/level_select.tscn")
