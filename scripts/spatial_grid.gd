extends Node

## Spatial hash grid for O(1) neighbor lookup.
## Rebuilt once per frame by Zoo before any fish _process() runs.
## Fish registered here are the live, active fish only.
## Pooled (inactive) fish are never registered.

@export_group("Spatial Grid")
## Grid cell size in pixels. Keep near common vision radii for fewer queried cells.
@export var cell_size: float = 120.0
## Rebuild full grid every N frames. 1 = every frame; 2 = every other frame (1-frame-old positions, fine for ambient sim).
@export_range(1, 4, 1) var rebuild_interval: int = 2

## Vector2i cell key -> Array of Fish in that cell.
var _cells: Dictionary = {}
var _rebuild_frame_counter: int = 0

## All live registered fish. Used for predator scan (kept small via register/unregister).
var _all_fish: Array[Fish] = []

## Subset of _all_fish that are predator species.
## Much smaller list; used only for predator detection scan.
var _potential_predators: Array[Fish] = []


## Called by Zoo._process() once per frame, BEFORE any Fish._process() runs.
func rebuild() -> void:
	_rebuild_frame_counter += 1
	if _rebuild_frame_counter % maxi(rebuild_interval, 1) != 0:
		return
	_cells.clear()
	for fish: Fish in _all_fish:
		if not is_instance_valid(fish) or fish.pending_remove:
			continue
		var cell: Vector2i = _cell_for(fish.global_position)
		if not _cells.has(cell):
			_cells[cell] = [] as Array[Fish]
		(_cells[cell] as Array).append(fish)


## Returns all fish in cells that overlap the given circle.
## May include fish slightly outside the exact radius; callers should distance-check if needed.
func query_neighbors(pos: Vector2, radius: float) -> Array[Fish]:
	var result: Array[Fish] = []
	var safe_cell_size: float = maxf(cell_size, 1.0)
	var cell_radius: int = ceili(radius / safe_cell_size)
	var center: Vector2i = _cell_for(pos)
	for dx: int in range(-cell_radius, cell_radius + 1):
		for dy: int in range(-cell_radius, cell_radius + 1):
			var cell: Vector2i = Vector2i(center.x + dx, center.y + dy)
			if _cells.has(cell):
				for fish: Fish in (_cells[cell] as Array):
					result.append(fish)
	return result


## Returns neighbors limited to one species for cheap target acquisition.
func query_neighbors_by_species(pos: Vector2, radius: float, species_name: StringName) -> Array[Fish]:
	var result: Array[Fish] = []
	for fish: Fish in query_neighbors(pos, radius):
		if fish.species == species_name:
			result.append(fish)
	return result


## Returns neighbors whose species are in the provided whitelist.
func query_neighbors_by_species_set(pos: Vector2, radius: float, species_set: Array[StringName]) -> Array[Fish]:
	var result: Array[Fish] = []
	for fish: Fish in query_neighbors(pos, radius):
		if species_set.has(fish.species):
			result.append(fish)
	return result


## Returns the live predator fish list.
func get_potential_predators() -> Array[Fish]:
	return _potential_predators


## Returns a filtered snapshot of currently live fish.
func get_live_fish_snapshot() -> Array[Fish]:
	var result: Array[Fish] = []
	for fish: Fish in _all_fish:
		if not is_instance_valid(fish) or fish.pending_remove:
			continue
		result.append(fish)
	return result


## Called when a fish enters the pond and starts its active life.
func register_fish(fish: Fish) -> void:
	if not _all_fish.has(fish):
		_all_fish.append(fish)
	if fish.is_predator and not _potential_predators.has(fish):
		_potential_predators.append(fish)


## Called when a fish exits or is released to the pool.
func unregister_fish(fish: Fish) -> void:
	_all_fish.erase(fish)
	_potential_predators.erase(fish)


func _cell_for(pos: Vector2) -> Vector2i:
	var safe_cell_size: float = maxf(cell_size, 1.0)
	return Vector2i(floori(pos.x / safe_cell_size), floori(pos.y / safe_cell_size))
