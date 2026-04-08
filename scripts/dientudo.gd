extends Fish
class_name Dientudo

enum HuntState {
	IDLE,
	WINDING_UP,
	DARTING
}

@export var debug_gizmo_enabled: bool = false
@export var gizmo_line_width: float = 1.5

var hunt_state: HuntState = HuntState.IDLE
var target_prey: Fish = null
var starting_weight_original: float = 0.0
var max_size_growth_ratio: float = 1.2
@export var dart_wind_up_seconds: float = 0.5
@export var dart_duration_seconds: float = 1.0
@export var dart_cooldown_seconds: float = 5.0
@export var dash_speed_multiplier: float = 3.0
@export var dash_turn_rate_factor: float = 0.25
@export var dash_abort_edge_distance_factor: float = 0.5
@export var digestion_speed_g_per_sec: float = 30.0
var wind_up_timer: float = 0.0
var dart_timer: float = 0.0
var dart_cooldown_timer: float = 0.0
var digesting_mass_remaining_g: float = 0.0
var wander_heading: Vector2 = Vector2.RIGHT
var at_max_size: bool = false


func _ready() -> void:
	species = SpeciesDB.DIENTUDO
	super._ready()
	var species_data: Dictionary = SpeciesDB.get_species(SpeciesDB.DIENTUDO)
	max_size_growth_ratio = float(species_data.get("max_size_growth_ratio", max_size_growth_ratio))
	dart_wind_up_seconds = float(species_data.get("dart_wind_up_seconds", dart_wind_up_seconds))
	dart_duration_seconds = float(species_data.get("dart_duration_seconds", dart_duration_seconds))
	dart_cooldown_seconds = float(species_data.get("dart_cooldown_seconds", dart_cooldown_seconds))
	dash_speed_multiplier = float(species_data.get("dash_speed_multiplier", dash_speed_multiplier))
	dash_turn_rate_factor = float(species_data.get("dash_turn_rate_factor", dash_turn_rate_factor))
	digestion_speed_g_per_sec = float(species_data.get("digestion_speed_g_per_sec", digestion_speed_g_per_sec))
	starting_weight_original = weight


func reinitialize() -> void:
	super.reinitialize()
	hunt_state = HuntState.IDLE
	target_prey = null
	wind_up_timer = 0.0
	dart_timer = 0.0
	dart_cooldown_timer = 0.0
	digesting_mass_remaining_g = 0.0
	at_max_size = false
	starting_weight_original = weight
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))


func _process(delta: float) -> void:
	dart_cooldown_timer = maxf(0.0, dart_cooldown_timer - delta)
	digesting_mass_remaining_g = maxf(0.0, digesting_mass_remaining_g - digestion_speed_g_per_sec * delta)
	super._process(delta)
	if debug_gizmo_enabled and not pending_remove:
		queue_redraw()


func can_hunt() -> bool:
	if not is_predator:
		return false
	if at_max_size:
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
		if not other.can_eat_fish(self ):
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
		if not can_eat_fish(other):
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

	if at_max_size:
		behavior_state = BehaviorState.DESCEND
		return

	if target_prey != null and is_instance_valid(target_prey) and not target_prey.pending_remove and can_hunt():
		behavior_state = BehaviorState.FEED
	else:
		behavior_state = BehaviorState.SCHOOL
		hunt_state = HuntState.IDLE


func _compute_acceleration(delta: float) -> Vector2:
	if _predator_valid():
		return _steer_towards(get_escape_vector()) * 2.0

	if at_max_size:
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
	if not can_hunt() or not can_eat_fish(target_prey):
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
		dart_cooldown_timer = dart_cooldown_seconds
		return Vector2.ZERO

	if dart_cooldown_timer > 0.0:
		return _compute_wander(delta)

	if hunt_state == HuntState.IDLE:
		hunt_state = HuntState.WINDING_UP
		wind_up_timer = 0.0

	if hunt_state == HuntState.WINDING_UP:
		wind_up_timer += delta
		if wind_up_timer >= dart_wind_up_seconds:
			hunt_state = HuntState.DARTING
			wind_up_timer = 0.0
			dart_timer = 0.0
		var desired_windup: Vector2 = to_prey.normalized() * top_speed * 0.2
		return _steer_towards(desired_windup) * 0.5

	if hunt_state == HuntState.DARTING:
		dart_timer += delta
		
		# Check if too close to boundary and abort dash if necessary
		var boundary_data: Dictionary = _nearest_point_on_out_boundary(global_position)
		if not boundary_data.is_empty():
			var distance_to_boundary: float = float(boundary_data["distance"])
			if distance_to_boundary <= out_avoid_distance * dash_abort_edge_distance_factor:
				hunt_state = HuntState.IDLE
				dart_timer = 0.0
				dart_cooldown_timer = dart_cooldown_seconds
				return _compute_out_boundary_avoidance()
		
		if dart_timer >= dart_duration_seconds:
			hunt_state = HuntState.IDLE
			dart_timer = 0.0
			dart_cooldown_timer = dart_cooldown_seconds
			return _compute_wander(delta)

	var dash_speed: float = top_speed * dash_speed_multiplier
	var desired_dart: Vector2 = to_prey.normalized() * dash_speed
	var reduced_force: float = max_force * dash_turn_rate_factor
	var steer: Vector2 = desired_dart - velocity
	if steer.length() > reduced_force:
		steer = steer.normalized() * reduced_force
	return steer


func _consume_prey(prey: Fish) -> void:
	if prey == null or not is_instance_valid(prey) or prey.pending_remove:
		return
	if not can_eat_fish(prey):
		return

	var prey_weight: float = prey.weight
	var prey_points: float = prey.points
	var absorbed_mass: float = prey_weight * 0.2
	weight += absorbed_mass
	points += prey_points * 0.5
	digesting_mass_remaining_g += absorbed_mass

	prey.pending_remove = true
	FishPool.release(prey)

	var max_weight: float = starting_weight_original * max_size_growth_ratio
	if weight >= max_weight:
		at_max_size = true
		weight = max_weight


func _compute_wander(delta: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-1.8, 1.8) * delta)
	var desired: Vector2 = wander_heading * top_speed * 0.6
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
