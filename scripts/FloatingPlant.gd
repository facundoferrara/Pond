# FloatingPlant.gd
# A lily-pad that slowly accumulates detritus.
# Feeder fish detect it via the "plants" group and call consume_detritus().
extends Node2D

const MAX_DETRITUS    := 5.0
const DETRITUS_RATE   := 0.25   ## units per second
const BASE_COLOR      := Color(0.18, 0.48, 0.12)
const RICH_COLOR      := Color(0.35, 0.52, 0.15)

var detritus_amount: float = 0.0

var _body: Polygon2D = null


func _ready() -> void:
	add_to_group("plants")
	_build_visuals()


func _build_visuals() -> void:
	_body = Polygon2D.new()
	var pts := PackedVector2Array()
	var segs := 12
	for i in range(segs):
		var angle := (float(i) / segs) * TAU
		# Slightly irregular radius for a natural look.
		var r := 20.0 + sin(angle * 3.0) * 3.5
		pts.append(Vector2(cos(angle) * r, sin(angle) * r * 0.55))
	_body.polygon = pts
	_body.color   = BASE_COLOR
	add_child(_body)


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	detritus_amount = minf(detritus_amount + DETRITUS_RATE * delta, MAX_DETRITUS)
	# Tint the pad brighter as it fills with detritus.
	if _body:
		var t := detritus_amount / MAX_DETRITUS
		_body.color = BASE_COLOR.lerp(RICH_COLOR, t)


## Returns true if the plant has enough detritus to attract feeders.
func has_detritus() -> bool:
	return detritus_amount >= 0.5


## Called by a feeder fish; reduces available detritus.
func consume_detritus() -> void:
	detritus_amount = maxf(detritus_amount - 1.0, 0.0)
