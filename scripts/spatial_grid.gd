extends Node

## Spatial hash grid for O(1) neighbor lookup.
## Rebuilt once per frame by Zoo before any fish _process() runs.
## Fish registered here are the live, active fish only.
## Pooled (inactive) fish are never registered.

const CELL_SIZE: float = 120.0 ## Matches default vision_radius.

## Vector2i cell key -> Array of Fish in that cell.
var _cells: Dictionary = {}

## All live registered fish. Used for predator scan (kept small via register/unregister).
var _all_fish: Array[Fish] = []

## Subset of _all_fish that are predator species.
## Much smaller list; used only for predator detection scan.
var _potential_predators: Array[Fish] = []


## Called by Zoo._process() once per frame, BEFORE any Fish._process() runs.
func rebuild() -> void:
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
	var cell_radius: int = ceili(radius / CELL_SIZE)
	var center: Vector2i = _cell_for(pos)
	for dx: int in range(-cell_radius, cell_radius + 1):
		for dy: int in range(-cell_radius, cell_radius + 1):
			var cell: Vector2i = Vector2i(center.x + dx, center.y + dy)
			if _cells.has(cell):
				for fish: Fish in (_cells[cell] as Array):
					result.append(fish)
	return result


## Returns the live predator fish list.
func get_potential_predators() -> Array[Fish]:
	return _potential_predators


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
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
