# FishBase.gd
# Behaviour script for every fish instance.
# Supports three behaviour modes based on species data:
#   • swimmer  — swim downstream with lateral wobble
#   • feeder   — swimmer + detour to floating plants to eat detritus
#   • predator — hunt and eat the nearest opposite-colour fish
extends Node2D

# ── Identity ──────────────────────────────────────────────────────────────────
var player_id: int      = 1
var species_index: int  = 0

# ── Stats (loaded from FishData) ──────────────────────────────────────────────
var biomass: float           = 1.0
var speed: float             = 60.0
var is_predator: bool        = false
var eats_detritus: bool      = false
var energy_reward: float     = 0.0
var wobble_amp: float        = 8.0
var wobble_freq: float       = 2.0
var detection_radius: float  = 100.0

# ── Internal state ─────────────────────────────────────────────────────────────
var _time: float        = 0.0
var _base_x: float      = 0.0   # X reference for wobble calculation
var _hunt_target: Node2D = null
var _eating: bool        = false
var _eat_timer: float    = 0.0
const EAT_DURATION := 1.5       # seconds to pause at a plant

var _body: Polygon2D = null


# ── Initialise ────────────────────────────────────────────────────────────────

## Called by SpawnSystem right after add_child so data is ready before _ready().
func setup(p_player_id: int, p_species_index: int) -> void:
	player_id     = p_player_id
	species_index = p_species_index

	var d := FishData.get_species(species_index)
	biomass          = d.get("base_biomass",     1.0)
	speed            = d.get("speed",           60.0)
	is_predator      = d.get("is_predator",    false)
	eats_detritus    = d.get("eats_detritus",  false)
	energy_reward    = d.get("energy_reward",    0.0)
	wobble_amp       = d.get("wobble_amp",       8.0)
	wobble_freq      = d.get("wobble_freq",      2.0)
	detection_radius = d.get("detection_radius",100.0)

	var color_key := "color_p%d" % player_id
	var body_color: Color = d.get(color_key, Color.WHITE)
	var sz: float         = d.get("size", 12.0)

	_base_x = position.x
	_build_visuals(body_color, sz)


func _ready() -> void:
	# _base_x may already be set by setup(); guard against _ready firing first.
	if _base_x == 0.0:
		_base_x = position.x


# ── Visuals ───────────────────────────────────────────────────────────────────

func _build_visuals(body_color: Color, sz: float) -> void:
	# Simple fish silhouette using a Polygon2D child.
	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-sz * 0.8,  0.0),
		Vector2(-sz * 0.3, -sz * 0.35),
		Vector2( sz * 0.5, -sz * 0.22),
		Vector2( sz * 0.8,  0.0),
		Vector2( sz * 0.5,  sz * 0.22),
		Vector2(-sz * 0.3,  sz * 0.35),
	])
	_body.color = body_color
	add_child(_body)


# ── Update loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not GameManager.game_active:
		return

	_time += delta

	# While eating at a plant, stay still.
	if _eating:
		_eat_timer -= delta
		if _eat_timer <= 0.0:
			_eating = false
		return

	# Choose behaviour based on species type.
	if is_predator:
		_behaviour_predator(delta)
	elif eats_detritus:
		_behaviour_feeder(delta)
	else:
		_behaviour_swimmer(delta)

	# Exit check — bottom of the pond.
	if position.y > GameManager.POND_RECT.end.y:
		_exit_pond()


# ── Behaviour modes ───────────────────────────────────────────────────────────

func _behaviour_swimmer(delta: float) -> void:
	# Move downstream with a sinusoidal lateral wobble.
	var wobble := sin(_time * wobble_freq * TAU) * wobble_amp
	position.x = _base_x + wobble
	position.y += speed * delta
	# Clamp within the pond width.
	var pr := GameManager.POND_RECT
	position.x = clampf(position.x, pr.position.x + 12.0, pr.end.x - 12.0)
	# Face the direction of travel.
	if _body:
		_body.rotation = 0.0   # facing right is default; rotate toward swim dir


func _behaviour_feeder(delta: float) -> void:
	# Find the closest plant with detritus within detection range.
	var nearest_plant: Node = null
	var nearest_dist := detection_radius

	for plant in get_tree().get_nodes_in_group("plants"):
		if not plant.has_method("has_detritus") or not plant.has_detritus():
			continue
		var d := position.distance_to(plant.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_plant = plant

	if nearest_plant != null:
		# Move toward the plant.
		var dir := (nearest_plant.position - position).normalized()
		position += dir * speed * delta
		_face_direction(dir)
		if nearest_dist < 16.0:
			_start_eating(nearest_plant)
	else:
		# No plant in range — swim downstream as normal.
		_behaviour_swimmer(delta)


func _behaviour_predator(delta: float) -> void:
	# Re-acquire target if missing or dead.
	if not is_instance_valid(_hunt_target):
		_hunt_target = _find_prey()

	if is_instance_valid(_hunt_target):
		var dir := (_hunt_target.position - position).normalized()
		position += dir * speed * 1.2 * delta
		_face_direction(dir)
		if position.distance_to(_hunt_target.position) < 14.0:
			_eat_fish(_hunt_target)
	else:
		# No prey — swim downstream.
		_behaviour_swimmer(delta)


# ── Predator helpers ──────────────────────────────────────────────────────────

func _find_prey() -> Node2D:
	var closest: Node2D  = null
	var closest_dist := detection_radius
	for fish in get_tree().get_nodes_in_group("fish"):
		if fish == self:
			continue
		# Only target fish belonging to the other player.
		if not fish.has_method("setup") or fish.player_id == player_id:
			continue
		var d := position.distance_to(fish.position)
		if d < closest_dist:
			closest_dist = d
			closest = fish
	return closest


func _eat_fish(prey: Node2D) -> void:
	if not is_instance_valid(prey):
		return
	biomass += prey.biomass * 0.5   # absorb half of prey's biomass
	prey.queue_free()
	_hunt_target = null


# ── Feeder helpers ────────────────────────────────────────────────────────────

func _start_eating(plant: Node) -> void:
	if _eating:
		return
	_eating    = true
	_eat_timer = EAT_DURATION
	plant.consume_detritus()
	biomass += 0.5

	# Reward the owning player with a small energy boost.
	if energy_reward > 0.0:
		for p in get_tree().get_nodes_in_group("players"):
			if p.player_id == player_id:
				p.energy = minf(p.energy + energy_reward, p.MAX_ENERGY)
				break


# ── Rotation helper ───────────────────────────────────────────────────────────

func _face_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		rotation = dir.angle()


# ── Exit pond ─────────────────────────────────────────────────────────────────

func _exit_pond() -> void:
	GameManager.score_fish(player_id, biomass)
	queue_free()
