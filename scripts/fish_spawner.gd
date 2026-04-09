extends Node2D
class_name FishSpawner

@export_range(1, 2) var player_id: int = 1
@export var spawn_jitter_radius: float = 30.0
@export var repel_radius: float = 340.0
@export var repel_force_multiplier: float = 1.8
@export var use_fixed_seed: bool = false
@export var fixed_seed: int = 1
@export_range(0.0, 2.0, 0.01) var allocation_correction_strength: float = 0.7
@export_range(0.0, 1.0, 0.01) var min_target_retention_ratio: float = 0.2

const RESOURCE_MAX: float = 100.0
const RESOURCE_REGEN: float = 1.0 ## Resources regenerated per second.
const GUPPY_BURST_INTERVAL: float = 0.22 ## Seconds between guppies in a burst.
const INDIVIDUAL_COOLDOWN: float = 0.5 ## Seconds after spawning sabalo/dientudo.

## Resource cost to spawn one fish of each species.
static func species_cost(species: StringName) -> int:
	return SpeciesRegistry.get_spawn_cost(species)

var resources: float = 0.0
var selected_species: StringName = SpeciesRegistry.DEFAULT_SPECIES

var _queued_species: StringName = SpeciesRegistry.DEFAULT_SPECIES
var _spawn_ready: bool = false
var _cooldown: float = 0.0
var strategy: Dictionary = {}
var strategy_name: String = "random"
var resources_spent_by_species: Dictionary = {}
var spawns_by_species: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal species_changed(pid: int, species: StringName)


func _ready() -> void:
	add_to_group("fish_spawners")
	if use_fixed_seed:
		_rng.seed = fixed_seed
	else:
		_rng.randomize()
	_initialize_species_tracking()


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
	if selected_species == SpeciesRegistry.GUPPY:
		_cooldown = GUPPY_BURST_INTERVAL
	else:
		_cooldown = INDIVIDUAL_COOLDOWN
	_roll_species()


func _roll_species() -> void:
	var species_list: Array[StringName] = SpeciesRegistry.all_species()
	if species_list.is_empty():
		selected_species = SpeciesRegistry.DEFAULT_SPECIES
		species_changed.emit(player_id, selected_species)
		return
	if strategy.is_empty():
		selected_species = species_list[_rng.randi_range(0, species_list.size() - 1)]
		species_changed.emit(player_id, selected_species)
		return
	var total_spent: float = 0.0
	for sp: StringName in resources_spent_by_species:
		total_spent += float(resources_spent_by_species.get(sp, 0.0))

	var weighted_species: Array[StringName] = []
	var weighted_values: Array[float] = []
	var weighted_total: float = 0.0
	for sp: StringName in strategy:
		var target: float = maxf(0.0, float(strategy.get(sp, 0.0)))
		if target <= 0.0:
			continue
		var actual: float = 0.0
		if total_spent > 0.0:
			actual = float(resources_spent_by_species.get(sp, 0.0)) / total_spent
		var deficit: float = target - actual
		var corrected: float = target + deficit * allocation_correction_strength
		var retained_floor: float = target * min_target_retention_ratio
		var adjusted_weight: float = maxf(retained_floor, corrected)
		if adjusted_weight <= 0.0:
			continue
		weighted_species.append(sp)
		weighted_values.append(adjusted_weight)
		weighted_total += adjusted_weight

	if weighted_species.is_empty() or weighted_total <= 0.0:
		selected_species = species_list[_rng.randi_range(0, species_list.size() - 1)]
		species_changed.emit(player_id, selected_species)
		return

	var roll: float = _rng.randf_range(0.0, weighted_total)
	var accum: float = 0.0
	selected_species = weighted_species[weighted_species.size() - 1]
	for i: int in weighted_species.size():
		accum += weighted_values[i]
		if roll <= accum:
			selected_species = weighted_species[i]
			break
	species_changed.emit(player_id, selected_species)


func configure_strategy(strategy_label: String, weights: Dictionary) -> void:
	strategy_name = strategy_label
	strategy = weights.duplicate()
	_roll_species()


func can_spawn(_current_count: int) -> bool:
	return _spawn_ready


func add_resource(amount: float) -> void:
	if amount <= 0.0:
		return
	resources = minf(RESOURCE_MAX, resources + amount)


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
	_queued_species = SpeciesRegistry.DEFAULT_SPECIES
	_spawn_ready = false
	_cooldown = 0.0
	_initialize_species_tracking()
	selected_species = SpeciesRegistry.DEFAULT_SPECIES
	_roll_species()


func _initialize_species_tracking() -> void:
	resources_spent_by_species.clear()
	spawns_by_species.clear()
	for species_name: StringName in SpeciesRegistry.all_species():
		resources_spent_by_species[species_name] = 0.0
		spawns_by_species[species_name] = 0
