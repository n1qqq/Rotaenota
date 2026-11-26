extends Node

const MotionMath = preload("res://src/motion_math.gd")
const GRAVITY_CORRECTION_SECONDS := 2.0
const ACCEL_FILTER_SECONDS := 0.04
const DERIVATIVE_FILTER_SECONDS := 0.04

var mode: int = Globals.GYRO.HANDHOLD
var poll_sensors := true
var is_calibrated := false
var angle_valid := false
var acceleration_valid := false
var output_angle_rad := 0.0
var angular_velocity_rad_s := 0.0
var angular_acceleration_rad_s2 := 0.0
var gyro_bias_rad_s := Vector3.ZERO
# Maps current device coordinates into the device frame at calibration completion.
var device_to_reference := Quaternion.IDENTITY
var _reference_gravity := Vector3.DOWN
var _estimated_gravity := Vector3.DOWN
var _desktop_normal := Vector3.BACK
var _desktop_right := Vector3.RIGHT
var _previous_angle := 0.0
var _previous_velocity := 0.0
var _have_angle := false
var _have_velocity := false


func configure(input_mode: int, gravity: Vector3, bias: Vector3) -> bool:
	mode = input_mode
	is_calibrated = false
	invalidate_sample()
	if mode not in [Globals.GYRO.HANDHOLD, Globals.GYRO.DESKTOP, Globals.GYRO.ACCEL]:
		return false
	if not MotionMath.supported_pose(mode, gravity) or not bias.is_finite():
		return false
	_reference_gravity = gravity.normalized()
	_estimated_gravity = _reference_gravity
	gyro_bias_rad_s = bias
	device_to_reference = Quaternion.IDENTITY
	# Horizontal-plane normal faces the initial screen front, including face-down use.
	_desktop_normal = _reference_gravity * signf(_reference_gravity.z)
	_desktop_right = Vector3.RIGHT.slide(_reference_gravity).normalized()
	output_angle_rad = 0.0 if mode == Globals.GYRO.DESKTOP else MotionMath.handhold_angle(gravity)
	is_calibrated = true
	angle_valid = true
	return true


func _physics_process(delta: float) -> void:
	if poll_sensors and is_calibrated:
		feed_sample(Input.get_gyroscope(), MotionMath.read_gravity_sample(mode), delta)


func invalidate_sample() -> void:
	angle_valid = false
	acceleration_valid = false
	angular_velocity_rad_s = 0.0
	angular_acceleration_rad_s2 = 0.0
	_have_angle = false
	_have_velocity = false


func feed_sample(gyro: Vector3, gravity: Vector3, delta: float) -> void:
	if not is_calibrated:
		return
	if not is_finite(delta) or delta <= 0.0 or delta > MotionMath.MAX_SAMPLE_INTERVAL:
		# Lost samples cannot be reconstructed, especially for DESKTOP heading.
		is_calibrated = false
		invalidate_sample()
		return
	if not MotionMath.valid_gravity(gravity) or not MotionMath.supported_pose(mode, gravity):
		# Do not retain an untracked heading across unsupported poses or missing data.
		is_calibrated = false
		invalidate_sample()
		return
	var rate := 0.0
	if mode == Globals.GYRO.ACCEL:
		_estimated_gravity = _estimated_gravity.lerp(gravity.normalized(),
			1.0 - exp(-delta / ACCEL_FILTER_SECONDS)).normalized()
		if not MotionMath.supported_pose(mode, _estimated_gravity):
			invalidate_sample()
			return
		output_angle_rad = MotionMath.handhold_angle(_estimated_gravity)
		if _have_angle:
			rate = wrapf(output_angle_rad - _previous_angle, -PI, PI) / delta
	else:
		if not gyro.is_finite():
			is_calibrated = false
			invalidate_sample()
			return
		var omega := gyro - gyro_bias_rad_s
		var speed := omega.length()
		if speed > 0.0:
			device_to_reference = (device_to_reference * Quaternion(omega / speed, speed * delta)).normalized()
		_estimated_gravity = device_to_reference.inverse() * _reference_gravity
		if mode == Globals.GYRO.HANDHOLD:
			# Correct tilt slowly; the quaternion still integrates all three gyro axes.
			var correction := Quaternion(gravity.normalized(), _estimated_gravity)
			device_to_reference = (device_to_reference * Quaternion.IDENTITY.slerp(
				correction, 1.0 - exp(-delta / GRAVITY_CORRECTION_SECONDS))).normalized()
			_estimated_gravity = device_to_reference.inverse() * _reference_gravity
			if not MotionMath.supported_pose(mode, _estimated_gravity):
				invalidate_sample()
				return
			output_angle_rad = MotionMath.handhold_angle(_estimated_gravity)
			var g := _estimated_gravity
			rate = omega.z - g.z * (omega.x * g.x + omega.y * g.y) / (g.x * g.x + g.y * g.y)
		else:
			if not MotionMath.supported_pose(mode, _estimated_gravity):
				invalidate_sample()
				return
			var right := (device_to_reference * Vector3.RIGHT).slide(_desktop_normal)
			var right_velocity := (device_to_reference * omega.cross(Vector3.RIGHT)).slide(_desktop_normal)
			output_angle_rad = atan2(_desktop_normal.dot(_desktop_right.cross(right)), _desktop_right.dot(right))
			rate = _desktop_normal.dot(right.cross(right_velocity)) / right.length_squared()
	angle_valid = true
	output_angle_rad = wrapf(output_angle_rad, -PI, PI)
	angular_velocity_rad_s = rate
	acceleration_valid = _have_velocity
	if _have_velocity:
		var acceleration := (rate - _previous_velocity) / delta
		angular_acceleration_rad_s2 = lerpf(angular_acceleration_rad_s2, acceleration,
			1.0 - exp(-delta / DERIVATIVE_FILTER_SECONDS))
	else:
		angular_acceleration_rad_s2 = 0.0
	_previous_velocity = rate
	_have_velocity = mode != Globals.GYRO.ACCEL or _have_angle
	_previous_angle = output_angle_rad
	_have_angle = true
