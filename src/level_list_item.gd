extends Button

signal selected(pack_info: Dictionary)

var level_pack_info := {}

func setup(pack_info: Dictionary, viewport: Vector2) -> void:
	level_pack_info = pack_info
	if pack_info.config.title == "":
		pack_info.config.title = pack_info.config.song.trim_suffix(".mp3").trim_suffix(".wav").trim_suffix(".ogg")
	custom_minimum_size = Vector2(0, viewport.y * .15)
	$Text.text = "[font_size=36]  %s    [/font_size][font_size=24]%s[/font_size]" \
				 % [pack_info.config.title, pack_info.config.author]

func _gui_input(event: InputEvent) -> void:
	# TODO: IEST triggers twice as the user touches and releases
	if event is InputEventScreenTouch:
		selected.emit(level_pack_info)
