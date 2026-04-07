# Game.gd
# Main scene controller — wires all subsystems together at startup.
extends Node2D

# ── Node references (populated in _ready via @onready) ───────────────────────
@onready var _plants_container: Node2D = $Plants
@onready var _fish_container:   Node2D = $FishContainer
@onready var _spawn_system:     Node   = $SpawnSystem
@onready var _player1:          Node   = $Players/Player1
@onready var _player2:          Node   = $Players/Player2
@onready var _ui:               Node   = $UI

# ── Plant layout (world positions) ───────────────────────────────────────────
# Spread plants across the mid-pond area.  Players set up art assets later.
const PLANT_POSITIONS: Array = [
	Vector2(200, 280), Vector2(380, 350), Vector2(560, 260),
	Vector2(640, 420), Vector2(720, 280), Vector2(900, 350),
	Vector2(1080, 270), Vector2(320, 480), Vector2(960, 490),
]


func _ready() -> void:
	# ── Wire spawn system ─────────────────────────────────────────────────────
	_spawn_system.fish_container = _fish_container

	# ── Wire players ──────────────────────────────────────────────────────────
	_player1.spawn_system = _spawn_system
	_player2.spawn_system = _spawn_system

	# ── Connect player signals to the UI ──────────────────────────────────────
	_player1.connect("energy_changed",  _ui.update_energy)
	_player1.connect("species_changed", _ui.update_species)
	_player2.connect("energy_changed",  _ui.update_energy)
	_player2.connect("species_changed", _ui.update_species)

	# ── Spawn plants ──────────────────────────────────────────────────────────
	_spawn_plants()

	# Sync the UI with the initial species selection.
	_ui.update_species(1, _player1.selected_species)
	_ui.update_species(2, _player2.selected_species)


func _spawn_plants() -> void:
	var plant_scene: PackedScene = load("res://scenes/FloatingPlant.tscn")
	for pos in PLANT_POSITIONS:
		var plant: Node2D = plant_scene.instantiate()
		plant.position = pos
		_plants_container.add_child(plant)
