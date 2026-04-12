extends Node2D

## Main match orchestrator.
## Owns scene wiring, spawn loop, scoring, analytics, and per-frame SpatialGrid rebuild.

enum ScheduleMode {
	ROUND_ROBIN,
	FOCUSED_SUITE,
	TWO_PLAYERS,
	ONE_PLAYER_CAMPAIGN
}

@onready var pond: Node2D = $Pond
@onready var pond_shape: Polygon2D = $PondShape
@onready var out_boundary: Line2D = $OutBoundary
@onready var out_boundary_debug: Line2D = $OutBoundaryDebug
@onready var despawn_area: Polygon2D = $DespawnAreas/DespawnArea
@onready var score_p1_label: Label = $CanvasLayer/ScoreP1
@onready var score_p2_label: Label = $CanvasLayer/ScoreP2
@onready var count_label: Label = $CanvasLayer/FishCount
@onready var spawner_p1: Node2D = $SpawnerP1
@onready var spawner_p2: Node2D = $SpawnerP2
@onready var _mode_overlay_node: Panel = $CanvasLayer/ModeOverlay
@onready var _btn_rr: Button = $CanvasLayer/ModeOverlay/BtnRoundRobin
@onready var _btn_fs: Button = $CanvasLayer/ModeOverlay/BtnFocusedSuite
@onready var _btn_2p: Button = $CanvasLayer/ModeOverlay/BtnTwoPlayers
@onready var _btn_campaign: Button = $CanvasLayer/ModeOverlay/BtnCampaign

@export_group("Zoo: Boundary")
## Contact distance used to reinsert fish inside the out boundary.
@export var out_boundary_touch_distance: float = 10.0
## Avoidance distance where boundary steering begins.
@export var out_boundary_avoid_distance: float = 140.0
## Draws OutBoundaryDebug overlay when true.
@export var debug_draw_out_boundary: bool = false

@export_group("Zoo: Despawn")
## Enables despawn polygon checks in the main loop.
@export var despawn_areas_enabled: bool = true
## Initial detritus units spawned at round start.
@export var startup_detritus_count: int = 20
## Required edge clearance for detritus spawn validity.
@export var detritus_min_edge_clearance_px: float = 50.0
## Number of retries when resolving valid detritus spawn points.
@export var detritus_spawn_max_attempts: int = 128

@export_group("Zoo: Pellet")
## Target live pellet population while match is active.
@export var pellet_target_count: int = 40
## Delay between pellet spawn checks when under target count.
@export var pellet_spawn_interval_seconds: float = 0.35

@export_group("Zoo: Match")
## Number of laps used in round-robin scheduling mode.
@export_range(1, 20) var round_robin_laps: int = 3
## Lead threshold required to end a match.
@export_range(1, 100) var win_lead_points: int = 25

@export_group("Zoo: Diagnostics")
## Enables extended end-of-match diagnostics during automated match runs.
@export var enable_match_diagnostics: bool = true
## Max contender distance in pixels for contest classification.
@export var diagnostics_contest_distance_threshold_px: float = 180.0
## Seconds contenders remain contest-eligible after last target sample.
@export var diagnostics_contest_window_seconds: float = 1.25
## Seconds a dropped contested target remains eligible as a denied opportunity.
@export var diagnostics_denied_opportunity_window_seconds: float = 1.5

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
const _COL_PANEL_BG_SELECTED: Color = Color(0.86, 0.93, 1.0, 0.95)
const _COL_TEXT_SUBTLE: Color = Color(1.0, 1.0, 1.0, 1.0)
const _SPECIES_FLICK_COOLDOWN_SECONDS: float = 0.16

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
const _CSV_SCHEMA_VERSION: int = 4
const _CAMPAIGN_STAGE_COUNT: int = 5
const _CAMPAIGN_FALLBACK_PROFILE_NAMES: Array[String] = [
	"G33S33D34",
	"G40S40D20",
	"G25S50D25",
	"G20S40D40",
	"G25S25D50"
]
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
var _fed_fish_by_player_species: Dictionary = {}
var _feed_point_gain_by_player_species: Dictionary = {}
var _feed_weight_gain_by_player_species: Dictionary = {}
var _alive_exits_by_player_species: Dictionary = {}
var _alive_exits_ge1_by_player_species: Dictionary = {}
var _alive_exits_ge3_by_player_species: Dictionary = {}
var _alive_exits_ge5_by_player_species: Dictionary = {}
var _predated_deaths_by_player_species: Dictionary = {}
var _self_predations_by_player_species: Dictionary = {}
var _opponent_predations_by_player_species: Dictionary = {}
var _contest_wins_by_player_species: Dictionary = {}
var _contest_losses_by_player_species: Dictionary = {}
var _contest_latency_sum_by_player_species: Dictionary = {}
var _contest_latency_count_by_player_species: Dictionary = {}
var _estimated_denied_opportunities_by_player_species: Dictionary = {}
var _fish_lifecycle_by_id: Dictionary = {}
var _contest_state_by_target_id: Dictionary = {}
var _last_target_snapshot_by_fish_id: Dictionary = {}
var _pending_denied_by_fish_id: Dictionary = {}
var _awaiting_mode_selection: bool = true
var _pellet_spawn_timer: float = 0.0
var _is_local_two_player_mode: bool = false
var _is_one_player_campaign_mode: bool = false
var _controller_to_player: Dictionary = {}
var _next_species_change_time_by_player: Dictionary = {1: 0.0, 2: 0.0}
var _campaign_opponent_indices: Array[int] = []
var _campaign_stage_index: int = 0
var _campaign_pending_winner_player: int = 0


## Initializes runtime systems, caches geometry, builds HUD, and waits for mode selection.
func _ready() -> void:
	_validate_scene_wiring()
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
	if out_boundary != null:
		out_boundary.visible = false
	if out_boundary_debug != null:
		out_boundary_debug.visible = debug_draw_out_boundary
	# Keep panel from hard-blocking while still allowing child buttons to be pickable.
	_mode_overlay_node.mouse_filter = Control.MOUSE_FILTER_PASS
	_btn_rr.pressed.connect(_begin_selected_mode.bind(ScheduleMode.ROUND_ROBIN))
	_btn_fs.pressed.connect(_begin_selected_mode.bind(ScheduleMode.FOCUSED_SUITE))
	_btn_2p.pressed.connect(_begin_selected_mode.bind(ScheduleMode.TWO_PLAYERS))
	_btn_campaign.pressed.connect(_begin_selected_mode.bind(ScheduleMode.ONE_PLAYER_CAMPAIGN))


## Fails fast when critical Zoo scene dependencies are missing.
func _validate_scene_wiring() -> void:
	assert(pond != null, "Zoo scene missing Pond node")
	assert(pond_shape != null, "Zoo scene missing PondShape node")
	assert(despawn_area != null, "Zoo scene missing DespawnArea node")
	assert(score_p1_label != null and score_p2_label != null and count_label != null, "Zoo scene missing HUD labels")
	assert(spawner_p1 != null and spawner_p2 != null, "Zoo scene missing spawners")
	assert(_btn_rr != null and _btn_fs != null and _btn_2p != null and _btn_campaign != null, "Zoo scene missing mode selection buttons")
	if get_node_or_null("/root/SpatialGrid") == null:
		push_warning("Zoo expects SpatialGrid autoload to be configured.")


## Starts selected schedule mode and boots first match.
func _begin_selected_mode(mode: ScheduleMode) -> void:
	if not _awaiting_mode_selection:
		return
	_awaiting_mode_selection = false
	_controller_to_player.clear()
	_next_species_change_time_by_player = {1: 0.0, 2: 0.0}
	_schedule_mode = mode
	_mode_overlay_node.hide()
	if _schedule_mode == ScheduleMode.TWO_PLAYERS:
		_start_local_two_player_match()
		return
	if _schedule_mode == ScheduleMode.ONE_PLAYER_CAMPAIGN:
		_start_one_player_campaign()
		return
	_build_schedule()
	_is_local_two_player_mode = false
	_is_one_player_campaign_mode = false
	print("Zoo: mode=%s profiles=%d laps=%d planned_matches=%d" % [
		"RR" if _schedule_mode == ScheduleMode.ROUND_ROBIN else "FOCUSED",
		_ai_profiles.size(),
		round_robin_laps,
		_schedule.size()
	])
	_init_csv_files()
	_start_match()


## Keyboard shortcut handling for mode selection overlay.
func _input(event: InputEvent) -> void:
	if _awaiting_mode_selection:
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
		elif key_event.keycode == KEY_3 or key_event.keycode == KEY_KP_3 or key_event.physical_keycode == KEY_3 or key_event.unicode == 51:
			_begin_selected_mode(ScheduleMode.TWO_PLAYERS)
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_4 or key_event.keycode == KEY_KP_4 or key_event.physical_keycode == KEY_4 or key_event.unicode == 52:
			_begin_selected_mode(ScheduleMode.ONE_PLAYER_CAMPAIGN)
			get_viewport().set_input_as_handled()
		return

	if (not _is_local_two_player_mode and not _is_one_player_campaign_mode) or not _match_active:
		return

	if event is InputEventKey:
		var local_key_event: InputEventKey = event as InputEventKey
		if not local_key_event.pressed or local_key_event.echo:
			return
		if local_key_event.keycode == KEY_ENTER or local_key_event.keycode == KEY_KP_ENTER:
			_return_to_mode_menu()
			get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_SPACE:
			_try_local_accept(1)
			get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_KP_0:
			if _is_local_two_player_mode:
				_try_local_accept(2)
				get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_W:
			_try_local_species_step(1, -1)
			get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_S:
			_try_local_species_step(1, 1)
			get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_UP:
			if _is_local_two_player_mode:
				_try_local_species_step(2, -1)
				get_viewport().set_input_as_handled()
			return
		if local_key_event.keycode == KEY_DOWN:
			if _is_local_two_player_mode:
				_try_local_species_step(2, 1)
				get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton:
		var joy_button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if not joy_button_event.pressed:
			return
		if joy_button_event.button_index == JOY_BUTTON_START:
			_return_to_mode_menu()
			get_viewport().set_input_as_handled()
			return
		var player_from_button: int = _resolve_player_for_device(joy_button_event.device)
		if player_from_button == 0:
			return
		if _is_one_player_campaign_mode and player_from_button != 1:
			return
		if joy_button_event.button_index == JOY_BUTTON_A or joy_button_event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_try_local_accept(player_from_button)
			get_viewport().set_input_as_handled()
			return
		if joy_button_event.button_index == JOY_BUTTON_DPAD_UP:
			_try_local_species_step(player_from_button, -1)
			get_viewport().set_input_as_handled()
			return
		if joy_button_event.button_index == JOY_BUTTON_DPAD_DOWN:
			_try_local_species_step(player_from_button, 1)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadMotion:
		var joy_motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		if joy_motion_event.axis != JOY_AXIS_LEFT_Y:
			return
		var player_from_motion: int = _resolve_player_for_device(joy_motion_event.device)
		if player_from_motion == 0:
			return
		if _is_one_player_campaign_mode and player_from_motion != 1:
			return
		if joy_motion_event.axis_value <= -0.55:
			_try_local_species_step(player_from_motion, -1)
			get_viewport().set_input_as_handled()
		elif joy_motion_event.axis_value >= 0.55:
			_try_local_species_step(player_from_motion, 1)
			get_viewport().set_input_as_handled()


## Assigns first two active joypads to player slots 1 and 2.
func _resolve_player_for_device(device_id: int) -> int:
	if device_id < 0:
		return 0
	if _controller_to_player.has(device_id):
		return int(_controller_to_player.get(device_id, 0))
	if _controller_to_player.size() >= 2:
		return 0
	var assigned_player: int = 1
	for mapped_player: Variant in _controller_to_player.values():
		if int(mapped_player) == 1:
			assigned_player = 2
			break
	_controller_to_player[device_id] = assigned_player
	return assigned_player


## Returns true when the per-player species-flick cooldown has elapsed.
func _consume_species_step_window(player_id: int) -> bool:
	var now_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	var next_allowed: float = float(_next_species_change_time_by_player.get(player_id, 0.0))
	if now_seconds < next_allowed:
		return false
	_next_species_change_time_by_player[player_id] = now_seconds + _SPECIES_FLICK_COOLDOWN_SECONDS
	return true


## Applies one local species step for the given player.
func _try_local_species_step(player_id: int, direction: int) -> void:
	if not _consume_species_step_window(player_id):
		return
	var target_spawner: Node2D = spawner_p1 if player_id == 1 else spawner_p2
	if target_spawner != null and target_spawner.has_method("cycle_selected_species"):
		target_spawner.call("cycle_selected_species", direction)


## Attempts one local manual spawn request for the given player.
func _try_local_accept(player_id: int) -> void:
	var target_spawner: Node2D = spawner_p1 if player_id == 1 else spawner_p2
	if target_spawner != null and target_spawner.has_method("request_spawn_accept"):
		target_spawner.call("request_spawn_accept")


## Main loop: rebuild grid, run match systems, or advance reset timer.
func _process(delta: float) -> void:
	if _awaiting_mode_selection:
		if Input.is_key_pressed(KEY_1) or Input.is_physical_key_pressed(KEY_1) or Input.is_key_pressed(KEY_KP_1):
			_begin_selected_mode(ScheduleMode.ROUND_ROBIN)
		elif Input.is_key_pressed(KEY_2) or Input.is_physical_key_pressed(KEY_2) or Input.is_key_pressed(KEY_KP_2):
			_begin_selected_mode(ScheduleMode.FOCUSED_SUITE)
		elif Input.is_key_pressed(KEY_3) or Input.is_physical_key_pressed(KEY_3) or Input.is_key_pressed(KEY_KP_3):
			_begin_selected_mode(ScheduleMode.TWO_PLAYERS)
		elif Input.is_key_pressed(KEY_4) or Input.is_physical_key_pressed(KEY_4) or Input.is_key_pressed(KEY_KP_4):
			_begin_selected_mode(ScheduleMode.ONE_PLAYER_CAMPAIGN)
		return
	SpatialGrid.rebuild()
	if _match_active:
		_match_elapsed_seconds += delta
		_match_frames += 1
		_process_pellet_spawning(delta)
		_handle_spawner(delta, spawner_p1)
		_handle_spawner(delta, spawner_p2)
		_process_despawn_areas()
		_sample_contested_targets()
		_check_win_condition()
	else:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_do_reset()
	_update_ui()
	_update_hud()


## Advances one spawner and consumes queued spawn payloads.
func _handle_spawner(delta: float, spawner: Node2D) -> void:
	if spawner == null:
		return
	if not spawner.has_method("advance"):
		return
	spawner.call("advance", delta)
	var current_count: int = _live_fish_count_from_spawner(spawner)
	if bool(spawner.call("can_spawn", current_count)):
		_spawn_fish(spawner.call("consume_spawn_request") as Dictionary)


## Acquires, configures, and registers a new fish from a spawn request payload.
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
		"point_gain_total": 0,
		"weight_gain_total_g": 0.0,
		"predated": false,
		"alive_exit": false
	}
	if fish is Dientudo:
		var predator: Dientudo = fish as Dientudo
		if not predator.prey_predated.is_connected(_on_prey_predated):
			predator.prey_predated.connect(_on_prey_predated)
	SpatialGrid.register_fish(fish)
	if player_id == 1:
		_spawns_p1[normalized_species] = int(_spawns_p1.get(normalized_species, 0)) + 1
		_spawn_seq_p1.append(normalized_species)
	else:
		_spawns_p2[normalized_species] = int(_spawns_p2.get(normalized_species, 0)) + 1
		_spawn_seq_p2.append(normalized_species)
	_record_spawn_sequence_event(player_id, normalized_species)


## Returns centroid of the despawn polygon in global space.
func _compute_despawn_center() -> Vector2:
	if despawn_area == null or despawn_area.polygon.size() < 3:
		return Vector2(640.0, 900.0)
	var accum: Vector2 = Vector2.ZERO
	for local_point: Vector2 in despawn_area.polygon:
		accum += despawn_area.to_global(local_point)
	return accum / float(despawn_area.polygon.size())


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
	detritus_fish.configure_from_zoo(SpeciesRegistry.DETRITUS, 1, Color(0.45, 0.30, 0.14, 1.0), pond_bounds)
	detritus_fish.reinitialize()
	detritus_fish.configure_out_boundary(out_boundary_polygon, out_boundary_touch_distance, out_boundary_avoid_distance)
	detritus_fish.configure_despawn_area(_compute_despawn_center())
	detritus_fish.set_source_spawner(NodePath())
	if detritus_fish is Detritus:
		(detritus_fish as Detritus).set_detritus_value(detritus_units)
	SpatialGrid.register_fish(detritus_fish)


## Spawns and registers a pellet entity at the requested position.
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


## Seeds startup detritus and prints a one-line spawn sanity sample.
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


## Returns a random in-pond point that excludes despawn polygon when possible.
func _random_point_in_pond_outside_despawn() -> Vector2:
	if _despawn_polygon_cached.size() < 3:
		return _random_point_in_pond()
	for _attempt: int in range(96):
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


## Validates detritus spawn points against pond bounds, edge clearance, and spawner repel zones.
func _is_detritus_spawn_valid(point: Vector2) -> bool:
	if out_boundary_polygon.size() >= 3 and not Geometry2D.is_point_in_polygon(point, out_boundary_polygon):
		return false

	if _distance_to_out_boundary(point) < maxf(detritus_min_edge_clearance_px, 0.0):
		return false

	for node: Node in get_tree().get_nodes_in_group("fish_spawners"):
		if not (node is Node2D):
			continue
		var spawner_node: Node2D = node as Node2D
		var repel_radius: float = float(spawner_node.get("repel_radius"))
		if repel_radius <= 0.0:
			repel_radius = 238.0
		if point.distance_to(spawner_node.global_position) <= repel_radius:
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

	for _attempt: int in range(48):
		var candidate: Vector2 = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(candidate, out_boundary_polygon):
			return candidate

	return out_boundary_polygon[randi() % out_boundary_polygon.size()]


## Handles predation analytics and optional detritus generation from consumed prey.
func _on_prey_predated(prey_position: Vector2, prey_weight_g: float, predator_player: int, predator_species: StringName, _predator_fish_id: int, prey_player: int, prey_species: StringName, prey_fish_id: int, prey_feed_count: int, _absorbed_mass_g: float, _earned_points: int) -> void:
	if predator_player == 1 or predator_player == 2:
		_predations_by_player[predator_player] = int(_predations_by_player.get(predator_player, 0)) + 1
		if _should_collect_diagnostics():
			if predator_player == prey_player:
				_increment_species_metric(_self_predations_by_player_species, predator_player, predator_species)
			else:
				_increment_species_metric(_opponent_predations_by_player_species, predator_player, predator_species)
	if prey_player == 1 or prey_player == 2:
		_increment_species_metric(_predated_deaths_by_player_species, prey_player, prey_species)
		if _fish_lifecycle_by_id.has(prey_fish_id):
			var prey_entry: Dictionary = _fish_lifecycle_by_id[prey_fish_id] as Dictionary
			prey_entry["predated"] = true
			prey_entry["feeds"] = maxi(int(prey_entry.get("feeds", 0)), prey_feed_count)
			_fish_lifecycle_by_id[prey_fish_id] = prey_entry
	var detritus_units: int = _roll_predation_detritus_value(prey_weight_g)
	if detritus_units > 0:
		_spawn_detritus(prey_position, detritus_units)


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
		# PondShape is editable in local space and may be moved/scaled in the scene.
		# Fish and Line2D need points in global (world) coordinates.
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
		return
	_despawn_polygon_cached = PackedVector2Array()
	for local_point: Vector2 in despawn_area.polygon:
		_despawn_polygon_cached.append(despawn_area.to_global(local_point))


## Returns player-specific tint for spawned species.
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


## Applies score/biomass accounting when fish exits alive.
func _on_fish_exited(player_id: int, point_value: int, redeemed_biomass_g: float, fish_id: int, fish_species: StringName, feed_count: int) -> void:
	if player_id != 1 and player_id != 2:
		return
	score_by_player[player_id] = float(score_by_player.get(player_id, 0.0)) + float(point_value)
	_redeemed_biomass_by_player[player_id] = float(_redeemed_biomass_by_player.get(player_id, 0.0)) + redeemed_biomass_g
	_register_alive_exit(player_id, fish_species, feed_count)
	if _fish_lifecycle_by_id.has(fish_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[fish_id] as Dictionary
		fish_entry["alive_exit"] = true
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		_fish_lifecycle_by_id[fish_id] = fish_entry


## Tracks successful feed analytics by player/species.
func _on_fish_feed_succeeded(player_id: int, fish_species: StringName, fish_id: int, feed_count: int, weight_gain_g: float, point_delta: int, target_fish_id: int, _target_species: StringName, _target_player_id: int) -> void:
	if player_id != 1 and player_id != 2:
		return
	_feed_events_by_player[player_id] = int(_feed_events_by_player.get(player_id, 0)) + 1
	_increment_species_metric(_feed_by_player_species, player_id, fish_species)
	if _should_collect_diagnostics():
		_add_species_metric_value(_feed_point_gain_by_player_species, player_id, fish_species, float(point_delta))
		_add_species_metric_value(_feed_weight_gain_by_player_species, player_id, fish_species, weight_gain_g)
		_resolve_contested_target(target_fish_id, player_id, fish_species, fish_id)
	if _fish_lifecycle_by_id.has(fish_id):
		var fish_entry: Dictionary = _fish_lifecycle_by_id[fish_id] as Dictionary
		var previous_feeds: int = int(fish_entry.get("feeds", 0))
		if _should_collect_diagnostics() and previous_feeds <= 0:
			_increment_species_metric(_fed_fish_by_player_species, player_id, fish_species)
		fish_entry["feeds"] = maxi(int(fish_entry.get("feeds", 0)), feed_count)
		fish_entry["point_gain_total"] = int(fish_entry.get("point_gain_total", 0)) + point_delta
		fish_entry["weight_gain_total_g"] = float(fish_entry.get("weight_gain_total_g", 0.0)) + weight_gain_g
		_fish_lifecycle_by_id[fish_id] = fish_entry


## Despawns fish that enter configured despawn polygons.
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


## Applies despawn scoring side effects and returns fish to pool.
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

	score_by_player[fish.player] = float(score_by_player.get(fish.player, 0.0)) + float(fish.get_point_value())
	_redeemed_biomass_by_player[fish.player] = float(_redeemed_biomass_by_player.get(fish.player, 0.0)) + fish.get_redeemable_biomass_g()
	_register_alive_exit(fish.player, fish.species, fish.get_successful_feed_count())
	FishPool.release(fish)


## Grants immediate resource bonus to the owning spawner.
func _grant_resource_bonus(player_id: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var target_spawner: Node2D = spawner_p1 if player_id == 1 else spawner_p2
	if target_spawner == null:
		return
	if target_spawner.has_method("add_resource"):
		target_spawner.call("add_resource", amount)


## Counts currently live non-detritus fish.
func _live_fish_count() -> int:
	var total: int = 0
	for child: Node in pond.get_children():
		if child is Fish:
			var fish: Fish = child as Fish
			if fish.species == SpeciesRegistry.DETRITUS:
				continue
			total += 1
	return total


## Counts live non-detritus fish spawned by one spawner.
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


## Updates top-line match UI labels (scores, count, lap, lead).
func _update_ui() -> void:
	var p1_score: int = int(round(float(score_by_player.get(1, 0.0))))
	var p2_score: int = int(round(float(score_by_player.get(2, 0.0))))
	score_p1_label.text = "%s POINTS: %d" % [_p1_ai_name, p1_score]
	score_p2_label.text = "%s POINTS: %d" % [_p2_ai_name, p2_score]
	if _is_one_player_campaign_mode:
		count_label.text = "CAMPAIGN STAGE %d/%d  |  %s vs %s  |  FISH %d  |  LEAD %d/%d pts" % [_campaign_stage_index + 1, maxi(1, _campaign_opponent_indices.size()), _p1_ai_name, _p2_ai_name, _live_fish_count(), absi(p1_score - p2_score), win_lead_points]
		return
	var lap: int = 1
	if _schedule_index < _schedule.size():
		lap = int(_schedule[_schedule_index].get("lap", 0)) + 1
	var lead: int = absi(p1_score - p2_score)
	count_label.text = "GAME %d/%d  LAP %d  |  %s vs %s  |  FISH %d  |  LEAD %d/%d pts" % [_game_id + 1, _schedule.size(), lap, _p1_ai_name, _p2_ai_name, _live_fish_count(), lead, win_lead_points]


## Builds and styles HUD widgets for scores, species slots, diagnostics, and winner banner.
func _setup_hud() -> void:
	var cl: CanvasLayer = $CanvasLayer
	var vp_w: float = get_viewport_rect().size.x
	var vp_h: float = get_viewport_rect().size.y

	score_p1_label.position = Vector2(vp_w * 0.5 - 430.0, 14.0)
	score_p1_label.size = Vector2(320.0, 34.0)
	score_p1_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_p1_label.add_theme_color_override("font_color", Color(0.58, 0.88, 1.0, 1.0))
	score_p1_label.add_theme_font_size_override("font_size", 24)
	score_p1_label.add_theme_constant_override("outline_size", 2)
	score_p1_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))

	score_p2_label.position = Vector2(vp_w * 0.5 + 110.0, 14.0)
	score_p2_label.size = Vector2(320.0, 34.0)
	score_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_p2_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 1.0))
	score_p2_label.add_theme_font_size_override("font_size", 24)
	score_p2_label.add_theme_constant_override("outline_size", 2)
	score_p2_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))

	count_label.position = Vector2(vp_w * 0.5 - 420.0, 48.0)
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
	_hud_diag_bg.position = Vector2(vp_w * 0.5 - 304.0, 80.0)
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
	_hud_diag_label.position = Vector2(vp_w * 0.5 - 290.0, 86.0)
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
	_win_label.position = Vector2(vp_w * 0.5 - 340.0, 170.0)
	_win_label.size = Vector2(680.0, 120.0)
	_win_label.hide()
	cl.add_child(_win_label)


## Creates a standardized HUD resource label.
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


## Caches species textures for HUD icons.
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


## Returns zero-initialized species counter dictionary.
func _zero_species_counter() -> Dictionary:
	var counters: Dictionary = {}
	for species_name: StringName in _species_order:
		counters[species_name] = 0
	return counters


## Sums numeric values across all tracked fish species.
func _sum_species_values(values: Dictionary) -> float:
	var total: float = 0.0
	for species_name: StringName in _species_order:
		total += float(values.get(species_name, 0.0))
	return total


## Builds one player's species slot panels in the HUD.
func _setup_player_hud(cl: CanvasLayer, base: Vector2, slots: Dictionary, styles: Dictionary, count_labels: Dictionary, right_aligned: bool) -> void:
	for i: int in _species_order.size():
		var species: StringName = _species_order[i]
		var panel: Panel = Panel.new()
		panel.position = base + Vector2(0.0, float(i) * (_SLOT_HEIGHT + _SLOT_GAP))
		panel.size = Vector2(_SLOT_WIDTH, _SLOT_HEIGHT)
		panel.pivot_offset = panel.size * 0.5
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


## Refreshes HUD state (resources, selected species, spawn counts, diagnostics).
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
			var style_p1: StyleBoxFlat = _hud_styles_p1[species] as StyleBoxFlat
			style_p1.border_color = _COL_SELECTED if species == sel1 else _COL_UNSELECTED
			style_p1.bg_color = _COL_PANEL_BG_SELECTED if species == sel1 else _COL_PANEL_BG
		if _hud_slots_p1.has(species):
			(_hud_slots_p1[species] as Panel).scale = Vector2.ONE * (1.10 if species == sel1 else 1.0)
		if _hud_styles_p2.has(species):
			var style_p2: StyleBoxFlat = _hud_styles_p2[species] as StyleBoxFlat
			style_p2.border_color = _COL_SELECTED if species == sel2 else _COL_UNSELECTED
			style_p2.bg_color = _COL_PANEL_BG_SELECTED if species == sel2 else _COL_PANEL_BG
		if _hud_slots_p2.has(species):
			(_hud_slots_p2[species] as Panel).scale = Vector2.ONE * (1.10 if species == sel2 else 1.0)
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


## Ends round when score lead reaches configured threshold.
func _check_win_condition() -> void:
	var s1: float = float(score_by_player.get(1, 0.0))
	var s2: float = float(score_by_player.get(2, 0.0))
	if s1 - s2 >= float(win_lead_points):
		_end_round(1)
	elif s2 - s1 >= float(win_lead_points):
		_end_round(2)


## Finalizes a round, shows winner UI, and writes analytics rows.
func _end_round(winner_player: int) -> void:
	_match_active = false
	_reset_timer = _RESET_DELAY
	var winner_ai: String = _p1_ai_name if winner_player == 1 else _p2_ai_name
	if _is_one_player_campaign_mode:
		_campaign_pending_winner_player = winner_player
	if _win_label != null:
		_win_label.text = "%s wins!" % winner_ai
		_win_label.show()
	if not _is_local_two_player_mode and not _is_one_player_campaign_mode:
		_write_csv_row(winner_ai)
		_write_round_metrics_row(winner_ai)
		_write_spawn_sequences()


## Returns from active gameplay to mode selection and resets runtime state.
func _return_to_mode_menu() -> void:
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
	_pellet_spawn_timer = 0.0
	_reset_match_analytics()
	if spawner_p1 != null and spawner_p1.has_method("reset"):
		spawner_p1.call("reset")
	if spawner_p2 != null and spawner_p2.has_method("reset"):
		spawner_p2.call("reset")
	if spawner_p1 != null and spawner_p1.has_method("set_manual_control_enabled"):
		spawner_p1.call("set_manual_control_enabled", false)
	if spawner_p2 != null and spawner_p2.has_method("set_manual_control_enabled"):
		spawner_p2.call("set_manual_control_enabled", false)
	_awaiting_mode_selection = true
	_is_local_two_player_mode = false
	_is_one_player_campaign_mode = false
	_controller_to_player.clear()
	_next_species_change_time_by_player = {1: 0.0, 2: 0.0}
	_match_active = false
	_reset_timer = 0.0
	_campaign_opponent_indices.clear()
	_campaign_stage_index = 0
	_campaign_pending_winner_player = 0
	_schedule.clear()
	_schedule_index = 0
	if _mode_overlay_node != null:
		_mode_overlay_node.show()
	if _win_label != null:
		_win_label.hide()
	_p1_ai_name = "?"
	_p2_ai_name = "?"


## Resets pond state and advances to the next scheduled match.
func _do_reset() -> void:
	if _is_local_two_player_mode:
		_return_to_mode_menu()
		return
	if _is_one_player_campaign_mode:
		_advance_campaign_after_round()
		return
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


## Appends one aggregated playtest row to playtests.csv.
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
	var total_feed_events: float = float(int(_feed_events_by_player.get(1, 0)) + int(_feed_events_by_player.get(2, 0)))
	var total_feed_point_gain: float = _sum_player_species_metric(_feed_point_gain_by_player_species, 1) + _sum_player_species_metric(_feed_point_gain_by_player_species, 2)
	var total_feed_weight_gain: float = _sum_player_species_metric(_feed_weight_gain_by_player_species, 1) + _sum_player_species_metric(_feed_weight_gain_by_player_species, 2)
	var p1_avg_conversion_points: float = _safe_ratio(_sum_player_species_metric(_feed_point_gain_by_player_species, 1), float(_feed_events_by_player.get(1, 0)))
	var p2_avg_conversion_points: float = _safe_ratio(_sum_player_species_metric(_feed_point_gain_by_player_species, 2), float(_feed_events_by_player.get(2, 0)))
	var global_avg_conversion_points: float = _safe_ratio(total_feed_point_gain, total_feed_events)
	var global_avg_conversion_weight: float = _safe_ratio(total_feed_weight_gain, total_feed_events)
	var row_values: Array[String] = [
		str(_CSV_SCHEMA_VERSION),
		str(_game_id),
		str(int(entry.get("lap", 0))),
		_p1_ai_name,
		_p2_ai_name,
		_weights_to_compact_string(_p1_ai_weights),
		_weights_to_compact_string(_p2_ai_weights),
		winner_ai,
		"%.3f" % _match_elapsed_seconds,
		str(_match_frames),
		str(int(_spawns_p1.get(&"guppy", 0))),
		str(int(_spawns_p1.get(&"sabalo", 0))),
		str(int(_spawns_p1.get(&"dientudo", 0))),
		str(int(_spawns_p2.get(&"guppy", 0))),
		str(int(_spawns_p2.get(&"sabalo", 0))),
		str(int(_spawns_p2.get(&"dientudo", 0))),
		str(int(_feed_events_by_player.get(1, 0))),
		str(int(_feed_events_by_player.get(2, 0))),
		str(int(_predations_by_player.get(1, 0))),
		str(int(_predations_by_player.get(2, 0))),
		"%.0f" % p1_spent_total,
		"%.0f" % p2_spent_total,
		"%.0f" % p1_points,
		"%.0f" % p2_points,
		"%.0f" % p1_biomass,
		"%.0f" % p2_biomass,
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.GUPPY))),
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.SABALO))),
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 1, SpeciesRegistry.DIENTUDO))),
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.GUPPY))),
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.SABALO))),
		str(int(_species_metric_value(_alive_exits_ge5_by_player_species, 2, SpeciesRegistry.DIENTUDO))),
		"%.4f" % p1_efficiency,
		"%.4f" % p2_efficiency,
		str(int(_sum_player_species_metric(_fed_fish_by_player_species, 1))),
		str(int(_sum_player_species_metric(_fed_fish_by_player_species, 2))),
		str(int(_sum_player_species_metric(_self_predations_by_player_species, 1))),
		str(int(_sum_player_species_metric(_opponent_predations_by_player_species, 1))),
		str(int(_sum_player_species_metric(_self_predations_by_player_species, 2))),
		str(int(_sum_player_species_metric(_opponent_predations_by_player_species, 2))),
		str(int(_sum_player_species_metric(_contest_wins_by_player_species, 1))),
		str(int(_sum_player_species_metric(_contest_wins_by_player_species, 2))),
		str(int(_sum_player_species_metric(_contest_losses_by_player_species, 1))),
		str(int(_sum_player_species_metric(_contest_losses_by_player_species, 2))),
		str(int(_sum_player_species_metric(_estimated_denied_opportunities_by_player_species, 1))),
		str(int(_sum_player_species_metric(_estimated_denied_opportunities_by_player_species, 2))),
		"%.4f" % _average_player_contest_latency(1),
		"%.4f" % _average_player_contest_latency(2),
		"%.4f" % p1_avg_conversion_points,
		"%.4f" % p2_avg_conversion_points,
		"%.4f" % global_avg_conversion_points,
		"%.4f" % global_avg_conversion_weight
	]
	var row: String = ",".join(row_values)
	file.store_line(row)
	file.close()
	print("Zoo: match=%d winner=%s duration=%.1fs points=%d/%d biomass=%dg/%dg efficiency=%.3f/%.3f contest=%d/%d pred(self/op)=%d/%d %d/%d conv=%.3f/%.3f all=%.3f" % [
		_game_id,
		winner_ai,
		_match_elapsed_seconds,
		int(round(p1_points)),
		int(round(p2_points)),
		int(round(p1_biomass)),
		int(round(p2_biomass)),
		p1_efficiency,
		p2_efficiency,
		int(_sum_player_species_metric(_contest_wins_by_player_species, 1)),
		int(_sum_player_species_metric(_contest_wins_by_player_species, 2)),
		int(_sum_player_species_metric(_self_predations_by_player_species, 1)),
		int(_sum_player_species_metric(_opponent_predations_by_player_species, 1)),
		int(_sum_player_species_metric(_self_predations_by_player_species, 2)),
		int(_sum_player_species_metric(_opponent_predations_by_player_species, 2)),
		p1_avg_conversion_points,
		p2_avg_conversion_points,
		global_avg_conversion_points
	])


## Appends per-player per-species metrics for the finished round.
func _write_round_metrics_row(winner_ai: String) -> void:
	var file: FileAccess = FileAccess.open("user://round_metrics.csv", FileAccess.READ_WRITE)
	if file == null:
		push_error("Zoo: could not open user://round_metrics.csv")
		return
	file.seek_end()
	for player_id: int in [1, 2]:
		for species_name: StringName in _species_order:
			var feed_events: int = int(_species_metric_value(_feed_by_player_species, player_id, species_name))
			var row_values: Array[String] = [
				str(_CSV_SCHEMA_VERSION),
				str(_game_id),
				winner_ai,
				_p1_ai_name if player_id == 1 else _p2_ai_name,
				str(player_id),
				String(species_name),
				str(feed_events),
				str(int(_species_metric_value(_fed_fish_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_alive_exits_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_alive_exits_ge1_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_alive_exits_ge3_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_alive_exits_ge5_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_predated_deaths_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_self_predations_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_opponent_predations_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_contest_wins_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_contest_losses_by_player_species, player_id, species_name))),
				str(int(_species_metric_value(_estimated_denied_opportunities_by_player_species, player_id, species_name))),
				"%.4f" % _average_species_contest_latency(player_id, species_name),
				str(int(round(_species_metric_float_value(_feed_point_gain_by_player_species, player_id, species_name)))),
				"%.4f" % _species_metric_float_value(_feed_weight_gain_by_player_species, player_id, species_name),
				"%.4f" % _safe_ratio(_species_metric_float_value(_feed_point_gain_by_player_species, player_id, species_name), float(feed_events)),
				"%.4f" % _safe_ratio(_species_metric_float_value(_feed_weight_gain_by_player_species, player_id, species_name), float(feed_events)),
				str(int(_spawns_p1.get(species_name, 0)) if player_id == 1 else int(_spawns_p2.get(species_name, 0)))
			]
			var row: String = ",".join(row_values)
			file.store_line(row)
	file.close()


## Appends ordered spawn sequence events for both players.
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


## Builds match schedule from current mode and lap count.
func _build_schedule() -> void:
	_schedule.clear()
	if _schedule_mode == ScheduleMode.FOCUSED_SUITE:
		_build_focused_suite_schedule()
		return
	for lap: int in range(maxi(1, round_robin_laps)):
		for i: int in range(_ai_profiles.size()):
			for j: int in range(i + 1, _ai_profiles.size()):
				_schedule.append({"lap": lap, "p1": i, "p2": j})


## Builds focused benchmark schedule for extreme profile matchups.
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


## Returns AI profile index by compact name, or -1 when missing.
func _find_ai_profile_index(profile_name: String) -> int:
	for i: int in range(_ai_profiles.size()):
		var profile: Dictionary = _ai_profiles[i] as Dictionary
		if String(profile.get("name", "")) == profile_name:
			return i
	return -1


## Reads historical results and returns ranked opponent profile names.
func _rank_campaign_opponent_names_from_csv() -> Array[String]:
	var file: FileAccess = FileAccess.open("user://playtests.csv", FileAccess.READ)
	if file == null:
		return []
	var raw_text: String = file.get_as_text()
	file.close()
	if raw_text.strip_edges() == "":
		return []
	var lines: PackedStringArray = raw_text.split("\n", false)
	if lines.size() < 2:
		return []
	var header_columns: PackedStringArray = lines[0].strip_edges().split(",")
	var p1_idx: int = header_columns.find("p1_ai")
	var p2_idx: int = header_columns.find("p2_ai")
	var winner_idx: int = header_columns.find("winner_ai")
	if p1_idx < 0 or p2_idx < 0 or winner_idx < 0:
		return []
	var stats_by_name: Dictionary = {}
	for line_idx: int in range(1, lines.size()):
		var row: String = String(lines[line_idx]).strip_edges()
		if row == "":
			continue
		var columns: PackedStringArray = row.split(",")
		var needed_index: int = maxi(p1_idx, maxi(p2_idx, winner_idx))
		if columns.size() <= needed_index:
			continue
		var p1_name: String = String(columns[p1_idx]).strip_edges()
		var p2_name: String = String(columns[p2_idx]).strip_edges()
		var winner_name: String = String(columns[winner_idx]).strip_edges()
		_register_campaign_result(stats_by_name, p1_name, p2_name, winner_name)

	var ranked_entries: Array[Dictionary] = []
	for profile_name_variant: Variant in stats_by_name.keys():
		var profile_name: String = String(profile_name_variant)
		if profile_name == "" or profile_name == "P1" or profile_name == "P2":
			continue
		if _find_ai_profile_index(profile_name) < 0:
			continue
		var metrics: Dictionary = stats_by_name[profile_name] as Dictionary
		var wins: int = int(metrics.get("wins", 0))
		var matches: int = int(metrics.get("matches", 0))
		if matches <= 0:
			continue
		ranked_entries.append({
			"name": profile_name,
			"wins": wins,
			"matches": matches,
			"win_rate": float(wins) / float(matches)
		})

	ranked_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wins_a: int = int(a.get("wins", 0))
		var wins_b: int = int(b.get("wins", 0))
		if wins_a != wins_b:
			return wins_a > wins_b
		var rate_a: float = float(a.get("win_rate", 0.0))
		var rate_b: float = float(b.get("win_rate", 0.0))
		if absf(rate_a - rate_b) > 0.0001:
			return rate_a > rate_b
		return String(a.get("name", "")) < String(b.get("name", ""))
	)

	var top_names_descending: Array[String] = []
	for entry: Dictionary in ranked_entries:
		if top_names_descending.size() >= _CAMPAIGN_STAGE_COUNT:
			break
		top_names_descending.append(String(entry.get("name", "")))
	top_names_descending.reverse()
	return top_names_descending


## Tracks match appearances and wins for campaign ranking.
func _register_campaign_result(stats_by_name: Dictionary, p1_name: String, p2_name: String, winner_name: String) -> void:
	for contender_name: String in [p1_name, p2_name]:
		if contender_name == "":
			continue
		if not stats_by_name.has(contender_name):
			stats_by_name[contender_name] = {"wins": 0, "matches": 0}
		var contender_stats: Dictionary = stats_by_name[contender_name] as Dictionary
		contender_stats["matches"] = int(contender_stats.get("matches", 0)) + 1
		stats_by_name[contender_name] = contender_stats
	if winner_name == "":
		return
	if not stats_by_name.has(winner_name):
		stats_by_name[winner_name] = {"wins": 0, "matches": 0}
	var winner_stats: Dictionary = stats_by_name[winner_name] as Dictionary
	winner_stats["wins"] = int(winner_stats.get("wins", 0)) + 1
	stats_by_name[winner_name] = winner_stats


## Builds campaign opponent profile indices from CSV ranking with fallback defaults.
func _build_campaign_opponent_indices() -> Array[int]:
	var selected_indices: Array[int] = []
	var ranked_names: Array[String] = _rank_campaign_opponent_names_from_csv()
	for profile_name: String in ranked_names:
		if selected_indices.size() >= _CAMPAIGN_STAGE_COUNT:
			break
		var profile_idx: int = _find_ai_profile_index(profile_name)
		if profile_idx >= 0 and not selected_indices.has(profile_idx):
			selected_indices.append(profile_idx)

	for fallback_name: String in _CAMPAIGN_FALLBACK_PROFILE_NAMES:
		if selected_indices.size() >= _CAMPAIGN_STAGE_COUNT:
			break
		var fallback_idx: int = _find_ai_profile_index(fallback_name)
		if fallback_idx >= 0 and not selected_indices.has(fallback_idx):
			selected_indices.append(fallback_idx)

	for i: int in range(_ai_profiles.size()):
		if selected_indices.size() >= _CAMPAIGN_STAGE_COUNT:
			break
		if not selected_indices.has(i):
			selected_indices.append(i)

	return selected_indices


## Initializes analytics CSV files and writes headers.
func _init_csv_files() -> void:
	var f1: FileAccess = FileAccess.open("user://playtests.csv", FileAccess.WRITE)
	if f1 != null:
		f1.store_line("schema_version,game_id,lap,p1_ai,p2_ai,p1_weights,p2_weights,winner_ai,match_seconds,match_frames,p1_guppy,p1_sabalo,p1_dientudo,p2_guppy,p2_sabalo,p2_dientudo,p1_feed_events,p2_feed_events,p1_predations,p2_predations,p1_resources_spent,p2_resources_spent,p1_score_points,p2_score_points,p1_redeemed_biomass_g,p2_redeemed_biomass_g,p1_guppy_alive_exit_ge5,p1_sabalo_alive_exit_ge5,p1_dientudo_alive_exit_ge5,p2_guppy_alive_exit_ge5,p2_sabalo_alive_exit_ge5,p2_dientudo_alive_exit_ge5,p1_points_per_resource,p2_points_per_resource,p1_fed_fish,p2_fed_fish,p1_self_predations,p1_opponent_predations,p2_self_predations,p2_opponent_predations,p1_contest_wins,p2_contest_wins,p1_contest_losses,p2_contest_losses,p1_denied_opportunities_est,p2_denied_opportunities_est,p1_avg_contest_latency_s,p2_avg_contest_latency_s,p1_avg_conversion_points_per_feed,p2_avg_conversion_points_per_feed,global_avg_conversion_points_per_feed,global_avg_conversion_weight_gain_g_per_feed")
		f1.close()
		print("Zoo: playtests.csv -> ", ProjectSettings.globalize_path("user://playtests.csv"))
	var f2: FileAccess = FileAccess.open("user://spawn_sequences.csv", FileAccess.WRITE)
	if f2 != null:
		f2.store_line("game_id,player_ai,order,species,frame,time_s,guppy_spent_ratio,sabalo_spent_ratio,dientudo_spent_ratio")
		f2.close()
	var f3: FileAccess = FileAccess.open("user://round_metrics.csv", FileAccess.WRITE)
	if f3 != null:
		f3.store_line("schema_version,game_id,winner_ai,player_ai,player_id,species,feed_events,fed_fish,alive_exits,alive_exits_ge1,alive_exits_ge3,alive_exits_ge5,predated_deaths,self_predations,opponent_predations,contest_wins,contest_losses,denied_opportunities_est,avg_contest_latency_s,point_gain_total,weight_gain_total_g,avg_conversion_points_per_feed,avg_conversion_weight_gain_g_per_feed,spawns")
		f3.close()


## Starts one scheduled match by applying AI strategies and seeding entities.
func _start_match() -> void:
	var entry: Dictionary = _schedule[_schedule_index]
	var p1_profile: Dictionary = _ai_profiles[int(entry["p1"])] as Dictionary
	var p2_profile: Dictionary = _ai_profiles[int(entry["p2"])] as Dictionary
	_is_local_two_player_mode = false
	_is_one_player_campaign_mode = false
	if spawner_p1 != null and spawner_p1.has_method("set_manual_control_enabled"):
		spawner_p1.call("set_manual_control_enabled", false)
	if spawner_p2 != null and spawner_p2.has_method("set_manual_control_enabled"):
		spawner_p2.call("set_manual_control_enabled", false)
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


## Starts one-player campaign against top-ranked AI opponents.
func _start_one_player_campaign() -> void:
	_is_local_two_player_mode = false
	_is_one_player_campaign_mode = true
	_campaign_opponent_indices = _build_campaign_opponent_indices()
	if _campaign_opponent_indices.is_empty():
		push_warning("Zoo: no campaign opponents available.")
		_return_to_mode_menu()
		return
	_campaign_stage_index = 0
	_campaign_pending_winner_player = 0
	_schedule.clear()
	for stage: int in range(mini(_CAMPAIGN_STAGE_COUNT, _campaign_opponent_indices.size())):
		_schedule.append({"lap": 0, "p1": - 1, "p2": _campaign_opponent_indices[stage]})
	_start_campaign_stage(_campaign_stage_index)


## Boots one campaign stage with manual player control versus AI profile opponent.
func _start_campaign_stage(stage_index: int) -> void:
	if stage_index < 0 or stage_index >= _campaign_opponent_indices.size():
		_return_to_mode_menu()
		return
	_campaign_stage_index = stage_index
	_schedule_index = stage_index
	_campaign_pending_winner_player = 0
	score_by_player = {1: 0.0, 2: 0.0}
	_redeemed_biomass_by_player = {1: 0.0, 2: 0.0}
	_spawns_p1 = _zero_species_counter()
	_spawns_p2 = _zero_species_counter()
	_spawn_seq_p1.clear()
	_spawn_seq_p2.clear()
	_spawn_seq_events_p1.clear()
	_spawn_seq_events_p2.clear()
	_fish_lifecycle_by_id.clear()
	_pellet_spawn_timer = 0.0
	_reset_match_analytics()
	_p1_ai_name = "P1"
	_p1_ai_weights = {}
	var opponent_index: int = _campaign_opponent_indices[_campaign_stage_index]
	var opponent_profile: Dictionary = _ai_profiles[opponent_index] as Dictionary
	_p2_ai_name = String(opponent_profile.get("name", "AI"))
	_p2_ai_weights = (opponent_profile.get("weights", {}) as Dictionary).duplicate(true)
	if spawner_p1 != null and spawner_p1.has_method("reset"):
		spawner_p1.call("reset")
	if spawner_p2 != null and spawner_p2.has_method("reset"):
		spawner_p2.call("reset")
	if spawner_p1 != null and spawner_p1.has_method("set_manual_control_enabled"):
		spawner_p1.call("set_manual_control_enabled", true)
	if spawner_p2 != null and spawner_p2.has_method("set_manual_control_enabled"):
		spawner_p2.call("set_manual_control_enabled", false)
	if spawner_p2 != null and spawner_p2.has_method("configure_strategy"):
		spawner_p2.call("configure_strategy", _p2_ai_name, opponent_profile.get("weights", {}))
	_match_active = true
	_reset_timer = 0.0
	if _win_label != null:
		_win_label.hide()
	_seed_startup_pellets()
	_seed_startup_detritus()


## Advances campaign stage on win, or retries current stage on loss.
func _advance_campaign_after_round() -> void:
	if _campaign_pending_winner_player == 1:
		var next_stage: int = _campaign_stage_index + 1
		if next_stage >= mini(_CAMPAIGN_STAGE_COUNT, _campaign_opponent_indices.size()):
			if _win_label != null:
				_win_label.text = "Campaign complete!"
				_win_label.show()
			_return_to_mode_menu()
			return
		_start_campaign_stage(next_stage)
		return
	_start_campaign_stage(_campaign_stage_index)


## Starts local two-player controller mode with manual species selection.
func _start_local_two_player_match() -> void:
	_is_local_two_player_mode = true
	_is_one_player_campaign_mode = false
	_schedule = [ {"lap": 0, "p1": - 1, "p2": - 1}]
	_schedule_index = 0
	score_by_player = {1: 0.0, 2: 0.0}
	_redeemed_biomass_by_player = {1: 0.0, 2: 0.0}
	_spawns_p1 = _zero_species_counter()
	_spawns_p2 = _zero_species_counter()
	_spawn_seq_p1.clear()
	_spawn_seq_p2.clear()
	_spawn_seq_events_p1.clear()
	_spawn_seq_events_p2.clear()
	_fish_lifecycle_by_id.clear()
	_pellet_spawn_timer = 0.0
	_reset_match_analytics()
	_p1_ai_name = "P1"
	_p2_ai_name = "P2"
	_p1_ai_weights = {}
	_p2_ai_weights = {}
	if spawner_p1 != null and spawner_p1.has_method("reset"):
		spawner_p1.call("reset")
	if spawner_p2 != null and spawner_p2.has_method("reset"):
		spawner_p2.call("reset")
	if spawner_p1 != null and spawner_p1.has_method("set_manual_control_enabled"):
		spawner_p1.call("set_manual_control_enabled", true)
	if spawner_p2 != null and spawner_p2.has_method("set_manual_control_enabled"):
		spawner_p2.call("set_manual_control_enabled", true)
	_match_active = true
	_reset_timer = 0.0
	_seed_startup_pellets()
	_seed_startup_detritus()


## Defines the built-in AI profile suite used for schedule generation.
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


## Creates one profile dictionary from species weight ratios.
func _make_profile(profile_name: String, guppy: float, sabalo: float, dientudo: float) -> Dictionary:
	return {
		"name": profile_name,
		"weights": {
			SpeciesRegistry.GUPPY: guppy,
			SpeciesRegistry.SABALO: sabalo,
			SpeciesRegistry.DIENTUDO: dientudo
		}
	}


## Validates profile count and normalized weight sums.
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


## Clears round analytics counters and lifecycle registries.
func _reset_match_analytics() -> void:
	_match_elapsed_seconds = 0.0
	_match_frames = 0
	_predations_by_player = {1: 0, 2: 0}
	_feed_events_by_player = {1: 0, 2: 0}
	_feed_by_player_species = _new_player_species_metrics()
	_fed_fish_by_player_species = _new_player_species_metrics()
	_feed_point_gain_by_player_species = _new_player_species_metrics()
	_feed_weight_gain_by_player_species = _new_player_species_metrics()
	_alive_exits_by_player_species = _new_player_species_metrics()
	_alive_exits_ge1_by_player_species = _new_player_species_metrics()
	_alive_exits_ge3_by_player_species = _new_player_species_metrics()
	_alive_exits_ge5_by_player_species = _new_player_species_metrics()
	_predated_deaths_by_player_species = _new_player_species_metrics()
	_self_predations_by_player_species = _new_player_species_metrics()
	_opponent_predations_by_player_species = _new_player_species_metrics()
	_contest_wins_by_player_species = _new_player_species_metrics()
	_contest_losses_by_player_species = _new_player_species_metrics()
	_contest_latency_sum_by_player_species = _new_player_species_metrics()
	_contest_latency_count_by_player_species = _new_player_species_metrics()
	_estimated_denied_opportunities_by_player_species = _new_player_species_metrics()
	_fish_lifecycle_by_id.clear()
	_contest_state_by_target_id.clear()
	_last_target_snapshot_by_fish_id.clear()
	_pending_denied_by_fish_id.clear()
	_spawn_seq_events_p1.clear()
	_spawn_seq_events_p2.clear()


## Creates nested player->species metrics dictionary initialized to zero.
func _new_player_species_metrics() -> Dictionary:
	return {
		1: _zero_species_counter(),
		2: _zero_species_counter()
	}


## Increments one player/species metric bucket.
func _increment_species_metric(metrics: Dictionary, player_id: int, species_name: StringName) -> void:
	if not metrics.has(player_id):
		metrics[player_id] = _zero_species_counter()
	var per_species: Dictionary = metrics[player_id] as Dictionary
	per_species[species_name] = int(per_species.get(species_name, 0)) + 1
	metrics[player_id] = per_species


## Adds an arbitrary numeric amount to one player/species metric bucket.
func _add_species_metric_value(metrics: Dictionary, player_id: int, species_name: StringName, amount: float) -> void:
	if amount == 0.0:
		return
	if not metrics.has(player_id):
		metrics[player_id] = _zero_species_counter()
	var per_species: Dictionary = metrics[player_id] as Dictionary
	per_species[species_name] = float(per_species.get(species_name, 0.0)) + amount
	metrics[player_id] = per_species


## Reads one player/species metric value with safe default.
func _species_metric_value(metrics: Dictionary, player_id: int, species_name: StringName) -> int:
	if not metrics.has(player_id):
		return 0
	var per_species: Dictionary = metrics[player_id] as Dictionary
	return int(per_species.get(species_name, 0))


## Reads one player/species metric as float with safe default.
func _species_metric_float_value(metrics: Dictionary, player_id: int, species_name: StringName) -> float:
	if not metrics.has(player_id):
		return 0.0
	var per_species: Dictionary = metrics[player_id] as Dictionary
	return float(per_species.get(species_name, 0.0))


## Tracks alive exits split by minimum feed-count thresholds.
func _register_alive_exit(player_id: int, species_name: StringName, feed_count: int) -> void:
	_increment_species_metric(_alive_exits_by_player_species, player_id, species_name)
	if feed_count >= 1:
		_increment_species_metric(_alive_exits_ge1_by_player_species, player_id, species_name)
	if feed_count >= 3:
		_increment_species_metric(_alive_exits_ge3_by_player_species, player_id, species_name)
	if feed_count >= 5:
		_increment_species_metric(_alive_exits_ge5_by_player_species, player_id, species_name)


## Returns true when extended match diagnostics should accumulate this frame.
func _should_collect_diagnostics() -> bool:
	return enable_match_diagnostics and _match_active and not _awaiting_mode_selection


## Samples active feed targets to classify contested resources across players.
func _sample_contested_targets() -> void:
	if not _should_collect_diagnostics():
		return
	var now: float = _match_elapsed_seconds
	_prune_pending_denied_opportunities(now)
	var previous_targets: Dictionary = _last_target_snapshot_by_fish_id.duplicate(true)
	var current_targets: Dictionary = {}
	for child: Node in pond.get_children():
		if not (child is Fish):
			continue
		var fish: Fish = child as Fish
		if fish.pending_remove:
			continue
		if fish.species == SpeciesRegistry.PELLET or fish.species == SpeciesRegistry.DETRITUS:
			continue
		var target: Fish = fish.get_diagnostic_feed_target()
		if target == null or not is_instance_valid(target) or target.pending_remove:
			continue
		var distance_px: float = fish.global_position.distance_to(target.global_position)
		if distance_px > diagnostics_contest_distance_threshold_px:
			continue
		var fish_id: int = fish.get_instance_id()
		var target_id: int = target.get_instance_id()
		current_targets[fish_id] = {
			"target_id": target_id,
			"player": fish.player,
			"species": fish.species,
			"time_s": now
		}
		_register_target_contender(target, fish, distance_px, now)
	_queue_abandoned_target_opportunities(previous_targets, current_targets, now)
	_last_target_snapshot_by_fish_id = current_targets
	_prune_contest_states(now)


## Stores one contender observation against the target currently being pursued.
func _register_target_contender(target: Fish, fish: Fish, distance_px: float, now: float) -> void:
	var target_id: int = target.get_instance_id()
	var target_owner: int = 0
	if target.species != SpeciesRegistry.PELLET and target.species != SpeciesRegistry.DETRITUS:
		target_owner = target.player
	var state: Dictionary = _contest_state_by_target_id.get(target_id, {
		"target_species": target.species,
		"target_player": target_owner,
		"first_seen_s": now,
		"first_contested_s": - 1.0,
		"last_seen_s": now,
		"contenders": {}
	}) as Dictionary
	var contenders: Dictionary = state.get("contenders", {}) as Dictionary
	contenders[fish.get_instance_id()] = {
		"player": fish.player,
		"species": fish.species,
		"distance_px": distance_px,
		"last_seen_s": now
	}
	state["contenders"] = contenders
	state["last_seen_s"] = now
	if _count_contesting_players(contenders) >= 2 and float(state.get("first_contested_s", -1.0)) < 0.0:
		state["first_contested_s"] = now
	_contest_state_by_target_id[target_id] = state


## Queues dropped contested targets so later opponent consumption can count as denied opportunity.
func _queue_abandoned_target_opportunities(previous_targets: Dictionary, current_targets: Dictionary, now: float) -> void:
	for fish_id_variant: Variant in previous_targets.keys():
		var fish_id: int = int(fish_id_variant)
		var previous_snapshot: Dictionary = previous_targets[fish_id] as Dictionary
		var previous_target_id: int = int(previous_snapshot.get("target_id", 0))
		if previous_target_id <= 0:
			continue
		var current_snapshot: Dictionary = current_targets.get(fish_id, {}) as Dictionary
		var current_target_id: int = int(current_snapshot.get("target_id", 0))
		if current_target_id == previous_target_id:
			continue
		if not _contest_state_by_target_id.has(previous_target_id):
			continue
		var state: Dictionary = _contest_state_by_target_id[previous_target_id] as Dictionary
		if not _state_has_opposing_contest(state, int(previous_snapshot.get("player", 0))):
			continue
		_pending_denied_by_fish_id[fish_id] = {
			"target_id": previous_target_id,
			"player": int(previous_snapshot.get("player", 0)),
			"species": previous_snapshot.get("species", SpeciesRegistry.DEFAULT_SPECIES) as StringName,
			"expires_at": now + diagnostics_denied_opportunity_window_seconds
		}


## Resolves a consumed contested target into win/loss/latency and pending denied metrics.
func _resolve_contested_target(target_fish_id: int, winner_player: int, winner_species: StringName, winner_fish_id: int) -> void:
	if not _should_collect_diagnostics():
		return
	_clear_pending_denied_for_fish(winner_fish_id)
	_clear_target_snapshots_for_target(target_fish_id)
	if target_fish_id <= 0 or not _contest_state_by_target_id.has(target_fish_id):
		return
	var now: float = _match_elapsed_seconds
	var state: Dictionary = _contest_state_by_target_id[target_fish_id] as Dictionary
	var contenders: Dictionary = state.get("contenders", {}) as Dictionary
	if _count_contesting_players(contenders) >= 2:
		_increment_species_metric(_contest_wins_by_player_species, winner_player, winner_species)
		var first_contested_s: float = float(state.get("first_contested_s", -1.0))
		if first_contested_s >= 0.0:
			_add_species_metric_value(_contest_latency_sum_by_player_species, winner_player, winner_species, maxf(0.0, now - first_contested_s))
			_increment_species_metric(_contest_latency_count_by_player_species, winner_player, winner_species)
		for contender_fish_id_variant: Variant in contenders.keys():
			var contender_fish_id: int = int(contender_fish_id_variant)
			if contender_fish_id == winner_fish_id:
				continue
			var contender: Dictionary = contenders[contender_fish_id] as Dictionary
			var contender_player: int = int(contender.get("player", 0))
			if contender_player == winner_player:
				continue
			_increment_species_metric(_contest_losses_by_player_species, contender_player, contender.get("species", SpeciesRegistry.DEFAULT_SPECIES) as StringName)
	_resolve_pending_denied_for_target(target_fish_id, winner_player, now)
	_contest_state_by_target_id.erase(target_fish_id)


## Drops contest states once contenders expire beyond the configured time window.
func _prune_contest_states(now: float) -> void:
	for target_id_variant: Variant in _contest_state_by_target_id.keys():
		var target_id: int = int(target_id_variant)
		var state: Dictionary = _contest_state_by_target_id[target_id] as Dictionary
		var contenders: Dictionary = state.get("contenders", {}) as Dictionary
		for contender_fish_id_variant: Variant in contenders.keys():
			var contender_fish_id: int = int(contender_fish_id_variant)
			var contender: Dictionary = contenders[contender_fish_id] as Dictionary
			if now - float(contender.get("last_seen_s", -9999.0)) > diagnostics_contest_window_seconds:
				contenders.erase(contender_fish_id)
		if contenders.is_empty() and now - float(state.get("last_seen_s", 0.0)) > diagnostics_contest_window_seconds:
			_contest_state_by_target_id.erase(target_id)
			continue
		state["contenders"] = contenders
		_contest_state_by_target_id[target_id] = state


## Removes expired pending denied-opportunity candidates.
func _prune_pending_denied_opportunities(now: float) -> void:
	for fish_id_variant: Variant in _pending_denied_by_fish_id.keys():
		var fish_id: int = int(fish_id_variant)
		var pending: Dictionary = _pending_denied_by_fish_id[fish_id] as Dictionary
		if now > float(pending.get("expires_at", -1.0)):
			_pending_denied_by_fish_id.erase(fish_id)


## Returns true when a target state includes at least one opposing contender.
func _state_has_opposing_contest(state: Dictionary, player_id: int) -> bool:
	var contenders: Dictionary = state.get("contenders", {}) as Dictionary
	for contender_variant: Variant in contenders.values():
		var contender: Dictionary = contender_variant as Dictionary
		if int(contender.get("player", 0)) != player_id:
			return true
	return false


## Counts unique players currently contesting the same target.
func _count_contesting_players(contenders: Dictionary) -> int:
	var seen_players: Dictionary = {}
	for contender_variant: Variant in contenders.values():
		var contender: Dictionary = contender_variant as Dictionary
		seen_players[int(contender.get("player", 0))] = true
	return seen_players.size()


## Clears target snapshots for fish that were still pointing at a resolved target.
func _clear_target_snapshots_for_target(target_fish_id: int) -> void:
	if target_fish_id <= 0:
		return
	for fish_id_variant: Variant in _last_target_snapshot_by_fish_id.keys():
		var fish_id: int = int(fish_id_variant)
		var snapshot: Dictionary = _last_target_snapshot_by_fish_id[fish_id] as Dictionary
		if int(snapshot.get("target_id", 0)) == target_fish_id:
			_last_target_snapshot_by_fish_id.erase(fish_id)


## Clears pending denied-opportunity bookkeeping for one fish after a successful consumption.
func _clear_pending_denied_for_fish(fish_id: int) -> void:
	if _pending_denied_by_fish_id.has(fish_id):
		_pending_denied_by_fish_id.erase(fish_id)


## Converts pending dropped-target records into estimated denied opportunities when opponents consume first.
func _resolve_pending_denied_for_target(target_fish_id: int, winner_player: int, now: float) -> void:
	for fish_id_variant: Variant in _pending_denied_by_fish_id.keys():
		var fish_id: int = int(fish_id_variant)
		var pending: Dictionary = _pending_denied_by_fish_id[fish_id] as Dictionary
		if int(pending.get("target_id", 0)) != target_fish_id:
			continue
		if now <= float(pending.get("expires_at", -1.0)) and int(pending.get("player", 0)) != winner_player:
			_increment_species_metric(_estimated_denied_opportunities_by_player_species, int(pending.get("player", 0)), pending.get("species", SpeciesRegistry.DEFAULT_SPECIES) as StringName)
		_pending_denied_by_fish_id.erase(fish_id)


## Sums all species buckets for one player metric dictionary.
func _sum_player_species_metric(metrics: Dictionary, player_id: int) -> float:
	if not metrics.has(player_id):
		return 0.0
	var total: float = 0.0
	var per_species: Dictionary = metrics[player_id] as Dictionary
	for value: Variant in per_species.values():
		total += float(value)
	return total


## Computes a zero-safe ratio for derived diagnostics.
func _safe_ratio(numerator: float, denominator: float) -> float:
	if denominator <= 0.0:
		return 0.0
	return numerator / denominator


## Returns average contest win latency across all species for a player.
func _average_player_contest_latency(player_id: int) -> float:
	return _safe_ratio(_sum_player_species_metric(_contest_latency_sum_by_player_species, player_id), _sum_player_species_metric(_contest_latency_count_by_player_species, player_id))


## Returns average contest win latency for one player/species bucket.
func _average_species_contest_latency(player_id: int, species_name: StringName) -> float:
	return _safe_ratio(_species_metric_float_value(_contest_latency_sum_by_player_species, player_id, species_name), _species_metric_float_value(_contest_latency_count_by_player_species, player_id, species_name))


## Records ordered spawn events and spent-resource ratios for sequence analytics.
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


## Encodes a compact printable weight triple (G|S|D).
func _weights_to_compact_string(weights: Dictionary) -> String:
	var g: float = float(weights.get(SpeciesRegistry.GUPPY, 0.0))
	var s: float = float(weights.get(SpeciesRegistry.SABALO, 0.0))
	var d: float = float(weights.get(SpeciesRegistry.DIENTUDO, 0.0))
	return "G%.2f|S%.2f|D%.2f" % [g, s, d]
