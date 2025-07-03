extends Node

# 配置参数
@export var smooth_factor = 0.2
@export var calibration_samples = 30

# 运行时变量
var current_pitch = 0.0
var smoothed_pitch = 0.0
var calibration_offset = 0.0
var is_calibrating = false
var calibration_data = []

func _ready():
	start_calibration()

func _process(delta):
	
	var raw_pitch = calculate_raw_pitch()
	
	if is_calibrating:
		handle_calibration(raw_pitch)
	else:
		# 应用平滑滤波
		smoothed_pitch = lerp(smoothed_pitch, raw_pitch - calibration_offset, smooth_factor)
		current_pitch = smoothed_pitch
		
		# 限制在±π/2范围内
		current_pitch = clamp(current_pitch, -PI/2, PI/2)

func calculate_raw_pitch() -> float:
	var accel = Input.get_accelerometer()
	
	# 计算俯仰角 (横置设备时的上下倾斜)
	# 使用atan2(y, z)计算绕x轴的旋转
	return atan2(accel.y, accel.z)

func start_calibration():
	is_calibrating = true
	calibration_data = []
	calibration_offset = 0.0

func handle_calibration(raw_pitch):
	calibration_data.append(raw_pitch)
	if calibration_data.size() >= calibration_samples:
		finish_calibration()

func finish_calibration():
	var sum = 0.0
	for sample in calibration_data:
		sum += sample
	calibration_offset = sum / calibration_data.size()
	is_calibrating = false

func calibrating():
	return is_calibrating

func get_pitch_angle() -> float:
	return current_pitch

func is_device_flat() -> bool:
	return abs(current_pitch) < deg_to_rad(5)  # 5度以内视为水平
