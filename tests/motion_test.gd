extends SceneTree

# godot --headless --path . --script tests/motion_test.gd
var Agent: GDScript
var Initializer: GDScript
var MotionMath: GDScript
enum Mode { HANDHOLD, DESKTOP, ACCEL }
const DT := 1.0 / 120.0
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func near_angle(actual: float, expected: float, message: String, tolerance := 0.002) -> void:
	check(absf(wrapf(actual - expected, -PI, PI)) < tolerance,
		"%s: actual=%f expected=%f" % [message, actual, expected])


func make_agent(mode: int, gravity: Vector3, bias := Vector3.ZERO) -> Node:
	var agent = Agent.new()
	agent.poll_sensors = false
	check(agent.configure(mode, gravity, bias), "Supported pose configures")
	return agent


func test_calibration() -> void:
	var init = Initializer.new()
	init.start_calibration()
	for i in range(1000):
		init.feed_sample(Vector3.ZERO, Vector3.ZERO, DT)
	check(not init.is_calibrating and init.gravity_direction == Vector3.ZERO,
		"No sensor times out without manufacturing a calibration")
	init.start_calibration()
	for i in range(180):
		init.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, DT)
	init.feed_sample(Vector3.ONE, Vector3.DOWN * MotionMath.GRAVITY, DT)
	for i in range(180):
		init.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, DT)
	check(init.is_calibrating, "Movement restarts the full stationary window")
	init.start_calibration()
	var bias := Vector3(0.01, -0.02, 0.03)
	for i in range(250):
		init.feed_sample(bias, Vector3.DOWN * MotionMath.GRAVITY, DT)
	check(not init.is_calibrating, "Two stationary seconds complete calibration")
	check(init.gyro_bias_rad_s.distance_to(bias) < 0.0001, "All three gyro biases are averaged")
	check(init.gravity_direction.distance_to(Vector3.DOWN) < 0.0001, "Gravity sign is preserved")
	init.mode = Mode.DESKTOP
	init.start_calibration()
	for i in range(250):
		init.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, DT)
	check(init.is_calibrating, "DESKTOP rejects wall pose during calibration")
	init.free()


func test_modes() -> void:
	for mode in [Mode.HANDHOLD, Mode.ACCEL]:
		for angle in [-2.5, 0.0, 0.7, 2.8]:
			for tilt in [-0.8, 0.0, 0.8]:
				var pose := Quaternion(Vector3.RIGHT, tilt) * Quaternion(Vector3.BACK, angle)
				var gravity := pose.inverse() * Vector3.DOWN
				var agent = make_agent(mode, gravity)
				near_angle(agent.output_angle_rad, angle, "Fixed zero independent of calibration roll and tilt")
				agent.feed_sample(Vector3.ZERO, gravity * MotionMath.GRAVITY, DT)
				near_angle(agent.output_angle_rad, angle, "Stationary angle remains fixed")
				agent.free()
		var unsupported = Agent.new()
		check(not unsupported.configure(mode, Vector3.FORWARD, Vector3.ZERO), "Horizontal handhold/accel rejected")
		unsupported.free()
	var desktop = make_agent(Mode.DESKTOP, Vector3.FORWARD)
	near_angle(desktop.output_angle_rad, 0.0, "DESKTOP starts at calibration heading")
	for i in range(120):
		desktop.feed_sample(Vector3(0, 0, PI / 2), Vector3.FORWARD * MotionMath.GRAVITY, DT)
	near_angle(desktop.output_angle_rad, PI / 2, "DESKTOP quarter turn")
	check(desktop.configure(Mode.DESKTOP, Vector3.FORWARD, Vector3.ZERO), "DESKTOP recalibrates")
	near_angle(desktop.output_angle_rad, 0.0, "DESKTOP new heading becomes zero")
	desktop.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, DT)
	check(not desktop.is_calibrated and not desktop.angle_valid, "DESKTOP wall pose invalidates calibration")
	desktop.free()


func test_three_axes() -> void:
	# Change pitch at a fixed roll: omega has X and Y components, no Z component.
	var roll := 0.7
	var initial := Quaternion(Vector3.BACK, roll)
	var agent = make_agent(Mode.HANDHOLD, initial.inverse() * Vector3.DOWN)
	var omega := initial.inverse() * Vector3.RIGHT * 0.6
	for i in range(120):
		var pose := Quaternion(Vector3.RIGHT, (i + 1) * DT * 0.6) * initial
		agent.feed_sample(omega, (pose.inverse() * Vector3.DOWN) * MotionMath.GRAVITY, DT)
	near_angle(agent.output_angle_rad, roll, "Changing tilt preserves roll")
	check(absf(agent.angular_velocity_rad_s) < 0.002, "Tilt alone is not roll velocity")
	check(agent.device_to_reference.get_angle() > 0.5, "X/Y angular velocity updates full orientation")
	agent.free()
	# DESKTOP can tilt away from the table without mistaking pitch for heading.
	agent = make_agent(Mode.DESKTOP, Vector3.FORWARD)
	for i in range(120):
		var pose := Quaternion(Vector3.UP, (i + 1) * DT * 0.6)
		agent.feed_sample(Vector3.UP * 0.6, pose.inverse() * Vector3.FORWARD * MotionMath.GRAVITY, DT)
	near_angle(agent.output_angle_rad, 0.0, "DESKTOP pitch preserves heading")
	check(absf(agent.angular_velocity_rad_s) < 0.002, "DESKTOP pitch is not Rotate")
	agent.free()
	# Turning around world vertical is irrelevant to HANDHOLD, even with initial tilt.
	initial = Quaternion(Vector3.RIGHT, 0.6) * Quaternion(Vector3.BACK, 0.4)
	agent = make_agent(Mode.HANDHOLD, initial.inverse() * Vector3.DOWN)
	omega = initial.inverse() * Vector3.UP * 0.8
	for i in range(120):
		agent.feed_sample(omega, (initial.inverse() * Vector3.DOWN) * MotionMath.GRAVITY, DT)
	near_angle(agent.output_angle_rad, 0.4, "World heading does not change HANDHOLD")
	check(absf(agent.angular_velocity_rad_s) < 0.002, "World yaw is not a Rotate input")
	agent.free()


func test_rotation() -> void:
	for fps in [30, 60, 120]:
		var dt: float = 1.0 / fps
		for mode in [Mode.HANDHOLD, Mode.DESKTOP, Mode.ACCEL]:
			var gravity := Vector3.FORWARD if mode == Mode.DESKTOP else Vector3.DOWN
			var agent = make_agent(mode, gravity)
			for i in range(4 * fps):
				var angle: float = (i + 1) * dt * 2.0
				var sample := Quaternion(Vector3.BACK, angle).inverse() * gravity
				agent.feed_sample(Vector3(0, 0, 2), sample * MotionMath.GRAVITY, dt)
				if i > fps:
					check(absf(agent.angular_acceleration_rad_s2) < 0.01, "Constant speed and wrap do not create Rotate")
			# ACCEL's documented low-pass delay is allowed here.
			near_angle(agent.output_angle_rad, 8.0, "Frame-rate independent angle", 0.1 if mode == Mode.ACCEL else 0.002)
			agent.free()
	# Equal signed angular acceleration at different starting angles.
	for start in [-2.0, 0.0, 2.0]:
		var agent = make_agent(Mode.HANDHOLD, Quaternion(Vector3.BACK, start).inverse() * Vector3.DOWN)
		var angle: float = start
		for i in range(121):
			var rate := i * DT * 2.0
			angle += rate * DT
			agent.feed_sample(Vector3(0, 0, rate), Quaternion(Vector3.BACK, angle).inverse() * Vector3.DOWN * MotionMath.GRAVITY, DT)
		check(agent.acceleration_valid and absf(agent.angular_acceleration_rad_s2 - 2.0) < 0.01, "Acceleration independent of starting angle")
		for i in range(120):
			var rate := 2.0 - (i + 1) * DT
			angle += rate * DT
			agent.feed_sample(Vector3(0, 0, rate), Quaternion(Vector3.BACK, angle).inverse() * Vector3.DOWN * MotionMath.GRAVITY, DT)
		check(agent.angular_velocity_rad_s > 0 and absf(agent.angular_acceleration_rad_s2 + 1.0) < 0.01,
			"Slowing positive rotation produces negative acceleration")
		agent.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, 0.5)
		check(not agent.angle_valid and not agent.acceleration_valid and not agent.is_calibrated, "Long gap requires recalibration")
		agent.free()
	check(MotionMath.catch_error(0, 0) < 0.0001, "Right Catch at zero")
	check(MotionMath.catch_error(0, PI) < 0.0001, "Left Catch at half turn")
	check(absf(MotionMath.catch_error(0.3, 0.1) - MotionMath.catch_error(0.3, PI + 0.1)) < 0.0001,
		"Catch error is half-turn equivalent")
	var bias := Vector3(0.01, -0.02, 0.03)
	var agent = make_agent(Mode.HANDHOLD, Vector3.DOWN, bias)
	for i in range(120):
		agent.feed_sample(bias, Vector3.DOWN * MotionMath.GRAVITY, DT)
	near_angle(agent.output_angle_rad, 0.0, "Stationary gyro bias is subtracted")
	agent.free()
	for mode in [Mode.DESKTOP, Mode.ACCEL]:
		var gravity := Vector3.FORWARD if mode == Mode.DESKTOP else Vector3.DOWN
		agent = make_agent(mode, gravity)
		var angle := 0.0
		for i in range(241):
			var rate := -i * DT * 2.0
			angle += rate * DT
			agent.feed_sample(Vector3(0, 0, rate), Quaternion(Vector3.BACK, angle).inverse() * gravity * MotionMath.GRAVITY, DT)
		check(agent.acceleration_valid and absf(agent.angular_acceleration_rad_s2 + 2.0) < 0.05,
			"DESKTOP/ACCEL negative angular acceleration")
		agent.free()


func test_sensor_adapter() -> void:
	var old_gravity := Input.get_gravity()
	var old_accel := Input.get_accelerometer()
	Input.set_gravity(Vector3.DOWN * MotionMath.GRAVITY)
	Input.set_accelerometer(Vector3.LEFT * MotionMath.GRAVITY)
	check(MotionMath.read_gravity_sample(Mode.HANDHOLD) == Input.get_gravity(),
		"HANDHOLD prefers gravity without negation")
	check(MotionMath.read_gravity_sample(Mode.ACCEL) == Input.get_accelerometer(),
		"ACCEL uses accelerometer without negation")
	Input.set_gravity(Vector3.ZERO)
	check(MotionMath.read_gravity_sample(Mode.DESKTOP) == Input.get_accelerometer(),
		"Missing gravity sensor falls back to accelerometer")
	Input.set_gravity(old_gravity)
	Input.set_accelerometer(old_accel)


func complete_level_calibration(level: Node) -> void:
	var init = level.gyro_initializer
	init.poll_sensors = false
	for i in range(250):
		if not init.is_calibrating:
			break
		init.feed_sample(Vector3.ZERO, Vector3.DOWN * MotionMath.GRAVITY, DT)
	if is_instance_valid(level.gyro_agent):
		level.gyro_agent.poll_sensors = false


func test_lifecycle() -> void:
	var globals = root.get_node("Globals")
	var previous_pack: Dictionary = globals.current_level_info
	var previous_mode: int = globals.gyro_type
	globals.gyro_type = Mode.HANDHOLD
	globals.current_level_info = {"path": "res://demo/demo_0/", "config": JSON.parse_string(FileAccess.get_file_as_string("res://demo/demo_0/config.json"))}
	var level = load("res://scn/level.tscn").instantiate()
	root.add_child(level)
	check(is_instance_valid(level.gyro_initializer) and level.gyro_agent == null, "Level calibrates before constructing the agent")
	var initializer_ref: WeakRef = weakref(level.gyro_initializer)
	complete_level_calibration(level)
	check(level.motion_ready and level.gyro_agent.is_calibrated, "Real scene starts configured agent after success")
	check(level.gyro_initializer == null, "Initializer released after success")
	await process_frame
	check(initializer_ref.get_ref() == null, "Initializer actually freed")
	var agent_ref: WeakRef = weakref(level.gyro_agent)
	paused = true
	check(not level.motion_ready and level.gyro_agent == null, "Pause stops and releases sensor agent")
	paused = false
	await process_frame
	check(is_instance_valid(level.gyro_initializer), "Resume starts new calibration")
	level.gyro_initializer.poll_sensors = false
	check(agent_ref.get_ref() == null, "Old agent freed after pause")
	var init = level.gyro_initializer
	for i in range(1000):
		if not init.is_calibrating:
			break
		init.feed_sample(Vector3.ZERO, Vector3.ZERO, DT)
	check(not level.motion_ready and level.gyro_agent == null and level.gyro_initializer == null,
		"Failure never starts an agent")
	level.start_motion_calibration()
	complete_level_calibration(level)
	check(level.motion_ready, "Retry can complete calibration")
	level.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not level.motion_ready, "Focus loss stops sensors")
	paused = true
	level.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	check(level.gyro_initializer == null, "Focus return while paused does not start calibration")
	paused = false
	await process_frame
	check(is_instance_valid(level.gyro_initializer), "Unpausing after focus return calibrates")
	complete_level_calibration(level)
	agent_ref = weakref(level.gyro_agent)
	level.queue_free()
	await process_frame
	check(agent_ref.get_ref() == null, "Leaving scene frees sensor node")
	globals.current_level_info = previous_pack
	globals.gyro_type = previous_mode


func run() -> void:
	Agent = load("res://src/gyroscope_agent.gd")
	Initializer = load("res://src/gyroscope_initializer.gd")
	MotionMath = load("res://src/motion_math.gd")
	test_calibration()
	test_modes()
	test_three_axes()
	test_rotation()
	test_sensor_adapter()
	await test_lifecycle()
	print("Motion tests: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
