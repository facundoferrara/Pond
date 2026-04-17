extends Node2D
class_name Fish

## Shared base class for active pond entities (fish, pellet, detritus).
## Lifecycle is pool-based: acquire -> configure_from_zoo -> reinitialize -> release.
## Zoo listens to fish_exited/feed_succeeded for ecosystem analytics.

signal fish_exited(fish_id: int, fish_species: StringName, feed_count: int, biomass_g: float)
signal feed_succeeded(feeder_species: StringName, feeder_id: int, feed_count: int, weight_gain_g: float, target_fish_id: int)

enum BehaviorState {
	SCHOOL,
	FLEE,
	FEED,
	DESCEND
}

@onready var sprite: Sprite2D = $Sprite2D

@export_group("Identity")
## Species identifier used to fetch defaults and route pooling.
@export var species: StringName = SpeciesDB.GUPPY
## Base tint applied to the fish sprite.
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Vitals")
## Energy applied at spawn/reinitialize time.
@export var starting_energy: float = 20.0
## Current energy consumed by hunger and flee behavior.
@export var energy: float = 20.0
## Current body mass in grams.
@export var weight: float = 50.0
## Starting saturation ratio applied at spawn.
@export_range(0.0, 1.0, 0.01) var starting_saturation_ratio: float = 0.75
## Current saturation ratio. Feeding events increase this up to 1.0.
@export_range(0.0, 1.0, 0.01) var saturation_ratio: float = 0.75
## Maximum movement speed in pixels per second.
@export var top_speed: float = 140.0
## Enables predatory behavior checks.
@export var is_predator: bool = false
## Max prey ratio this fish can consume (prey <= weight * ratio).
@export_range(0.05, 1.0, 0.05) var prey_weight_ratio_limit: float = 0.5

@export_group("Sensing And Steering")
## Radius used for boid neighbor detection.
@export var vision_radius: float = 120.0
## Radius used to detect predators.
@export var predator_detection_radius: float = 120.0
## Desired minimum neighbor spacing.
@export var separation_radius: float = 30.0
## Maximum steering force applied each frame.
@export var max_force: float = 170.0

@export_group("Lifecycle")
## Lifespan used to drive aging ratio.
@export var life_span_seconds: float = 60.0
## Optional aging multiplier for special modes/debug.
@export var age_speed_multiplier: float = 1.0
## Exit pressure toward despawn as age increases.
@export var age_exit_bias: float = 240.0
## Lifespan ratio where despawn steering starts ramping up.
@export_range(0.0, 1.0, 0.01) var despawn_bias_start_ratio: float = 0.75
## Energy drain per second.
@export var hunger_rate: float = 1.2
## Catch/eat interaction distance.
@export var eat_radius: float = 15.0
## Max white-mix amount applied at end of lifespan.
@export_range(0.0, 1.0, 0.01) var age_whiten_max_ratio: float = 0.2
## Predator size ratio required to force flee override.
@export var flee_override_predator_ratio: float = 2.0

@export_group("Rendering")
## Sprite rotation offset to align art with movement direction.
@export var heading_offset_radians: float = PI / 2.0
## Global multiplier for visual scale by mass.
@export_range(0.001, 100.0, 0.001) var visual_scale_multiplier: float = 2.0
## Mass reference used for normalized scale computation.
@export var scale_reference_weight_g: float = 50.0

@export_group("Boundary")
## Distance considered in-contact with outer boundary.
@export var out_touch_distance: float = 8.0
## Distance where avoidance starts ramping in.
@export var out_avoid_distance: float = 64.0

@export_group("Debug")
## Emits facing warnings when displacement is near zero.
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
## Centroid of out_boundary_polygon, computed once in configure_out_boundary().
var _cached_pond_center: Vector2 = Vector2.ZERO
var _pond_center_valid: bool = false
## Pre-computed boundary segment midpoints for broadphase rejection in nearest-point queries.
var _boundary_segment_midpoints: PackedVector2Array = PackedVector2Array()
## Pre-computed boundary segment half-lengths paired with _boundary_segment_midpoints.
var _boundary_segment_half_lengths: PackedFloat32Array = PackedFloat32Array()
## Per-fish frame offset so context updates are staggered across the population.
var _context_frame_offset: int = 0
## Number of successful feeding events during this fish lifecycle.
var _successful_feed_count: int = 0
var _pending_feed_target: Fish = null

const _CONTEXT_UPDATE_INTERVAL: int = 10


## Registers fish and initializes species defaults plus visuals.
func _ready() -> void:
	add_to_group("fish")
	_context_frame_offset = randi() % _CONTEXT_UPDATE_INTERVAL
	_apply_species_defaults()
	previous_global_position = global_position
	_refresh_visual()
	_refresh_scale()


## Resets runtime state so a pooled fish can be re-used without re-instantiation.
## Call AFTER configure_from_zoo() so species defaults are already applied.
func reinitialize() -> void:
	pending_remove = false
	is_out_of_game = false
	age_seconds = 0.0
	_successful_feed_count = 0
	_pending_feed_target = null
	age_speed_multiplier = 1.0
	boid_neighbors.clear()
	nearest_predator = null
	behavior_state = BehaviorState.SCHOOL
	warned_facing_no_motion = false
	velocity = Vector2.ZERO
	saturation_ratio = clampf(starting_saturation_ratio, 0.0, 1.0)
	previous_global_position = global_position


## Applies per-spawn ownership/tint/bounds and refreshes species-driven defaults.
func configure_from_zoo(species_name: StringName, tint: Color, bounds: Rect2) -> void:
	species = species_name
	color = tint
	pond_bounds = bounds
	previous_global_position = global_position
	_apply_species_defaults()
	_refresh_visual()
	_refresh_scale()

func configure_despawn_area(center: Vector2) -> void:
	despawn_area_center = center


func configure_out_boundary(polygon: PackedVector2Array, touch_distance: float, avoid_distance: float) -> void:
	out_boundary_polygon = polygon
	out_touch_distance = touch_distance
	out_avoid_distance = avoid_distance
	_boundary_segment_midpoints.clear()
	_boundary_segment_half_lengths.clear()
	if polygon.size() >= 3:
		var accum: Vector2 = Vector2.ZERO
		for pt: Vector2 in polygon:
			accum += pt
		_cached_pond_center = accum / float(polygon.size())
		_pond_center_valid = true
		# Pre-compute segment broadphase data so _nearest_point_on_out_boundary can reject
		# distant segments before calling Geometry2D.get_closest_point_to_segment.
		for i: int in range(polygon.size()):
			var seg_a: Vector2 = polygon[i]
			var seg_b: Vector2 = polygon[(i + 1) % polygon.size()]
			_boundary_segment_midpoints.append((seg_a + seg_b) * 0.5)
			_boundary_segment_half_lengths.append((seg_b - seg_a).length() * 0.5)
	else:
		_pond_center_valid = false


func _age_ratio() -> float:
	return clampf(age_seconds / maxf(life_span_seconds, 0.001), 0.0, 1.0)


## Main per-frame lifecycle: update state, steer, feed, refresh visuals, and emit exits.
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
	accel += _compute_out_boundary_avoidance()

	velocity += accel * delta
	if velocity.length() > top_speed:
		velocity = velocity.normalized() * top_speed
	position += velocity * delta
	_keep_inside_pond()

	_update_orientation()
	_process_feeding(delta)
	_refresh_visual()
	_refresh_scale()

	is_out_of_game = not _is_inside_pond(global_position)
	if _should_exit():
		pending_remove = true
		fish_exited.emit(get_instance_id(), species, _successful_feed_count, get_redeemable_biomass_g())
		FishPool.release(self )


## Loads species defaults from SpeciesDB, preserving current inspector values as fallback.
func _apply_species_defaults() -> void:
	var species_data: Dictionary = SpeciesDB.get_species(species)
	starting_energy = float(species_data.get("starting_energy", starting_energy))
	energy = starting_energy
	starting_saturation_ratio = float(species_data.get("starting_saturation_ratio", starting_saturation_ratio))
	saturation_ratio = clampf(starting_saturation_ratio, 0.0, 1.0)
	top_speed = float(species_data.get("top_speed", top_speed))
	is_predator = bool(species_data.get("is_predator", is_predator))
	prey_weight_ratio_limit = float(species_data.get("prey_weight_ratio_limit", prey_weight_ratio_limit))
	vision_radius = float(species_data.get("vision_radius", vision_radius))
	predator_detection_radius = float(species_data.get("predator_detection_radius", vision_radius))
	separation_radius = float(species_data.get("separation_radius", separation_radius))
	max_force = float(species_data.get("max_force", max_force))
	life_span_seconds = float(species_data.get("life_span_seconds", life_span_seconds))
	age_exit_bias = float(species_data.get("age_exit_bias", age_exit_bias))
	despawn_bias_start_ratio = float(species_data.get("despawn_bias_start_ratio", despawn_bias_start_ratio))
	hunger_rate = float(species_data.get("hunger_rate", hunger_rate))
	eat_radius = float(species_data.get("eat_radius", eat_radius))
	age_whiten_max_ratio = float(species_data.get("age_whiten_max_ratio", age_whiten_max_ratio))
	flee_override_predator_ratio = float(species_data.get("flee_override_predator_ratio", flee_override_predator_ratio))
	boid_weights = species_data.get("boid_weights", boid_weights) as Dictionary
	var texture_path: String = String(species_data.get("texture_path", ""))
	if texture_path != "" and _ensure_sprite():
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			sprite.texture = texture


## Computes boid separation/alignment/cohesion steering from nearby neighbors.
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


## Updates boid neighbors and nearest predator using SpatialGrid queries.
func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null
	var nearest_distance: float = INF

	# Boid neighbors via spatial grid (O(k) instead of O(N)).
	var nearby: Array[Fish] = SpatialGrid.query_neighbors(global_position, vision_radius)
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if other.species != species:
			continue
		if global_position.distance_to(other.global_position) <= vision_radius:
			boid_neighbors.append(other)

	# Predator detection: distance-gate first so can_eat_target is skipped for far predators.
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


## Selects default flee/descend/school behavior for base fish.
func _update_behavior_state() -> void:
	if _predator_valid():
		behavior_state = BehaviorState.FLEE
		return
	if _age_ratio() >= 1.0:
		behavior_state = BehaviorState.DESCEND
		return
	behavior_state = BehaviorState.SCHOOL


## Computes baseline acceleration for descend or normal movement.
func _compute_acceleration(_delta: float) -> Vector2:
	if behavior_state == BehaviorState.DESCEND:
		var descend_bias: Vector2 = _compute_guppy_style_age_despawn_bias(1.0)
		return descend_bias
	return _compute_despawn_bias()


func _process_feeding(_delta: float) -> void:
	pass


func can_feed() -> bool:
	return _age_ratio() < 1.0


func can_hunt() -> bool:
	return is_predator and can_feed()


func can_eat_target(target: Fish) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or target.pending_remove:
		return false
	if not can_hunt():
		return false
	if is_predator and (target.species == SpeciesRegistry.PELLET or target.species == SpeciesRegistry.DETRITUS):
		return false
	if target.species == species:
		return false
	if is_predator:
		return target.weight <= weight * 0.5
	return target.weight <= weight * prey_weight_ratio_limit


func can_eat_fish(target: Fish) -> bool:
	return can_eat_target(target)


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
	var sat: float = clampf(color.s * saturation_ratio, 0.0, 1.0)
	var base_tinted: Color = Color.from_hsv(color.h, sat, color.v, color.a)
	var age_t: float = _age_ratio()
	var white_mix: float = clampf(age_t * maxf(age_whiten_max_ratio, 0.0), 0.0, 0.95)
	sprite.modulate = base_tinted.lerp(Color(1.0, 1.0, 1.0, color.a), white_mix)


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


func mark_successful_feed(weight_gain_g: float = 0.0) -> void:
	if not can_feed():
		_pending_feed_target = null
		return
	_successful_feed_count += 1
	if weight_gain_g > 0.0:
		weight = maxf(0.001, weight + weight_gain_g)
	_refresh_scale()
	saturation_ratio = clampf(saturation_ratio + 0.05, 0.0, 1.0)
	var target_fish_id: int = 0
	if _pending_feed_target != null and is_instance_valid(_pending_feed_target):
		target_fish_id = _pending_feed_target.get_instance_id()
	feed_succeeded.emit(species, get_instance_id(), _successful_feed_count, weight_gain_g, target_fish_id)
	_pending_feed_target = null


func get_successful_feed_count() -> int:
	return _successful_feed_count


func get_diagnostic_feed_target() -> Fish:
	return null

func get_redeemable_biomass_g() -> float:
	return maxf(weight, 0.0)


func _compute_guppy_style_age_despawn_bias(strength_multiplier: float = 1.0) -> Vector2:
	var ratio: float = _age_ratio()
	if ratio < despawn_bias_start_ratio:
		return Vector2.ZERO

	var span: float = maxf(1.0 - despawn_bias_start_ratio, 0.001)
	var t: float = clampf((ratio - despawn_bias_start_ratio) / span, 0.0, 1.0)
	var to_despawn: Vector2 = despawn_area_center - global_position
	if to_despawn.length_squared() <= 0.000001:
		return Vector2.ZERO

	var desired: Vector2 = to_despawn.normalized() * top_speed
	return _steer_towards(desired) * (t * maxf(strength_multiplier, 0.0))


func _compute_despawn_bias() -> Vector2:
	var ratio: float = _age_ratio()
	if ratio < despawn_bias_start_ratio:
		return Vector2.ZERO
	var span: float = maxf(1.0 - despawn_bias_start_ratio, 0.001)
	var t: float = clampf((ratio - despawn_bias_start_ratio) / span, 0.0, 1.0)
	var to_despawn: Vector2 = despawn_area_center - global_position
	if to_despawn.length_squared() <= 0.000001:
		return Vector2.ZERO
	var desired: Vector2 = to_despawn.normalized() * top_speed
	return _steer_towards(desired) * (age_exit_bias * (0.15 + 0.85 * t))


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


func _nearest_point_on_out_boundary(point: Vector2) -> Dictionary:
	var seg_count: int = out_boundary_polygon.size()
	if seg_count < 3:
		return {}

	var best_distance: float = INF
	var best_point: Vector2 = Vector2.ZERO
	var best_tangent: Vector2 = Vector2.RIGHT
	var use_broadphase: bool = _boundary_segment_midpoints.size() == seg_count
	for i: int in range(seg_count):
		# Broadphase: dist(point, midpoint) - half_length is a lower bound on dist(point, segment).
		# If the lower bound already exceeds best found, skip expensive closest-point call.
		if use_broadphase:
			var lower_bound: float = point.distance_to(_boundary_segment_midpoints[i]) - _boundary_segment_half_lengths[i]
			if lower_bound > best_distance:
				continue
		var a: Vector2 = out_boundary_polygon[i]
		var b: Vector2 = out_boundary_polygon[(i + 1) % seg_count]
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
