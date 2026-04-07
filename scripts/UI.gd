# UI.gd
# Builds and manages the in-game HUD at runtime.
# Displays: victory meter, per-player energy bars, selected species label.
extends CanvasLayer

# ── Widget references (set in _build_ui) ─────────────────────────────────────
var _victory_bar:      ProgressBar = null
var _p1_energy_bar:    ProgressBar = null
var _p2_energy_bar:    ProgressBar = null
var _p1_species_label: Label       = null
var _p2_species_label: Label       = null
var _winner_label:     Label       = null


func _ready() -> void:
	# HUD must stay visible even while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameManager.connect("victory_changed", _on_victory_changed)
	GameManager.connect("game_over",       _on_game_over)


# ── Public API (called by Player nodes via signal) ────────────────────────────

func update_energy(pid: int, value: float) -> void:
	if pid == 1 and _p1_energy_bar:
		_p1_energy_bar.value = value
	elif pid == 2 and _p2_energy_bar:
		_p2_energy_bar.value = value


func update_species(pid: int, species_index: int) -> void:
	var d        := FishData.get_species(species_index)
	var sp_name  : String = d.get("name",        "?")
	var cost     : int    = d.get("energy_cost",   0)
	var txt      := "◄ %s (%d E) ►" % [sp_name, cost]
	if pid == 1 and _p1_species_label:
		_p1_species_label.text = txt
	elif pid == 2 and _p2_species_label:
		_p2_species_label.text = txt


# ── Signal callbacks ──────────────────────────────────────────────────────────

func _on_victory_changed(value: float) -> void:
	if _victory_bar:
		_victory_bar.value = value


func _on_game_over(winner_id: int) -> void:
	if _winner_label:
		_winner_label.text    = "Player %d Wins!\nPress Start to restart" % winner_id
		_winner_label.visible = true


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Victory meter (centre-top) ────────────────────────────────────────────
	var vic_container := VBoxContainer.new()
	vic_container.position = Vector2(440, 6)
	vic_container.size     = Vector2(400, 54)
	root.add_child(vic_container)

	var vic_title := Label.new()
	vic_title.text                   = "← P1   VICTORY METER   P2 →"
	vic_title.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	vic_title.add_theme_font_size_override("font_size", 13)
	vic_container.add_child(vic_title)

	_victory_bar              = ProgressBar.new()
	_victory_bar.min_value    = 0.0
	_victory_bar.max_value    = 100.0
	_victory_bar.value        = 50.0
	_victory_bar.show_percentage = false
	_victory_bar.custom_minimum_size = Vector2(400, 26)
	vic_container.add_child(_victory_bar)

	# ── Player 1 panel (left) ─────────────────────────────────────────────────
	var p1_panel := _make_player_panel(1)
	p1_panel.position = Vector2(8, 8)
	root.add_child(p1_panel)

	# ── Player 2 panel (right) ────────────────────────────────────────────────
	var p2_panel := _make_player_panel(2)
	p2_panel.position = Vector2(1072, 8)
	root.add_child(p2_panel)

	# ── Winner label (hidden until game over) ─────────────────────────────────
	_winner_label                        = Label.new()
	_winner_label.visible                = false
	_winner_label.position               = Vector2(390, 290)
	_winner_label.size                   = Vector2(500, 100)
	_winner_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	_winner_label.add_theme_font_size_override("font_size", 36)
	root.add_child(_winner_label)


func _make_player_panel(pid: int) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(190, 0)

	var title := Label.new()
	title.text = "Player %d" % pid
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)

	var e_bar := ProgressBar.new()
	e_bar.min_value          = 0.0
	e_bar.max_value          = 100.0
	e_bar.value              = 100.0
	e_bar.custom_minimum_size = Vector2(190, 18)
	e_bar.show_percentage    = false
	panel.add_child(e_bar)

	var sp_label := Label.new()
	sp_label.text = "◄ Guppy (10 E) ►"
	sp_label.add_theme_font_size_override("font_size", 13)
	panel.add_child(sp_label)

	if pid == 1:
		_p1_energy_bar    = e_bar
		_p1_species_label = sp_label
	else:
		_p2_energy_bar    = e_bar
		_p2_species_label = sp_label

	return panel
