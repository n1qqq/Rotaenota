extends Control

@onready var chart_parser = preload("res://src/chart_parser.gd")
@onready var gyro_initializer = preload("res://src/gyroscope_initializer.gd").new()
@onready var gyro_agent = Node.new()
@onready var bg = $Aspect2/Background
@onready var start_time: int
@onready var prev_time: int
@onready var bpm: float
@onready var chart_data: Dictionary
@onready var metas: Array[Dictionary] = []	## Meta-data. Flipped to avoid frequent revision of indeces
@onready var notes: Array[Dictionary] = []	## Note info. Flipped to avoid frequent revision of indeces
@onready var music: AudioStream
@onready var music_playback
@export var up_direction := Vector3.ZERO

func _ready():
	add_child(gyro_agent)
	if !setup():
		var lbl = RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = get_viewport_rect().size
		lbl.clip_contents = false
		lbl.text = "[font_size=30][u]Could not launch %s. Please check resource files.[/u][/font_size]" % \
					Globals.current_level_info.config.title
		add_child(lbl)
		await get_tree().create_timer(2).timeout
		gyro_initializer = null
		get_tree().change_scene_to_file("res://scn/level_select.tscn")
		return
	initialize_chart_data()
	add_child(gyro_initializer)
	while gyro_initializer.calibrating:
		await get_tree().create_timer(.3).timeout
		if gyro_initializer.failure:
			gyro_initializer.get_parent().queue_free()
			gyro_initializer = null
			get_tree().change_scene_to_file("res://scn/level_select.tscn")
			return
	up_direction = gyro_initializer.up_direction
	gyro_initializer.get_parent().queue_free()
	gyro_initializer = null
	gyro_agent.set_script(preload("res://src/gyroscope_agent.gd"))

func setup() -> bool:
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

func _process(_delta):
	match Globals.gyro_type:
		Globals.GYRO.HANDHOLD, Globals.GYRO.DESKTOP:
			var gyro = Input.get_gyroscope()
			handle_gyro_input(gyro)
		Globals.GYRO.ACCEL:
			var accel = Input.get_accelerometer()
			handle_accel_input(accel)

## Unwraps chart_data into METAS and NOTES, do respective calculations, then flip the two arrays back-to-front.
func initialize_chart_data() -> void:
	metas.clear()
	notes.clear()
	

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
	get_tree().change_scene_to_file("res://scn/level_select.tscn")
