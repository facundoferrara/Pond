extends RefCounted
class_name SpeciesRegistry

const GUPPY: StringName = &"guppy"
const SABALO: StringName = &"sabalo"
const DIENTUDO: StringName = &"dientudo"
const PELLET: StringName = &"pellet"
const DETRITUS: StringName = &"detritus"

const DEFAULT_SPECIES: StringName = GUPPY
const FISH_SPECIES_ORDER: Array[StringName] = [GUPPY, SABALO, DIENTUDO]
const POOLED_SPECIES_ORDER: Array[StringName] = [GUPPY, SABALO, DIENTUDO, PELLET, DETRITUS]

const GUPPY_SCENE: PackedScene = preload("res://scenes/guppy.tscn")
const SABALO_SCENE: PackedScene = preload("res://scenes/sabalo.tscn")
const DIENTUDO_SCENE: PackedScene = preload("res://scenes/dientudo.tscn")
const PELLET_SCENE: PackedScene = preload("res://scenes/pellet.tscn")
const DETRITUS_SCENE: PackedScene = preload("res://scenes/detritus.tscn")

const SCENES: Dictionary = {
	GUPPY: GUPPY_SCENE,
	SABALO: SABALO_SCENE,
	DIENTUDO: DIENTUDO_SCENE,
	PELLET: PELLET_SCENE,
	DETRITUS: DETRITUS_SCENE
}

const DISPLAY_NAMES: Dictionary = {
	GUPPY: "Guppy",
	SABALO: "Sabalo",
	DIENTUDO: "Dientudo",
	PELLET: "Pellet",
	DETRITUS: "Detritus"
}

const TEXTURE_PATHS: Dictionary = {
	GUPPY: "res://assets/mojarrita.png",
	SABALO: "res://assets/sabalo.png",
	DIENTUDO: "res://assets/dientudo.png",
	PELLET: "res://assets/pellet.png",
	DETRITUS: "res://assets/pellet.png"
}

const SPAWN_COSTS: Dictionary = {
	GUPPY: 1,
	SABALO: 4,
	DIENTUDO: 8,
	PELLET: 0,
	DETRITUS: 0
}

const PREWARM_COUNTS: Dictionary = {
	GUPPY: 20,
	SABALO: 10,
	DIENTUDO: 5,
	PELLET: 50,
	DETRITUS: 20
}


static func all_species() -> Array[StringName]:
	return FISH_SPECIES_ORDER.duplicate()


static func all_pooled_species() -> Array[StringName]:
	return POOLED_SPECIES_ORDER.duplicate()


static func has_species(species_name: StringName) -> bool:
	return SCENES.has(species_name)


static func normalize_species(species_name: StringName) -> StringName:
	if has_species(species_name):
		return species_name
	return DEFAULT_SPECIES


static func get_scene(species_name: StringName) -> PackedScene:
	var normalized: StringName = normalize_species(species_name)
	return SCENES.get(normalized, GUPPY_SCENE) as PackedScene


static func get_display_name(species_name: StringName) -> String:
	var normalized: StringName = normalize_species(species_name)
	return String(DISPLAY_NAMES.get(normalized, String(normalized)))


static func get_spawn_cost(species_name: StringName) -> int:
	var normalized: StringName = normalize_species(species_name)
	return int(SPAWN_COSTS.get(normalized, 1))


static func get_prewarm_count(species_name: StringName) -> int:
	var normalized: StringName = normalize_species(species_name)
	return int(PREWARM_COUNTS.get(normalized, 0))


static func get_texture_path(species_name: StringName) -> String:
	var normalized: StringName = normalize_species(species_name)
	return String(TEXTURE_PATHS.get(normalized, ""))


static func get_species_data(species_name: StringName) -> Dictionary:
	return SpeciesDB.get_species(normalize_species(species_name))


static func get_spawn_weight_range(species_name: StringName, fallback_weight: float) -> Vector2:
	var species_data: Dictionary = get_species_data(species_name)
	var min_weight: float = float(species_data.get("spawn_weight_min_g", fallback_weight))
	var max_weight: float = float(species_data.get("spawn_weight_max_g", fallback_weight))
	if max_weight < min_weight:
		var temp: float = min_weight
		min_weight = max_weight
		max_weight = temp
	return Vector2(min_weight, max_weight)
