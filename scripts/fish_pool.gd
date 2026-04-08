extends Node

## Dynamic, growing object pool for Fish nodes.
## Pre-warms a baseline count at startup to avoid first-spawn hitches.
## When the free list is exhausted, allocates a new instance and keeps it permanently.
## Population is never hard-capped; the ceiling is determined by gameplay parameters.

const GUPPY_SCENE: PackedScene = preload("res://scenes/guppy.tscn")
const SABALO_SCENE: PackedScene = preload("res://scenes/sabalo.tscn")
const DIENTUDO_SCENE: PackedScene = preload("res://scenes/dientudo.tscn")

## Fish instantiated at startup per type to avoid cold-start hitch.
@export var pre_warm_guppy_count: int = 20
@export var pre_warm_sabalo_count: int = 10
@export var pre_warm_dientudo_count: int = 5

var _free_guppies: Array[Fish] = []
var _free_sabalos: Array[Fish] = []
var _free_dientudos: Array[Fish] = []

## Hidden container keeps pooled nodes in the tree so they retain script state.
var _pool_container: Node


func _ready() -> void:
	_pool_container = Node.new()
	_pool_container.name = "FishPoolContainer"
	add_child(_pool_container)
	_prewarm(GUPPY_SCENE, pre_warm_guppy_count, _free_guppies)
	_prewarm(SABALO_SCENE, pre_warm_sabalo_count, _free_sabalos)
	_prewarm(DIENTUDO_SCENE, pre_warm_dientudo_count, _free_dientudos)


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
	if species_name == SpeciesDB.SABALO:
		return _acquire(SABALO_SCENE, _free_sabalos)
	if species_name == SpeciesDB.DIENTUDO:
		return _acquire(DIENTUDO_SCENE, _free_dientudos)
	return _acquire(GUPPY_SCENE, _free_guppies)


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

	if fish.species == SpeciesDB.SABALO:
		_free_sabalos.append(fish)
	elif fish.species == SpeciesDB.DIENTUDO:
		_free_dientudos.append(fish)
	else:
		_free_guppies.append(fish)
