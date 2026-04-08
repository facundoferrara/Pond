extends Fish
class_name Guppy

var flee_energy_drain_rate: float = 5.0
var despawner_avoid_radius: float = 220.0
var despawner_avoid_force_multiplier: float = 2.1
var turn_rate_rad_per_sec: float = 9.0
var wander_heading: Vector2 = Vector2.RIGHT
var wander_speed_factor: float = 0.38
var swim_mode: int = 0
var mode_switch_timer: float = 0.0
var next_mode_switch_interval: float = 3.5


func _ready() -> void:
	species = SpeciesDB.GUPPY
	super._ready()
	var species_data: Dictionary = SpeciesDB.get_species(SpeciesDB.GUPPY)
	flee_energy_drain_rate = float(species_data.get("flee_energy_drain_rate", flee_energy_drain_rate))
	despawner_avoid_radius = float(species_data.get("despawner_avoid_radius", despawner_avoid_radius))
	despawner_avoid_force_multiplier = float(species_data.get("despawner_avoid_force_multiplier", despawner_avoid_force_multiplier))
	turn_rate_rad_per_sec = float(species_data.get("turn_rate_rad_per_sec", turn_rate_rad_per_sec))


func reinitialize() -> void:
	super.reinitialize()
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	swim_mode = 0
	mode_switch_timer = 0.0
	next_mode_switch_interval = randf_range(2.0, 5.0)


func _process(delta: float) -> void:
	super._process(delta)
	_update_swim_mode(delta)
	if _is_exhausted():
		if velocity.length() > top_speed * 0.6:
			velocity = velocity.normalized() * top_speed * 0.6
	_refresh_age_tint()


func _compute_acceleration(delta: float) -> Vector2:
	var avoid_despawner: Vector2 = _compute_despawner_avoidance()

	if behavior_state == BehaviorState.FLEE:
		var flee_steer: Vector2 = _compute_distance_scaled_flee_steer()
		energy = maxf(0.0, energy - flee_energy_drain_rate * delta)
		if _is_exhausted():
			return flee_steer + avoid_despawner
		var flee: Vector2 = flee_steer * 2.1
		var support_school: Vector2 = _compute_boid_steering(boid_neighbors) * 0.35
		return flee + support_school + avoid_despawner

	if _is_exhausted():
		if _age_ratio() < 0.75:
			return avoid_despawner
		return _steer_towards_despawn()

	var boid: Vector2 = _compute_age_aware_boid_steering()
	var age_bias: Vector2 = _compute_age_despawn_bias()
	var wander: Vector2 = _compute_wander(delta)
	var result: Vector2 = boid + age_bias + wander + avoid_despawner
	if swim_mode == 1:
		result += _compute_zigzag_steering(delta)
	return result


func _compute_distance_scaled_flee_steer() -> Vector2:
	if not _predator_valid():
		return Vector2.ZERO

	var away: Vector2 = global_position - nearest_predator.global_position
	if away.length_squared() <= 0.000001:
		away = Vector2.RIGHT.rotated(randf_range(-PI, PI))

	var distance: float = away.length()
	var detection_radius: float = maxf(predator_detection_radius, 0.001)
	var threat_t: float = 1.0 - clampf(distance / detection_radius, 0.0, 1.0)
	var speed_scale: float = 0.45 + threat_t * 0.55
	var steer_scale: float = 0.35 + threat_t * 0.65
	var desired: Vector2 = away.normalized() * top_speed * speed_scale
	return _steer_towards(desired) * steer_scale


func _compute_age_aware_boid_steering() -> Vector2:
	var ratio: float = _age_ratio()
	if ratio >= 0.75:
		return _compute_boid_steering(boid_neighbors)

	var young_neighbors: Array[Fish] = []
	for other: Fish in boid_neighbors:
		var other_ratio: float = clampf(other.age_seconds / maxf(other.life_span_seconds, 0.001), 0.0, 1.0)
		if other_ratio < 0.75:
			young_neighbors.append(other)

	var young_boid: Vector2 = _compute_boid_steering(young_neighbors)
	var old_group_pull: Vector2 = _compute_old_group_cohesion_pull()
	return young_boid + old_group_pull


func _compute_wander(delta: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-1.8, 1.8) * delta)
	var desired: Vector2 = wander_heading * top_speed * wander_speed_factor
	return _steer_towards(desired) * 0.62


func _update_swim_mode(delta: float) -> void:
	mode_switch_timer += delta
	if mode_switch_timer >= next_mode_switch_interval:
		mode_switch_timer = 0.0
		next_mode_switch_interval = randf_range(2.0, 5.0)
		if randf() < 0.5:
			swim_mode = 1 - swim_mode


func _compute_zigzag_steering(delta: float) -> Vector2:
	if velocity.length_squared() <= 0.000001:
		return Vector2.ZERO

	var forward: Vector2 = velocity.normalized()
	var lateral: Vector2 = Vector2(-forward.y, forward.x)
	var phase: float = mode_switch_timer * 3.5
	var zig: float = sin(phase)
	var lateral_strength: float = zig * top_speed * 0.35
	var desired: Vector2 = (forward + lateral * sign(zig) * 0.48).normalized() * top_speed
	return _steer_towards(desired) * 0.78


func _compute_old_group_cohesion_pull() -> Vector2:
	var old_count: int = 0
	var centroid: Vector2 = Vector2.ZERO
	for other: Fish in boid_neighbors:
		var other_ratio: float = clampf(other.age_seconds / maxf(other.life_span_seconds, 0.001), 0.0, 1.0)
		if other_ratio < 0.75:
			continue
		old_count += 1
		centroid += other.global_position

	# A lone old fish should not drag young fish out; groups can influence slightly.
	if old_count < 3:
		return Vector2.ZERO

	centroid /= float(old_count)
	var toward_old_group: Vector2 = centroid - global_position
	if toward_old_group.length_squared() <= 0.000001:
		return Vector2.ZERO

	var desired: Vector2 = toward_old_group.normalized() * top_speed
	var group_t: float = clampf(float(old_count - 2) / 4.0, 0.0, 1.0)
	var pull_strength: float = 0.20 + group_t * 0.45
	return _steer_towards(desired) * pull_strength


func _is_exhausted() -> bool:
	return energy <= 0.0


func _steer_towards_despawn() -> Vector2:
	var desired: Vector2 = (despawn_area_center - global_position).normalized() * top_speed
	return _steer_towards(desired)


func _compute_age_despawn_bias() -> Vector2:
	var ratio: float = _age_ratio()
	if ratio < 0.75:
		return Vector2.ZERO
	var t: float = (ratio - 0.75) / 0.25
	return _steer_towards_despawn() * t


func _compute_despawner_avoidance() -> Vector2:
	var ratio: float = _age_ratio()
	if ratio >= 0.75:
		return Vector2.ZERO

	var away: Vector2 = global_position - despawn_area_center
	var distance: float = away.length()
	if distance >= despawner_avoid_radius:
		return Vector2.ZERO
	if away.length_squared() <= 0.000001:
		away = Vector2.RIGHT.rotated(randf_range(-PI, PI))

	var strength: float = 1.0 - clampf(distance / max(despawner_avoid_radius, 0.0001), 0.0, 1.0)
	var youth_t: float = 1.0 - clampf(ratio / 0.75, 0.0, 1.0)
	var desired: Vector2 = away.normalized() * top_speed
	var young_boost: float = 1.0 + youth_t * 0.16
	return _steer_towards(desired) * (despawner_avoid_force_multiplier * young_boost * (0.45 + strength * 1.55))


func _refresh_age_tint() -> void:
	if not _ensure_sprite():
		return
	var ratio: float = _age_ratio()
	if ratio < 0.75:
		sprite.modulate = color
		return
	var t: float = (ratio - 0.75) / 0.25
	var hsv: Vector3 = Vector3(color.h, color.s, color.v)
	var target_s: float = hsv.y * 0.5
	var current_s: float = lerpf(hsv.y, target_s, t)
	sprite.modulate = Color.from_hsv(hsv.x, current_s, hsv.z, color.a)


func _update_orientation() -> void:
	if not _ensure_sprite():
		return

	var displacement: Vector2 = global_position - previous_global_position
	if displacement.length_squared() <= 0.000001:
		if debug_facing and not warned_facing_no_motion:
			warned_facing_no_motion = true
			push_warning("Facing skipped: negligible displacement this frame. If fish still look wrong, check heading_offset_radians.")
		previous_global_position = global_position
		return

	warned_facing_no_motion = false
	var target_angle: float = atan2(displacement.y, displacement.x)
	var max_step: float = turn_rate_rad_per_sec * get_process_delta_time()
	global_rotation = rotate_toward(global_rotation, target_angle, max_step)
	sprite.rotation = heading_offset_radians
	previous_global_position = global_position


func _process_feeding(_delta: float) -> void:
	return
