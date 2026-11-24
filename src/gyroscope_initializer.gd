extends Node

const ADJUSTMENT_DURATION = 2.
const GRAVITY_SMOOTHING_FACTOR = 0.1
const MIN_GRAVITY_MAGNITUDE = 8.0  		## Unit: m/s²

@export var gravity_vector: Vector3 = Vector3.ZERO
@export var is_calibrating: bool = false
var _calibration_start_time: float = 0.0

func _ready():
	start_calibration()

func start_calibration():
	is_calibrating = true
	_calibration_start_time = Time.get_ticks_msec() / 1000.0
	gravity_vector = get_parent().gravity_direction
	print("Starting gravity calibration...")

func _process(delta: float):
	var raw_accel = Input.get_accelerometer()
	
	_update_gravity_estimate(raw_accel, delta)
	
	if is_calibrating:
		if _check_calibration_complete():
			_finish_calibration()


func _update_gravity_estimate(raw_accel: Vector3, delta: float):
	if raw_accel.length() < MIN_GRAVITY_MAGNITUDE:
		return
	
	# Smoothing factor
	var smoothing = clamp(GRAVITY_SMOOTHING_FACTOR * delta * 60.0, 0.01, 0.9)
	
	# 更新重力向量（使用低通滤波）
	# 注意：加速度计数据是重力方向的反方向
	#      所以我们需要取反来获得真实重力方向
	var current_gravity = -raw_accel
	gravity_vector = gravity_vector.lerp(current_gravity, smoothing).normalized()

func _check_calibration_complete() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _calibration_start_time > ADJUSTMENT_DURATION:
		return true
	return false

func _finish_calibration():
	if gravity_vector.length() < 0.1:
		push_warning("Invalid gravity vector after calibration")
		gravity_vector = Vector3.DOWN  # default
	
	is_calibrating = false
	print("Gravity calibration complete. Gravity direction: ", gravity_vector)
