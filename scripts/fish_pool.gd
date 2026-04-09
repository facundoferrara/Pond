extends Node

## Dynamic, growing object pool for Fish nodes.
## Pre-warms a baseline count at startup to avoid first-spawn hitches.
## When the free list is exhausted, allocates a new instance and keeps it permanently.
## Population is never hard-capped; the ceiling is determined by gameplay parameters.

## Fish instantiated at startup per type to avoid cold-start hitch.
@export var pre_warm_guppy_count: int = 20
@export var pre_warm_sabalo_count: int = 10
@export var pre_warm_dientudo_count: int = 5
@export var pre_warm_pellet_count: int = 50
@export var pre_warm_detritus_count: int = 20

var _free_by_species: Dictionary = {}

## Hidden container keeps pooled nodes in the tree so they retain script state.
var _pool_container: Node


func _ready() -> void:
	_pool_container = Node.new()
	_pool_container.name = "FishPoolContainer"
	add_child(_pool_container)
	for species_name: StringName in SpeciesRegistry.all_pooled_species():
		_get_pool(species_name)
		_prewarm(SpeciesRegistry.get_scene(species_name), _prewarm_count(species_name), _get_pool(species_name))


func _prewarm(scene: PackedScene, count: int, pool: Array[Fish]) -> void:
	for _i: int in range(count):
		var fish: Fish = scene.instantiate() as Fish
		_pool_container.add_child(fish)
		fish.hide()
		fish.set_process(false)
		pool.append(fish)


## Returns a fish for the given species, reusing a pooled one if available.
## The returned fish is still parented to the pool container — caller must reparent.
func acquire(species_name: StringName) -> Fish:
	var normalized_species: StringName = SpeciesRegistry.normalize_species(species_name)
	return _acquire(SpeciesRegistry.get_scene(normalized_species), _get_pool(normalized_species))


func _acquire(scene: PackedScene, pool: Array[Fish]) -> Fish:
	if not pool.is_empty():
		return pool.pop_back()
	# Pool exhausted — grow it permanently.
	var fish: Fish = scene.instantiate() as Fish
	_pool_container.add_child(fish)
	return fish


## Returns a fish to the pool. Disconnects signals, disables processing, and hides.
## Caller must NOT queue_free the fish after calling this.
func release(fish: Fish) -> void:
	if fish == null or not is_instance_valid(fish):
		return

	SpatialGrid.unregister_fish(fish)

	# Disconnect all fish_exited listeners to prevent duplicates on re-use.
	var connections: Array = fish.fish_exited.get_connections()
	for conn: Dictionary in connections:
		fish.fish_exited.disconnect(conn["callable"] as Callable)

	fish.set_process(false)
	fish.pending_remove = true
	fish.reparent(_pool_container)
	fish.hide()
	_get_pool(SpeciesRegistry.normalize_species(fish.species)).append(fish)


func _prewarm_count(species_name: StringName) -> int:
	match SpeciesRegistry.normalize_species(species_name):
		SpeciesRegistry.GUPPY:
			return pre_warm_guppy_count
		SpeciesRegistry.SABALO:
			return pre_warm_sabalo_count
		SpeciesRegistry.DIENTUDO:
			return pre_warm_dientudo_count
		SpeciesRegistry.PELLET:
			return pre_warm_pellet_count
		SpeciesRegistry.DETRITUS:
			return pre_warm_detritus_count
	return 0


func _get_pool(species_name: StringName) -> Array[Fish]:
	var normalized_species: StringName = SpeciesRegistry.normalize_species(species_name)
	if not _free_by_species.has(normalized_species):
		var new_pool: Array[Fish] = []
		_free_by_species[normalized_species] = new_pool
	var pool: Array[Fish] = _free_by_species[normalized_species]
	return pool
