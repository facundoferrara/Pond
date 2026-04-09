extends Fish
class_name Pellet

@export_group("Pellet: Fish Advection")
@export var fish_influence_radius: float = 58.0
@export_range(-1.0, 1.0, 0.05) var approach_dot_threshold: float = 0.35
@export_range(0.0, 1.0, 0.05) var away_dot_threshold: float = 0.35
@export var approach_influence: float = 0.85
@export var tangent_influence: float = 1.55
@export var away_influence: float = 2.55
@export_range(0.05, 1.0, 0.05) var max_speed_ratio_to_fish: float = 0.70

@export_group("Pellet: River Flow")
@export var flow_bias_strength: float = 0.85
@export var flow_speed_factor: float = 0.30

@export_group("Pellet: Motion")
@export var pellet_boid_scale: float = 0.20
@export var drift_strength: float = 3.5
@export var drift_frequency: float = 0.9
@export var linear_damping: float = 0.8
@export var pellet_overlay_z_index: int = 120

var _nearby_fish: Array[Fish] = []
var _drift_phase: float = 0.0


func _ready() -> void:
	species = SpeciesRegistry.PELLET
	super._ready()


func reinitialize() -> void:
	super.reinitialize()
	z_index = pellet_overlay_z_index
	_drift_phase = randf_range(0.0, TAU)
	var flow_dir: Vector2 = (despawn_area_center - global_position)
	if flow_dir.length_squared() <= 0.000001:
		flow_dir = Vector2.DOWN
	velocity = flow_dir.normalized().rotated(randf_range(-0.35, 0.35)) * top_speed * 0.15


func _update_context() -> void:
	boid_neighbors.clear()
	_nearby_fish.clear()
	nearest_predator = null
	var query_radius: float = maxf(vision_radius, fish_influence_radius)
	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, query_radius)
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if other.species == SpeciesRegistry.PELLET:
			if distance <= vision_radius:
				boid_neighbors.append(other)
		elif distance <= fish_influence_radius:
			_nearby_fish.append(other)


func _update_behavior_state() -> void:
	behavior_state = BehaviorState.SCHOOL


func _compute_acceleration(delta: float) -> Vector2:
	var pellet_boid: Vector2 = _compute_boid_steering(boid_neighbors) * pellet_boid_scale
	var fish_advection: Vector2 = _compute_fish_advection()
	var flow_bias: Vector2 = _compute_flow_bias()
	var drift: Vector2 = _compute_drift(delta)
	var damping: Vector2 = - velocity * linear_damping
	return pellet_boid + fish_advection + flow_bias + drift + damping


func _compute_fish_advection() -> Vector2:
	if _nearby_fish.is_empty():
		return Vector2.ZERO

	var influence: Vector2 = Vector2.ZERO
	var strongest_fish_speed: float = 0.0
	for fish: Fish in _nearby_fish:
		var fish_speed: float = fish.velocity.length()
		if fish_speed <= 0.001:
			continue

		var fish_dir: Vector2 = fish.velocity / fish_speed
		var from_fish_to_pellet: Vector2 = global_position - fish.global_position
		var distance: float = from_fish_to_pellet.length()
		if distance <= 0.001:
			continue

		strongest_fish_speed = maxf(strongest_fish_speed, fish_speed)
		var radial_dir: Vector2 = from_fish_to_pellet / distance
		var heading_dot: float = fish_dir.dot(radial_dir)
		var distance_weight: float = 1.0 - clampf(distance / maxf(fish_influence_radius, 0.001), 0.0, 1.0)
		var speed_weight: float = clampf(fish_speed / maxf(fish.top_speed, 0.001), 0.2, 1.0)

		var influence_scalar: float = tangent_influence
		if heading_dot >= approach_dot_threshold:
			influence_scalar = approach_influence
		elif heading_dot <= -away_dot_threshold:
			influence_scalar = - away_influence

		influence += fish_dir * influence_scalar * distance_weight * speed_weight

	if influence.length_squared() <= 0.000001:
		return Vector2.ZERO

	var desired_speed: float = top_speed
	if strongest_fish_speed > 0.0:
		desired_speed = minf(desired_speed, strongest_fish_speed * max_speed_ratio_to_fish)
	var strength: float = clampf(influence.length(), 0.0, 1.0)
	var desired: Vector2 = influence.normalized() * desired_speed * lerpf(0.35, 1.0, strength)
	return _steer_towards(desired)


func _compute_flow_bias() -> Vector2:
	var to_despawn: Vector2 = despawn_area_center - global_position
	if to_despawn.length_squared() <= 0.000001:
		return Vector2.ZERO
	var desired: Vector2 = to_despawn.normalized() * top_speed * flow_speed_factor
	return _steer_towards(desired) * flow_bias_strength


func _compute_drift(delta: float) -> Vector2:
	_drift_phase += delta * drift_frequency
	var drift_dir: Vector2 = Vector2(cos(_drift_phase), sin(_drift_phase * 0.73))
	if drift_dir.length_squared() <= 0.000001:
		return Vector2.ZERO
	return drift_dir.normalized() * drift_strength


func _process_feeding(_delta: float) -> void:
	return
