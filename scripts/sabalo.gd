extends Fish
class_name Sabalo

@export_group("Sabalo: Debug")
## Draws behavior gizmos for local debugging.
@export var debug_gizmo_enabled: bool = false
## Line thickness for debug gizmos.
@export var gizmo_line_width: float = 1.5

var wander_heading: Vector2 = Vector2.RIGHT
var feed_phase: float = 0.0
@export_group("Sabalo: Feeding")
## Distance from shore used to trigger feeding opportunities.
@export var feeding_start_distance: float = 54.0
## Per-second chance to enter feeding state near shore.
@export var feeding_chance_per_second: float = 0.8
## Feeding ends when energy reaches this ratio of starting energy.
@export var feeding_energy_ratio: float = 0.92
## Energy gained each second while feeding.
@export var feeding_energy_gain: float = 1.35
## Points generated each second while feeding.
@export var feed_points_per_second: float = 0.5
## Lockout duration before feeding is allowed after spawn/reset.
@export var feed_lock_seconds: float = 8.0
var feed_lock_remaining: float = 0.0
var feed_origin: Vector2 = Vector2.ZERO
var feed_escape_dir: Vector2 = Vector2.ZERO
var feed_origin_valid: bool = false

@export_group("Sabalo: Zone Handling")
## Radius where young sabalos avoid despawn zone.
@export var despawner_avoid_radius: float = 240.0
## Steering multiplier for despawn-zone avoidance.
@export var despawner_avoid_force_multiplier: float = 2.35
## Time spent in safer post-spawn movement mode.
@export var spawn_egress_lock_seconds: float = 3.4
var spawn_egress_lock_remaining: float = 0.0
## Margin around repel zone where feeding is denied.
@export var repel_zone_feed_margin: float = 24.0
## Shore threshold ratio for near-shore checks.
@export var upper_zone_ratio: float = 0.34
## Preferred vertical depth ratio inside pond bounds.
@export var depth_preference_ratio: float = 0.68
## Strength of steering toward preferred depth.
@export var depth_preference_strength: float = 0.7
## Deadzone around preferred depth where no correction is applied.
@export var depth_preference_deadzone: float = 26.0

@export_group("Sabalo: Recovery")
## Speed ratio below which stall detection starts counting.
@export var stall_speed_ratio_threshold: float = 0.16
## Time below stall threshold before unstuck behavior triggers.
@export var stall_trigger_seconds: float = 1.0
## Duration of unstuck force boost.
@export var unstuck_boost_seconds: float = 2.0
## Strength multiplier for unstuck escape force.
@export var unstuck_force_multiplier: float = 1.7
var stalled_time: float = 0.0
var unstuck_boost_remaining: float = 0.0
var unstuck_zone_lock: bool = false

@export_group("Sabalo: Steering")
## Rotation speed cap when turning toward movement direction.
@export var turn_rate_rad_per_sec: float = 2.8
## Turn slowdown factor for sharp turns.
@export var turn_slow_min_speed_factor: float = 1.0
## Separation steering strength from nearby sabalos.
@export var local_separation_strength: float = 2.2
## Radius used for local separation.
@export var local_separation_radius: float = 42.0

@export_group("Sabalo: Panic")
## Duration of panic burst after predator trigger.
@export var panic_duration_seconds: float = 1.0
## Cooldown before panic can trigger again.
@export var panic_cooldown_seconds: float = 5.0
## Speed multiplier while panicking.
@export var panic_speed_multiplier: float = 2.0
var panic_remaining: float = 0.0
var panic_cooldown_remaining: float = 0.0
var panic_dir: Vector2 = Vector2.ZERO


func _ready() -> void:
	species = SpeciesDB.SABALO
	super._ready()
	feed_lock_remaining = feed_lock_seconds
	spawn_egress_lock_remaining = spawn_egress_lock_seconds
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	queue_redraw()


func reinitialize() -> void:
	super.reinitialize()
	feed_lock_remaining = feed_lock_seconds
	feed_origin_valid = false
	feed_escape_dir = Vector2.ZERO
	spawn_egress_lock_remaining = spawn_egress_lock_seconds
	unstuck_boost_remaining = 0.0
	stalled_time = 0.0
	unstuck_zone_lock = false
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	feed_phase = 0.0
	panic_remaining = 0.0
	panic_cooldown_remaining = 0.0
	panic_dir = Vector2.ZERO


func _process(delta: float) -> void:
	feed_lock_remaining = maxf(0.0, feed_lock_remaining - delta)
	spawn_egress_lock_remaining = maxf(0.0, spawn_egress_lock_remaining - delta)
	unstuck_boost_remaining = maxf(0.0, unstuck_boost_remaining - delta)
	panic_remaining = maxf(0.0, panic_remaining - delta)
	panic_cooldown_remaining = maxf(0.0, panic_cooldown_remaining - delta)
	super._process(delta)
	_update_stall_recovery(delta)
	if debug_gizmo_enabled and not pending_remove:
		queue_redraw()


func _apply_species_defaults() -> void:
	super._apply_species_defaults()
	var species_data: Dictionary = SpeciesDB.get_species(species)
	feeding_start_distance = float(species_data.get("feeding_start_distance", feeding_start_distance))
	feeding_chance_per_second = float(species_data.get("feeding_chance_per_second", feeding_chance_per_second))
	feeding_energy_ratio = float(species_data.get("feeding_energy_ratio", feeding_energy_ratio))
	feeding_energy_gain = float(species_data.get("feeding_energy_gain", feeding_energy_gain))
	feed_points_per_second = float(species_data.get("feed_points_per_second", feed_points_per_second))
	feed_lock_seconds = float(species_data.get("feed_lock_seconds", feed_lock_seconds))
	despawner_avoid_radius = float(species_data.get("despawner_avoid_radius", despawner_avoid_radius))
	despawner_avoid_force_multiplier = float(species_data.get("despawner_avoid_force_multiplier", despawner_avoid_force_multiplier))
	spawn_egress_lock_seconds = float(species_data.get("spawn_egress_lock_seconds", spawn_egress_lock_seconds))
	repel_zone_feed_margin = float(species_data.get("repel_zone_feed_margin", repel_zone_feed_margin))
	upper_zone_ratio = float(species_data.get("upper_zone_ratio", upper_zone_ratio))
	depth_preference_ratio = float(species_data.get("depth_preference_ratio", depth_preference_ratio))
	depth_preference_strength = float(species_data.get("depth_preference_strength", depth_preference_strength))
	depth_preference_deadzone = float(species_data.get("depth_preference_deadzone", depth_preference_deadzone))
	stall_speed_ratio_threshold = float(species_data.get("stall_speed_ratio_threshold", stall_speed_ratio_threshold))
	stall_trigger_seconds = float(species_data.get("stall_trigger_seconds", stall_trigger_seconds))
	unstuck_boost_seconds = float(species_data.get("unstuck_boost_seconds", unstuck_boost_seconds))
	unstuck_force_multiplier = float(species_data.get("unstuck_force_multiplier", unstuck_force_multiplier))
	turn_rate_rad_per_sec = float(species_data.get("turn_rate_rad_per_sec", turn_rate_rad_per_sec))
	turn_slow_min_speed_factor = float(species_data.get("turn_slow_min_speed_factor", turn_slow_min_speed_factor))
	local_separation_strength = float(species_data.get("local_separation_strength", local_separation_strength))
	local_separation_radius = float(species_data.get("local_separation_radius", local_separation_radius))
	panic_duration_seconds = float(species_data.get("panic_duration_seconds", panic_duration_seconds))
	panic_cooldown_seconds = float(species_data.get("panic_cooldown_seconds", panic_cooldown_seconds))
	panic_speed_multiplier = float(species_data.get("panic_speed_multiplier", panic_speed_multiplier))


func _update_orientation() -> void:
	if not _ensure_sprite():
		return

	var displacement: Vector2 = global_position - previous_global_position
	if displacement.length_squared() <= 0.000001:
		previous_global_position = global_position
		return

	var target_angle: float = atan2(displacement.y, displacement.x)
	var max_step: float = turn_rate_rad_per_sec * get_process_delta_time()
	global_rotation = rotate_toward(global_rotation, target_angle, max_step)
	sprite.rotation = heading_offset_radians
	previous_global_position = global_position


func _turn_speed_factor(desired_dir: Vector2) -> float:
	if desired_dir.length_squared() <= 0.000001:
		return 1.0
	if velocity.length_squared() <= 0.000001:
		return 1.0

	var current_dir: Vector2 = velocity.normalized()
	var angle_delta: float = absf(wrapf(current_dir.angle_to(desired_dir), -PI, PI))
	var t: float = clampf(angle_delta / PI, 0.0, 1.0)
	return lerpf(1.0, turn_slow_min_speed_factor, pow(t, 0.75))


func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null
	var nearest_distance: float = INF

	# Sabalos don't school — only scan the small potential-predator list.
	for other: Fish in SpatialGrid.get_potential_predators():
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if not other.can_eat_fish(self ):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance > vision_radius:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_predator = other


func _update_behavior_state() -> void:
	# Sabalo uses a custom state machine inside _compute_acceleration.
	pass


func _compute_acceleration(delta: float) -> Vector2:
	var avoid_despawner: Vector2 = _compute_despawner_avoidance()
	if _predator_valid():
		if _can_trigger_panic():
			_begin_panic_from_flock_center()
		if panic_remaining > 0.0:
			behavior_state = BehaviorState.FLEE
			feed_origin_valid = false
			return _compute_panic_escape() + avoid_despawner
		behavior_state = BehaviorState.FLEE
		feed_origin_valid = false
		return _compute_predator_escape() + avoid_despawner

	if spawn_egress_lock_remaining > 0.0:
		behavior_state = BehaviorState.SCHOOL
		feed_origin_valid = false
		return _compute_spawn_egress() + avoid_despawner

	if feed_lock_remaining > 0.0:
		behavior_state = BehaviorState.SCHOOL
		feed_origin_valid = false
		return _compose_school_motion(delta) + avoid_despawner

	if behavior_state == BehaviorState.FEED:
		if energy >= starting_energy * feeding_energy_ratio or _is_inside_spawner_repel_zone(repel_zone_feed_margin):
			behavior_state = BehaviorState.SCHOOL
			feed_origin_valid = false
		else:
			return _compose_feed_motion(delta) + avoid_despawner

	if _is_near_shore() and not _is_inside_spawner_repel_zone(repel_zone_feed_margin) and randf() < feeding_chance_per_second * delta:
		behavior_state = BehaviorState.FEED
		_begin_feeding_path()
		return _compose_feed_motion(delta) + avoid_despawner

	behavior_state = BehaviorState.SCHOOL
	feed_origin_valid = false
	return _compose_school_motion(delta) + avoid_despawner


func _can_trigger_panic() -> bool:
	return panic_remaining <= 0.0 and panic_cooldown_remaining <= 0.0


func _begin_panic_from_flock_center() -> void:
	var flock_center: Vector2 = _compute_local_flock_center()
	var flee_from_center: Vector2 = global_position - flock_center
	if flee_from_center.length_squared() <= 0.000001:
		flee_from_center = get_escape_vector()
	if flee_from_center.length_squared() <= 0.000001:
		flee_from_center = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	panic_dir = flee_from_center.normalized()
	panic_remaining = panic_duration_seconds
	panic_cooldown_remaining = panic_cooldown_seconds


func _compute_local_flock_center() -> Vector2:
	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, local_separation_radius * 2.0)
	var center: Vector2 = global_position
	var count: int = 1
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if other.species != SpeciesDB.SABALO:
			continue
		center += other.global_position
		count += 1
	return center / float(count)


func _compute_panic_escape() -> Vector2:
	var desired_dir: Vector2 = panic_dir
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = get_escape_vector().normalized()
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = Vector2.RIGHT

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if not nearest_data.is_empty():
		var dist: float = float(nearest_data["distance"])
		if dist <= out_avoid_distance * 0.95:
			var shore_point: Vector2 = nearest_data["point"] as Vector2
			desired_dir = (desired_dir + _inward_direction_from_boundary(shore_point) * 0.9).normalized()

	var desired_speed: float = top_speed * panic_speed_multiplier
	var desired: Vector2 = desired_dir.normalized() * desired_speed * _turn_speed_factor(desired_dir)
	return _steer_towards(desired) * 3.2


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
	var young_boost: float = 1.0 + youth_t * 0.22
	return _steer_towards(desired) * (despawner_avoid_force_multiplier * young_boost * (0.45 + strength * 1.55))


func _begin_feeding_path() -> void:
	feed_origin = global_position
	feed_origin_valid = true
	feed_phase = randf_range(0.0, TAU)

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(feed_origin)
	if not nearest_data.is_empty():
		var shore_point: Vector2 = nearest_data["point"] as Vector2
		feed_escape_dir = _inward_direction_from_boundary(shore_point)

	if feed_escape_dir.length_squared() <= 0.000001:
		feed_escape_dir = (pond_bounds.get_center() - feed_origin).normalized()
	if feed_escape_dir.length_squared() <= 0.000001:
		feed_escape_dir = Vector2.RIGHT.rotated(randf_range(-PI, PI))


func _process_feeding(delta: float) -> void:
	if behavior_state != BehaviorState.FEED:
		return
	energy = minf(starting_energy, energy + feeding_energy_gain * delta)
	points += feed_points_per_second * delta


func _compute_wander(delta: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-1.1, 1.1) * delta)
	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	var inward: Vector2 = Vector2.ZERO
	if not nearest_data.is_empty():
		var shore_point: Vector2 = nearest_data["point"] as Vector2
		inward = _inward_direction_from_boundary(shore_point)

	var desired_dir: Vector2 = (wander_heading * 0.68 + inward * 0.32).normalized()
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = Vector2.RIGHT
	var desired: Vector2 = desired_dir * top_speed * 0.78 * _turn_speed_factor(desired_dir)
	return _steer_towards(desired) * 1.15


func _compose_school_motion(delta: float) -> Vector2:
	var base: Vector2 = _compute_wander(delta)
	base += _compute_local_separation()
	base += _compute_depth_bias()
	if _is_unstuck_active():
		base += _compute_unstuck_escape()
	return base


func _compose_feed_motion(delta: float) -> Vector2:
	var base: Vector2 = _compute_feeding_swim(delta)
	base += _compute_local_separation()
	base += _compute_depth_bias()
	if _is_unstuck_active():
		base += _compute_unstuck_escape()
	return base


func _compute_depth_bias() -> Vector2:
	var target_y: float = pond_bounds.position.y + pond_bounds.size.y * depth_preference_ratio
	var delta_y: float = target_y - global_position.y
	if absf(delta_y) <= depth_preference_deadzone:
		return Vector2.ZERO

	var desired_dir: Vector2 = Vector2(0.0, signf(delta_y))
	var desired: Vector2 = desired_dir * top_speed * 0.45
	return _steer_towards(desired) * depth_preference_strength


func _compute_local_separation() -> Vector2:
	if local_separation_strength <= 0.0 or local_separation_radius <= 0.001:
		return Vector2.ZERO

	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, local_separation_radius)
	var repulsion: Vector2 = Vector2.ZERO
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if other.species != SpeciesDB.SABALO:
			continue

		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance <= 0.001 or distance > local_separation_radius:
			continue

		var falloff: float = 1.0 - clampf(distance / local_separation_radius, 0.0, 1.0)
		repulsion += offset.normalized() * (0.35 + falloff * 0.65)

	if repulsion.length_squared() <= 0.000001:
		return Vector2.ZERO

	var desired: Vector2 = repulsion.normalized() * top_speed
	return _steer_towards(desired) * local_separation_strength


func _compute_spawn_egress() -> Vector2:
	var center: Vector2 = pond_bounds.get_center()
	var target: Vector2 = _egress_target_point()
	var toward_target: Vector2 = target - global_position
	if toward_target.length_squared() <= 0.000001:
		toward_target = center - global_position

	var desired_dir: Vector2 = toward_target.normalized()
	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if not nearest_data.is_empty():
		var shore_point: Vector2 = nearest_data["point"] as Vector2
		desired_dir = (desired_dir * 0.72 + _inward_direction_from_boundary(shore_point) * 0.28).normalized()

	var desired: Vector2 = desired_dir * top_speed * 0.86 * _turn_speed_factor(desired_dir)
	return _steer_towards(desired) * 1.35


func _compute_feeding_swim(delta: float) -> Vector2:
	feed_phase += delta * 4.6
	if not feed_origin_valid:
		_begin_feeding_path()

	var away_from_origin: Vector2 = global_position - feed_origin
	var radial_dir: Vector2 = feed_escape_dir
	if away_from_origin.length_squared() > 64.0:
		radial_dir = away_from_origin.normalized()
	if radial_dir.length_squared() <= 0.000001:
		radial_dir = feed_escape_dir
	if radial_dir.length_squared() <= 0.000001:
		radial_dir = (pond_bounds.get_center() - global_position).normalized()
	if radial_dir.length_squared() <= 0.000001:
		radial_dir = Vector2.DOWN

	var lateral: Vector2 = Vector2(-radial_dir.y, radial_dir.x)
	var zig: float = sin(feed_phase)
	if absf(zig) < 0.12:
		zig = signf(zig + 0.001)
	var desired_dir: Vector2 = (radial_dir * 0.78 + lateral * zig * 0.42).normalized()
	var desired: Vector2 = desired_dir * top_speed * 0.52 * _turn_speed_factor(desired_dir)
	return _steer_towards(desired) * 1.45


func _compute_predator_escape() -> Vector2:
	if not _predator_valid():
		return Vector2.ZERO

	var away_predator: Vector2 = global_position - nearest_predator.global_position
	if away_predator.length_squared() <= 0.000001:
		away_predator = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	away_predator = away_predator.normalized()

	var center_line_target: Vector2 = Vector2(
		global_position.x + away_predator.x * vision_radius,
		pond_bounds.get_center().y
	)
	var toward_center_line: Vector2 = center_line_target - global_position
	if toward_center_line.length_squared() <= 0.000001:
		toward_center_line = away_predator
	var desired_dir: Vector2 = (toward_center_line.normalized() * 0.62) + (away_predator * 0.38)

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if not nearest_data.is_empty():
		var dist: float = float(nearest_data["distance"])
		if dist <= out_avoid_distance * 0.95:
			var shore_point: Vector2 = nearest_data["point"] as Vector2
			desired_dir += _inward_direction_from_boundary(shore_point) * 1.15

	if desired_dir.length_squared() <= 0.000001:
		desired_dir = away_predator
	var desired_n: Vector2 = desired_dir.normalized()
	var desired: Vector2 = desired_n * top_speed * _turn_speed_factor(desired_n)
	return _steer_towards(desired) * 2.9


func _is_near_shore() -> bool:
	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if nearest_data.is_empty():
		return false
	return float(nearest_data["distance"]) <= feeding_start_distance


func _update_stall_recovery(delta: float) -> void:
	var inside_repel_zone: bool = _is_inside_spawner_repel_zone(0.0)
	if unstuck_zone_lock:
		if inside_repel_zone:
			unstuck_boost_remaining = unstuck_boost_seconds
		else:
			unstuck_zone_lock = false

	if behavior_state == BehaviorState.FLEE:
		stalled_time = 0.0
		return
	if not _is_in_upper_zone():
		stalled_time = 0.0
		return
	if not inside_repel_zone:
		stalled_time = maxf(0.0, stalled_time - delta * 0.5)
		return

	var slow_threshold: float = top_speed * stall_speed_ratio_threshold
	if velocity.length() <= slow_threshold:
		stalled_time += delta
		if stalled_time >= stall_trigger_seconds:
			unstuck_zone_lock = true
			unstuck_boost_remaining = unstuck_boost_seconds
			stalled_time = 0.0
	else:
		stalled_time = maxf(0.0, stalled_time - delta)


func _is_unstuck_active() -> bool:
	return unstuck_zone_lock or unstuck_boost_remaining > 0.0


func _compute_unstuck_escape() -> Vector2:
	var center: Vector2 = pond_bounds.get_center()
	var target: Vector2 = _unstuck_target_point()
	var desired_dir: Vector2 = (target - global_position)
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = center - global_position
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = Vector2.DOWN
	var desired_n: Vector2 = desired_dir.normalized()
	var desired: Vector2 = desired_n * top_speed * _turn_speed_factor(desired_n)
	return _steer_towards(desired) * unstuck_force_multiplier


func _is_in_upper_zone() -> bool:
	var upper_limit: float = pond_bounds.position.y + pond_bounds.size.y * upper_zone_ratio
	return global_position.y <= upper_limit


func _is_inside_spawner_repel_zone(extra_margin: float) -> bool:
	var nearest_data: Dictionary = _nearest_spawner_data()
	if nearest_data.is_empty():
		return false
	var dist: float = float(nearest_data["distance"])
	var radius: float = float(nearest_data["radius"])
	return dist <= radius + extra_margin


func _nearest_spawner_data() -> Dictionary:
	var best_distance: float = INF
	var best_radius: float = 0.0
	var best_position: Vector2 = Vector2.ZERO
	var found: bool = false
	for spawner_node: Node2D in _get_spawner_cache():
		var radius: float = float(spawner_node.get("repel_radius"))
		if radius <= 0.0:
			radius = spawner_repel_radius
		var dist: float = global_position.distance_to(spawner_node.global_position)
		if dist < best_distance:
			best_distance = dist
			best_radius = radius
			best_position = spawner_node.global_position
			found = true

	if not found:
		return {}

	return {
		"distance": best_distance,
		"radius": best_radius,
		"position": best_position
	}


func _egress_target_point() -> Vector2:
	var center: Vector2 = pond_bounds.get_center()
	return Vector2(center.x, pond_bounds.position.y + pond_bounds.size.y * 0.6)


func _unstuck_target_point() -> Vector2:
	var center: Vector2 = pond_bounds.get_center()
	return Vector2(center.x, pond_bounds.position.y + pond_bounds.size.y * 0.62)


func _draw() -> void:
	if not debug_gizmo_enabled:
		return

	var state_color: Color = Color(0.28, 0.88, 0.45, 0.8)
	if behavior_state == BehaviorState.FEED:
		state_color = Color(1.0, 0.83, 0.32, 0.9)
	elif behavior_state == BehaviorState.FLEE:
		state_color = Color(1.0, 0.34, 0.32, 0.9)
	elif spawn_egress_lock_remaining > 0.0:
		state_color = Color(0.42, 0.76, 1.0, 0.92)
	elif _is_unstuck_active():
		state_color = Color(1.0, 0.6, 0.14, 0.92)

	draw_arc(Vector2.ZERO, out_avoid_distance, 0.0, TAU, 64, Color(0.18, 0.92, 0.96, 0.56), maxf(1.0, gizmo_line_width - 0.2))
	draw_arc(Vector2.ZERO, feeding_start_distance, 0.0, TAU, 48, state_color, gizmo_line_width)
	if _is_unstuck_active():
		draw_arc(Vector2.ZERO, feeding_start_distance * 0.56, 0.0, TAU, 40, Color(1.0, 0.62, 0.2, 0.9), gizmo_line_width + 0.4)

	var upper_limit_y: float = pond_bounds.position.y + pond_bounds.size.y * upper_zone_ratio
	var upper_left: Vector2 = to_local(Vector2(pond_bounds.position.x, upper_limit_y))
	var upper_right: Vector2 = to_local(Vector2(pond_bounds.position.x + pond_bounds.size.x, upper_limit_y))
	draw_line(upper_left, upper_right, Color(0.55, 0.85, 1.0, 0.38), maxf(1.0, gizmo_line_width - 0.3))

	var nearest_spawner: Dictionary = _nearest_spawner_data()
	if not nearest_spawner.is_empty():
		var nearest_radius: float = float(nearest_spawner["radius"])
		var feed_block_radius: float = nearest_radius + repel_zone_feed_margin
		var nearest_dist: float = float(nearest_spawner["distance"])
		var nearest_position: Vector2 = nearest_spawner["position"] as Vector2
		var feed_block_color: Color = Color(1.0, 0.88, 0.2, 0.45)
		if nearest_dist <= feed_block_radius:
			feed_block_color = Color(1.0, 0.35, 0.22, 0.62)
		var spawner_local: Vector2 = to_local(nearest_position)
		draw_arc(spawner_local, feed_block_radius, 0.0, TAU, 96, feed_block_color, maxf(1.0, gizmo_line_width - 0.45))
		draw_line(Vector2.ZERO, spawner_local, Color(1.0, 0.92, 0.4, 0.7), maxf(1.0, gizmo_line_width - 0.4))

	var egress_target_local: Vector2 = to_local(_egress_target_point())
	draw_circle(egress_target_local, 4.0, Color(0.3, 0.78, 1.0, 0.8))
	if spawn_egress_lock_remaining > 0.0:
		draw_line(Vector2.ZERO, egress_target_local, Color(0.3, 0.78, 1.0, 0.8), gizmo_line_width)

	if _is_unstuck_active():
		var unstuck_target_local: Vector2 = to_local(_unstuck_target_point())
		draw_circle(unstuck_target_local, 4.0, Color(1.0, 0.58, 0.18, 0.88))
		draw_line(Vector2.ZERO, unstuck_target_local, Color(1.0, 0.58, 0.18, 0.88), gizmo_line_width + 0.2)

	for spawner_node: Node2D in _get_spawner_cache():
		var repel_radius: float = float(spawner_node.get("repel_radius"))
		if repel_radius <= 0.0:
			repel_radius = spawner_repel_radius
		draw_arc(to_local(spawner_node.global_position), repel_radius, 0.0, TAU, 96, Color(1.0, 0.47, 0.16, 0.5), maxf(1.0, gizmo_line_width - 0.3))

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if not nearest_data.is_empty():
		var shore_point_local: Vector2 = to_local(nearest_data["point"] as Vector2)
		draw_line(Vector2.ZERO, shore_point_local, Color(0.3, 0.75, 1.0, 0.85), gizmo_line_width)

	if _predator_valid():
		var predator_local: Vector2 = to_local(nearest_predator.global_position)
		draw_line(Vector2.ZERO, predator_local, Color(1.0, 0.25, 0.25, 0.95), gizmo_line_width + 0.5)

	if velocity.length_squared() > 0.000001:
		var velocity_line: Vector2 = velocity.normalized() * minf(30.0, velocity.length() * 0.25)
		draw_line(Vector2.ZERO, velocity_line, Color(0.98, 0.98, 0.98, 0.92), gizmo_line_width)

	if wander_heading.length_squared() > 0.000001:
		draw_line(Vector2.ZERO, wander_heading.normalized() * 22.0, Color(0.88, 0.3, 1.0, 0.85), gizmo_line_width)
