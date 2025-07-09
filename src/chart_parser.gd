class_name ChartParser


static func parse_chart(text: String) -> Dictionary:
	var chart = {
		"metadata": [],
		"notes": [],
		"lines": []
	}
	var lines = text.split("\n")
	for line in lines:
		# Remove Comments
		line = _preprocess_line(line)
		if line.is_empty():
			continue
		# Separate: ':'
		var parts = line.split(":", false, 1)
		if parts.size() != 2:
			push_warning("Unknown Format: " + line)
			continue
		var command_part = parts[0].strip_edges()
		var value_part = parts[1].strip_edges()
		# Separate: '|'
		var commands = command_part.split("|", false)
		commands = _clean_commands(commands)
		# Commands Details
		match commands[0]:
			"m", "meta":
				_parse_meta(chart, commands.slice(1), value_part)
			"n", "note":
				_parse_note(chart, commands.slice(1), value_part)
			_:
				push_warning("Unknown Command: " + commands[0])
	return chart

static func _preprocess_line(line: String) -> String:
	var comment_start = line.find("//")
	if comment_start == -1:
		comment_start = line.find("#")
	# Keep the part before the comment signature
	if comment_start != -1:
		line = line.substr(0, comment_start)
	return line.strip_edges()

static func _clean_commands(commands: Array) -> Array:
	var cleaned = []
	for cmd in commands:
		cmd = cmd.strip_edges()
		if not cmd.is_empty():
			cleaned.append(cmd)
	return cleaned

static func _parse_meta(chart: Dictionary, commands: Array, value: String) -> void:
	if commands.is_empty():
		push_warning("Empty metadata statement.")
		return
	commands = _clean_commands(commands)
	match commands[0]:
		"b", "bpm":
			_parse_bpm(chart, value)
		"l", "line":
			_parse_line(chart, commands.slice(1), value)

static func _parse_bpm(chart: Dictionary, value: String) -> void:
	chart.metadata.append({ bpm = _parse_values(value) })

static func _parse_line(chart: Dictionary, commands: Array, value: String):
	var line = {
		"type" = commands[0] if not commands.is_empty() else "default",
		"values" = _parse_values(value)
	}
	chart.metadata.append(line)

static func _parse_note(chart: Dictionary, commands: Array, value: String):
	if commands.is_empty():
		push_warning("Improper format: lacking note type.")
		return
	var note = {
		type = commands[0],
		subtype = commands[1] if commands.size() > 1 else "",
		params = _parse_values(value),
	}
	if note.type in _rotate:
		if note.subtype in _rotate_red:
			note.direction = "clockwise"
		elif note.subtype in _rotate_blue:
			note.direction = "counterclockwise"
	if note.type in _slide:
		if note.subtype in _slide_large:
			note.style = "large"
		elif note.subtype in _slide_small:
			note.style = "small"
	chart.notes.append(note)

static func _parse_values(value_str: String) -> Array:
	var values = []
	for part in value_str.split("|", false):
		part = part.strip_edges()
		if part.is_empty():
			continue
		if part.is_valid_int():
			values.append(part.to_int())
		elif part.is_valid_float():
			values.append(part.to_float())
		else:
			values.append(part)
	return values

const _rotate = 		["r", "rotate"]
const _rotate_red = 	["c", "cw", "clockwise", "r", "red"]
const _rotate_blue = 	["cc", "ccw", "counterclockwise", "b", "blue"]
const _slide = 			["s", "slide", "d", "drag"]
const _slide_small = 	["s", "small", "l", "little"]
const _slide_large = 	["b", "big", "L", "Large"]
