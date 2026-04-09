extends Fish
class_name Detritus

## Static consumable remains that sabalos convert into energy and points.

const _DETRITUS_COLOR: Color = Color(0.45, 0.30, 0.14, 1.0)

@export_group("Detritus: Rendering")
## Draw order used to keep detritus below fish and pellets.
@export var detritus_z_index: int = -100
## Base alpha used when detritus value is one unit.
@export_range(0.0, 1.0, 0.01) var base_visibility_alpha: float = 0.05
## Added alpha per extra detritus unit up to cap.
@export_range(0.0, 1.0, 0.01) var opacity_per_additional_point: float = 0.05
## Unit count where alpha reaches its visibility cap.
@export_range(1, 100) var max_visible_point_value: int = 11

## Current consumable value units for sabalo feeding.
var detritus_value: int = 1


## Keeps base lifecycle initialization for pooled entity setup.
func _ready() -> void:
	super._ready()


## Resets static movement and reapplies visibility from current value.
func reinitialize() -> void:
	super.reinitialize()
	velocity = Vector2.ZERO
	set_detritus_value(detritus_value)


## Updates detritus value plus alpha/z-index visualization state.
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


## Detritus has no context queries.
func _update_context() -> void:
	boid_neighbors.clear()
	nearest_predator = null


## Detritus remains in passive SCHOOL state.
func _update_behavior_state() -> void:
	behavior_state = BehaviorState.SCHOOL


## Detritus is static and applies no acceleration.
func _compute_acceleration(_delta: float) -> Vector2:
	return Vector2.ZERO


func _process_feeding(_delta: float) -> void:
	return


func _refresh_scale() -> void:
	return
