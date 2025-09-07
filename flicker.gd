extends SpotLight3D

# --- base settings ---
@export var base_energy: float = 2.0         # default steady brightness
@export var min_energy: float = 0.1          # minimum dip in flutter
@export var off_energy: float = 0.0          # energy for full blackout

# --- event pacing (editable) ---
@export var chance_per_second: float = 0.03  # probability per second that an event starts
@export var blackout_enabled: bool = true    # toggle blackouts on/off
@export var blackout_prob: float = 0.2       # when an event fires, prob it is a blackout (0..1)
@export var flutter_weight: float = 0.8      # fallback weight for flutter when blackout is enabled

# --- flutter tuning (fast small dips) ---
@export var flutter_min_pulses: int = 3
@export var flutter_max_pulses: int = 8
@export var flutter_min_interval: float = 0.03
@export var flutter_max_interval: float = 0.12
@export var flutter_min_depth: float = 0.15  # fraction of base (0..1)
@export var flutter_max_depth: float = 0.6   # fraction of base (0..1)

# --- blackout tuning (rare longer offs) ---
@export var blackout_min_duration: float = 0.2
@export var blackout_max_duration: float = 1.1

# --- smoothing ---
@export var energy_lerp_speed: float = 18.0  # how fast energy interpolates to target

# --- debug ---
@export var debug: bool = false

# --- internal state ---
var rng := RandomNumberGenerator.new()
var sequence: Array = []     # array of dictionaries { "target": float, "duration": float }
var seq_timer: float = 0.0
var current_target_energy: float = 0.0
var actual_energy: float = 0.0

func _ready() -> void:
	rng.randomize()
	current_target_energy = base_energy
	actual_energy = base_energy
	light_energy = base_energy

func _process(delta: float) -> void:
	# step sequence if active
	if sequence.size() > 0:
		seq_timer -= delta
		if seq_timer <= 0.0:
			# consume current item
			sequence.remove_at(0)
			if sequence.size() > 0:
				var item = sequence[0]
				current_target_energy = item.get("target", base_energy)
				seq_timer = item.get("duration", 0.0)
				if debug:
					print("flicker: next target=", current_target_energy, " dur=", seq_timer)
			else:
				# finished, restore base
				current_target_energy = base_energy
				seq_timer = 0.0
				if debug:
					print("flicker: sequence finished, restoring base")
	else:
		# no active sequence: chance to spawn a new one
		if rng.randf() < chance_per_second * delta:
			_start_random_event()

	# smoothly approach the current target energy
	actual_energy = lerp(actual_energy, current_target_energy, clamp(delta * energy_lerp_speed, 0.0, 1.0))
	light_energy = actual_energy

# -------------------------
# Event builders
# -------------------------
func _start_random_event() -> void:
	# Decide whether to start a blackout or flutter
	var choose_blackout: bool = false
	if blackout_enabled:
		# use blackout_prob if set; otherwise fallback to flutter_weight
		choose_blackout = rng.randf() < blackout_prob
	else:
		choose_blackout = false

	if choose_blackout:
		_start_blackout()
	else:
		_start_flutter()

func _start_flutter() -> void:
	sequence.clear()
	var pulses := rng.randi_range(flutter_min_pulses, flutter_max_pulses)
	for i in pulses:
		var depth_frac = lerp(flutter_min_depth, flutter_max_depth, rng.randf())
		var target_e = max(min_energy, base_energy * depth_frac)
		var dur = lerp(flutter_min_interval, flutter_max_interval, rng.randf())
		# dip then quick recover
		sequence.append({"target": target_e, "duration": dur})
		sequence.append({"target": base_energy * lerp(0.85, 1.0, rng.randf()), "duration": dur * 0.6})
	# final restore
	sequence.append({"target": base_energy, "duration": 0.08})
	# start sequence now
	var first = sequence[0]
	current_target_energy = first.get("target", base_energy)
	seq_timer = first.get("duration", 0.0)
	if debug:
		print("flicker: started flutter pulses=", pulses)

func _start_blackout() -> void:
	sequence.clear()
	var off_dur = lerp(blackout_min_duration, blackout_max_duration, rng.randf())
	sequence.append({"target": off_energy, "duration": off_dur})
	sequence.append({"target": base_energy * 0.25, "duration": 0.12}) # faint stutter back
	sequence.append({"target": base_energy, "duration": 0.0})
	var first = sequence[0]
	current_target_energy = first.get("target", base_energy)
	seq_timer = first.get("duration", 0.0)
	if debug:
		print("flicker: started blackout dur=", off_dur)

# -------------------------
# Public API (call these from other scripts)
# -------------------------
func set_blackout_enabled(enabled: bool) -> void:
	blackout_enabled = enabled

func toggle_blackout() -> void:
	blackout_enabled = not blackout_enabled

func set_chance_per_second(chance: float) -> void:
	chance_per_second = max(0.0, chance)

func set_blackout_probability(prob: float) -> void:
	blackout_prob = clamp(prob, 0.0, 1.0)

# Force a blackout event immediately (optional duration)
func trigger_blackout_now(opt_duration: float = -1.0) -> void:
	sequence.clear()
	var off_dur = opt_duration if opt_duration > 0.0 else lerp(blackout_min_duration, blackout_max_duration, rng.randf())
	sequence.append({"target": off_energy, "duration": off_dur})
	sequence.append({"target": base_energy * 0.25, "duration": 0.12})
	sequence.append({"target": base_energy, "duration": 0.0})
	var first = sequence[0]
	current_target_energy = first.get("target", base_energy)
	seq_timer = first.get("duration", 0.0)
	if debug:
		print("flicker: triggered blackout now dur=", off_dur)

func trigger_flutter_now() -> void:
	_start_flutter()
