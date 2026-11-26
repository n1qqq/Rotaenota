extends Node

@export var gravity_direction: Vector3 = Vector3.DOWN

@export var orientation_correction_deg: int = 0  # 当前分支输出 0 或 180 度
@export var z_angle_rad: float = 0.0  # Z 轴积分角，弧度，范围 [-PI, PI)，不保留圈数
@export var output_angle_rad: float = 0.0  # 输出角，弧度；现有方向修正的单位换算待修复

const Z_DRIFT_THRESHOLD = deg_to_rad(3.0)  # 3度漂移阈值
const RECALIBRATION_TIME = 180.0  # 3分钟（秒）
const Z_AXIS = Vector3(0, 0, 1)  # 设备Z轴（屏幕向外）
const Y_AXIS_NEGATIVE = Vector3(0, -1, 0)  # 设备Y轴（屏幕向下）

var last_calibration_time: float = 0.0
var initial_angle_offset_rad: float = 0.0  # 初始重力投影角偏置，弧度；不是角速度零偏

# 仅由 Z 轴积分得到的旋转，不代表完整三轴姿态
var z_rotation_quat: Quaternion = Quaternion.IDENTITY

func _ready():
	# 初始校准
	gravity_direction = get_parent().gravity_direction
	initial_angle_offset_rad = atan2(gravity_direction.y, gravity_direction.x) - atan2(Y_AXIS_NEGATIVE.y, Y_AXIS_NEGATIVE.x)
	last_calibration_time = Time.get_ticks_msec() / 1000.0

func _process(delta):
	# 1. 获取传感器数据
	var gyro = Input.get_gyroscope()
	var accel = Input.get_accelerometer()
	
	# 2. 更新旋转状态
	_update_rotation_state(gyro, delta)
	
	# 3. 应用0/180°逻辑
	_apply_orientation_logic()
	
	# 4. 检查是否需要重新校准
	_check_recalibration(accel)
	
	# 5. 计算最终2D旋转
	output_angle_rad = initial_angle_offset_rad + z_angle_rad + orientation_correction_deg * PI

func is_almost_equal(a: float, b: float, epsilon: float = 1e-6) -> bool:
	return abs(a - b) < epsilon

# 初始校准/重新校准
func recalibrate(accel: Vector3):
	if !is_almost_equal(accel.length_squared(), 96.04, 5):
		return
	z_rotation_quat = Quaternion.IDENTITY
	z_angle_rad = 0.0
	gravity_direction = -accel.normalized()
	initial_angle_offset_rad = atan2(gravity_direction.y, gravity_direction.x) - atan2(Y_AXIS_NEGATIVE.y, Y_AXIS_NEGATIVE.x)
	last_calibration_time = Time.get_ticks_msec() / 1000.0
	print("Recalibrated at time: ", last_calibration_time)

# 更新旋转状态
func _update_rotation_state(gyro: Vector3, delta: float):
	# 积分Z轴旋转
	var rotation_quat = Quaternion(Z_AXIS, gyro.z * delta)
	z_rotation_quat = (z_rotation_quat * rotation_quat).normalized()
	
	# 更新 Z 轴积分角
	z_angle_rad += gyro.z * delta
	
	# 角度按一圈取模，不保留累计圈数
	z_angle_rad = wrapf(z_angle_rad, -PI, PI)

# 应用0/180°逻辑
func _apply_orientation_logic():
	# 3. 计算当前重力角度（相对于初始重力）
	var current_angle = initial_angle_offset_rad + z_angle_rad
	
	# 4. 确定单位圆半区
	var is_right_half = cos(current_angle) > 0
	
	# 5. 获取设备Y轴在世界坐标系中的方向
	var device_y_world = z_rotation_quat * Vector3(0, 1, 0)
	var y_dot_g = device_y_world.dot(gravity_direction)
	
	# 6. 应用新规则
	if y_dot_g > 0:  # 设备Y轴朝上
		if is_right_half:
			# 指向右半圆且Y朝上 -> 返回0
			orientation_correction_deg = 0
		else:
			# 指向左半圆且Y朝上 -> 返回180
			orientation_correction_deg = 180
	elif y_dot_g < 0:  # 设备Y轴朝下
		if is_right_half:
			# 指向右半圆且Y朝下 -> 返回180
			orientation_correction_deg = 180
		else:
			# 指向左半圆且Y朝下 -> 返回0
			orientation_correction_deg = 0
	# 当y_dot_g≈0时保持原值

# 检查是否需要重新校准
func _check_recalibration(accel: Vector3):
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# 1. 检查时间条件（3分钟）
	if current_time - last_calibration_time < RECALIBRATION_TIME:
		return
	
	# 3. 如果，重新校准
	if false:
		recalibrate(accel)

# 手动重新校准接口
func force_recalibration():
	print("Forced recalibration")
	recalibrate(Input.get_accelerometer())
