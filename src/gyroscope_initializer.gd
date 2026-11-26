extends Node

signal completed(gravity_direction: Vector3, gyro_bias_rad_s: Vector3)
signal failed(reason: String)

const MotionMath = preload("res://src/motion_math.gd")
const CALIBRATION_DURATION := 2.0
const CALIBRATION_TIMEOUT := 8.0
const MAX_STATIONARY_RATE := 0.08
const MAX_DIRECTION_CHANGE := deg_to_rad(2.0)

var mode: int = Globals.GYRO.HANDHOLD
var poll_sensors := true
var is_calibrating := false
var gravity_direction := Vector3.ZERO
var gyro_bias_rad_s := Vector3.ZERO
var _elapsed := 0.0
var _stable_time := 0.0
var _sample_count := 0
var _gravity_sum := Vector3.ZERO
var _gyro_sum := Vector3.ZERO
var _anchor_direction := Vector3.ZERO


func _ready() -> void:
	start_calibration()


func start_calibration() -> void:
	is_calibrating = true
	_elapsed = 0.0
	gravity_direction = Vector3.ZERO
	gyro_bias_rad_s = Vector3.ZERO
	_reset_samples()


func _physics_process(delta: float) -> void:
	if poll_sensors:
		feed_sample(Input.get_gyroscope(), MotionMath.read_gravity_sample(mode), delta)


func _reset_samples() -> void:
	_stable_time = 0.0
	_sample_count = 0
	_gravity_sum = Vector3.ZERO
	_gyro_sum = Vector3.ZERO
	_anchor_direction = Vector3.ZERO


func feed_sample(gyro: Vector3, gravity: Vector3, delta: float) -> void:
	if not is_calibrating or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= CALIBRATION_TIMEOUT:
		is_calibrating = false
		failed.emit("Calibration failed. Hold the device still in a supported pose, then retry.")
		return
	var valid := MotionMath.valid_gravity(gravity) and MotionMath.supported_pose(mode, gravity)
	valid = valid and delta <= MotionMath.MAX_SAMPLE_INTERVAL
	if mode != Globals.GYRO.ACCEL:
		valid = valid and gyro.is_finite() and gyro.length() <= MAX_STATIONARY_RATE
	if not valid:
		_reset_samples()
		return
	var direction := gravity.normalized()
	if _sample_count > 0 and direction.angle_to(_anchor_direction) > MAX_DIRECTION_CHANGE:
		_reset_samples()
	if _sample_count == 0:
		_anchor_direction = direction
	_stable_time += delta
	_sample_count += 1
	_gravity_sum += direction * delta
	if mode != Globals.GYRO.ACCEL:
		_gyro_sum += gyro * delta
	if _stable_time >= CALIBRATION_DURATION and _sample_count >= 30:
		gravity_direction = _gravity_sum.normalized()
		gyro_bias_rad_s = _gyro_sum / _stable_time
		is_calibrating = false
		completed.emit(gravity_direction, gyro_bias_rad_s)
