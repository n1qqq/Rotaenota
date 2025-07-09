extends Node

# 导出的竖直向上方向（水平面的法向量）
@export var up_direction: Vector3 = Vector3.UP

# 传感器处理参数
const GRAVITY_SMOOTHING_FACTOR := 0.1
const MIN_GRAVITY_MAGNITUDE := 8.0  	# Unit: m/s²

# 内部状态
var _gravity_vector: Vector3 = Vector3.ZERO
var _is_calibrating: bool = true
var _calibration_start_time: float = 0.0

func _ready():
	start_calibration()

func start_calibration():
	_is_calibrating = true
	_calibration_start_time = Time.get_ticks_msec() / 1000.0
	_gravity_vector = Vector3.DOWN  # 初始化为向下方向
	print("Starting gravity calibration...")

func _process(delta: float):
	# 获取原始加速度计数据
	var raw_accel := Input.get_accelerometer()
	
	# 更新重力估计
	_update_gravity_estimate(raw_accel, delta)
	
	# 如果正在校准，检查是否完成
	if _is_calibrating:
		if _check_calibration_complete():
			_finish_calibration()
	
	# 实时更新向上方向（即使在校准过程中）
	up_direction = -_gravity_vector.normalized()

func _update_gravity_estimate(raw_accel: Vector3, delta: float):
	# 有效重力检测 - 排除明显非重力情况
	if raw_accel.length() < MIN_GRAVITY_MAGNITUDE:
		return
	
	# 计算平滑因子 (基于时间delta)
	var smoothing = clamp(GRAVITY_SMOOTHING_FACTOR * delta * 60.0, 0.01, 0.9)
	
	# 更新重力向量（使用低通滤波）
	# 注意：加速度计数据是重力方向的反方向
	# 所以我们需要取反来获得真实重力方向
	var current_gravity = -raw_accel
	
	_gravity_vector = _gravity_vector.lerp(
		current_gravity, 
		smoothing
	)

func _check_calibration_complete() -> bool:
	# 1. 超时检查 (3秒)
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _calibration_start_time > 3.0:
		return true
	
	# 2. 稳定性检查 - 简化为固定时间
	return true  # 实际应用中可添加更复杂的运动检测

func _finish_calibration():
	# 确保我们有有效的重力向量
	if _gravity_vector.length() < 0.1:
		push_warning("Invalid gravity vector after calibration")
		_gravity_vector = Vector3.DOWN  # 默认值
	
	# 计算最终的向上方向
	up_direction = -_gravity_vector.normalized()
	
	_is_calibrating = false
	print("Gravity calibration complete. Up direction: ", up_direction)
	emit_signal("calibration_finished")

# 获取当前倾斜角度（与竖直方向的夹角，弧度）
func get_tilt_angle() -> float:
	return acos(clamp(up_direction.dot(Vector3.UP), -1.0, 1.0))

# 获取当前倾斜角度（度）
func get_tilt_angle_degrees() -> float:
	return rad_to_deg(get_tilt_angle())

# 判断设备是否大致水平（倾斜角度小于阈值）
func is_device_level(threshold_degrees: float = 5.0) -> bool:
	return get_tilt_angle_degrees() < threshold_degrees
