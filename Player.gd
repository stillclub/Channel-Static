extends Node3D

# --- exported variables ---
@export var rotation_smooth: float = 8.0
@export var forward_speed: float = 2.0
@export var max_forward_distance: float = 2.0
@export var idle_bob_amplitude: float = 0.05
@export var forward_bob_amplitude: float = 0.15
@export var bob_speed: float = 6.0
@export var stress_intensity: float = 0.01
@export var stress_speed: float = 3.0
@export var debug_prints: bool = false

# --- Mouse drift settings ---
@export var mouse_drift_strength: float = 0.0008
@export var max_drift_angle: float = 30.0
@export var horizontal_drift_range: float = 40.0
@export var drift_smoothing: float = 3.0  # slower = more drifty
@export var head_tilt_amount: float = 15.0
@export var tilt_smoothing: float = 6.0
@export var drift_return_speed: float = 1.5

# --- Front-facing threshold (degrees) ---
@export var face_threshold_deg: float = 8.0

# --- Movement variables ---
var target_rot_deg: float = 0.0
var pending_rot_deg: float = 0.0
var start_position: Vector3
var move_forward: bool = false
var returning: bool = false
var forward_progress: float = 0.0
var bob_timer: float = 0.0
var rotation_locked: bool = false

# --- Camera effects ---
var stress_offset: Vector3 = Vector3.ZERO
var stress_target: Vector3 = Vector3.ZERO

# --- Mouse drift system ---
var current_mouse_pos: Vector2 = Vector2.ZERO
var screen_center: Vector2 = Vector2.ZERO
var drift_x: float = 0.0
var drift_y: float = 0.0
var target_drift_x: float = 0.0
var target_drift_y: float = 0.0
var head_tilt: float = 0.0
var target_head_tilt: float = 0.0

@onready var cam: Camera3D = $Camera3D
var base_cam_origin: Vector3 = Vector3.ZERO
var base_cam_rot: Vector3 = Vector3.ZERO

# Tween reference for stress — explicitly typed to avoid inference error
var _stress_tween: Object = null  # will hold the tween instance when active

func _ready() -> void:
	target_rot_deg = rotation_degrees.y
	start_position = global_transform.origin
	
	# Keep mouse visible and free
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	screen_center = get_viewport().get_visible_rect().size / 2
	
	# cache camera base transforms (local)
	if cam:
		base_cam_origin = cam.transform.origin
		base_cam_rot = cam.rotation  # radians
	if debug_prints:
		print("Player ready - rotation:", rotation_degrees.y, " position:", start_position)

func _input(event):
	# Track mouse position for drift effect
	if event is InputEventMouseMotion:
		current_mouse_pos = event.position

func _process(delta: float) -> void:
	handle_directional_input()
	handle_rotation(delta)
	handle_mouse_drift(delta)
	handle_movement(delta)
	handle_camera_effects(delta)
	apply_camera_transform()

# -------------------------
# INPUT: Updated Front behavior
# -------------------------
func handle_directional_input():
	var new_target_deg = null

	var left_just = Input.is_action_just_pressed("Left")
	var right_just = Input.is_action_just_pressed("Right")
	var back_just = Input.is_action_just_pressed("Back")
	var front_just = Input.is_action_just_pressed("Front")
	
	# FRONT logic (three-step behavior)
	if front_just:
		# If currently moving forward and at max -> pressing Front triggers return
		if move_forward and forward_progress >= max_forward_distance:
			move_forward = false
			returning = true
			if debug_prints: print("Front pressed at max -> start returning")
			return
		
		# If currently returning -> ignore front presses (or you could cancel return)
		if returning:
			if debug_prints: print("Front pressed while returning -> ignored")
			return
		
		# If not moving/returning:
		# If not facing front -> rotate to face front (1st press)
		var facing_diff = abs(_wrap_degrees(rotation_degrees.y - 0.0))
		if facing_diff > face_threshold_deg:
			target_rot_deg = 0.0
			if debug_prints: print("Front pressed -> rotate to face front (1st press)")
			return
		# else if already facing front -> start moving forward (2nd press)
		if not move_forward:
			move_forward = true
			forward_progress = 0.0
			start_position = global_transform.origin
			if debug_prints: print("Front pressed facing front -> begin moving forward (2nd press)")
			return

	# RIGHT / BACK / LEFT logic (unchanged)
	if right_just:
		new_target_deg = target_rot_deg - 90.0  # turn right from current target
	elif back_just:
		new_target_deg = target_rot_deg + 180.0  # turn around
	elif left_just:
		new_target_deg = target_rot_deg + 90.0  # turn left
	
	# Normalize angle 0..360
	if new_target_deg != null:
		new_target_deg = fmod(new_target_deg, 360.0)
		if new_target_deg < 0:
			new_target_deg += 360.0

	if new_target_deg != null:
		# If we are moving forward and user presses a direction:
		# cancel forward, start returning, and store pending rotation
		if new_target_deg != target_rot_deg and move_forward:
			returning = true
			move_forward = false
			rotation_locked = true
			pending_rot_deg = new_target_deg
			if debug_prints:
				print("Direction change while forward -> returning. pending:", pending_rot_deg)
		elif not move_forward:
			# Snap rotation immediately when not moving
			target_rot_deg = new_target_deg
			rotation_locked = false
			if debug_prints:
				print("Set target rotation:", target_rot_deg)

# -------------------------
# ROTATION / MOVEMENT / CAMERA (unchanged)
# -------------------------
func handle_rotation(delta: float):
	var t = clamp(delta * rotation_smooth, 0.0, 1.0)
	rotation_degrees.y = lerp_angle_degrees(rotation_degrees.y, target_rot_deg, t)

func handle_mouse_drift(delta: float):
	# Calculate mouse offset from screen center
	var mouse_offset = current_mouse_pos - screen_center
	
	# Convert mouse position to drift angles
	target_drift_x = -mouse_offset.y * mouse_drift_strength
	target_drift_y = -mouse_offset.x * mouse_drift_strength
	
	# Clamp drift amounts (convert deg clamps to radians)
	target_drift_x = clamp(target_drift_x, -deg_to_rad(max_drift_angle), deg_to_rad(max_drift_angle))
	target_drift_y = clamp(target_drift_y, -deg_to_rad(horizontal_drift_range), deg_to_rad(horizontal_drift_range))
	
	# Calculate head tilt from drift (or turning)
	var tilt_from_drift = target_drift_y * 0.4
	var rotation_vel = abs(_wrap_degrees(target_rot_deg - rotation_degrees.y))
	
	if rotation_vel > 1.0:
		var rotation_dir = sign(_wrap_degrees(target_rot_deg - rotation_degrees.y))
		target_head_tilt = rotation_dir * deg_to_rad(head_tilt_amount)
	else:
		target_head_tilt = tilt_from_drift
	
	# Smoothly drift camera toward target (slower = more drifty feel)
	var drift_t = clamp(delta * drift_smoothing, 0.0, 1.0)
	var tilt_t = clamp(delta * tilt_smoothing, 0.0, 1.0)
	
	drift_x = lerp(drift_x, target_drift_x, drift_t)
	drift_y = lerp(drift_y, target_drift_y, drift_t)
	head_tilt = lerp(head_tilt, target_head_tilt, tilt_t)

func handle_movement(delta: float):
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()

	if move_forward:
		var step = forward_speed * delta
		forward_progress += step
		if forward_progress > max_forward_distance:
			# clamp overshoot
			step -= forward_progress - max_forward_distance
			forward_progress = max_forward_distance
		global_transform.origin += forward_dir * step

	elif returning:
		var to_start = start_position - global_transform.origin
		var dist = to_start.length()
		var move_step = forward_speed * delta
		if move_step >= dist:
			global_transform.origin = start_position
			returning = false
			forward_progress = 0.0
			rotation_locked = false
			# Apply pending rotation (if any)
			if pending_rot_deg != null and pending_rot_deg != 0.0:
				target_rot_deg = pending_rot_deg
				pending_rot_deg = 0.0
			if debug_prints:
				print("Returned to start position.")
		else:
			global_transform.origin += to_start.normalized() * move_step

func handle_camera_effects(delta: float):
	# Head bob
	bob_timer += delta * bob_speed
	# amplitude depends on forward state
	var amplitude = idle_bob_amplitude if not move_forward else forward_bob_amplitude

	# Stress effect: move stress_target towards a new random tiny value and assign stress_offset
	stress_target = Vector3(
		lerp(stress_target.x, (randf() - 0.5) * 2.0 * stress_intensity, delta * stress_speed),
		lerp(stress_target.y, (randf() - 0.5) * 2.0 * stress_intensity, delta * stress_speed),
		lerp(stress_target.z, (randf() - 0.5) * 2.0 * stress_intensity, delta * stress_speed)
	)
	stress_offset = stress_target

func apply_camera_transform():
	# Combine all camera effects (relative to base)
	var bob_val = sin(bob_timer) * (idle_bob_amplitude if not move_forward else forward_bob_amplitude)
	var final_position = Vector3(
		stress_offset.x,
		bob_val + stress_offset.y,
		stress_offset.z
	)
	
	# rotation components are in radians (drift_x / drift_y / head_tilt are radians)
	var final_rotation = Vector3(
		drift_x,     # pitch (up/down)
		drift_y,     # yaw (left/right) - typically we won't modify yaw here
		head_tilt    # roll (tilt)
	)
	
	# Apply relative to base camera transform
	if cam:
		# position relative to cached base origin
		var new_origin = base_cam_origin + final_position
		var ct = cam.transform
		ct.origin = new_origin
		cam.transform = ct
		
		# rotation: base_cam_rot (Vector3 radians) + final_rotation
		cam.rotation = base_cam_rot + final_rotation

# Helper functions
func _wrap_degrees(angle: float) -> float:
	angle = fmod(angle + 180.0, 360.0)
	if angle < 0.0:
		angle += 360.0
	return angle - 180.0

func lerp_angle_degrees(a: float, b: float, t: float) -> float:
	var diff = _wrap_degrees(b - a)
	return a + diff * t

# ---- stress tween helper (unchanged) ----
func add_stress(intensity: float = 0.05, duration: float = 1.0) -> void:
	# cancel previous tween if present and valid
	if _stress_tween != null and is_instance_valid(_stress_tween):
		if _stress_tween.has_method("kill"):
			_stress_tween.kill()
		_stress_tween = null

	var original_intensity = stress_intensity
	# apply immediate stress
	stress_intensity = intensity

	# create a new tween that lerps stress_intensity back to original
	_stress_tween = create_tween()
	_stress_tween.tween_property(self, "stress_intensity", original_intensity, duration)
