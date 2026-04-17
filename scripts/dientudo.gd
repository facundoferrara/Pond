extends Fish
class_name Dientudo

## Predator fish with a simple hunt state machine (IDLE/CHASING).
## Consumes prey for mass gain and adds digestion cooldown.

signal prey_predated(prey_position: Vector2, prey_weight_g: float, predator_species: StringName, predator_fish_id: int, prey_species: StringName, prey_fish_id: int, prey_feed_count: int, absorbed_mass_g: float)

enum HuntState {
	IDLE,
	CHASING
}

@export_group("Dientudo: Debug")
## Draws predator/hunt gizmos in editor and runtime.
@export var debug_gizmo_enabled: bool = false
## Line thickness for debug gizmos.
@export var gizmo_line_width: float = 1.5

## Current hunt state used by the chase state machine.
var hunt_state: HuntState = HuntState.IDLE
## Current selected prey target while hunting.
var target_prey: Fish = null
@export_group("Dientudo: Hunt")
## Multiplier for chase steering while pursuing prey.
@export var chase_steering_multiplier: float = 2.3

@export_group("Dientudo: Movement")
## Center pull while searching for prey without a current target.
var search_wander_center_bias_strength: float = 0.1
## Speed ratio used while searching for prey.
var search_wander_speed_factor: float = 0.85
## Steering multiplier used while searching for prey.
var search_wander_steer_multiplier: float = 0.82
## Max heading turn rate (rad/s) while searching for prey.
var search_wander_turn_rate_rad_per_sec: float = 0.8
## Center pull while descending due to lifecycle constraints.
var descend_wander_center_bias_strength: float = 0.45
## Speed ratio used while descending.
var descend_wander_speed_factor: float = 0.6
## Steering multiplier used while descending.
var descend_wander_steer_multiplier: float = 0.7
## Max heading turn rate (rad/s) while descending.
var descend_wander_turn_rate_rad_per_sec: float = 1.8

@export_group("Dientudo: Exit")
## Strength multiplier for age-ramped descend pull.
@export var descend_bias_strength_multiplier: float = 1.15

@export_group("Dientudo: Digestion")
## Digested mass per second after consuming prey.
@export var digestion_speed_g_per_sec: float = 30.0
## Fraction of prey mass converted into predator growth and digestion backlog.
@export_range(0.0, 1.0, 0.01) var prey_mass_absorption_ratio: float = 0.5
## Remaining digesting mass that blocks repeated hunts.
var digesting_mass_remaining_g: float = 0.0
## Heading accumulator used by random wander.
var wander_heading: Vector2 = Vector2.RIGHT


## Sets species before base initialization.
func _ready() -> void:
	species = SpeciesDB.DIENTUDO
	super._ready()


## Applies species database overrides for hunt/exit/digestion tuning.
func _apply_species_defaults() -> void:
	super._apply_species_defaults()
	var species_data: Dictionary = SpeciesDB.get_species(species)
	chase_steering_multiplier = float(species_data.get("chase_steering_multiplier", chase_steering_multiplier))
	search_wander_center_bias_strength = float(species_data.get("search_wander_center_bias_strength", search_wander_center_bias_strength))
	search_wander_speed_factor = float(species_data.get("search_wander_speed_factor", search_wander_speed_factor))
	search_wander_steer_multiplier = float(species_data.get("search_wander_steer_multiplier", search_wander_steer_multiplier))
	search_wander_turn_rate_rad_per_sec = float(species_data.get("search_wander_turn_rate_rad_per_sec", search_wander_turn_rate_rad_per_sec))
	descend_wander_center_bias_strength = float(species_data.get("descend_wander_center_bias_strength", descend_wander_center_bias_strength))
	descend_wander_speed_factor = float(species_data.get("descend_wander_speed_factor", descend_wander_speed_factor))
	descend_wander_steer_multiplier = float(species_data.get("descend_wander_steer_multiplier", descend_wander_steer_multiplier))
	descend_wander_turn_rate_rad_per_sec = float(species_data.get("descend_wander_turn_rate_rad_per_sec", descend_wander_turn_rate_rad_per_sec))
	descend_bias_strength_multiplier = float(species_data.get("descend_bias_strength_multiplier", descend_bias_strength_multiplier))
	digestion_speed_g_per_sec = float(species_data.get("digestion_speed_g_per_sec", digestion_speed_g_per_sec))
	prey_mass_absorption_ratio = float(species_data.get("prey_mass_absorption_ratio", prey_mass_absorption_ratio))


## Resets hunt and digestion runtime state when reused from pool.
func reinitialize() -> void:
	super.reinitialize()
	hunt_state = HuntState.IDLE
	target_prey = null
	digesting_mass_remaining_g = 0.0
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))


## Drains digestion backlog and updates optional debug gizmos.
func _process(delta: float) -> void:
	digesting_mass_remaining_g = maxf(0.0, digesting_mass_remaining_g - digestion_speed_g_per_sec * delta)
	super._process(delta)
	if debug_gizmo_enabled and not pending_remove:
		queue_redraw()


## Returns true only when predator mode, feeding eligibility, and digestion cooldown permit hunts.
func can_hunt() -> bool:
	if not is_predator:
		return false
	if not can_feed():
		return false
	return digesting_mass_remaining_g <= 0.001


## Refreshes nearby predators, boid peers, and the nearest huntable prey.
func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null
	target_prey = null
	var nearest_distance: float = INF
	var nearest_prey_distance: float = INF

	# Predator detection: distance-gate before can_eat_target to skip far predators.
	for other: Fish in SpatialGrid.get_potential_predators():
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance > predator_detection_radius:
			continue
		if not other.can_eat_target(self ):
			continue
		if other.weight < weight * maxf(flee_override_predator_ratio, 1.0):
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_predator = other

	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, vision_radius)
	# Cache can_hunt() so the loop below avoids re-evaluating the same condition per fish.
	var hunting: bool = can_hunt()
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		# Boid neighbor accumulation.
		if other.species == species and distance <= vision_radius:
			boid_neighbors.append(other)
		# Prey selection: single pass, skipped entirely when not hunting.
		if hunting and distance <= vision_radius and can_eat_target(other):
			if distance < nearest_prey_distance:
				nearest_prey_distance = distance
				target_prey = other


## Selects flee/descend/feed/school state and keeps hunt state synchronized.
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


## Computes steering for flee, descend, hunt, and school modes.
func _compute_acceleration(delta: float) -> Vector2:
	if _predator_valid():
		return _steer_towards(get_escape_vector()) * 2.0
	if behavior_state == BehaviorState.DESCEND:
		var descend_bias: Vector2 = _compute_guppy_style_age_despawn_bias(descend_bias_strength_multiplier)
		var glide: Vector2 = (_compute_boid_steering(boid_neighbors) * 0.35) + (_compute_descend_wander(delta) * 0.45)
		return glide + descend_bias

	if behavior_state == BehaviorState.FEED and target_prey != null and is_instance_valid(target_prey):
		return _compute_hunt_acceleration(delta)

	var boid: Vector2 = _compute_boid_steering(boid_neighbors)
	var boundary_proximity: float = _compute_boundary_proximity_ratio()
	var wander: Vector2 = _compute_search_wander(delta) * (1.0 - boundary_proximity)
	return boid + wander


## Handles chase steering and close-range prey consumption.
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
		return _compute_search_wander(delta)

	if distance_to_prey <= eat_radius:
		_consume_prey(target_prey)
		target_prey = null
		hunt_state = HuntState.IDLE
		return Vector2.ZERO

	# Continuous chase replaces legacy dart/wind-up states.
	hunt_state = HuntState.CHASING
	var desired: Vector2 = to_prey.normalized() * top_speed
	return _steer_towards(desired) * chase_steering_multiplier


## Applies prey consumption effects: mass gain, digestion backlog, and analytics signal.
func _consume_prey(prey: Fish) -> void:
	if prey == null or not is_instance_valid(prey) or prey.pending_remove:
		return
	if not can_eat_fish(prey):
		return

	var prey_weight: float = prey.weight
	var prey_position: Vector2 = prey.global_position
	var prey_species: StringName = prey.species
	var prey_fish_id: int = prey.get_instance_id()
	var prey_feed_count: int = prey.get_successful_feed_count()
	var absorbed_mass: float = prey_weight * clampf(prey_mass_absorption_ratio, 0.0, 1.0)
	mark_successful_feed(absorbed_mass)
	digesting_mass_remaining_g += absorbed_mass
	prey_predated.emit(prey_position, prey_weight, species, get_instance_id(), prey_species, prey_fish_id, prey_feed_count, absorbed_mass)

	prey.pending_remove = true
	FishPool.release(prey)


func get_diagnostic_feed_target() -> Fish:
	if target_prey == null or not is_instance_valid(target_prey) or target_prey.pending_remove:
		return null
	return target_prey


## Wide meander used while searching for prey with no locked target.
func _compute_search_wander(delta: float) -> Vector2:
	return _compute_wander_profile(
		delta,
		search_wander_center_bias_strength,
		search_wander_speed_factor,
		search_wander_steer_multiplier,
		search_wander_turn_rate_rad_per_sec
	)


## Lower-energy wander used when descending due to lifecycle state.
func _compute_descend_wander(delta: float) -> Vector2:
	return _compute_wander_profile(
		delta,
		descend_wander_center_bias_strength,
		descend_wander_speed_factor,
		descend_wander_steer_multiplier,
		descend_wander_turn_rate_rad_per_sec
	)


## Shared wander profile helper for search and descend movement tuning.
func _compute_wander_profile(delta: float, center_bias_strength: float, speed_factor: float, steer_multiplier: float, turn_rate_rad_per_sec: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-turn_rate_rad_per_sec, turn_rate_rad_per_sec) * delta)
	var random_dir: Vector2 = wander_heading
	if random_dir.length_squared() <= 0.000001:
		random_dir = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	var center_dir: Vector2 = (_pond_center_point() - global_position)
	if center_dir.length_squared() <= 0.000001:
		center_dir = random_dir
	var center_t: float = clampf(center_bias_strength, 0.0, 1.0)
	var desired_dir: Vector2 = (random_dir.normalized() * (1.0 - center_t)) + (center_dir.normalized() * center_t)
	if desired_dir.length_squared() <= 0.000001:
		desired_dir = random_dir.normalized()
	var desired: Vector2 = desired_dir.normalized() * top_speed * maxf(speed_factor, 0.0)
	return _steer_towards(desired) * maxf(steer_multiplier, 0.0)


## Computes how close the predator is to the boundary (0 = safe, 1 = at/past avoid threshold).
func _compute_boundary_proximity_ratio() -> float:
	if out_boundary_polygon.size() < 3:
		return 0.0
	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if nearest_data.is_empty():
		return 0.0
	var distance: float = nearest_data.get("distance", 0.0) as float
	if distance >= out_avoid_distance:
		return 0.0
	var proximity: float = 1.0 - clampf(distance / maxf(out_avoid_distance, 0.001), 0.0, 1.0)
	return proximity * proximity


## Legacy helper for direct despawn steering (kept for compatibility/debug use).
func _steer_towards_despawn() -> Vector2:
	var to_despawn: Vector2 = despawn_area_center - global_position
	if to_despawn.length_squared() <= 0.001:
		return Vector2.ZERO
	var desired: Vector2 = to_despawn.normalized() * top_speed
	return _steer_towards(desired) * 1.5


## Draws optional hunt/predator debug overlays.
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
