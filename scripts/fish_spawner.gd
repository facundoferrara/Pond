extends Node2D
class_name FishSpawner

@export_range(1, 2) var player_id: int = 1
@export var spawn_jitter_radius: float = 30.0
@export var repel_radius: float = 340.0
@export var repel_force_multiplier: float = 1.8

const RESOURCE_MAX: float = 100.0
const RESOURCE_REGEN: float = 1.0 ## Points regenerated per second.
const GUPPY_BURST_INTERVAL: float = 0.22 ## Seconds between guppies in a burst.
const INDIVIDUAL_COOLDOWN: float = 0.5 ## Seconds after spawning sabalo/dientudo.

## Resource cost to spawn one fish of each species.
static func species_cost(species: StringName) -> int:
	match species:
		SpeciesDB.GUPPY: return 1
		SpeciesDB.SABALO: return 4
		SpeciesDB.DIENTUDO: return 8
	return 1

var resources: float = 0.0
var selected_species: StringName = SpeciesDB.GUPPY

var _queued_species: StringName = SpeciesDB.GUPPY
var _spawn_ready: bool = false
var _cooldown: float = 0.0
var strategy: Dictionary = {}
var strategy_name: String = "random"
var resources_spent_by_species: Dictionary = {
	SpeciesDB.GUPPY: 0.0,
	SpeciesDB.SABALO: 0.0,
	SpeciesDB.DIENTUDO: 0.0
}
var spawns_by_species: Dictionary = {
	SpeciesDB.GUPPY: 0,
	SpeciesDB.SABALO: 0,
	SpeciesDB.DIENTUDO: 0
}

signal species_changed(pid: int, species: StringName)


func _ready() -> void:
	add_to_group("fish_spawners")


func advance(delta: float) -> void:
	resources = minf(RESOURCE_MAX, resources + RESOURCE_REGEN * delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0 and not _spawn_ready:
		_try_queue_spawn()


func _try_queue_spawn() -> void:
	var cost: int = FishSpawner.species_cost(selected_species)
	if resources < float(cost):
		return
	resources -= float(cost)
	resources_spent_by_species[selected_species] = float(resources_spent_by_species.get(selected_species, 0.0)) + float(cost)
	_queued_species = selected_species
	_spawn_ready = true
	if selected_species == SpeciesDB.GUPPY:
		_cooldown = GUPPY_BURST_INTERVAL
	else:
		_cooldown = INDIVIDUAL_COOLDOWN
	_roll_species()


func _roll_species() -> void:
	if strategy.is_empty():
		var idx: int = randi() % 3
		if idx == 0:
			selected_species = SpeciesDB.GUPPY
		elif idx == 1:
			selected_species = SpeciesDB.SABALO
		else:
			selected_species = SpeciesDB.DIENTUDO
		species_changed.emit(player_id, selected_species)
		return
	var total_spent: float = 0.0
	for sp: StringName in resources_spent_by_species:
		total_spent += float(resources_spent_by_species.get(sp, 0.0))
	var best_deficit: float = - INF
	var best_sp: StringName = SpeciesDB.GUPPY
	for sp: StringName in strategy:
		var target: float = float(strategy[sp])
		var actual: float = 0.0
		if total_spent > 0.0:
			actual = float(resources_spent_by_species.get(sp, 0.0)) / total_spent
		var deficit: float = target - actual
		if deficit > best_deficit:
			best_deficit = deficit
			best_sp = sp
	selected_species = best_sp
	species_changed.emit(player_id, selected_species)


func configure_strategy(name: String, weights: Dictionary) -> void:
	strategy_name = name
	strategy = weights.duplicate()
	_roll_species()


func can_spawn(_current_count: int) -> bool:
	return _spawn_ready


func consume_spawn_request() -> Dictionary:
	_spawn_ready = false
	spawns_by_species[_queued_species] = int(spawns_by_species.get(_queued_species, 0)) + 1
	var jitter: Vector2 = Vector2(
		randf_range(-spawn_jitter_radius, spawn_jitter_radius),
		randf_range(-spawn_jitter_radius, spawn_jitter_radius)
	)
	return {
		"species": _queued_species,
		"player": player_id,
		"origin": global_position + jitter,
		"spawner_path": get_path()
	}


func reset() -> void:
	resources = 0.0
	_queued_species = SpeciesDB.GUPPY
	_spawn_ready = false
	_cooldown = 0.0
	for key: StringName in spawns_by_species:
		spawns_by_species[key] = 0
	for key: StringName in resources_spent_by_species:
		resources_spent_by_species[key] = 0.0
	_roll_species()
