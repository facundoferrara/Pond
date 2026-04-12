extends Fish
class_name Sabalo

## Guppy-style sabalo behavior with detritus-only feeding.
## Keeps Sabalo species identity in data while removing bespoke state systems.

@export_group("Sabalo: Feeding")
## Energy gained per second while consuming detritus.
@export var feeding_energy_gain: float = 1.0
## Interaction radius used for detritus consumption checks.
@export var feeding_consume_radius: float = 12.0
## Seconds per consumed detritus unit while in contact.
@export var detritus_consume_tick_seconds: float = 1.0

@export_group("Sabalo: Flee")
## Extra energy drain while actively fleeing predators.
@export var flee_energy_drain_rate: float = 5.0

@export_group("Sabalo: Movement")
## Rotation speed limit used when orienting body to velocity.
@export var turn_rate_rad_per_sec: float = 9.0
## Base speed ratio used by wander behavior.
@export var wander_speed_factor: float = 0.38
## Descend-bias multiplier once age pressure starts.
@export var descend_bias_strength_multiplier: float = 1.3

@export_group("Sabalo: Debug")
## Enables minimal debug lines for target and predator context.
@export var debug_gizmo_enabled: bool = false
## Line width used by debug overlay lines.
@export var gizmo_line_width: float = 1.5

## Heading accumulator for smooth random wander.
var wander_heading: Vector2 = Vector2.RIGHT
## Current detritus target while feeding.
var target_detritus: Detritus = null
## Accumulator toward next detritus unit consumption.
var detritus_consume_progress: float = 0.0
## Total detritus units consumed this lifecycle.
var detritus_units_consumed: int = 0
## Exhaustion accumulator used for speed cap nerf ramping.
var exhaustion_time: float = 0.0

const _EXHAUSTION_RAMP_SECONDS: float = 4.0
const _MAX_EXHAUSTION_SPEED_NERF: float = 0.2


## Sets species and initializes wander heading for pooled lifecycle.
func _ready() -> void:
	species = SpeciesDB.SABALO
	super._ready()
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))


## Resets targeting and energy cadence state when reused from pool.
func reinitialize() -> void:
	super.reinitialize()
	wander_heading = Vector2.RIGHT.rotated(randf_range(-PI, PI))
	target_detritus = null
	detritus_consume_progress = 0.0
	detritus_units_consumed = 0
	exhaustion_time = 0.0
	queue_redraw()


## Applies SpeciesDB overrides for sabalo tuning knobs.
func _apply_species_defaults() -> void:
	super._apply_species_defaults()
	var species_data: Dictionary = SpeciesDB.get_species(species)
	feeding_energy_gain = float(species_data.get("feeding_energy_gain", feeding_energy_gain))
	feeding_consume_radius = float(species_data.get("feeding_consume_radius", feeding_consume_radius))
	detritus_consume_tick_seconds = float(species_data.get("detritus_consume_tick_seconds", detritus_consume_tick_seconds))
	flee_energy_drain_rate = float(species_data.get("flee_energy_drain_rate", flee_energy_drain_rate))
	turn_rate_rad_per_sec = float(species_data.get("turn_rate_rad_per_sec", turn_rate_rad_per_sec))
	wander_speed_factor = float(species_data.get("wander_speed_factor", wander_speed_factor))
	descend_bias_strength_multiplier = float(species_data.get("descend_bias_strength_multiplier", descend_bias_strength_multiplier))


## Toggles minimal debug overlays for this sabalo instance.
func set_debug_focus(enabled: bool) -> void:
	debug_gizmo_enabled = enabled
	queue_redraw()


## Updates base movement and applies Guppy-style exhaustion speed ramp.
func _process(delta: float) -> void:
	super._process(delta)
	if _is_exhausted():
		exhaustion_time = minf(_EXHAUSTION_RAMP_SECONDS, exhaustion_time + delta)
	else:
		exhaustion_time = maxf(0.0, exhaustion_time - delta)

	var exhaustion_t: float = clampf(exhaustion_time / _EXHAUSTION_RAMP_SECONDS, 0.0, 1.0)
	var speed_factor: float = 1.0 - (_MAX_EXHAUSTION_SPEED_NERF * exhaustion_t)
	var speed_cap: float = top_speed * speed_factor
	if _is_exhausted() and velocity.length() > speed_cap:
		velocity = velocity.normalized() * speed_cap

	if debug_gizmo_enabled and not pending_remove:
		queue_redraw()


## Computes sabalo steering using Guppy-style state priorities.
func _compute_acceleration(delta: float) -> Vector2:
	var age_bias: Vector2 = _compute_age_despawn_bias()

	if behavior_state == BehaviorState.DESCEND:
		var descend_bias: Vector2 = _compute_guppy_style_age_despawn_bias(descend_bias_strength_multiplier)
		return _compute_wander(delta) + descend_bias

	if behavior_state == BehaviorState.FEED and target_detritus != null and is_instance_valid(target_detritus) and not target_detritus.pending_remove:
		var to_detritus: Vector2 = target_detritus.global_position - global_position
		if to_detritus.length_squared() > 0.000001:
			var desired: Vector2 = to_detritus.normalized() * top_speed
			return _steer_towards(desired) * 1.8 + age_bias

	if behavior_state == BehaviorState.FLEE:
		var flee_steer: Vector2 = _compute_distance_scaled_flee_steer()
		energy = maxf(0.0, energy - flee_energy_drain_rate * delta)
		if _is_exhausted():
			return flee_steer + age_bias
		var flee: Vector2 = flee_steer * 2.1
		var support_school: Vector2 = _compute_boid_steering(boid_neighbors) * 0.2
		return flee + support_school + age_bias

	if _is_exhausted():
		if _age_ratio() < 0.75:
			return age_bias
		return _steer_towards_despawn() + age_bias

	var boid: Vector2 = _compute_boid_steering(boid_neighbors)
	var wander: Vector2 = _compute_wander(delta)
	return boid + wander + age_bias


## Refreshes base context plus nearest detritus target when safe to feed.
func _update_context() -> void:
	super._update_context()
	target_detritus = null
	if _predator_valid():
		detritus_consume_progress = 0.0
		return

	var nearest_distance: float = INF
	var nearby: Array[Fish] = SpatialGrid.query_neighbors_by_species(global_position, vision_radius, SpeciesRegistry.DETRITUS)
	for other: Fish in nearby:
		if other == self or other.pending_remove or not is_instance_valid(other):
			continue
		if not (other is Detritus):
			continue
		var detritus: Detritus = other as Detritus
		if detritus.detritus_value <= 0:
			continue
		var distance: float = global_position.distance_to(detritus.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			target_detritus = detritus


## Selects state from predator risk, age, and detritus availability.
func _update_behavior_state() -> void:
	if _predator_valid():
		behavior_state = BehaviorState.FLEE
		return
	if _age_ratio() >= 1.0:
		behavior_state = BehaviorState.DESCEND
		return
	if target_detritus != null and is_instance_valid(target_detritus) and not target_detritus.pending_remove:
		behavior_state = BehaviorState.FEED
		return
	behavior_state = BehaviorState.SCHOOL


## Consumes detritus units over time when within feeding radius.
func _process_feeding(delta: float) -> void:
	if not can_feed() or behavior_state != BehaviorState.FEED:
		return
	if target_detritus == null or not is_instance_valid(target_detritus) or target_detritus.pending_remove:
		return
	if global_position.distance_to(target_detritus.global_position) > maxf(eat_radius, feeding_consume_radius):
		return

	energy = minf(starting_energy, energy + feeding_energy_gain * delta)
	detritus_consume_progress += delta
	var consume_tick: float = maxf(0.01, detritus_consume_tick_seconds)
	while detritus_consume_progress >= consume_tick and target_detritus != null and is_instance_valid(target_detritus):
		detritus_consume_progress -= consume_tick
		if target_detritus.detritus_value <= 0:
			target_detritus.pending_remove = true
			FishPool.release(target_detritus)
			target_detritus = null
			break

		target_detritus.set_detritus_value(target_detritus.detritus_value - 1)
		detritus_units_consumed += 1
		add_points(1)
		set_pending_feed_diagnostics(1, target_detritus)
		mark_successful_feed(10.0)

		if target_detritus.detritus_value <= 0:
			target_detritus.pending_remove = true
			FishPool.release(target_detritus)
			target_detritus = null
			break


func get_diagnostic_feed_target() -> Fish:
	if target_detritus == null or not is_instance_valid(target_detritus) or target_detritus.pending_remove:
		return null
	return target_detritus


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


func _compute_wander(delta: float) -> Vector2:
	wander_heading = wander_heading.rotated(randf_range(-1.8, 1.8) * delta)
	var desired: Vector2 = wander_heading * top_speed * wander_speed_factor
	return _steer_towards(desired) * 0.62


func _is_exhausted() -> bool:
	return energy <= 0.0


func _steer_towards_despawn() -> Vector2:
	var desired: Vector2 = (despawn_area_center - global_position).normalized() * top_speed
	return _steer_towards(desired)


func _compute_age_despawn_bias() -> Vector2:
	return _compute_guppy_style_age_despawn_bias(1.0)


func _refresh_age_tint() -> void:
	return


## Keeps body orientation smooth and bounded by turn rate.
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


## Returns detritus-based refund units for zoo resource accounting.
func get_resource_refund_units() -> int:
	return floori(float(detritus_units_consumed) / 2.0)


func _draw() -> void:
	if not debug_gizmo_enabled:
		return

	if _predator_valid():
		var predator_local: Vector2 = to_local(nearest_predator.global_position)
		draw_line(Vector2.ZERO, predator_local, Color(1.0, 0.25, 0.25, 0.95), gizmo_line_width)

	if target_detritus != null and is_instance_valid(target_detritus) and not target_detritus.pending_remove:
		var detritus_local: Vector2 = to_local(target_detritus.global_position)
		draw_line(Vector2.ZERO, detritus_local, Color(1.0, 0.84, 0.32, 0.95), gizmo_line_width)

	if velocity.length_squared() > 0.000001:
		var velocity_line: Vector2 = velocity.normalized() * minf(30.0, velocity.length() * 0.25)
		draw_line(Vector2.ZERO, velocity_line, Color(0.98, 0.98, 0.98, 0.92), maxf(1.0, gizmo_line_width - 0.2))
