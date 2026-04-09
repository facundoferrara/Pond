extends Fish
class_name Debris

const _DEBRIS_COLOR: Color = Color(0.45, 0.30, 0.14, 1.0)

@export var debris_z_index: int = -100
@export var opacity_per_point: float = 0.05


func _ready() -> void:
	species = SpeciesDB.DEBRIS
	super._ready()


func reinitialize() -> void:
	super.reinitialize()
	velocity = Vector2.ZERO
	set_value_points(int(round(points)))


func set_value_points(value_points: int) -> void:
	var clamped_value: int = maxi(value_points, 0)
	base_points = float(clamped_value)
	points = float(clamped_value)
	z_index = debris_z_index
	var alpha: float = clampf(float(clamped_value) * opacity_per_point, 0.0, 1.0)
	color = Color(_DEBRIS_COLOR.r, _DEBRIS_COLOR.g, _DEBRIS_COLOR.b, alpha)
	_refresh_visual()
	_refresh_scale()


func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null


func _update_behavior_state() -> void:
	behavior_state = BehaviorState.SCHOOL


func _compute_acceleration(_delta: float) -> Vector2:
	return Vector2.ZERO


func _process_feeding(_delta: float) -> void:
	return


func _refresh_scale() -> void:
	if not _ensure_sprite():
		return
	sprite.scale = Vector2.ONE
