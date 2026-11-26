extends SceneTree

# Run: godot --headless --path . --script tests/preferences_test.gd
# Fixtures stay in the ignored project cache; real user preferences are untouched.
var config: Node
var fixture_dir: String
var fixture_path: String
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)


func defaults() -> void:
	config.gyro_type = 0
	config.note_speed = 4.0
	config.offset = 0
	config.render_timing = 4.0
	config.render_pool = 128


func snapshot() -> Array:
	return [config.gyro_type, config.note_speed, config.offset, config.render_timing, config.render_pool]


func write_fixture(content: String) -> void:
	var file = FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(content)


func run() -> void:
	fixture_dir = "res://.godot/preferences_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(fixture_dir)
	fixture_path = fixture_dir.path_join("preferences.json")
	config = load("res://src/globals.gd").new()
	# No scene-tree entry: avoid _ready loading real preferences.
	defaults()
	var initial = snapshot()
	config.load_config(fixture_path)
	check(snapshot() == initial, "Missing file must preserve defaults")
	check(config.save_config(fixture_path) == OK, "First save must succeed")
	check(FileAccess.file_exists(fixture_path), "First save must create the file")
	check(JSON.parse_string(FileAccess.get_file_as_string(fixture_path)) is Dictionary,
		"Saved file must be a JSON object")

	config.gyro_type = 2
	config.note_speed = 7.25
	config.offset = -123
	config.render_timing = 6.5
	config.render_pool = 256
	var expected = snapshot()
	check(config.save_config(fixture_path) == OK, "Overwriting preferences must succeed")
	defaults()
	config.load_config(fixture_path)
	check(snapshot() == expected, "All settings must survive save/load")

	for content in ["{broken", "[]", "null", "42", "\"text\"", "{}"]:
		defaults()
		write_fixture(content)
		config.load_config(fixture_path)
		check(snapshot() == initial, "Invalid or empty config must preserve defaults: " + content)

	defaults()
	write_fixture('{"note_speed": 5.5, "unknown_future_setting": true}')
	config.load_config(fixture_path)
	check(snapshot() == [0, 5.5, 0, 4.0, 128], "Partial config must load valid fields")

	for content in [
		'{"gyro_type": 1.5, "note_speed": "fast", "offset": false, "render_timing": null, "render_pool": []}',
		'{"gyro_type": 3, "note_speed": 9, "offset": -2001, "render_timing": 0, "render_pool": 0}',
		'{"gyro_type": -1, "note_speed": 0, "offset": 0.5, "render_timing": -1, "render_pool": 1.5}'
	]:
		defaults()
		write_fixture(content)
		config.load_config(fixture_path)
		check(snapshot() == initial, "Invalid field values must preserve defaults: " + content)

	defaults()
	write_fixture('{"gyro_type": "bad", "note_speed": 8, "offset": 2000, "render_timing": 0.5, "render_pool": 1}')
	config.load_config(fixture_path)
	check(snapshot() == [0, 8.0, 2000, 0.5, 1], "One invalid field must not block valid fields")
	check(not config._valid_number(INF, 0, INF), "Infinity must be rejected")
	check(not config._valid_number(NAN, 0, INF), "NaN must be rejected")
	check(config.save_config(fixture_dir.path_join("missing/preferences.json")) != OK,
		"Unavailable destination must return an error without crashing")

	config.free()
	DirAccess.remove_absolute(fixture_path)
	DirAccess.remove_absolute(fixture_dir)
	print("Preferences tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)
