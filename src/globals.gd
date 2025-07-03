extends Node

func _ready() -> void:
	pass
func _process(delta: float) -> void:
	pass

enum GYRO { HANDHOLD, DESKTOP, ACCEL }

var gyro_type := GYRO.HANDHOLD		## HANDHOLD, DESKTOP, or ACCEL
var note_speed := 4

func get_next_angle(prev: Vector3, delta: Vector3) -> Vector3:
	# use .z to get the angle
	match gyro_type:
		GYRO.HANDHOLD, GYRO.DESKTOP:
			return prev + delta
		GYRO.ACCEL:
			return prev + delta / 3
	return Vector3.ZERO
