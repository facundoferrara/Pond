extends Fish
class_name Dientudo

signal prey_predated(prey_position: Vector2, prey_weight_g: float, predator_player: int, prey_player: int, prey_species: StringName, prey_fish_id: int, prey_feed_count: int)

enum HuntState {
	IDLE,
	CHASING
}

@export_group("Dientudo: Debug")
## Draws predator/hunt gizmos in editor and runtime.
@export var debug_gizmo_enabled: bool = false
## Line thickness for debug gizmos.
@export var gizmo_line_width: float = 1.5

var hunt_state: HuntState = HuntState.IDLE
var target_prey: Fish = null
@export_group("Dientudo: Hunt")
## Multiplier for chase steering while pursuing prey.
@export var chase_steering_multiplier: float = 2.3
## Blend strength that pulls wander toward pond center.
@export_range(0.0, 1.0, 0.01) var roam_center_bias_strength: float = 0.45

@export_group("Dientudo: Digestion")
## Digested mass per second after consuming prey.
@export var digestion_speed_g_per_sec: float = 30.0
var digesting_mass_remaining_g: float = 0.0
var wander_heading: Vector2 = Vector2.RIGHT
var point_mass_remainder_g: float = 0.0


func _ready() -> void:
	species = SpeciesDB.DIENTUDO
	super._ready()


func _apply_species_defaults() -> void:
	super._apply_species_defaults()
	var species_data: Dictionary = SpeciesDB.get_species(species)
	chase_steering_multiplier = float(species_data.get("chase_steering_multiplier", chase_steering_multiplier))
	roam_center_bias_strength = float(species_data.get("roam_center_bias_strength", roam_center_bias_strength))
	digestion_speed_g_per_sec = float(species_data.get("digestion_speed_g_per_sec", digestion_speed_g_per_sec))


func reinitialize() -> void:
	super.reinitialize()
	hunt_state = HuntState.IDLE
	target_prey = null
	digesting_mass_remaining_g = 0.0
	point_mass_remainder_g = 0.0
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))


func _process(delta: float) -> void:
	digesting_mass_remaining_g = maxf(0.0, digesting_mass_remaining_g - digestion_speed_g_per_sec * delta)
	super._process(delta)
	if debug_gizmo_enabled and not pending_remove:
		queue_redraw()


func can_hunt() -> bool:
	if not is_predator:
		return false
	if not can_feed():
		return false
	return digesting_mass_remaining_g <= 0.001


func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null
	target_prey = null
	var nearest_distance: float = INF
	var nearest_prey_distance: float = INF

	for other: Fish in SpatialGrid.get_potential_predators():
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if not other.can_eat_target(self ):
			continue
		if other.weight < weight * maxf(flee_override_predator_ratio, 1.0):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance > predator_detection_radius:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_predator = other

	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, vision_radius)
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if other.species != species:
			continue
		if global_position.distance_to(other.global_position) <= vision_radius:
			boid_neighbors.append(other)

	if not can_hunt():
		return

	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if not can_eat_target(other):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance > vision_radius:
			continue
		if distance < nearest_prey_distance:
			nearest_prey_distance = distance
			target_prey = other


func _update_behavior_state() -> void:
	if _predator_valid():
		behavior_state = BehaviorState.FLEE
		hunt_state = HuntState.IDLE
		target_prey = null
		return
	if not can_feed():
		behavior_state = BehaviorState.DESCEND
		hunt_state = HuntState.IDLE
		target_prey = null
		return

	if target_prey != null and is_instance_valid(target_prey) and not target_prey.pending_remove and can_hunt():
		behavior_state = BehaviorState.FEED
	else:
		behavior_state = BehaviorState.SCHOOL
		hunt_state = HuntState.IDLE


func _compute_acceleration(delta: float) -> Vector2:
	if _predator_valid():
		return _steer_towards(get_escape_vector()) * 2.0
	if behavior_state == BehaviorState.DESCEND:
		return _steer_towards_despawn()

	if behavior_state == BehaviorState.FEED and target_prey != null and is_instance_valid(target_prey):
		return _compute_hunt_acceleration(delta)

	var boid: Vector2 = _compute_boid_steering(boid_neighbors)
	var wander: Vector2 = _compute_wander(delta)
	return boid + wander


func _compute_hunt_acceleration(delta: float) -> Vector2:
	if target_prey == null or not is_instance_valid(target_prey) or target_prey.pending_remove:
		hunt_state = HuntState.IDLE
		return Vector2.ZERO
	if not can_hunt() or not can_eat_target(target_prey):
		hunt_state = HuntState.IDLE
		target_prey = null
		return Vector2.ZERO

	var to_prey: Vector2 = target_prey.global_position - global_position
	var distance_to_prey: float = to_prey.length()
	if distance_to_prey > vision_radius:
		hunt_state = HuntState.IDLE
		target_prey = null
		return _compute_wander(delta)

	if distance_to_prey <= eat_radius:
		_consume_prey(target_prey)
		target_prey = null
		hunt_state = HuntState.IDLE
		return Vector2.ZERO

	# Continuous chase replaces legacy dart/wind-up states.
	hunt_state = HuntState.CHASING
	var desired: Vector2 = to_prey.normalized() * top_speed
	return _steer_towards(desired) * chase_steering_multiplier


func _consume_prey(prey: Fish) -> void:
	if prey == null or not is_instance_valid(prey) or prey.pending_remove:
		return
	if not can_eat_fish(prey):
		return

	var prey_weight: float = prey.weight
	var prey_position: Vector2 = prey.global_position
	var prey_player: int = prey.player
	var prey_species: StringName = prey.species
	var prey_fish_id: int = prey.get_instance_id()
	var prey_feed_count: int = prey.get_successful_feed_count()
	var absorbed_mass: float = prey_weight * 0.1
	point_mass_remainder_g += prey_weight
	var earned_points: int = int(floor(point_mass_remainder_g / 50.0))
	if earned_points > 0:
		add_points(earned_points)
		point_mass_remainder_g -= float(earned_points) * 50.0
	mark_successful_feed(absorbed_mass)
	digesting_mass_remaining_g += absorbed_mass
	prey_predated.emit(prey_position, prey_weight, player, prey_player, prey_species, prey_fish_id, prey_feed_count)

	prey.pending_remove = true
	FishPool.release(prey)


func _compute_wander(delta: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-1.8, 1.8) * delta)
	var random_dir: Vector2 = wander_heading
	if random_dir.length_squared() <= 0.000001:
		random_dir = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	var center_dir: Vector2 = (_pond_center_point() - global_position)
	if center_dir.length_squared() <= 0.000001:
		center_dir = random_dir
	var center_t: float = clampf(roam_center_bias_strength, 0.0, 1.0)
	var desired_dir: Vector2 = (random_dir.normalized() * (1.0 - center_t)) + (center_dir.normalized() * center_t)
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = random_dir.normalized()
	var desired: Vector2 = desired_dir.normalized() * top_speed * 0.6
	return _steer_towards(desired) * 0.7


func _steer_towards_despawn() -> Vector2:
	var to_despawn: Vector2 = despawn_area_center - global_position
	if to_despawn.length_squared() <= 0.001:
		return Vector2.ZERO
	var desired: Vector2 = to_despawn.normalized() * top_speed
	return _steer_towards(desired) * 1.5


func _draw() -> void:
	if not debug_gizmo_enabled:
		return

	draw_arc(Vector2.ZERO, vision_radius, 0.0, TAU, 64, Color(1.0, 0.7, 0.15, 0.55), maxf(1.0, gizmo_line_width - 0.2))
	draw_arc(Vector2.ZERO, eat_radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.2, 0.8), gizmo_line_width)

	if target_prey != null and is_instance_valid(target_prey) and not target_prey.pending_remove:
		draw_line(Vector2.ZERO, to_local(target_prey.global_position), Color(1.0, 0.15, 0.15, 0.95), gizmo_line_width)

	if _predator_valid():
		draw_line(Vector2.ZERO, to_local(nearest_predator.global_position), Color(0.3, 0.8, 1.0, 0.95), gizmo_line_width)

	if velocity.length_squared() > 0.000001:
		var velocity_line: Vector2 = velocity.normalized() * minf(32.0, velocity.length() * 0.35)
		draw_line(Vector2.ZERO, velocity_line, Color(0.95, 0.95, 0.95, 0.9), gizmo_line_width)
