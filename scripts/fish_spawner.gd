extends Node2D
class_name FishSpawner

## Autonomous spawner for continuous ecosystem simulation.
## Adaptively balances species populations toward target ratios.

@export_group("Spawner Configuration")
## Max random offset from spawner origin for each spawn (px).
@export var spawn_jitter_radius: float = 30.0

@export_group("Spawner Population Targets")
## Target proportion of guppies among all spawned fish (0.0-1.0).
@export_range(0.0, 1.0, 0.01) var target_guppy_ratio: float = 0.4
## Target proportion of sabalos among all spawned fish (0.0-1.0).
@export_range(0.0, 1.0, 0.01) var target_sabalo_ratio: float = 0.35
## Target proportion of dientudos among all spawned fish (0.0-1.0).
@export_range(0.0, 1.0, 0.01) var target_dientudo_ratio: float = 0.25

@export_group("Spawner Balancing")
## Deficit-correction gain for adaptive weight adjustment (0.0-2.0).
@export_range(0.0, 2.0, 0.01) var allocation_correction_strength: float = 0.7
## Minimum spawn weight to prevent species starvation.
@export_range(0.0, 1.0, 0.01) var min_spawn_weight_ratio: float = 0.15
## Seconds between population sampling for adaptation (lower = more responsive).
@export var population_check_interval: float = 2.0

@export_group("Spawner RNG")
## Enables deterministic spawn rolls for repeatable ecology.
@export var use_fixed_seed: bool = false
## Seed used when fixed RNG mode is enabled.
@export var fixed_seed: int = 1

const SPAWN_INTERVAL_GUPPY: float = 0.22 ## Seconds between guppy spawns.
const SPAWN_INTERVAL_OTHER: float = 0.5 ## Seconds between sabalo/dientudo spawns.

var _queued_species: StringName = SpeciesRegistry.DEFAULT_SPECIES
var _spawn_ready: bool = false
var _cooldown: float = 0.0
var _population_check_timer: float = 0.0
var _live_species_counts: Dictionary = {} ## Current observed populations.
var _spawn_weights: Dictionary = {} ## Normalized weights driving next roll.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal spawned_species(species: StringName)


## Initializes RNG and spawn weight distribution.
func _ready() -> void:
	add_to_group("fish_spawners")
	if use_fixed_seed:
		_rng.seed = fixed_seed
	else:
		_rng.randomize()
	_initialize_spawn_weights()
	_update_population_counts()


## Advances cooldown and queues spawns; periodically re-balances population targets.
func advance(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_population_check_timer -= delta
	
	if _population_check_timer <= 0.0:
		_update_population_counts()
		_recalculate_spawn_weights()
		_population_check_timer = population_check_interval
	
	if _cooldown <= 0.0 and not _spawn_ready:
		_try_queue_spawn()


## Samples current live fish populations grouped by species.
func _update_population_counts() -> void:
	_live_species_counts.clear()
	for species_name: StringName in SpeciesRegistry.all_species():
		_live_species_counts[species_name] = 0

	for fish: Fish in SpatialGrid.get_live_fish_snapshot():
		if not _live_species_counts.has(fish.species):
			continue
		var count: int = int(_live_species_counts.get(fish.species, 0))
		_live_species_counts[fish.species] = count + 1


## Initializes spawn weight distribution from target ratios.
func _initialize_spawn_weights() -> void:
	_spawn_weights.clear()
	_spawn_weights[SpeciesRegistry.GUPPY] = maxf(target_guppy_ratio, 0.0)
	_spawn_weights[SpeciesRegistry.SABALO] = maxf(target_sabalo_ratio, 0.0)
	_spawn_weights[SpeciesRegistry.DIENTUDO] = maxf(target_dientudo_ratio, 0.0)
	var total: float = 0.0
	for weight: Variant in _spawn_weights.values():
		total += float(weight)
	if total <= 0.0:
		_spawn_weights[SpeciesRegistry.GUPPY] = 0.4
		_spawn_weights[SpeciesRegistry.SABALO] = 0.35
		_spawn_weights[SpeciesRegistry.DIENTUDO] = 0.25


## Recalculates spawn weights based on current population deficit/surplus.
func _recalculate_spawn_weights() -> void:
	var total_alive: int = 0
	for count: Variant in _live_species_counts.values():
		total_alive += int(count)
	
	var target_ratios: Dictionary = {
		SpeciesRegistry.GUPPY: target_guppy_ratio,
		SpeciesRegistry.SABALO: target_sabalo_ratio,
		SpeciesRegistry.DIENTUDO: target_dientudo_ratio
	}
	
	var adjusted_weights: Dictionary = {}
	var total_weight: float = 0.0
	
	for species_name: StringName in SpeciesRegistry.all_species():
		var target_ratio: float = float(target_ratios.get(species_name, 0.0))
		if target_ratio <= 0.0:
			adjusted_weights[species_name] = 0.0
			continue
		
		var actual_ratio: float = 0.0
		if total_alive > 0:
			var current_count: int = int(_live_species_counts.get(species_name, 0))
			actual_ratio = float(current_count) / float(total_alive)
		
		var deficit: float = target_ratio - actual_ratio
		var corrected_weight: float = target_ratio + deficit * allocation_correction_strength
		var min_weight: float = target_ratio * min_spawn_weight_ratio
		var final_weight: float = maxf(min_weight, corrected_weight)
		
		adjusted_weights[species_name] = maxf(0.0, final_weight)
		total_weight += final_weight
	
	if total_weight <= 0.0:
		_initialize_spawn_weights()
		return
	
	# Normalize weights to sum to 1.0
	for species_name: StringName in adjusted_weights:
		_spawn_weights[species_name] = float(adjusted_weights[species_name]) / total_weight


## Queues one spawn with the next adaptive species choice.
func _try_queue_spawn() -> void:
	_queued_species = _roll_next_species()
	_spawn_ready = true
	if _queued_species == SpeciesRegistry.GUPPY:
		_cooldown = SPAWN_INTERVAL_GUPPY
	else:
		_cooldown = SPAWN_INTERVAL_OTHER
	spawned_species.emit(_queued_species)


## Weighted random roll from current spawn weight distribution.
func _roll_next_species() -> StringName:
	var species_list: Array[StringName] = SpeciesRegistry.all_species()
	if species_list.is_empty():
		return SpeciesRegistry.DEFAULT_SPECIES
	
	var roll: float = _rng.randf_range(0.0, 1.0)
	var accum: float = 0.0
	var selected: StringName = species_list[0]
	
	for species_name: StringName in species_list:
		accum += float(_spawn_weights.get(species_name, 0.0))
		if roll <= accum:
			selected = species_name
			break
	
	return selected


## Returns true when a spawn payload is ready for consumption.
func can_spawn(_current_count: int) -> bool:
	return _spawn_ready


## Returns a queued spawn request payload consumed by Zoo.
func consume_spawn_request() -> Dictionary:
	_spawn_ready = false
	var jitter: Vector2 = Vector2(
		_rng.randf_range(-spawn_jitter_radius, spawn_jitter_radius),
		_rng.randf_range(-spawn_jitter_radius, spawn_jitter_radius)
	)
	return {
		"species": _queued_species,
		"origin": global_position + jitter
	}


## Resets spawner state for continuous operation.
func reset() -> void:
	_cooldown = 0.0
	_spawn_ready = false
	_queued_species = SpeciesRegistry.DEFAULT_SPECIES
	_population_check_timer = 0.0
	_initialize_spawn_weights()
	_update_population_counts()
	_recalculate_spawn_weights()
