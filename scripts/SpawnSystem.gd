# SpawnSystem.gd
# Instantiates fish at per-player spawn positions and registers them in the pond.
extends Node

# ── Wired by Game.gd ─────────────────────────────────────────────────────────
var fish_container: Node2D = null

# ── Spawn X positions (centre of each player's spawn zone) ───────────────────
@export var p1_spawn_x: float = 320.0
@export var p2_spawn_x: float = 960.0
@export var spawn_y: float    = 90.0

# Small random horizontal spread so fish don't stack.
const SPAWN_SPREAD := 30.0

var _fish_scene: PackedScene = null


func _ready() -> void:
	_fish_scene = load("res://scenes/Fish.tscn")


## Spawn one fish for the given player using the given species index.
func spawn_fish(player_id: int, species_index: int) -> void:
	if not GameManager.game_active or _fish_scene == null or fish_container == null:
		return

	var fish: Node2D = _fish_scene.instantiate()
	fish_container.add_child(fish)
	fish.add_to_group("fish")

	var sx := p1_spawn_x if player_id == 1 else p2_spawn_x
	sx += randf_range(-SPAWN_SPREAD, SPAWN_SPREAD)
	fish.position = Vector2(sx, spawn_y)

	# Pass data before the fish's own _ready runs (setup is called immediately).
	fish.setup(player_id, species_index)
