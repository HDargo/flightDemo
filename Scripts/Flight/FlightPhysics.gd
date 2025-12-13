extends Node

class_name FlightPhysics

## Static utility class for flight physics calculations
## Shared by Aircraft and potentially other flying entities

## Calculate target speed based on throttle and performance factors
static func calculate_target_speed(
	throttle: float,
	min_speed: float,
	max_speed: float,
	engine_factor: float
) -> float:
	return lerp(min_speed, max_speed, throttle) * engine_factor

## Calculate drag force
static func calculate_drag(
	current_speed: float,
	drag_factor: float,
	delta: float
) -> float:
	var drag = drag_factor * current_speed * current_speed
	return drag * delta

## Calculate lift force vector
## Returns lift velocity in m/s
static func calculate_lift(
	current_speed: float,
	lift_factor: float,
	lift_multiplier: float,
	up_vector: Vector3
) -> Vector3:
	# Lift velocity proportional to speed squared (realistic aerodynamics)
	# Returns m/s which will be multiplied by delta in caller
	var lift_magnitude = lift_factor * lift_multiplier * current_speed * current_speed
	return up_vector * lift_magnitude

## Apply pitch rotation to basis
static func apply_pitch_rotation(
	basis: Basis,
	pitch_input: float,
	pitch_speed: float,
	delta: float
) -> Basis:
	var pitch_angle = pitch_input * pitch_speed * delta
	return basis.rotated(basis.x, pitch_angle)

## Apply roll rotation to basis
static func apply_roll_rotation(
	basis: Basis,
	roll_input: float,
	roll_speed: float,
	delta: float
) -> Basis:
	var roll_angle = roll_input * roll_speed * delta
	return basis.rotated(basis.z, -roll_angle)

## Apply yaw rotation to basis
static func apply_yaw_rotation(
	basis: Basis,
	yaw_input: float,
	yaw_speed: float,
	delta: float
) -> Basis:
	var yaw_angle = yaw_input * yaw_speed * delta
	return basis.rotated(basis.y, yaw_angle)

## Calculate crash rotation with increasing chaos
static func calculate_crash_rotation(
	basis: Basis,
	spin_factor: float,
	crash_timer: float,
	pitch_speed: float,
	roll_speed: float,
	delta: float
) -> Basis:
	# Spin intensity ramps up over time
	var spin_intensity = min(crash_timer * 0.3, 1.2)
	
	# Crash rotation values
	var crash_roll = spin_factor * spin_intensity * 4.0
	var crash_pitch = -spin_intensity * 1.5
	
	# Apply rotations
	var pitch_angle = crash_pitch * pitch_speed * delta
	var roll_angle = crash_roll * roll_speed * delta
	var yaw_chaos = sin(crash_timer * 3.0) * spin_intensity * 0.5
	
	var new_basis = basis.rotated(basis.x, pitch_angle)
	new_basis = new_basis.rotated(new_basis.z, -roll_angle)
	new_basis = new_basis.rotated(new_basis.y, yaw_chaos * delta)
	
	return new_basis.orthonormalized()

## Calculate horizontal velocity for crash state
static func calculate_crash_horizontal_velocity(
	forward: Vector3,
	current_speed: float
) -> Vector3:
	return Vector3(forward.x, 0, forward.z).normalized() * current_speed

## Check if landing conditions are met
static func check_landing_conditions(
	current_speed: float,
	up_vector: Vector3,
	speed_threshold: float = 20.0,
	angle_threshold: float = 0.9
) -> bool:
	var dot = up_vector.dot(Vector3.UP)
	return current_speed < speed_threshold and dot > angle_threshold

## Calculate angle of attack (simplified)
static func calculate_angle_of_attack(
	velocity: Vector3,
	forward: Vector3
) -> float:
	if velocity.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(acos(velocity.normalized().dot(forward)))

## Calculate stall factor based on angle of attack
static func calculate_stall_factor(angle_of_attack: float) -> float:
	var critical_aoa = 15.0  # Degrees
	if angle_of_attack > critical_aoa:
		var excess = angle_of_attack - critical_aoa
		return max(0.0, 1.0 - (excess / 30.0))  # Gradual stall
	return 1.0

## Calculate turn radius at current speed
static func calculate_turn_radius(
	current_speed: float,
	bank_angle: float
) -> float:
	if abs(bank_angle) < 0.01:
		return INF
	var g = 9.8
	return (current_speed * current_speed) / (g * tan(bank_angle))

## Calculate G-force from turn rate
static func calculate_g_force(
	current_speed: float,
	turn_radius: float
) -> float:
	if turn_radius == INF or turn_radius < 0.01:
		return 1.0
	var g = 9.8
	var centripetal = (current_speed * current_speed) / turn_radius
	return 1.0 + (centripetal / g)

## Interpolate smoothly between current and target value
static func smooth_approach(
	current: float,
	target: float,
	rate: float,
	delta: float
) -> float:
	return move_toward(current, target, rate * delta)
