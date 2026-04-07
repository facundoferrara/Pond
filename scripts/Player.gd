# Player.gd
# Per-player controller.  Attach to a Node in the scene and set player_id / device_id.
# Handles input from one specific gamepad (or keyboard fallback),
# manages energy, and delegates spawning to SpawnSystem.
extends Node

# ── Configuration (set in scene or from Game.gd) ─────────────────────────────
@export var player_id: int = 1   ## 1 or 2
@export var device_id: int = 0   ## Gamepad device index: 0 = first pad, 1 = second pad

# ── Energy ───────────────────────────────────────────────────────────────────
const MAX_ENERGY      := 100.0
const ENERGY_REGEN    := 8.0    ## units per second
var energy: float = MAX_ENERGY

# ── Species selection ─────────────────────────────────────────────────────────
var selected_species: int = 0   ## index into FishData.SPECIES

# ── Continuous spawn (hold A) ─────────────────────────────────────────────────
const HOLD_SPAWN_INTERVAL := 0.6   ## seconds between auto-spawns while holding
var _holding_spawn: bool  = false
var _hold_timer: float    = 0.0

# ── Wired by Game.gd ─────────────────────────────────────────────────────────
var spawn_system: Node = null

# ── Signals ──────────────────────────────────────────────────────────────────
## Fired every frame so the UI can display a smooth bar.
signal energy_changed(pid: int, value: float)
## Fired when the selected species changes so the UI label can update.
signal species_changed(pid: int, species_index: int)


func _ready() -> void:
	add_to_group("players")


func _process(delta: float) -> void:
	# Regenerate energy over time
	energy = minf(energy + ENERGY_REGEN * delta, MAX_ENERGY)
	emit_signal("energy_changed", player_id, energy)

	# Continuous spawn while the button is held
	if _holding_spawn:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_try_spawn()
			_hold_timer = HOLD_SPAWN_INTERVAL


func _input(event: InputEvent) -> void:
	# Accept events from our device OR from the keyboard (device == -1).
	# Different key bindings per player prevent keyboard conflicts.
	if event.device != device_id and event.device != -1:
		return

	var prefix := "p%d_" % player_id

	# ── Species navigation ────────────────────────────────────────────────────
	if event.is_action_pressed(prefix + "select_left"):
		_select_species(-1)
	elif event.is_action_pressed(prefix + "select_right"):
		_select_species(1)

	# ── Spawn ─────────────────────────────────────────────────────────────────
	if event.is_action_pressed(prefix + "spawn"):
		_try_spawn()
		_holding_spawn = true
		_hold_timer = HOLD_SPAWN_INTERVAL
	elif event.is_action_released(prefix + "spawn"):
		_holding_spawn = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _select_species(direction: int) -> void:
	var total := FishData.count()
	selected_species = (selected_species + direction + total) % total
	emit_signal("species_changed", player_id, selected_species)


func _try_spawn() -> void:
	if spawn_system == null or not GameManager.game_active:
		return
	var species_data := FishData.get_species(selected_species)
	var cost: int = species_data.get("energy_cost", 10)
	if energy < cost:
		return   # not enough energy — silent refuse
	energy -= cost
	emit_signal("energy_changed", player_id, energy)
	spawn_system.spawn_fish(player_id, selected_species)
