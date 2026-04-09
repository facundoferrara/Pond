extends Fish
class_name Detritus

const _DETRITUS_COLOR: Color = Color(0.45, 0.30, 0.14, 1.0)

@export var detritus_z_index: int = -100
@export_range(0.0, 1.0, 0.01) var base_visibility_alpha: float = 0.5
@export_range(0.0, 1.0, 0.01) var opacity_per_additional_point: float = 0.05
@export_range(1, 100) var max_visible_point_value: int = 11

var detritus_value: int = 1


func _ready() -> void:
	super._ready()


func reinitialize() -> void:
	super.reinitialize()
	velocity = Vector2.ZERO
	set_detritus_value(detritus_value)


func set_detritus_value(value_units: int) -> void:
	var clamped_value: int = maxi(value_units, 0)
	detritus_value = clamped_value
	z_index = detritus_z_index
	var alpha: float = 0.0
	if clamped_value > 0:
		var visible_points: int = mini(clamped_value, maxi(max_visible_point_value, 1))
		alpha = base_visibility_alpha + float(maxi(visible_points - 1, 0)) * opacity_per_additional_point
	alpha = clampf(alpha, 0.0, 1.0)
	color = Color(_DETRITUS_COLOR.r, _DETRITUS_COLOR.g, _DETRITUS_COLOR.b, alpha)
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
