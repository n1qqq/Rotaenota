extends RefCounted

# Device axes: X right, Y up, Z out of the screen. Positive angles are CCW.
const GRAVITY := 9.80665
const GRAVITY_TOLERANCE := 1.5
const MIN_PROJECTION := 0.2
const MAX_SAMPLE_INTERVAL := 0.1


static func valid_gravity(sample: Vector3) -> bool:
	return sample.is_finite() and absf(sample.length() - GRAVITY) <= GRAVITY_TOLERANCE


static func supported_pose(mode: int, gravity: Vector3) -> bool:
	if not gravity.is_finite() or gravity.is_zero_approx():
		return false
	var direction := gravity.normalized()
	if mode == Globals.GYRO.DESKTOP:
		return absf(direction.z) >= MIN_PROJECTION
	return Vector2(direction.x, direction.y).length() >= MIN_PROJECTION


static func handhold_angle(gravity: Vector3) -> float:
	return wrapf(atan2(-gravity.x, -gravity.y), -PI, PI)


static func catch_error(note_angle: float, device_angle: float) -> float:
	return absf(wrapf(note_angle - device_angle, -PI / 2.0, PI / 2.0))


static func read_gravity_sample(mode: int) -> Vector3:
	# Godot supplies screen-oriented sensor vectors. Do not rotate again.
	# ACCEL intentionally uses only the accelerometer, including its motion noise.
	if mode != Globals.GYRO.ACCEL:
		var gravity := Input.get_gravity()
		if valid_gravity(gravity):
			return gravity
	return Input.get_accelerometer()
