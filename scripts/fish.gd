extends Node2D
class_name Fish

signal fish_exited(player_id: int, fish_points: float)

enum BehaviorState {
	SCHOOL,
	FLEE,
	FEED,
	DESCEND
}

@onready var sprite: Sprite2D = $Sprite2D

@export var species: StringName = SpeciesDB.GUPPY
@export_range(1, 2) var player: int = 1
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export var starting_energy: float = 20.0
@export var energy: float = 20.0
@export var weight: float = 50.0
@export var base_points: float = 1.0
@export var points: float = 1.0
@export var top_speed: float = 140.0
@export var is_predator: bool = false
@export_range(0.05, 1.0, 0.05) var prey_weight_ratio_limit: float = 0.5

@export var vision_radius: float = 120.0
@export var predator_detection_radius: float = 120.0
@export var separation_radius: float = 30.0
@export var max_force: float = 170.0
@export var life_span_seconds: float = 60.0
@export var age_speed_multiplier: float = 1.0
@export var age_exit_bias: float = 240.0
@export var hunger_rate: float = 1.2
@export var eat_radius: float = 15.0
@export var heading_offset_radians: float = PI / 2.0
@export_range(0.001, 100.0, 0.001) var visual_scale_multiplier: float = 2.0
@export var scale_reference_weight_g: float = 50.0
@export var out_touch_distance: float = 8.0
@export var out_avoid_distance: float = 64.0
@export var debug_facing: bool = false

var velocity: Vector2 = Vector2.ZERO
var age_seconds: float = 0.0
var pending_remove: bool = false
var is_out_of_game: bool = false
var behavior_state: BehaviorState = BehaviorState.SCHOOL
var boid_neighbors: Array[Fish] = []
var nearest_predator: Fish = null
var despawn_area_center: Vector2 = Vector2(640.0, 540.0)
var boid_weights: Dictionary = {
	"separation": 1.5,
	"alignment": 0.9,
	"cohesion": 0.8
}
var pond_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
var out_boundary_polygon: PackedVector2Array = PackedVector2Array()
var previous_global_position: Vector2 = Vector2.ZERO
var warned_facing_no_motion: bool = false
var source_spawner: NodePath = NodePath()
var spawner_repel_radius: float = 340.0
var spawner_repel_force_multiplier: float = 1.8

## Cached spawner nodes, populated on first use (spawners outlive all fish).
var _cached_spawners: Array[Node2D] = []
## Centroid of out_boundary_polygon, computed once in configure_out_boundary().
var _cached_pond_center: Vector2 = Vector2.ZERO
var _pond_center_valid: bool = false
## Per-fish frame offset so context updates are staggered across the population.
var _context_frame_offset: int = 0

const _CONTEXT_UPDATE_INTERVAL: int = 3


func _ready() -> void:
	add_to_group("fish")
	_context_frame_offset = randi() % _CONTEXT_UPDATE_INTERVAL
	_apply_species_defaults()
	if velocity == Vector2.ZERO:
		velocity = Vector2.RIGHT.rotated(randf_range(-0.55, 0.55)) * top_speed * 0.35
	previous_global_position = global_position
	_refresh_visual()
	_refresh_scale()


## Resets runtime state so a pooled fish can be re-used without re-instantiation.
## Call AFTER configure_from_zoo() so top_speed is already set from species data.
func reinitialize() -> void:
	pending_remove = false
	is_out_of_game = false
	age_seconds = 0.0
	age_speed_multiplier = 1.0
	boid_neighbors.clear()
	nearest_predator = null
	behavior_state = BehaviorState.SCHOOL
	warned_facing_no_motion = false
	points = base_points
	velocity = Vector2.RIGHT.rotated(randf_range(-0.55, 0.55)) * top_speed * 0.35
	previous_global_position = global_position


func configure_from_zoo(species_name: StringName, owner_player: int, tint: Color, bounds: Rect2) -> void:
	species = species_name
	player = owner_player
	color = tint
	pond_bounds = bounds
	previous_global_position = global_position
	_apply_species_defaults()
	_refresh_visual()
	_refresh_scale()


func set_source_spawner(spawner_path: NodePath) -> void:
	source_spawner = spawner_path


func configure_despawn_area(center: Vector2) -> void:
	despawn_area_center = center


func configure_out_boundary(polygon: PackedVector2Array, touch_distance: float, avoid_distance: float) -> void:
	out_boundary_polygon = polygon
	out_touch_distance = touch_distance
	out_avoid_distance = avoid_distance
	# Pre-compute centroid so _pond_center_point() is O(1) for the life of this fish.
	if polygon.size() >= 3:
		var accum: Vector2 = Vector2.ZERO
		for pt: Vector2 in polygon:
			accum += pt
		_cached_pond_center = accum / float(polygon.size())
		_pond_center_valid = true
	else:
		_pond_center_valid = false


func _age_ratio() -> float:
	return clampf(age_seconds / maxf(life_span_seconds, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if pending_remove:
		return

	age_seconds += delta * maxf(age_speed_multiplier, 0.0)
	energy = max(0.0, energy - hunger_rate * delta)

	# Stagger expensive context updates across consecutive frames.
	if (Engine.get_process_frames() + _context_frame_offset) % _CONTEXT_UPDATE_INTERVAL == 0:
		_update_context()
		_update_behavior_state()
	var accel: Vector2 = _compute_acceleration(delta)
	accel += _compute_spawner_repulsion()
	accel += _compute_out_boundary_avoidance()

	velocity += accel * delta
	if velocity.length() > top_speed:
		velocity = velocity.normalized() * top_speed
	position += velocity * delta
	_keep_inside_pond()

	_update_orientation()
	_process_feeding(delta)
	_refresh_scale()

	is_out_of_game = not _is_inside_pond(global_position)
	if _should_exit():
		pending_remove = true
		fish_exited.emit(player, points)
		FishPool.release(self )


func _apply_species_defaults() -> void:
	var species_data: Dictionary = SpeciesDB.get_species(species)
	starting_energy = float(species_data.get("starting_energy", starting_energy))
	energy = starting_energy
	weight = float(species_data.get("starting_weight", weight))
	base_points = float(species_data.get("base_points", base_points))
	points = base_points
	top_speed = float(species_data.get("top_speed", top_speed))
	is_predator = bool(species_data.get("is_predator", is_predator))
	prey_weight_ratio_limit = float(species_data.get("prey_weight_ratio_limit", prey_weight_ratio_limit))
	vision_radius = float(species_data.get("vision_radius", vision_radius))
	predator_detection_radius = float(species_data.get("predator_detection_radius", vision_radius))
	separation_radius = float(species_data.get("separation_radius", separation_radius))
	max_force = float(species_data.get("max_force", max_force))
	life_span_seconds = float(species_data.get("life_span_seconds", life_span_seconds))
	age_exit_bias = float(species_data.get("age_exit_bias", age_exit_bias))
	hunger_rate = float(species_data.get("hunger_rate", hunger_rate))
	eat_radius = float(species_data.get("eat_radius", eat_radius))
	boid_weights = species_data.get("boid_weights", boid_weights) as Dictionary
	var texture_path: String = String(species_data.get("texture_path", ""))
	if texture_path != "" and _ensure_sprite():
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			sprite.texture = texture


func _compute_boid_steering(neighbors: Array[Fish]) -> Vector2:
	var neighbor_count: int = 0
	var separation_vector: Vector2 = Vector2.ZERO
	var alignment_vector: Vector2 = Vector2.ZERO
	var cohesion_center: Vector2 = Vector2.ZERO

	for other: Fish in neighbors:
		if not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance <= 0.001:
			continue

		neighbor_count += 1
		alignment_vector += other.velocity
		cohesion_center += other.global_position
		if distance < separation_radius:
			separation_vector += offset / max(distance, 0.001)

	if neighbor_count == 0:
		return Vector2.ZERO

	var alignment_desired: Vector2 = alignment_vector / float(neighbor_count)
	if alignment_desired.length() > 0.001:
		alignment_desired = alignment_desired.normalized() * top_speed

	var cohesion_target: Vector2 = (cohesion_center / float(neighbor_count)) - global_position
	if cohesion_target.length() > 0.001:
		cohesion_target = cohesion_target.normalized() * top_speed

	if separation_vector.length() > 0.001:
		separation_vector = separation_vector.normalized() * top_speed

	var separation_weight: float = float(boid_weights.get("separation", 1.5))
	var alignment_weight: float = float(boid_weights.get("alignment", 0.9))
	var cohesion_weight: float = float(boid_weights.get("cohesion", 0.8))

	var separation_steer: Vector2 = _steer_towards(separation_vector) * separation_weight
	var alignment_steer: Vector2 = _steer_towards(alignment_desired) * alignment_weight
	var cohesion_steer: Vector2 = _steer_towards(cohesion_target) * cohesion_weight
	return separation_steer + alignment_steer + cohesion_steer


func _steer_towards(desired_velocity: Vector2) -> Vector2:
	if desired_velocity.length() <= 0.001:
		return Vector2.ZERO
	var steer: Vector2 = desired_velocity - velocity
	if steer.length() > max_force:
		steer = steer.normalized() * max_force
	return steer


func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null
	var nearest_distance: float = INF

	# Boid neighbors via spatial grid (O(k) instead of O(N)).
	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, vision_radius)
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if global_position.distance_to(other.global_position) <= vision_radius:
			boid_neighbors.append(other)

	# Predator detection from small potential-predator list (predator species only).
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


func _update_behavior_state() -> void:
	if _predator_valid():
		behavior_state = BehaviorState.FLEE
		return

	# Aging/descend state is currently disabled.
	behavior_state = BehaviorState.SCHOOL


func _compute_acceleration(_delta: float) -> Vector2:
	return Vector2.ZERO


func _process_feeding(_delta: float) -> void:
	pass


func can_hunt() -> bool:
	return is_predator


func can_eat_fish(target: Fish) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or target.pending_remove:
		return false
	if not can_hunt():
		return false
	if target.species == species and target.player == player:
		return false
	return target.weight <= weight * prey_weight_ratio_limit


func _predator_valid() -> bool:
	return nearest_predator != null and is_instance_valid(nearest_predator)


func get_escape_vector() -> Vector2:
	if not _predator_valid():
		return Vector2.ZERO
	var away: Vector2 = global_position - nearest_predator.global_position
	if away.length() <= 0.001:
		return Vector2.ZERO
	return away.normalized() * top_speed


func _ensure_sprite() -> bool:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	return sprite != null


func _refresh_visual() -> void:
	if not _ensure_sprite():
		return
	sprite.modulate = color


func _refresh_scale() -> void:
	if not _ensure_sprite():
		return
	var normalized_mass: float = maxf(weight, 0.001) / maxf(scale_reference_weight_g, 0.001)
	var base_scaled: float = clampf(0.01 * pow(normalized_mass, 1.0 / 3.0), 0.005, 0.03)
	var scaled: float = base_scaled * visual_scale_multiplier
	sprite.scale = Vector2.ONE * scaled


func set_weight_grams(new_weight: float) -> void:
	weight = maxf(0.001, new_weight)
	_refresh_scale()


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
	global_rotation = atan2(displacement.y, displacement.x)
	sprite.rotation = heading_offset_radians
	previous_global_position = global_position


func _compute_out_boundary_avoidance() -> Vector2:
	if out_boundary_polygon.size() < 3:
		return Vector2.ZERO

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if nearest_data.is_empty():
		return Vector2.ZERO

	var distance: float = float(nearest_data["distance"])
	if distance >= out_avoid_distance:
		return Vector2.ZERO

	var closest_point: Vector2 = nearest_data["point"] as Vector2
	var inside_pond: bool = _is_inside_pond(global_position)
	var away: Vector2 = global_position - closest_point
	if not inside_pond:
		away = closest_point - global_position
	if away.length_squared() <= 0.000001:
		away = _inward_direction_from_boundary(closest_point)
	if away.length_squared() <= 0.000001:
		return Vector2.ZERO

	var desired: Vector2 = away.normalized() * top_speed
	var strength: float = 1.0 - clampf(distance / max(out_avoid_distance, 0.0001), 0.0, 1.0)
	# Softer onset near the boundary limit, while still ramping strongly close to shore.
	var scaled_strength: float = 0.08 + pow(strength, 3.0) * 1.35
	return _steer_towards(desired) * (2.2 * scaled_strength)


func _get_spawner_cache() -> Array[Node2D]:
	if _cached_spawners.is_empty():
		for node: Node in get_tree().get_nodes_in_group("fish_spawners"):
			if node is Node2D:
				_cached_spawners.append(node as Node2D)
	return _cached_spawners


func _compute_spawner_repulsion() -> Vector2:
	var spawners: Array[Node2D] = _get_spawner_cache()
	if spawners.is_empty():
		return Vector2.ZERO

	var total: Vector2 = Vector2.ZERO
	for node: Node2D in spawners:
		var spawner_node: Node2D = node
		var radius: float = float(spawner_node.get("repel_radius"))
		if radius <= 0.0:
			radius = spawner_repel_radius

		var to_fish: Vector2 = global_position - spawner_node.global_position
		var distance: float = to_fish.length()
		if distance >= radius:
			continue

		if to_fish.length_squared() <= 0.000001:
			to_fish = Vector2.RIGHT.rotated(randf_range(-PI, PI))

		var proximity: float = 1.0 - clampf(distance / max(radius, 0.0001), 0.0, 1.0)
		var repel_multiplier: float = float(spawner_node.get("repel_force_multiplier"))
		if repel_multiplier <= 0.0:
			repel_multiplier = spawner_repel_force_multiplier

		var desired: Vector2 = to_fish.normalized() * top_speed
		# Push starts earlier near the zone edge and ramps up strongly deeper inside.
		var curved_proximity: float = pow(proximity, 1.4)
		var scaled_strength: float = 0.30 + curved_proximity * 1.20
		total += _steer_towards(desired) * (repel_multiplier * 2.1 * scaled_strength)

	return total


func _is_touching_out_boundary(point: Vector2) -> bool:
	if out_boundary_polygon.size() < 3:
		return false
	var nearest_data: Dictionary = _nearest_point_on_out_boundary(point)
	if nearest_data.is_empty():
		return false
	return float(nearest_data["distance"]) <= out_touch_distance


func _nearest_point_on_out_boundary(point: Vector2) -> Dictionary:
	if out_boundary_polygon.size() < 3:
		return {}

	var best_distance: float = INF
	var best_point: Vector2 = Vector2.ZERO
	var best_tangent: Vector2 = Vector2.RIGHT
	for i: int in range(out_boundary_polygon.size()):
		var a: Vector2 = out_boundary_polygon[i]
		var b: Vector2 = out_boundary_polygon[(i + 1) % out_boundary_polygon.size()]
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var dist: float = point.distance_to(candidate)
		if dist < best_distance:
			best_distance = dist
			best_point = candidate
			var segment: Vector2 = b - a
			if segment.length_squared() > 0.000001:
				best_tangent = segment.normalized()

	return {
		"point": best_point,
		"distance": best_distance,
		"tangent": best_tangent
	}


func _should_exit() -> bool:
	return global_position.distance_to(pond_bounds.get_center()) > max(pond_bounds.size.x, pond_bounds.size.y) * 2.0


func _is_inside_pond(point: Vector2) -> bool:
	if out_boundary_polygon.size() < 3:
		return pond_bounds.has_point(point)
	return Geometry2D.is_point_in_polygon(point, out_boundary_polygon)


func _keep_inside_pond() -> void:
	if _is_inside_pond(global_position):
		return

	var nearest_data: Dictionary = _nearest_point_on_out_boundary(global_position)
	if nearest_data.is_empty():
		return

	var nearest_point: Vector2 = nearest_data["point"] as Vector2
	var inward: Vector2 = _inward_direction_from_boundary(nearest_point)
	if inward.length_squared() <= 0.000001:
		inward = (pond_bounds.get_center() - global_position).normalized()

	global_position = nearest_point + inward * max(out_touch_distance + 3.0, 6.0)
	if velocity.length_squared() > 0.000001:
		var tangent: Vector2 = nearest_data.get("tangent", Vector2.RIGHT) as Vector2
		velocity = (tangent * velocity.dot(tangent) * 0.45) + (inward * top_speed * 0.38)


func _inward_direction_from_boundary(boundary_point: Vector2) -> Vector2:
	var center: Vector2 = _pond_center_point()
	var inward: Vector2 = center - boundary_point
	if inward.length_squared() <= 0.000001:
		inward = center - global_position
	if inward.length_squared() <= 0.000001:
		return Vector2.UP
	return inward.normalized()


func _pond_center_point() -> Vector2:
	if _pond_center_valid:
		return _cached_pond_center
	if out_boundary_polygon.size() < 3:
		return pond_bounds.get_center()
	var accum: Vector2 = Vector2.ZERO
	for point: Vector2 in out_boundary_polygon:
		accum += point
	_cached_pond_center = accum / float(out_boundary_polygon.size())
	_pond_center_valid = true
	return _cached_pond_center
