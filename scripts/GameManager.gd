# GameManager.gd
# Autoload singleton — owns global game state: victory meter, pause, win/lose.
# Access from any script as:  GameManager.score_fish(...)  etc.
extends Node

## Emitted every time the victory meter value changes.
signal victory_changed(value: float)

## Emitted when a player wins.  winner_id is 1 or 2.
signal game_over(winner_id: int)

## Emitted when the pause state changes.
signal pause_changed(is_paused: bool)

# ── Victory meter ────────────────────────────────────────────────────────────
## Meter range: 0 = Player 1 wins, 100 = Player 2 wins, starts at 50.
const VICTORY_MIN := 0.0
const VICTORY_MAX := 100.0

## Pond boundaries used by fish and spawn system (pixels in viewport space).
const POND_RECT := Rect2(64.0, 64.0, 1152.0, 592.0)

var victory_meter: float = 50.0
var game_active: bool = false


func _ready() -> void:
	# Keep this node alive and responsive even while the tree is paused
	# so pause/resume and game-over restart always work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_active = true


# ── Public API ───────────────────────────────────────────────────────────────

## Call when a fish exits the pond at the bottom.
## player_id: 1 or 2.  biomass: final fish biomass.
func score_fish(player_id: int, biomass: float) -> void:
	if not game_active:
		return
	# Scale factor — tweak to taste.
	var delta := biomass * 1.5
	if player_id == 1:
		victory_meter -= delta   # P1 fish push meter LEFT (toward 0)
	else:
		victory_meter += delta   # P2 fish push meter RIGHT (toward 100)
	victory_meter = clampf(victory_meter, VICTORY_MIN, VICTORY_MAX)
	emit_signal("victory_changed", victory_meter)
	_check_win()


## Toggle game pause state.
func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	emit_signal("pause_changed", get_tree().paused)


## Reload the current scene to restart the match.
func restart() -> void:
	get_tree().paused = false
	victory_meter = 50.0
	game_active = true
	get_tree().reload_current_scene()


# ── Input: handles pause & game-over restart globally ───────────────────────
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_pause") or event.is_action_pressed("p2_pause"):
		if not game_active:
			# Game is over — any Start press restarts.
			restart()
		else:
			toggle_pause()


# ── Internal ─────────────────────────────────────────────────────────────────
func _check_win() -> void:
	if victory_meter <= VICTORY_MIN:
		_end_game(1)
	elif victory_meter >= VICTORY_MAX:
		_end_game(2)


func _end_game(winner_id: int) -> void:
	game_active = false
	emit_signal("game_over", winner_id)
