extends Node2D

enum ScheduleMode {
	ROUND_ROBIN,
	FOCUSED_SUITE
}

@onready var pond: Node2D = $Pond
@onready var pond_shape: Polygon2D = $PondShape
@onready var out_boundary: Line2D = $OutBoundary
@onready var despawn_area: Polygon2D = $DespawnAreas/DespawnArea
@onready var score_p1_label: Label = $CanvasLayer/ScoreP1
@onready var score_p2_label: Label = $CanvasLayer/ScoreP2
@onready var count_label: Label = $CanvasLayer/FishCount
@onready var spawner_p1: Node2D = $SpawnerP1
@onready var spawner_p2: Node2D = $SpawnerP2
@onready var _mode_overlay_node: Panel = $CanvasLayer/ModeOverlay
@onready var _btn_rr: Button = $CanvasLayer/ModeOverlay/BtnRoundRobin
@onready var _btn_fs: Button = $CanvasLayer/ModeOverlay/BtnFocusedSuite

@export var out_boundary_touch_distance: float = 10.0
@export var out_boundary_avoid_distance: float = 140.0
@export var despawn_areas_enabled: bool = true
@export var startup_detritus_count: int = 20
@export var pellet_target_count: int = 40
@export var pellet_spawn_interval_seconds: float = 0.35
@export_range(1, 20) var round_robin_laps: int = 3
@export_range(1, 100) var win_lead_points: int = 12

var pond_bounds: Rect2
var out_boundary_polygon: PackedVector2Array = PackedVector2Array()
var score_by_player: Dictionary = {1: 0.0, 2: 0.0}
var _redeemed_biomass_by_player: Dictionary = {1: 0.0, 2: 0.0}
## Cached global-space despawn polygon (static after _ready).
var _despawn_polygon_cached: PackedVector2Array = PackedVector2Array()

# --- Playtest HUD ---
var _species_order: Array[StringName] = SpeciesRegistry.all_species()
var _species_textures: Dictionary = {}
const _SLOT_WIDTH: float = 264.0
const _SLOT_HEIGHT: float = 58.0
const _SLOT_GAP: float = 6.0
const _PANEL_TOP: float = 0.0
const _COL_SELECTED: Color = Color(1.0, 0.85, 0.15, 0.92)
const _COL_UNSELECTED: Color = Color(0.08, 0.10, 0.18, 0.80)
const _COL_PANEL_BG: Color = Color(0.03, 0.04, 0.08, 0.83)
const _COL_TEXT_SUBTLE: Color = Color(1.0, 1.0, 1.0, 1.0)

var _hud_slots_p1: Dictionary = {}
var _hud_slots_p2: Dictionary = {}
var _hud_styles_p1: Dictionary = {}
var _hud_styles_p2: Dictionary = {}
var _hud_count_labels_p1: Dictionary = {}
var _hud_count_labels_p2: Dictionary = {}
var _hud_res_p1: Label
var _hud_res_p2: Label
var _hud_diag_bg: Panel
var _hud_diag_label: Label

# --- Match state ---
const _RESET_DELAY: float = 3.5
const _CSV_SCHEMA_VERSION: int = 3
var _ai_profiles: Array = []
var _schedule: Array = []
var _schedule_mode: ScheduleMode = ScheduleMode.ROUND_ROBIN
var _schedule_index: int = 0
var _p1_ai_name: String = "?"
var _p2_ai_name: String = "?"
var _p1_ai_weights: Dictionary = {}
var _p2_ai_weights: Dictionary = {}
var _match_active: bool = true
var _reset_timer: float = 0.0
var _game_id: int = 0
var _win_label: Label
var _spawns_p1: Dictionary = {}
var _spawns_p2: Dictionary = {}
var _spawn_seq_p1: Array[StringName] = []
var _spawn_seq_p2: Array[StringName] = []
var _spawn_seq_events_p1: Array[Dictionary] = []
var _spawn_seq_events_p2: Array[Dictionary] = []
var _match_elapsed_seconds: float = 0.0
var _match_frames: int = 0
var _predations_by_player: Dictionary = {1: 0, 2: 0}
var _feed_events_by_player: Dictionary = {1: 0, 2: 0}
var _feed_by_player_species: Dictionary = {}
var _alive_exits_by_player_species: Dictionary = {}
var _alive_exits_ge1_by_player_species: Dictionary = {}
var _alive_exits_ge3_by_player_species: Dictionary = {}
var _alive_exits_ge5_by_player_species: Dictionary = {}
var _predated_deaths_by_player_species: Dictionary = {}
var _fish_lifecycle_by_id: Dictionary = {}
var _awaiting_mode_selection: bool = true
var _pellet_spawn_timer: float = 0.0
var _debug_sabalo_fish_id: int = 0
var _debug_sabalo_pending_handoff: bool = true


func _ready() -> void:
	randomize()
	_initialize_ai_profiles()
	_species_order = SpeciesRegistry.all_species()
	_spawns_p1 = _zero_species_counter()
	_spawns_p2 = _zero_species_counter()
	_reset_match_analytics()
	_cache_species_textures()
	pond_bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	_build_out_boundary_polygon()
	_build_despawn_polygon_cache()
	_setup_hud()
	# Keep panel from hard-blocking while still allowing child buttons to be pickable.
	_mode_overlay_node.mouse_filter = Control.MOUSE_FILTER_PASS
	_btn_rr.pressed.connect(_begin_selected_mode.bind(ScheduleMode.ROUND_ROBIN))
	_btn_fs.pressed.connect(_begin_selected_mode.bind(ScheduleMode.FOCUSED_SUITE))


func _begin_selected_mode(mode: ScheduleMode) -> void:
	if not _awaiting_mode_selection:
		return
	_awaiting_mode_selection = false
	_schedule_mode = mode
	_mode_overlay_node.hide()
	_build_schedule()
	print("Zoo: mode=%s profiles=%d laps=%d planned_matches=%d" % [
		"RR" if _schedule_mode == ScheduleMode.ROUND_ROBIN else "FOCUSED",
		_ai_profiles.size(),
		round_robin_laps,
		_schedule.size()
	])
	_init_csv_files()
	_start_match()


func _input(event: InputEvent) -> void:
	if not _awaiting_mode_selection:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_1 or key_event.keycode == KEY_KP_1 or key_event.physical_keycode == KEY_1 or key_event.unicode == 49:
		_begin_selected_mode(ScheduleMode.ROUND_ROBIN)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_2 or key_event.keycode == KEY_KP_2 or key_event.physical_keycode == KEY_2 or key_event.unicode == 50:
		_begin_selected_mode(ScheduleMode.FOCUSED_SUITE)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _awaiting_mode_selection:
		if Input.is_key_pressed(KEY_1) or Input.is_physical_key_pressed(KEY_1) or Input.is_key_pressed(KEY_KP_1):
			_begin_selected_mode(ScheduleMode.ROUND_ROBIN)
		elif Input.is_key_pressed(KEY_2) or Input.is_physical_key_pressed(KEY_2) or Input.is_key_pressed(KEY_KP_2):
			_begin_selected_mode(ScheduleMode.FOCUSED_SUITE)
		return
	SpatialGrid.rebuild()
	if _match_active:
		_match_elapsed_seconds += delta
		_match_frames += 1
		_process_pellet_spawning(delta)
		_handle_spawner(delta, spawner_p1)
		_handle_spawner(delta, spawner_p2)
		_process_despawn_areas()
		_check_win_condition()
	else:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_do_reset()
	_update_ui()
	_update_hud()


func _handle_spawner(delta: float, spawner: Node2D) -> void:
	if spawner == null:
		return
	if not spawner.has_method("advance"):
		return
	spawner.call("advance", delta)
	var current_count: int = _live_fish_count_from_spawner(spawner)
	if bool(spawner.call("can_spawn", current_count)):
		_spawn_fish(spawner.call("consume_spawn_request") as Dictionary)


func _spawn_fish(fish_data: Dictionary) -> void:
	var species_name: StringName = fish_data.get("species", SpeciesRegistry.DEFAULT_SPECIES) as StringName
	var normalized_species: StringName = SpeciesRegistry.normalize_species(species_name)
	var fish: Fish = FishPool.acquire(normalized_species)
	if fish == null:
		return

	var player_id: int = int(fish_data.get("player", 1))
	fish.reparent(pond)
	fish.show()
	fish.set_process(true)
	fish.position = fish_data.get("origin", Vector2.ZERO) as Vector2
	var avoid_distance: float = out_boundary_avoid_distance
	if normalized_species == SpeciesDB.SABALO:
		avoid_distance *= 0.5
	var spawn_weight_range: Vector2 = SpeciesRegistry.get_spawn_weight_range(normalized_species, fish.weight)
	fish.configure_from_zoo(
		normalized_species,
		player_id,
		_pick_species_tint(normalized_species, player_id),
		pond_bounds
	)
	fish.set_weight_grams(randf_range(spawn_weight_range.x, spawn_weight_range.y))
	fish.reinitialize()
	fish.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, avoid_distance)
	fish.configure_despawn_area(_compute_despawn_center())
	fish.set_source_spawner(fish_data.get("spawner_path", NodePath()) as NodePath)
	fish.fish_exited.connect(_on_fish_exited)
	if not fish.feed_succeeded.is_connected(_on_fish_feed_succeeded):
		fish.feed_succeeded.connect(_on_fish_feed_succeeded)
	_fish_lifecycle_by_id[fish.get_instance_id()] = {
		"player": player_id,
		"species": normalized_species,
		"feeds": 0,
		"predated": false,
		"alive_exit": false
	}
	if fish is Dientudo:
		var predator: Dientudo = fish as Dientudo
		if not predator.prey_predated.is_connected(_on_prey_predated):
			predator.prey_predated.connect(_on_prey_predated)
	if fish is Sabalo:
		var sabalo: Sabalo = fish as Sabalo
		var should_debug: bool = _debug_sabalo_pending_handoff
		sabalo.set_debug_focus(should_debug)
		if should_debug:
			_debug_sabalo_pending_handoff = false
			_debug_sabalo_fish_id = fish.get_instance_id()
	SpatialGrid.register_fish(fish)
	if player_id == 1:
		_spawns_p1[normalized_species] = int(_spawns_p1.get(normalized_species, 0)) + 1
		_spawn_seq_p1.append(normalized_species)
	else:
		_spawns_p2[normalized_species] = int(_spawns_p2.get(normalized_species, 0)) + 1
		_spawn_seq_p2.append(normalized_species)
	_record_spawn_sequence_event(player_id, normalized_species)


func _compute_despawn_center() -> Vector2:
	if despawn_area == null or despawn_area.polygon.size() < 3:
		return Vector2(640.0, 900.0)
	var accum: Vector2 = Vector2.ZERO
	for local_point: Vector2 in despawn_area.polygon:
		accum += despawn_area.to_global(local_point)
	return accum / float(despawn_area.polygon.size())


func _spawn_detritus(spawn_position: Vector2, detritus_units: int) -> void:
	if detritus_units <= 0:
		return
	var detritus_fish: Fish = FishPool.acquire(SpeciesRegistry.DETRITUS)
	if detritus_fish == null:
		return

	detritus_fish.reparent(pond)
	detritus_fish.show()
	detritus_fish.set_process(true)
	detritus_fish.position = spawn_position
	detritus_fish.configure_from_zoo(SpeciesRegistry.DETRITUS, 1, Color(0.45, 0.30, 0.14, 1.0), pond_bounds)
	detritus_fish.reinitialize()
	detritus_fish.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, out_boundary_avoid_distance)
	detritus_fish.configure_despawn_area(_compute_despawn_center())
	detritus_fish.set_source_spawner(NodePath())
	if detritus_fish is Detritus:
		(detritus_fish as Detritus).set_detritus_value(detritus_units)
	SpatialGrid.register_fish(detritus_fish)


func _spawn_pellet(spawn_position: Vector2) -> void:
	var pellet: Fish = FishPool.acquire(SpeciesRegistry.PELLET)
	if pellet == null:
		return

	pellet.reparent(pond)
	pellet.show()
	pellet.set_process(true)
	pellet.position = spawn_position
	pellet.configure_from_zoo(SpeciesRegistry.PELLET, 1, Color(1.0, 1.0, 1.0, 1.0), pond_bounds)
	pellet.reinitialize()
	pellet.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, out_boundary_avoid_distance)
	pellet.configure_despawn_area(_compute_despawn_center())
	pellet.set_source_spawner(NodePath())
	SpatialGrid.register_fish(pellet)


func _seed_startup_pellets() -> void:
	for _i: int in range(maxi(pellet_target_count, 0)):
		_spawn_pellet(_random_point_in_pond())


func _process_pellet_spawning(delta: float) -> void:
	if pellet_target_count <= 0:
		return
	_pellet_spawn_timer -= delta
	if _pellet_spawn_timer > 0.0:
		return

	var live_pellets: int = 0
	for child: Node in pond.get_children():
		if not (child is Fish):
			continue
		var fish: Fish = child as Fish
		if fish.species == SpeciesRegistry.PELLET and not fish.pending_remove:
			live_pellets += 1

	if live_pellets < pellet_target_count:
		_spawn_pellet(_random_point_in_pond())
		_pellet_spawn_timer = maxf(pellet_spawn_interval_seconds, 0.02)
	else:
		_pellet_spawn_timer = 0.25


func _seed_startup_detritus() -> void:
	var requested: int = maxi(startup_detritus_count, 0)
	for _i: int in range(requested):
		_spawn_detritus(_random_point_in_pond_outside_despawn(), 1)

	var live_now: int = _count_live_species(SpeciesRegistry.DETRITUS)
	var sample_alpha: float = -1.0
	for child: Node in pond.get_children():
		if not (child is Detritus):
			continue
		var d: Detritus = child as Detritus
		if d.pending_remove:
			continue
		if d.sprite != null:
			sample_alpha = d.sprite.modulate.a
		break
	print("Zoo: startup detritus requested=%d live_now=%d sample_alpha=%.2f" % [requested, live_now, sample_alpha])


func _random_point_in_pond_outside_despawn() -> Vector2:
	if _despawn_polygon_cached.size() < 3:
		return _random_point_in_pond()
	for _attempt: int in range(96):
		var candidate: Vector2 = _random_point_in_pond()
		if not Geometry2D.is_point_in_polygon(candidate, _despawn_polygon_cached):
			return candidate
	return _random_point_in_pond()


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

	for _attempt: int in range(48):
		var candidate: Vector2 = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(candidate, out_boundary_polygon):
			return candidate

	return out_boundary_polygon[randi() % out_boundary_polygon.size()]


func _on_prey_predated(prey_position: Vector2, prey_weight_g: float, predator_player: int, prey_player: int, prey_species: StringName, prey_fish_id: int, prey_feed_count: int) -> void:
	if predator_player == 1 or predator_player == 2:
		_predations_by_player[predator_player] = int(_predations_by_player.get(predator_player, 0)) + 1
	if prey_player == 1 or prey_player == 2:
		_increment_species_metric(_predated_deaths_by_player_species, prey_player, prey_species)
		if _fish_lifecycle_by_id.has(prey_fish_id):
			var prey_entry: Dictionary = _fish_lifecycle_by_id[prey_fish_id] as Dictionary
			prey_entry["predated"] = true
			prey_entry["feeds"] = maxi(int(prey_entry.get("feeds", 0)), prey_feed_count)
			_fish_lifecycle_by_id[prey_fish_id] = prey_entry
	if prey_species == SpeciesRegistry.SABALO and prey_fish_id == _debug_sabalo_fish_id:
		_debug_sabalo_fish_id = 0
		_debug_sabalo_pending_handoff = true
	var detritus_units: int = _roll_predation_detritus_value(prey_weight_g)
	if detritus_units > 0:
		_spawn_detritus(prey_position, detritus_units)


func _roll_predation_detritus_value(prey_weight_g: float) -> int:
	var roll_count: int = int(floor(prey_weight_g / 50.0))
	if roll_count <= 0:
		return 0
	var detritus_units: int = 0
	for _i: int in range(roll_count):
		if randf() <= 0.20:
			detritus_units += 1
	return detritus_units


func _build_out_boundary_polygon() -> void:
	if pond_shape == null or pond_shape.polygon.size() < 3:
		out_boundary_polygon = PackedVector2Array([
			Vector2(60.0, 120.0),
			Vector2(1220.0, 105.0),
			Vector2(1240.0, 680.0),
			Vector2(40.0, 690.0)
		])
	else:
		# PondShape is editable in local space and may be moved/scaled in the scene.
		# Fish and Line2D need points in global (world) coordinates.
		var global_poly: PackedVector2Array = PackedVector2Array()
		for local_point: Vector2 in pond_shape.polygon:
			global_poly.append(pond_shape.to_global(local_point))
		out_boundary_polygon = global_poly

	if out_boundary != null:
		out_boundary.points = out_boundary_polygon


func _build_despawn_polygon_cache() -> void:
	if despawn_area == null or despawn_area.polygon.size() < 3:
		return
	_despawn_polygon_cached = PackedVector2Array()
	for local_point: Vector2 in despawn_area.polygon:
		_despawn_polygon_cached.append(despawn_area.to_global(local_point))


func _pick_species_tint(species_name: StringName, player_id: int) -> Color:
	if species_name == SpeciesRegistry.GUPPY:
		if player_id == 1:
			return Color.from_hsv(randf_range(0.612, 0.632), randf_range(0.88, 0.96), randf_range(0.74, 0.86), 1.0)
		return Color.from_hsv(randf_range(0.030, 0.055), randf_range(0.90, 1.00), randf_range(0.85, 0.96), 1.0)

	if species_name == SpeciesRegistry.SABALO:
		if player_id == 1:
			return Color.from_hsv(randf_range(0.56, 0.62), randf_range(0.12, 0.24), randf_range(0.54, 0.72), 1.0)
		return Color.from_hsv(randf_range(0.90, 0.96), randf_range(0.35, 0.54), randf_range(0.84, 0.96), 1.0)

	if species_name == SpeciesRegistry.DIENTUDO:
		if player_id == 1:
			return Color.from_hsv(randf_range(0.43, 0.47), randf_range(0.62, 0.86), randf_range(0.78, 0.95), 1.0)
		return Color.from_hsv(randf_range(0.0, 0.01), randf_range(0.90, 1.00), randf_range(0.90, 1.00), 1.0)

	if species_name == SpeciesRegistry.DETRITUS:
		return Color(0.45, 0.30, 0.14, 1.0)

	return Color(1.0, 1.0, 1.0, 1.0)


func _on_fish_exited(player_id: int, point_value: int, redeemed_biomass_g: float, fish_id: int, fish_species: StringName, feed_count: int) -> void:
	if player_id != 1 and player_id != 2:
		return
	if fish_species == SpeciesRegistry.SABALO and fish_id == _debug_sabalo_fish_id:
		_debug_sabalo_fish_id = 0
		_debug_sabalo_pending_handoff = true
	score_by_player[player_id] = float(score_by_player.get(player_id, 0.0)) + float(point_value)
	_redeemed_biomass_by_player[player_id] = float(_redeemed_biomass_by_player.get(player_id, 0.0)) + redeemed_biomass_g
	_register_alive_exit(player_id, fish_species, feed_count)
	if _fish_lifecycle_by_id.has(fish_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[fish_id] as Dictionary
		fish_entry["alive_exit"] = true
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		_fish_lifecycle_by_id[fish_id] = fish_entry


func _on_fish_feed_succeeded(player_id: int, fish_species: StringName, fish_id: int, feed_count: int) -> void:
	if player_id != 1 and player_id != 2:
		return
	_feed_events_by_player[player_id] = int(_feed_events_by_player.get(player_id, 0)) + 1
	_increment_species_metric(_feed_by_player_species, player_id, fish_species)
	if _fish_lifecycle_by_id.has(fish_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[fish_id] as Dictionary
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		_fish_lifecycle_by_id[fish_id] = fish_entry


func _process_despawn_areas() -> void:
	if not despawn_areas_enabled:
		return
	if despawn_area == null or _despawn_polygon_cached.size() < 3:
		return

	for child: Node in pond.get_children():
		if not (child is Fish):
			continue

		var fish: Fish = child as Fish
		if fish.pending_remove:
			continue

		if Geometry2D.is_point_in_polygon(fish.global_position, _despawn_polygon_cached):
			_despawn_and_tally(fish)


func _despawn_and_tally(fish: Fish) -> void:
	if fish.pending_remove:
		return
	if fish.species == SpeciesRegistry.DETRITUS:
		FishPool.release(fish)
		return
	if fish is Sabalo:
		var sabalo: Sabalo = fish as Sabalo
		var refund_units: int = sabalo.get_resource_refund_units()
		if refund_units > 0:
			_grant_resource_bonus(fish.player, float(refund_units))
		if fish.get_instance_id() == _debug_sabalo_fish_id:
			_debug_sabalo_fish_id = 0
			_debug_sabalo_pending_handoff = true

	score_by_player[fish.player] = float(score_by_player.get(fish.player, 0.0)) + float(fish.get_point_value())
	_redeemed_biomass_by_player[fish.player] = float(_redeemed_biomass_by_player.get(fish.player, 0.0)) + fish.get_redeemable_biomass_g()
	_register_alive_exit(fish.player, fish.species, fish.get_successful_feed_count())
	FishPool.release(fish)


func _grant_resource_bonus(player_id: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var target_spawner: Node2D = spawner_p1 if player_id == 1 else spawner_p2
	if target_spawner == null:
		return
	if target_spawner.has_method("add_resource"):
		target_spawner.call("add_resource", amount)


func _live_fish_count() -> int:
	var total: int = 0
	for child: Node in pond.get_children():
		if child is Fish:
			var fish: Fish = child as Fish
			if fish.species == SpeciesRegistry.DETRITUS:
				continue
			total += 1
	return total


func _live_fish_count_from_spawner(spawner: Node2D) -> int:
	var total: int = 0
	var spawner_path: NodePath = spawner.get_path()
	for child: Node in pond.get_children():
		if not (child is Fish):
			continue
		var fish: Fish = child as Fish
		if fish.species == SpeciesRegistry.DETRITUS:
			continue
		if fish.source_spawner == spawner_path:
			total += 1
	return total


func _update_ui() -> void:
	var p1_score: int = int(round(float(score_by_player.get(1, 0.0))))
	var p2_score: int = int(round(float(score_by_player.get(2, 0.0))))
	score_p1_label.text = "%s POINTS: %d" % [_p1_ai_name, p1_score]
	score_p2_label.text = "%s POINTS: %d" % [_p2_ai_name, p2_score]
	var lap: int = 1
	if _schedule_index < _schedule.size():
		lap = int(_schedule[_schedule_index].get("lap", 0)) + 1
	var lead: int = absi(p1_score - p2_score)
	count_label.text = "GAME %d/%d  LAP %d  |  %s vs %s  |  FISH %d  |  LEAD %d/%d pts" % [_game_id + 1, _schedule.size(), lap, _p1_ai_name, _p2_ai_name, _live_fish_count(), lead, win_lead_points]


func _setup_hud() -> void:
	var cl: CanvasLayer = $CanvasLayer
	var vp_w: float = get_viewport_rect().size.x
	var vp_h: float = get_viewport_rect().size.y

	score_p1_label.position = Vector2(vp_w * 0.5 - 430.0, vp_h - 148.0)
	score_p1_label.size = Vector2(320.0, 34.0)
	score_p1_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_p1_label.add_theme_color_override("font_color", Color(0.58, 0.88, 1.0, 1.0))
	score_p1_label.add_theme_font_size_override("font_size", 24)
	score_p1_label.add_theme_constant_override("outline_size", 2)
	score_p1_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))

	score_p2_label.position = Vector2(vp_w * 0.5 + 110.0, vp_h - 148.0)
	score_p2_label.size = Vector2(320.0, 34.0)
	score_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_p2_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 1.0))
	score_p2_label.add_theme_font_size_override("font_size", 24)
	score_p2_label.add_theme_constant_override("outline_size", 2)
	score_p2_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))

	count_label.position = Vector2(vp_w * 0.5 - 420.0, vp_h - 114.0)
	count_label.size = Vector2(840.0, 28.0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_constant_override("outline_size", 2)
	count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))

	_hud_res_p1 = _make_res_label(Vector2(42.0, vp_h - 254.0), HORIZONTAL_ALIGNMENT_LEFT)
	cl.add_child(_hud_res_p1)
	_hud_res_p2 = _make_res_label(Vector2(vp_w - _SLOT_WIDTH - 42.0, vp_h - 254.0), HORIZONTAL_ALIGNMENT_RIGHT)
	cl.add_child(_hud_res_p2)

	_setup_player_hud(cl, Vector2(42.0, vp_h - 220.0), _hud_slots_p1, _hud_styles_p1, _hud_count_labels_p1, false)
	_setup_player_hud(cl, Vector2(vp_w - _SLOT_WIDTH - 42.0, vp_h - 220.0), _hud_slots_p2, _hud_styles_p2, _hud_count_labels_p2, true)

	_hud_diag_bg = Panel.new()
	_hud_diag_bg.position = Vector2(vp_w * 0.5 - 304.0, vp_h - 92.0)
	_hud_diag_bg.size = Vector2(608.0, 80.0)
	var diag_bg_style: StyleBoxFlat = StyleBoxFlat.new()
	diag_bg_style.bg_color = Color(0.02, 0.02, 0.05, 0.82)
	diag_bg_style.set_corner_radius_all(8)
	diag_bg_style.border_width_left = 1
	diag_bg_style.border_width_right = 1
	diag_bg_style.border_width_top = 1
	diag_bg_style.border_width_bottom = 1
	diag_bg_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	_hud_diag_bg.add_theme_stylebox_override("panel", diag_bg_style)
	cl.add_child(_hud_diag_bg)

	_hud_diag_label = Label.new()
	_hud_diag_label.position = Vector2(vp_w * 0.5 - 290.0, vp_h - 86.0)
	_hud_diag_label.size = Vector2(580.0, 72.0)
	_hud_diag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_diag_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_hud_diag_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_hud_diag_label.add_theme_constant_override("outline_size", 1)
	_hud_diag_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_hud_diag_label.add_theme_font_size_override("font_size", 16)
	cl.add_child(_hud_diag_label)
	# Win announcement label
	var win_bg: StyleBoxFlat = StyleBoxFlat.new()
	win_bg.bg_color = Color(0.04, 0.04, 0.08, 0.88)
	win_bg.set_corner_radius_all(12)
	_win_label = Label.new()
	_win_label.add_theme_stylebox_override("normal", win_bg)
	_win_label.add_theme_font_size_override("font_size", 52)
	_win_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15, 1.0))
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_win_label.position = Vector2(vp_w * 0.5 - 340.0, vp_h * 0.5 - 60.0)
	_win_label.size = Vector2(680.0, 120.0)
	_win_label.hide()
	cl.add_child(_win_label)


func _make_res_label(pos: Vector2, align: HorizontalAlignment) -> Label:
	var lbl: Label = Label.new()
	lbl.position = pos
	lbl.custom_minimum_size = Vector2(_SLOT_WIDTH, 30.0)
	lbl.horizontal_alignment = align
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_font_size_override("font_size", 19)
	return lbl


func _cache_species_textures() -> void:
	_species_textures.clear()
	for species_name: StringName in _species_order:
		var species_data: Dictionary = SpeciesRegistry.get_species_data(species_name)
		var texture_path: String = String(species_data.get("texture_path", ""))
		if texture_path == "":
			continue
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			_species_textures[species_name] = texture


func _zero_species_counter() -> Dictionary:
	var counters: Dictionary = {}
	for species_name: StringName in _species_order:
		counters[species_name] = 0
	return counters


func _sum_species_values(values: Dictionary) -> float:
	var total: float = 0.0
	for species_name: StringName in _species_order:
		total += float(values.get(species_name, 0.0))
	return total


func _setup_player_hud(cl: CanvasLayer, base: Vector2, slots: Dictionary, styles: Dictionary, count_labels: Dictionary, right_aligned: bool) -> void:
	for i: int in _species_order.size():
		var species: StringName = _species_order[i]
		var panel: Panel = Panel.new()
		panel.position = base + Vector2(0.0, float(i) * (_SLOT_HEIGHT + _SLOT_GAP))
		panel.size = Vector2(_SLOT_WIDTH, _SLOT_HEIGHT)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = _COL_PANEL_BG
		style.set_corner_radius_all(6)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = _COL_UNSELECTED
		panel.add_theme_stylebox_override("panel", style)

		var row: HBoxContainer = HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)

		if right_aligned:
			row.alignment = BoxContainer.ALIGNMENT_END

		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(42.0, 42.0)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _species_textures.get(species, null) as Texture2D

		var name_lbl: Label = Label.new()
		name_lbl.text = "%s (%d)" % [SpeciesRegistry.get_display_name(species), SpeciesRegistry.get_spawn_cost(species)]
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_constant_override("outline_size", 2)
		name_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		name_lbl.custom_minimum_size = Vector2(132.0, 42.0)

		var count_lbl: Label = Label.new()
		count_lbl.text = "x0"
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		count_lbl.add_theme_constant_override("outline_size", 2)
		count_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		count_lbl.custom_minimum_size = Vector2(56.0, 42.0)

		if right_aligned:
			row.add_child(count_lbl)
			row.add_child(name_lbl)
			row.add_child(icon)
		else:
			row.add_child(icon)
			row.add_child(name_lbl)
			row.add_child(count_lbl)

		cl.add_child(panel)
		slots[species] = panel
		styles[species] = style
		count_labels[species] = count_lbl


func _update_hud() -> void:
	if spawner_p1 == null or spawner_p2 == null:
		return
	if _hud_res_p1 == null or _hud_res_p2 == null:
		return
	var p1_score: int = int(round(float(score_by_player.get(1, 0.0))))
	var p2_score: int = int(round(float(score_by_player.get(2, 0.0))))
	var res1: float = float(spawner_p1.get("resources"))
	var res2: float = float(spawner_p2.get("resources"))
	_hud_res_p1.text = "%s | RES %d/%d" % [_p1_ai_name, int(res1), int(FishSpawner.RESOURCE_MAX)]
	_hud_res_p2.text = "%s | RES %d/%d" % [_p2_ai_name, int(res2), int(FishSpawner.RESOURCE_MAX)]
	var sel1: StringName = spawner_p1.get("selected_species") as StringName
	var sel2: StringName = spawner_p2.get("selected_species") as StringName
	for species: StringName in _species_order:
		if _hud_styles_p1.has(species):
			(_hud_styles_p1[species] as StyleBoxFlat).border_color = _COL_SELECTED if species == sel1 else _COL_UNSELECTED
		if _hud_styles_p2.has(species):
			(_hud_styles_p2[species] as StyleBoxFlat).border_color = _COL_SELECTED if species == sel2 else _COL_UNSELECTED
		if _hud_count_labels_p1.has(species):
			(_hud_count_labels_p1[species] as Label).text = "x%d" % int(_spawns_p1.get(species, 0))
		if _hud_count_labels_p2.has(species):
			(_hud_count_labels_p2[species] as Label).text = "x%d" % int(_spawns_p2.get(species, 0))

	if _hud_diag_label != null:
		var lead: int = p1_score - p2_score
		var match_state: String = "RUNNING" if _match_active else "RESET %.1fs" % maxf(0.0, _reset_timer)
		var spent_p1: Dictionary = {}
		var spent_p2: Dictionary = {}
		if spawner_p1 != null and spawner_p1.get("resources_spent_by_species") is Dictionary:
			spent_p1 = spawner_p1.get("resources_spent_by_species") as Dictionary
		if spawner_p2 != null and spawner_p2.get("resources_spent_by_species") is Dictionary:
			spent_p2 = spawner_p2.get("resources_spent_by_species") as Dictionary
		_hud_diag_label.text = "Systems: %s | Lead %+d | Sel P1 %s / P2 %s\nSpent P1 %.0f / P2 %.0f | Sched %d/%d" % [
			match_state,
			lead,
			SpeciesRegistry.get_display_name(sel1),
			SpeciesRegistry.get_display_name(sel2),
			_sum_species_values(spent_p1),
			_sum_species_values(spent_p2),
			_schedule_index + 1,
			_schedule.size()
		]


func _check_win_condition() -> void:
	var s1: float = float(score_by_player.get(1, 0.0))
	var s2: float = float(score_by_player.get(2, 0.0))
	if s1 - s2 >= float(win_lead_points):
		_end_round(1)
	elif s2 - s1 >= float(win_lead_points):
		_end_round(2)


func _end_round(winner_player: int) -> void:
	_match_active = false
	_reset_timer = _RESET_DELAY
	var winner_ai: String = _p1_ai_name if winner_player == 1 else _p2_ai_name
	if _win_label != null:
		_win_label.text = "%s wins!" % winner_ai
		_win_label.show()
	_write_csv_row(winner_ai)
	_write_round_metrics_row(winner_ai)
	_write_spawn_sequences()


func _do_reset() -> void:
	var children: Array = pond.get_children().duplicate()
	for child: Node in children:
		if child is Fish:
			FishPool.release(child as Fish)
	score_by_player = {1: 0.0, 2: 0.0}
	_redeemed_biomass_by_player = {1: 0.0, 2: 0.0}
	_spawns_p1 = _zero_species_counter()
	_spawns_p2 = _zero_species_counter()
	_spawn_seq_p1.clear()
	_spawn_seq_p2.clear()
	_spawn_seq_events_p1.clear()
	_spawn_seq_events_p2.clear()
	_fish_lifecycle_by_id.clear()
	_debug_sabalo_fish_id = 0
	_debug_sabalo_pending_handoff = true
	_pellet_spawn_timer = 0.0
	_reset_match_analytics()
	if spawner_p1 != null and spawner_p1.has_method("reset"):
		spawner_p1.call("reset")
	if spawner_p2 != null and spawner_p2.has_method("reset"):
		spawner_p2.call("reset")
	_game_id += 1
	if _win_label != null:
		_win_label.hide()
	_schedule_index += 1
	if _schedule_index >= _schedule.size():
		get_tree().quit()
		return
	_start_match()


func _write_csv_row(winner_ai: String) -> void:
	var path: String = "user://playtests.csv"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Zoo: could not open %s" % path)
		return
	file.seek_end()
	var entry: Dictionary = _schedule[_schedule_index]
	var p1_spent: Dictionary = {}
	var p2_spent: Dictionary = {}
	if spawner_p1 != null and spawner_p1.get("resources_spent_by_species") is Dictionary:
		p1_spent = spawner_p1.get("resources_spent_by_species") as Dictionary
	if spawner_p2 != null and spawner_p2.get("resources_spent_by_species") is Dictionary:
		p2_spent = spawner_p2.get("resources_spent_by_species") as Dictionary
	var p1_spent_total: float = _sum_species_values(p1_spent)
	var p2_spent_total: float = _sum_species_values(p2_spent)
	var p1_points: float = float(score_by_player.get(1, 0.0))
	var p2_points: float = float(score_by_player.get(2, 0.0))
	var p1_biomass: float = float(_redeemed_biomass_by_player.get(1, 0.0))
	var p2_biomass: float = float(_redeemed_biomass_by_player.get(2, 0.0))
	var p1_efficiency: float = p1_points / maxf(1.0, p1_spent_total)
	var p2_efficiency: float = p2_points / maxf(1.0, p2_spent_total)
	var row: String = "%d,%d,%d,%s,%s,%s,%s,%s,%.3f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%d,%d,%.4f,%.4f" % [
		_CSV_SCHEMA_VERSION,
		_game_id,
		int(entry.get("lap", 0)),
		_p1_ai_name,
		_p2_ai_name,
		_weights_to_compact_string(_p1_ai_weights),
		_weights_to_compact_string(_p2_ai_weights),
		winner_ai,
		_match_elapsed_seconds,
		_match_frames,
		int(_spawns_p1.get(&"guppy", 0)),
		int(_spawns_p1.get(&"sabalo", 0)),
		int(_spawns_p1.get(&"dientudo", 0)),
		int(_spawns_p2.get(&"guppy", 0)),
		int(_spawns_p2.get(&"sabalo", 0)),
		int(_spawns_p2.get(&"dientudo", 0)),
		int(_feed_events_by_player.get(1, 0)),
		int(_feed_events_by_player.get(2, 0)),
		int(_predations_by_player.get(1, 0)),
		int(_predations_by_player.get(2, 0)),
		p1_spent_total,
		p2_spent_total,
		p1_points,
		p2_points,
		p1_biomass,
		p2_biomass,
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.GUPPY)),
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.SABALO)),
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.DIENTUDO)),
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.GUPPY)),
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.SABALO)),
		int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.DIENTUDO)),
		p1_efficiency,
		p2_efficiency
	]
	file.store_line(row)
	file.close()
	print("Zoo: match=%d winner=%s duration=%.1fs points=%d/%d biomass=%dg/%dg efficiency=%.3f/%.3f" % [
		_game_id,
		winner_ai,
		_match_elapsed_seconds,
		int(round(p1_points)),
		int(round(p2_points)),
		int(round(p1_biomass)),
		int(round(p2_biomass)),
		p1_efficiency,
		p2_efficiency
	])


func _write_round_metrics_row(winner_ai: String) -> void:
	var file: FileAccess = FileAccess.open("user://round_metrics.csv", FileAccess.READ_WRITE)
	if file == null:
		push_error("Zoo: could not open user://round_metrics.csv")
		return
	file.seek_end()
	for player_id: int in [1, 2]:
		for species_name: StringName in _species_order:
			var row: String = "%d,%d,%s,%s,%d,%s,%d,%d,%d,%d,%d,%d,%d" % [
				_CSV_SCHEMA_VERSION,
				_game_id,
				winner_ai,
				_p1_ai_name if player_id == 1 else _p2_ai_name,
				player_id,
				species_name,
				int(_species_metric_value(_feed_by_player_species, player_id, species_name)),
				int(_species_metric_value(_alive_exits_by_player_species, player_id, species_name)),
				int(_species_metric_value(_alive_exits_ge1_by_player_species, player_id, species_name)),
				int(_species_metric_value(_alive_exits_ge3_by_player_species, player_id, species_name)),
				int(_species_metric_value(_alive_exits_ge5_by_player_species, player_id, species_name)),
				int(_species_metric_value(_predated_deaths_by_player_species, player_id, species_name)),
				int(_spawns_p1.get(species_name, 0)) if player_id == 1 else int(_spawns_p2.get(species_name, 0))
			]
			file.store_line(row)
	file.close()


func _write_spawn_sequences() -> void:
	var path: String = "user://spawn_sequences.csv"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Zoo: could not open %s" % path)
		return
	file.seek_end()
	for event: Dictionary in _spawn_seq_events_p1:
		file.store_line("%d,%s,%d,%s,%d,%.3f,%.4f,%.4f,%.4f" % [
			_game_id,
			_p1_ai_name,
			int(event.get("order", 0)),
			event.get("species", SpeciesRegistry.DEFAULT_SPECIES),
			int(event.get("frame", 0)),
			float(event.get("time_s", 0.0)),
			float(event.get("guppy_spent_ratio", 0.0)),
			float(event.get("sabalo_spent_ratio", 0.0)),
			float(event.get("dientudo_spent_ratio", 0.0))
		])
	for event: Dictionary in _spawn_seq_events_p2:
		file.store_line("%d,%s,%d,%s,%d,%.3f,%.4f,%.4f,%.4f" % [
			_game_id,
			_p2_ai_name,
			int(event.get("order", 0)),
			event.get("species", SpeciesRegistry.DEFAULT_SPECIES),
			int(event.get("frame", 0)),
			float(event.get("time_s", 0.0)),
			float(event.get("guppy_spent_ratio", 0.0)),
			float(event.get("sabalo_spent_ratio", 0.0)),
			float(event.get("dientudo_spent_ratio", 0.0))
		])
	file.close()


func _build_schedule() -> void:
	_schedule.clear()
	if _schedule_mode == ScheduleMode.FOCUSED_SUITE:
		_build_focused_suite_schedule()
		return
	for lap: int in range(maxi(1, round_robin_laps)):
		for i: int in range(_ai_profiles.size()):
			for j: int in range(i + 1, _ai_profiles.size()):
				_schedule.append({"lap": lap, "p1": i, "p2": j})


func _build_focused_suite_schedule() -> void:
	var idx_g: int = _find_ai_profile_index("G100S0D0")
	var idx_s: int = _find_ai_profile_index("G0S100D0")
	var idx_d: int = _find_ai_profile_index("G0S0D100")
	if idx_g < 0 or idx_s < 0 or idx_d < 0:
		# Fallback to current full schedule if expected profiles are missing.
		for lap: int in range(maxi(1, round_robin_laps)):
			for i: int in range(_ai_profiles.size()):
				for j: int in range(i + 1, _ai_profiles.size()):
					_schedule.append({"lap": lap, "p1": i, "p2": j})
		return

	var pairings: Array = [
		{"p1": idx_g, "p2": idx_s},
		{"p1": idx_s, "p2": idx_d},
		{"p1": idx_d, "p2": idx_g},
	]
	for lap: int in range(maxi(1, round_robin_laps)):
		for pairing: Dictionary in pairings:
			_schedule.append({"lap": lap, "p1": int(pairing["p1"]), "p2": int(pairing["p2"])})


func _find_ai_profile_index(profile_name: String) -> int:
	for i: int in range(_ai_profiles.size()):
		var profile: Dictionary = _ai_profiles[i] as Dictionary
		if String(profile.get("name", "")) == profile_name:
			return i
	return -1


func _init_csv_files() -> void:
	var f1: FileAccess = FileAccess.open("user://playtests.csv", FileAccess.WRITE)
	if f1 != null:
		f1.store_line("schema_version,game_id,lap,p1_ai,p2_ai,p1_weights,p2_weights,winner_ai,match_seconds,match_frames,p1_guppy,p1_sabalo,p1_dientudo,p2_guppy,p2_sabalo,p2_dientudo,p1_feed_events,p2_feed_events,p1_predations,p2_predations,p1_resources_spent,p2_resources_spent,p1_score_points,p2_score_points,p1_redeemed_biomass_g,p2_redeemed_biomass_g,p1_guppy_alive_exit_ge5,p1_sabalo_alive_exit_ge5,p1_dientudo_alive_exit_ge5,p2_guppy_alive_exit_ge5,p2_sabalo_alive_exit_ge5,p2_dientudo_alive_exit_ge5,p1_points_per_resource,p2_points_per_resource")
		f1.close()
		print("Zoo: playtests.csv -> ", ProjectSettings.globalize_path("user://playtests.csv"))
	var f2: FileAccess = FileAccess.open("user://spawn_sequences.csv", FileAccess.WRITE)
	if f2 != null:
		f2.store_line("game_id,player_ai,order,species,frame,time_s,guppy_spent_ratio,sabalo_spent_ratio,dientudo_spent_ratio")
		f2.close()
	var f3: FileAccess = FileAccess.open("user://round_metrics.csv", FileAccess.WRITE)
	if f3 != null:
		f3.store_line("schema_version,game_id,winner_ai,player_ai,player_id,species,feed_events,alive_exits,alive_exits_ge1,alive_exits_ge3,alive_exits_ge5,predated_deaths,spawns")
		f3.close()


func _start_match() -> void:
	var entry: Dictionary = _schedule[_schedule_index]
	var p1_profile: Dictionary = _ai_profiles[int(entry["p1"])] as Dictionary
	var p2_profile: Dictionary = _ai_profiles[int(entry["p2"])] as Dictionary
	_p1_ai_name = p1_profile["name"] as String
	_p2_ai_name = p2_profile["name"] as String
	_p1_ai_weights = (p1_profile.get("weights", {}) as Dictionary).duplicate(true)
	_p2_ai_weights = (p2_profile.get("weights", {}) as Dictionary).duplicate(true)
	_reset_match_analytics()
	if spawner_p1 != null and spawner_p1.has_method("configure_strategy"):
		spawner_p1.call("configure_strategy", _p1_ai_name, p1_profile["weights"])
	if spawner_p2 != null and spawner_p2.has_method("configure_strategy"):
		spawner_p2.call("configure_strategy", _p2_ai_name, p2_profile["weights"])
	_match_active = true
	_seed_startup_pellets()
	_seed_startup_detritus()


func _initialize_ai_profiles() -> void:
	_ai_profiles = [
		_make_profile("G100S0D0", 1.00, 0.00, 0.00),
		_make_profile("G0S100D0", 0.00, 1.00, 0.00),
		_make_profile("G0S0D100", 0.00, 0.00, 1.00),
		_make_profile("G33S33D34", 0.33, 0.33, 0.34),
		_make_profile("G50S25D25", 0.50, 0.25, 0.25),
		_make_profile("G25S50D25", 0.25, 0.50, 0.25),
		_make_profile("G25S25D50", 0.25, 0.25, 0.50),
		_make_profile("G75S15D10", 0.75, 0.15, 0.10),
		_make_profile("G75S10D15", 0.75, 0.10, 0.15),
		_make_profile("G15S75D10", 0.15, 0.75, 0.10),
		_make_profile("G10S75D15", 0.10, 0.75, 0.15),
		_make_profile("G15S10D75", 0.15, 0.10, 0.75),
		_make_profile("G10S15D75", 0.10, 0.15, 0.75),
		_make_profile("G40S40D20", 0.40, 0.40, 0.20),
		_make_profile("G40S20D40", 0.40, 0.20, 0.40),
		_make_profile("G20S40D40", 0.20, 0.40, 0.40),
	]
	_validate_ai_profiles()


func _make_profile(profile_name: String, guppy: float, sabalo: float, dientudo: float) -> Dictionary:
	return {
		"name": profile_name,
		"weights": {
			SpeciesRegistry.GUPPY: guppy,
			SpeciesRegistry.SABALO: sabalo,
			SpeciesRegistry.DIENTUDO: dientudo
		}
	}


func _validate_ai_profiles() -> void:
	if _ai_profiles.size() != 16:
		push_error("Zoo: expected 16 AI profiles, got %d" % _ai_profiles.size())
	for profile_any: Variant in _ai_profiles:
		var profile: Dictionary = profile_any as Dictionary
		var profile_name: String = String(profile.get("name", ""))
		var weights: Dictionary = profile.get("weights", {}) as Dictionary
		var sum_weights: float = 0.0
		for species_name: StringName in _species_order:
			sum_weights += maxf(0.0, float(weights.get(species_name, 0.0)))
		if absf(sum_weights - 1.0) > 0.001:
			push_error("Zoo: invalid weights for %s (sum=%.4f)" % [profile_name, sum_weights])


func _reset_match_analytics() -> void:
	_match_elapsed_seconds = 0.0
	_match_frames = 0
	_predations_by_player = {1: 0, 2: 0}
	_feed_events_by_player = {1: 0, 2: 0}
	_feed_by_player_species = _new_player_species_metrics()
	_alive_exits_by_player_species = _new_player_species_metrics()
	_alive_exits_ge1_by_player_species = _new_player_species_metrics()
	_alive_exits_ge3_by_player_species = _new_player_species_metrics()
	_alive_exits_ge5_by_player_species = _new_player_species_metrics()
	_predated_deaths_by_player_species = _new_player_species_metrics()
	_fish_lifecycle_by_id.clear()
	_spawn_seq_events_p1.clear()
	_spawn_seq_events_p2.clear()


func _new_player_species_metrics() -> Dictionary:
	return {
		1: _zero_species_counter(),
		2: _zero_species_counter()
	}


func _increment_species_metric(metrics: Dictionary, player_id: int, species_name: StringName) -> void:
	if not metrics.has(player_id):
		metrics[player_id] = _zero_species_counter()
	var per_species: Dictionary = metrics[player_id] as Dictionary
	per_species[species_name] = int(per_species.get(species_name, 0)) + 1
	metrics[player_id] = per_species


func _species_metric_value(metrics: Dictionary, player_id: int, species_name: StringName) -> int:
	if not metrics.has(player_id):
		return 0
	var per_species: Dictionary = metrics[player_id] as Dictionary
	return int(per_species.get(species_name, 0))


func _register_alive_exit(player_id: int, species_name: StringName, feed_count: int) -> void:
	_increment_species_metric(_alive_exits_by_player_species, player_id, species_name)
	if feed_count >= 1:
		_increment_species_metric(_alive_exits_ge1_by_player_species, player_id, species_name)
	if feed_count >= 3:
		_increment_species_metric(_alive_exits_ge3_by_player_species, player_id, species_name)
	if feed_count >= 5:
		_increment_species_metric(_alive_exits_ge5_by_player_species, player_id, species_name)


func _record_spawn_sequence_event(player_id: int, species_name: StringName) -> void:
	var target: Array[Dictionary] = _spawn_seq_events_p1 if player_id == 1 else _spawn_seq_events_p2
	var source_spawner: Node2D = spawner_p1 if player_id == 1 else spawner_p2
	var spent: Dictionary = {}
	if source_spawner != null and source_spawner.get("resources_spent_by_species") is Dictionary:
		spent = source_spawner.get("resources_spent_by_species") as Dictionary
	var spent_total: float = _sum_species_values(spent)
	var g_ratio: float = 0.0
	var s_ratio: float = 0.0
	var d_ratio: float = 0.0
	if spent_total > 0.0:
		g_ratio = float(spent.get(SpeciesRegistry.GUPPY, 0.0)) / spent_total
		s_ratio = float(spent.get(SpeciesRegistry.SABALO, 0.0)) / spent_total
		d_ratio = float(spent.get(SpeciesRegistry.DIENTUDO, 0.0)) / spent_total
	target.append({
		"order": target.size(),
		"species": species_name,
		"frame": _match_frames,
		"time_s": _match_elapsed_seconds,
		"guppy_spent_ratio": g_ratio,
		"sabalo_spent_ratio": s_ratio,
		"dientudo_spent_ratio": d_ratio
	})


func _weights_to_compact_string(weights: Dictionary) -> String:
	var g: float = float(weights.get(SpeciesRegistry.GUPPY, 0.0))
	var s: float = float(weights.get(SpeciesRegistry.SABALO, 0.0))
	var d: float = float(weights.get(SpeciesRegistry.DIENTUDO, 0.0))
	return "G%.2f|S%.2f|D%.2f" % [g, s, d]
