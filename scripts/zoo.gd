extends Node2D

## Main pond orchestrator for continuous autonomous ecosystem simulation.
## Manages: fish lifecycle, feeding/predation, pellet/detritus spawning, despawn areas.
## No players, no scoring, no rounds—only simulation.

@onready var pond: Node2D = $Pond
@onready var pond_shape: Polygon2D = $PondShape
@onready var out_boundary: Line2D = $OutBoundary
@onready var out_boundary_debug: Line2D = $OutBoundaryDebug
@onready var despawn_area: Polygon2D = $DespawnAreas/DespawnArea
@onready var productivity_modules: Control = $CanvasLayer/ProductivityModules

@export_group("Pond: Boundary")
## Contact distance used to reinsert fish inside the out boundary.
@export var out_boundary_touch_distance: float = 10.0
## Avoidance distance where boundary steering begins.
@export var out_boundary_avoid_distance: float = 140.0
## Draws OutBoundaryDebug overlay when true.
@export var debug_draw_out_boundary: bool = false

@export_group("Pond: Despawn")
## Enables despawn polygon checks in the main loop.
@export var despawn_areas_enabled: bool = true
## Frames between despawn polygon passes (1 = every frame).
@export_range(1, 6, 1) var despawn_check_interval_frames: int = 2
## Initial detritus units spawned at startup.
@export var startup_detritus_count: int = 20
## Required edge clearance for detritus spawn validity.
@export var detritus_min_edge_clearance_px: float = 50.0
## Number of retries when resolving valid detritus spawn points.
@export var detritus_spawn_max_attempts: int = 128

@export_group("Pond: Pellet")
## Target live pellet population while simulation is active.
@export var pellet_target_count: int = 40
## Delay between pellet spawn checks when under target count.
@export var pellet_spawn_interval_seconds: float = 0.35
## Retry cap for random in-pond sampling.
@export_range(4, 96, 1) var pond_random_point_max_attempts: int = 16
## Retry cap for random in-pond sampling that excludes despawn polygon.
@export_range(4, 128, 1) var pond_outside_despawn_max_attempts: int = 24

@export_group("Pond: Performance")
## Max FPS when the window is focused. 0 = unlimited.
@export_range(0, 60, 5) var target_fps_focused: int = 40
## Max FPS when the window loses OS focus (minimized, other app in foreground).
@export_range(0, 30, 5) var target_fps_unfocused: int = 10

@export_group("Pond: Profiling")
## Keeps active fish count locked to the target for repeatable profiling.
@export var profile_force_fish_count_enabled: bool = false
## Desired live fish count (guppy/sabalo/dientudo only).
@export_range(1, 400, 1) var profile_target_fish_count: int = 150
## Max fish spawned in a single frame while filling deficit.
@export_range(1, 200, 1) var profile_fill_max_spawns_per_frame: int = 40

var pond_bounds: Rect2
var out_boundary_polygon: PackedVector2Array = PackedVector2Array()
## Cached global-space despawn polygon (static after _ready).
var _despawn_polygon_cached: PackedVector2Array = PackedVector2Array()
## Cached despawn centroid to avoid repeated polygon centroid loops.
var _cached_despawn_center: Vector2 = Vector2(640.0, 900.0)
var _pellet_spawn_timer: float = 0.0
var _simulation_active: bool = true
var _fish_lifecycle_by_id: Dictionary = {}
## Dynamically discovered spawner nodes (Spawner1, Spawner2, etc.).
var _spawners: Array[Node2D] = []
var _live_pellet_count: int = 0
var _live_detritus_count: int = 0
var _live_swimmer_count: int = 0
var _despawn_frame_index: int = 0


## Registers fish and validates scene wiring for pond orchestration.
func _ready() -> void:
	_validate_scene_wiring()
	randomize()
	pond_bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	_build_out_boundary_polygon()
	_build_despawn_polygon_cache()
	_connect_pool_signals()
	_sync_live_cached_counts()
	
	if out_boundary != null:
		out_boundary.visible = false
	if out_boundary_debug != null:
		out_boundary_debug.visible = debug_draw_out_boundary
	
	_seed_startup_pellets()
	_seed_startup_detritus()
	_simulation_active = true
	Engine.max_fps = maxi(target_fps_focused, 0)
	get_window().focus_entered.connect(_on_window_focus_entered)
	get_window().focus_exited.connect(_on_window_focus_exited)
	print("Pond: Ecosystem initialized. %d spawner(s) ready." % _spawners.size())


## Connects Zoo listeners to pool lifecycle signals for cheap live-count bookkeeping.
func _connect_pool_signals() -> void:
	if FishPool == null:
		return
	if not FishPool.fish_released.is_connected(_on_pool_fish_released):
		FishPool.fish_released.connect(_on_pool_fish_released)


## Recomputes cached live pellet/detritus counts (startup/recovery path).
func _sync_live_cached_counts() -> void:
	_live_pellet_count = 0
	_live_detritus_count = 0
	_live_swimmer_count = 0
	for child: Node in pond.get_children():
		if not (child is Fish):
			continue
		var fish: Fish = child as Fish
		if fish.pending_remove:
			continue
		if fish.species == SpeciesRegistry.PELLET:
			_live_pellet_count += 1
		elif fish.species == SpeciesRegistry.DETRITUS:
			_live_detritus_count += 1
		elif _is_swimmer_species(fish.species):
			_live_swimmer_count += 1


## Decrements cached counts when active pooled entities are released.
func _on_pool_fish_released(species_name: StringName) -> void:
	if species_name == SpeciesRegistry.PELLET:
		_live_pellet_count = maxi(_live_pellet_count - 1, 0)
	elif species_name == SpeciesRegistry.DETRITUS:
		_live_detritus_count = maxi(_live_detritus_count - 1, 0)
	elif _is_swimmer_species(species_name):
		_live_swimmer_count = maxi(_live_swimmer_count - 1, 0)


func _is_swimmer_species(species_name: StringName) -> bool:
	return species_name == SpeciesRegistry.GUPPY or species_name == SpeciesRegistry.SABALO or species_name == SpeciesRegistry.DIENTUDO


## Fails fast when critical Zoo scene dependencies are missing.
## Discovers Spawner1, Spawner2, ... nodes dynamically.
func _validate_scene_wiring() -> void:
	assert(pond != null, "Pond scene missing Pond node")
	assert(pond_shape != null, "Pond scene missing PondShape node")
	assert(despawn_area != null, "Pond scene missing DespawnArea node")
	assert(productivity_modules != null, "Pond scene missing CanvasLayer/ProductivityModules")
	if get_node_or_null("/root/SpatialGrid") == null:
		push_warning("Pond expects SpatialGrid autoload to be configured.")
	
	# Discover spawners dynamically (Spawner1, Spawner2, ...)
	_spawners.clear()
	var spawner_index: int = 1
	while true:
		var spawner: Node2D = get_node_or_null("Spawner%d" % spawner_index) as Node2D
		if spawner == null:
			break
		_spawners.append(spawner)
		spawner_index += 1
	
	if _spawners.is_empty():
		push_warning("Pond scene has no spawners (expected Spawner1, Spawner2, ...)")


## Keyboard shortcut handling for debugging (ESC to quit).
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and (key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_Q):
			get_tree().quit()
			get_viewport().set_input_as_handled()


## Main loop: rebuild spatial grid, run simulation, manage entities.
func _process(delta: float) -> void:
	if not _simulation_active:
		return
	
	SpatialGrid.rebuild()
	_process_pellet_spawning(delta)
	_enforce_profile_fish_count()
	
	# Advance all spawners and consume spawned fish.
	for spawner: Node2D in _spawners:
		_handle_spawner(delta, spawner)
	
	_process_despawn_areas()


## Advances one spawner and consumes queued spawn payloads.
func _handle_spawner(delta: float, spawner: Node2D) -> void:
	if spawner == null:
		return
	if not spawner.has_method("advance"):
		return
	spawner.call("advance", delta)
	if bool(spawner.call("can_spawn", 0)):
		_spawn_fish(spawner.call("consume_spawn_request") as Dictionary)


## Acquires, configures, and registers a new fish from a spawn request payload.
func _spawn_fish(fish_data: Dictionary) -> void:
	var species_name: StringName = fish_data.get("species", SpeciesRegistry.DEFAULT_SPECIES) as StringName
	var normalized_species: StringName = SpeciesRegistry.normalize_species(species_name)
	if profile_force_fish_count_enabled and _is_swimmer_species(normalized_species) and _live_swimmer_count >= maxi(profile_target_fish_count, 1):
		return
	var fish: Fish = FishPool.acquire(normalized_species)
	if fish == null:
		return

	fish.reparent(pond)
	fish.show()
	fish.set_process(true)
	fish.position = fish_data.get("origin", Vector2.ZERO) as Vector2
	var avoid_distance: float = out_boundary_avoid_distance
	if normalized_species == SpeciesDB.SABALO:
		avoid_distance *= 0.5
	
	# Use species-specific tint (no player ownership).
	var tint: Color = _pick_species_tint(normalized_species)
	fish.configure_from_zoo(normalized_species, tint, pond_bounds)
	fish.reinitialize()
	fish.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, avoid_distance)
	fish.configure_despawn_area(_cached_despawn_center)
	fish.fish_exited.connect(_on_fish_exited)
	if not fish.feed_succeeded.is_connected(_on_fish_feed_succeeded):
		fish.feed_succeeded.connect(_on_fish_feed_succeeded)
	_fish_lifecycle_by_id[fish.get_instance_id()] = {
		"species": normalized_species,
		"feeds": 0
	}
	if fish is Dientudo:
		var predator: Dientudo = fish as Dientudo
		if not predator.prey_predated.is_connected(_on_prey_predated):
			predator.prey_predated.connect(_on_prey_predated)
	SpatialGrid.register_fish(fish)
	if _is_swimmer_species(normalized_species):
		_live_swimmer_count += 1


## Fills fish deficits immediately so profiling can run at a stable active count.
func _enforce_profile_fish_count() -> void:
	if not profile_force_fish_count_enabled:
		return

	var target_count: int = maxi(profile_target_fish_count, 1)
	if _live_swimmer_count >= target_count:
		return

	var deficit: int = target_count - _live_swimmer_count
	var spawn_budget: int = mini(deficit, maxi(profile_fill_max_spawns_per_frame, 1))
	for _i: int in range(spawn_budget):
		_spawn_fish({
			"species": _random_profile_species(),
			"origin": _random_point_in_pond_outside_despawn()
		})


func _random_profile_species() -> StringName:
	var roll: int = randi_range(0, 2)
	if roll == 0:
		return SpeciesRegistry.GUPPY
	if roll == 1:
		return SpeciesRegistry.SABALO
	return SpeciesRegistry.DIENTUDO


## Picks species-specific tint with subtle shade variation.
func _pick_species_tint(species_name: StringName) -> Color:
	if species_name == SpeciesRegistry.GUPPY:
		return Color.from_hsv(randf_range(0.15, 0.20), randf_range(0.70, 0.85), randf_range(0.75, 0.90), 1.0)
	
	if species_name == SpeciesRegistry.SABALO:
		return Color.from_hsv(randf_range(0.50, 0.58), randf_range(0.35, 0.50), randf_range(0.60, 0.75), 1.0)
	
	if species_name == SpeciesRegistry.DIENTUDO:
		return Color.from_hsv(randf_range(0.85, 0.95), randf_range(0.10, 0.20), randf_range(0.85, 0.95), 1.0)

	return Color(0.5, 0.5, 0.5, 1.0)


## Handles fish exit (alive departure from pond).
func _on_fish_exited(fish_id: int, _fish_species: StringName, feed_count: int, _biomass_g: float) -> void:
	if _fish_lifecycle_by_id.has(fish_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[fish_id] as Dictionary
		fish_entry["alive_exit"] = true
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		_fish_lifecycle_by_id[fish_id] = fish_entry


## Tracks successful feed events.
func _on_fish_feed_succeeded(_feeder_species: StringName, feeder_id: int, feed_count: int, _weight_gain_g: float, _target_fish_id: int) -> void:
	if _fish_lifecycle_by_id.has(feeder_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[feeder_id] as Dictionary
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		_fish_lifecycle_by_id[feeder_id] = fish_entry


## Handles predation events and spawns detritus from prey biomass.
func _on_prey_predated(prey_position: Vector2, prey_weight_g: float, _predator_species: StringName, _predator_fish_id: int, _prey_species: StringName, prey_fish_id: int, prey_feed_count: int, _absorbed_mass_g: float) -> void:
	var detritus_units: int = _roll_predation_detritus_value(prey_weight_g)
	if detritus_units > 0:
		_spawn_detritus(prey_position, detritus_units)
	
	if _fish_lifecycle_by_id.has(prey_fish_id):
		var prey_entry: Dictionary = _fish_lifecycle_by_id[prey_fish_id] as Dictionary
		prey_entry["predated"] = true
		prey_entry["feeds"] = maxi(int(prey_entry.get("feeds", 0)), prey_feed_count)
		_fish_lifecycle_by_id[prey_fish_id] = prey_entry


## Converts prey biomass to probabilistic detritus units.
func _roll_predation_detritus_value(prey_weight_g: float) -> int:
	var roll_count: int = int(floor(prey_weight_g / 50.0))
	if roll_count <= 0:
		return 0
	var detritus_units: int = 0
	for _i: int in range(roll_count):
		if randf() <= 0.20:
			detritus_units += 1
	return detritus_units


## Returns centroid of the despawn polygon in global space.
func _compute_despawn_center() -> Vector2:
	return _cached_despawn_center


## Spawns detritus with validity checks and initial value units.
func _spawn_detritus(spawn_position: Vector2, detritus_units: int) -> void:
	if detritus_units <= 0:
		return
	var safe_spawn_position: Vector2 = _resolve_detritus_spawn_point(spawn_position)
	if not _is_detritus_spawn_valid(safe_spawn_position):
		return
	var detritus_fish: Fish = FishPool.acquire(SpeciesRegistry.DETRITUS)
	if detritus_fish == null:
		return

	detritus_fish.reparent(pond)
	detritus_fish.show()
	detritus_fish.set_process(true)
	detritus_fish.position = safe_spawn_position
	detritus_fish.configure_from_zoo(SpeciesRegistry.DETRITUS, Color(0.45, 0.30, 0.14, 1.0), pond_bounds)
	detritus_fish.reinitialize()
	detritus_fish.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, out_boundary_avoid_distance)
	detritus_fish.configure_despawn_area(_cached_despawn_center)
	if detritus_fish is Detritus:
		(detritus_fish as Detritus).set_detritus_value(detritus_units)
	SpatialGrid.register_fish(detritus_fish)
	_live_detritus_count += 1


## Spawns and registers a pellet entity at the requested position.
func _spawn_pellet(spawn_position: Vector2) -> void:
	var pellet: Fish = FishPool.acquire(SpeciesRegistry.PELLET)
	if pellet == null:
		return

	pellet.reparent(pond)
	pellet.show()
	pellet.set_process(true)
	pellet.position = spawn_position
	pellet.configure_from_zoo(SpeciesRegistry.PELLET, Color(1.0, 1.0, 1.0, 1.0), pond_bounds)
	pellet.reinitialize()
	pellet.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, out_boundary_avoid_distance)
	pellet.configure_despawn_area(_cached_despawn_center)
	SpatialGrid.register_fish(pellet)
	_live_pellet_count += 1


## Seeds pellets up to the configured startup target.
func _seed_startup_pellets() -> void:
	for _i: int in range(maxi(pellet_target_count, 0)):
		_spawn_pellet(_random_point_in_pond())


## Maintains pellet population around pellet_target_count.
func _process_pellet_spawning(delta: float) -> void:
	if pellet_target_count <= 0:
		return
	_pellet_spawn_timer -= delta
	if _pellet_spawn_timer > 0.0:
		return

	if _live_pellet_count < pellet_target_count:
		_spawn_pellet(_random_point_in_pond())
		_pellet_spawn_timer = maxf(pellet_spawn_interval_seconds, 0.02)
	else:
		_pellet_spawn_timer = 0.25


## Seeds startup detritus.
func _seed_startup_detritus() -> void:
	var requested: int = maxi(startup_detritus_count, 0)
	for _i: int in range(requested):
		_spawn_detritus(_random_point_in_pond_outside_despawn(), 1)

	var live_now: int = _live_detritus_count
	print("Pond: Startup detritus seeded. Requested=%d, Live=%d" % [requested, live_now])


## Returns a random in-pond point that excludes despawn polygon when possible.
func _random_point_in_pond_outside_despawn() -> Vector2:
	if _despawn_polygon_cached.size() < 3:
		return _random_point_in_pond()
	for _attempt: int in range(maxi(pond_outside_despawn_max_attempts, 1)):
		var candidate: Vector2 = _random_point_in_pond()
		if not Geometry2D.is_point_in_polygon(candidate, _despawn_polygon_cached):
			return candidate
	return _random_point_in_pond()


## Attempts to relocate invalid detritus spawns to a safe in-pond point.
func _resolve_detritus_spawn_point(preferred: Vector2) -> Vector2:
	if _is_detritus_spawn_valid(preferred):
		return preferred

	for _attempt: int in range(maxi(detritus_spawn_max_attempts, 1)):
		var candidate: Vector2 = _random_point_in_pond_outside_despawn()
		if _is_detritus_spawn_valid(candidate):
			return candidate

	return preferred


## Validates detritus spawn points against pond bounds and edge clearance.
func _is_detritus_spawn_valid(point: Vector2) -> bool:
	if out_boundary_polygon.size() >= 3 and not Geometry2D.is_point_in_polygon(point, out_boundary_polygon):
		return false

	if _distance_to_out_boundary(point) < maxf(detritus_min_edge_clearance_px, 0.0):
		return false

	return true


## Returns shortest distance from a point to the out-boundary polyline.
func _distance_to_out_boundary(point: Vector2) -> float:
	if out_boundary_polygon.size() < 2:
		var left: float = point.x - pond_bounds.position.x
		var right: float = pond_bounds.end.x - point.x
		var top: float = point.y - pond_bounds.position.y
		var bottom: float = pond_bounds.end.y - point.y
		return minf(minf(left, right), minf(top, bottom))

	var nearest_distance: float = INF
	for i: int in range(out_boundary_polygon.size()):
		var a: Vector2 = out_boundary_polygon[i]
		var b: Vector2 = out_boundary_polygon[(i + 1) % out_boundary_polygon.size()]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		nearest_distance = minf(nearest_distance, point.distance_to(closest))

	return nearest_distance


## Counts live fish by species, skipping pending removals.
func _count_live_species(species_name: StringName) -> int:
	var total: int = 0
	for child: Node in pond.get_children():
		if not (child is Fish):
			continue
		var fish: Fish = child as Fish
		if fish.pending_remove:
			continue
		if fish.species == species_name:
			total += 1
	return total


## Picks a random point inside pond polygon (or viewport bounds fallback).
func _random_point_in_pond() -> Vector2:
	if out_boundary_polygon.size() < 3:
		return Vector2(
			randf_range(pond_bounds.position.x, pond_bounds.end.x),
			randf_range(pond_bounds.position.y, pond_bounds.end.y)
		)

	var min_x: float = INF
	var max_x: float = - INF
	var min_y: float = INF
	var max_y: float = - INF
	for point: Vector2 in out_boundary_polygon:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	for _attempt: int in range(maxi(pond_random_point_max_attempts, 1)):
		var candidate: Vector2 = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(candidate, out_boundary_polygon):
			return candidate

	return out_boundary_polygon[randi() % out_boundary_polygon.size()]


## Builds and caches world-space out boundary polygon from PondShape.
func _build_out_boundary_polygon() -> void:
	if pond_shape == null or pond_shape.polygon.size() < 3:
		out_boundary_polygon = PackedVector2Array([
			Vector2(60.0, 120.0),
			Vector2(1220.0, 105.0),
			Vector2(1240.0, 680.0),
			Vector2(40.0, 690.0)
		])
	else:
		var global_poly: PackedVector2Array = PackedVector2Array()
		for local_point: Vector2 in pond_shape.polygon:
			global_poly.append(pond_shape.to_global(local_point))
		out_boundary_polygon = global_poly

	if out_boundary != null:
		out_boundary.points = out_boundary_polygon
	if out_boundary_debug != null:
		out_boundary_debug.points = out_boundary_polygon
		out_boundary_debug.visible = debug_draw_out_boundary


## Caches despawn polygon in world space for fast point-in-polygon checks.
func _build_despawn_polygon_cache() -> void:
	if despawn_area == null or despawn_area.polygon.size() < 3:
		_cached_despawn_center = Vector2(640.0, 900.0)
		return
	_despawn_polygon_cached = PackedVector2Array()
	var accum: Vector2 = Vector2.ZERO
	for local_point: Vector2 in despawn_area.polygon:
		var global_point: Vector2 = despawn_area.to_global(local_point)
		_despawn_polygon_cached.append(global_point)
		accum += global_point
	_cached_despawn_center = accum / float(despawn_area.polygon.size())


## Despawns fish that enter configured despawn polygons.
func _process_despawn_areas() -> void:
	if not despawn_areas_enabled:
		return
	if despawn_area == null or _despawn_polygon_cached.size() < 3:
		return

	_despawn_frame_index += 1
	if _despawn_frame_index % maxi(despawn_check_interval_frames, 1) != 0:
		return

	for fish: Fish in SpatialGrid.get_live_fish_snapshot():
		if fish.pending_remove:
			continue

		if Geometry2D.is_point_in_polygon(fish.global_position, _despawn_polygon_cached):
			_despawn_fish(fish)


## Removes fish from pond by returning it to the pool.
func _despawn_fish(fish: Fish) -> void:
	if fish.pending_remove:
		return
	FishPool.release(fish)


## Toggles productivity module visibility for screensaver mode.
func set_productivity_ui_visible(should_show: bool) -> void:
	if productivity_modules != null:
		productivity_modules.visible = should_show


## Restores focused FPS cap when OS window regains focus.
func _on_window_focus_entered() -> void:
	Engine.max_fps = maxi(target_fps_focused, 0)


## Drops to background FPS cap when OS window loses focus.
func _on_window_focus_exited() -> void:
	Engine.max_fps = maxi(target_fps_unfocused, 1)
