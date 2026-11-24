extends Control

func _ready():
	#print(JSON.stringify({"title": "Demo 01", "author": "Not Applicable", "jacket": "", "chart": "", "song": "", "preview": "", "difficulty": NAN}, "\t"))
	# Full-Screen Touchable
	print(rad_to_deg(Vector3(-1, -1, -1).angle_to(Vector3(0, -1, -1))))
	var a = Vector2(1, 0)
	var b = Vector2(0, -1)
	print(rad_to_deg(atan2(a.y, a.x) - atan2(b.y, b.x)))
	var touch_area = ColorRect.new()
	touch_area.color = Color(0, 0, 0, 0)  # Transparent
	touch_area.custom_minimum_size = get_viewport_rect().size
	touch_area.connect("gui_input", _on_touch_area_gui_input)
	add_child(touch_area)
	
	var title = RichTextLabel.new()
	title.bbcode_enabled = true
	title.text = "[b][font_size=48]Rotaenota[/font_size][/b]"
	title.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
	title.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, get_viewport_rect().size.y * 0.3)
	title.size = Vector2(get_viewport_rect().size.x, 100)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

func _on_touch_area_gui_input(event):
	if event is InputEventScreenTouch and event.pressed:
		ResourceLoader.load_threaded_request("res://scn/level_select.tscn")
		while not ResourceLoader.load_threaded_get_status("res://scn/level_select.tscn") == ResourceLoader.THREAD_LOAD_LOADED:
			await get_tree().create_timer(.1).timeout
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get("res://scn/level_select.tscn"))
