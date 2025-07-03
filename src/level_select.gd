extends Control

func _ready():
	setup_ui_layout()
	start_button.pressed.connect(_on_start_button_pressed)
	top_bar_button.pressed.connect(_on_settings_button_pressed)
	refresh_levels()

const LEVELS_DIR_NAME = "user://Levels/"
const DEMO_LEVEL_PATH = "res://demo/demo_0/"
@onready var current_selected_pack: Dictionary = {}
@onready var all_level_packs: Array[Dictionary] = []
@onready var texture: Resource = preload("res://res/Journey_with_You_jacket.webp")
@onready var content_container := $Content
@onready var level_list_container := $Content/ScrollContainer/VBoxContainer
@onready var preview_panel := $Content/PreviewPanel
@onready var level_preview := $Content/PreviewPanel/LevelPreview
@onready var level_details := $Content/PreviewPanel/LevelDetails
@onready var level_name_label := $Content/PreviewPanel/LevelDetails/LevelInfo/Name
@onready var level_author_label := $Content/PreviewPanel/LevelDetails/LevelInfo/Author
@onready var level_difficulty_label := $Content/PreviewPanel/LevelDetails/LevelInfo/Difficulty
@onready var start_button := $Content/PreviewPanel/LevelDetails/StartButton
@onready var top_bar_container := $TopBar
@onready var top_bar_button := $TopBar/SettingsButton

func setup_ui_layout():
	var viewport := get_viewport_rect().size
	# TopBar
	top_bar_container.offset_bottom = viewport.y * 0.15  # Height: 15%
	# Content
	content_container.offset_top = top_bar_container.offset_bottom * 1.2
	content_container.split_offset = viewport.x * 0.66  # 2:1
	preview_panel.split_offset = viewport.y * 0.5
	level_details.split_offset = viewport.y * 0.2

func get_all_level_packs() -> Array[Dictionary]:
	var packs = scan_file_system_levels()
	if !packs:
		# Fallback
		var file = FileAccess.open(DEMO_LEVEL_PATH + "config.json", FileAccess.READ)
		var demo_config = JSON.parse_string(file.get_as_text(true))
		if demo_config:
			packs.append({
				"name": "Demo Level",
				"path": DEMO_LEVEL_PATH,
				"config": demo_config,
			})
	return packs

func scan_file_system_levels() -> Array[Dictionary]:
	var packs: Array[Dictionary] = []
	var dir = DirAccess.open(LEVELS_DIR_NAME)
	if dir:
		dir.list_dir_begin()		# signal the start of traversal for current DirAccess object
		var folder = dir.get_next()
		while folder != "":
			if dir.current_is_dir() and not folder.begins_with("."):
				var pack_path = LEVELS_DIR_NAME + folder
				var config_path = pack_path + "/config.json"
				if dir.file_exists(config_path):
					var file = FileAccess.open(config_path, FileAccess.READ)
					var config = JSON.parse_string(file.get_as_text(true))
					if config:
						packs.append({
							"name": folder,
							"path": pack_path,
							"config": config,
						})
			folder = dir.get_next()
	return packs


func refresh_levels() -> void:
	all_level_packs = get_all_level_packs()
	update_level_list()
	if all_level_packs:
		select_level(all_level_packs[0])

func update_level_list(packs=all_level_packs) -> void:
	for node in level_list_container.get_children():
		node.queue_free()
	for pack in packs:
		var item = preload("res://scn/level_list_item.tscn").instantiate()
		item.setup(pack, get_viewport_rect().size)
		item.selected.connect(select_level)
		level_list_container.add_child(item)

func select_level(pack) -> void:
	current_selected_pack = pack
	update_preview_panel(pack)

func update_preview_panel(pack) -> void:
	texture = load_image_file(pack.path + pack.config.jacket)
	level_preview.texture = texture
	level_name_label.text = pack.config.song
	level_author_label.text = "Composer: " + pack.config.author
	level_difficulty_label.text = "Difficulty: " + str(pack.config.difficulty)
	start_button.disabled = false

func load_image_file(path):
	if ResourceLoader.exists(path, "Image"):
		return load(path)
	return preload("res://res/Journey_with_You_jacket.webp")		# Placeholder

func _on_start_button_pressed():
	if current_selected_pack:
		var game_scene = preload("res://scn/level.tscn").instantiate()
		game_scene.setup_pack(current_selected_pack)
		get_tree().root.add_child(game_scene)

func _on_settings_button_pressed():
	var settings_scene = preload("res://scn/settings.tscn").instantiate()
	add_child(settings_scene)
