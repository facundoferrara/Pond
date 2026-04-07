# PauseMenu.gd
# Pause overlay with Resume / Restart / Quit.
# process_mode is set to PROCESS_MODE_ALWAYS so buttons respond while paused.
extends CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	GameManager.connect("pause_changed", _on_pause_changed)


func _on_pause_changed(is_paused: bool) -> void:
	visible = is_paused


func _build_ui() -> void:
	# Semi-transparent full-screen backdrop.
	var backdrop := ColorRect.new()
	backdrop.color               = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter        = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Centred panel.
	var panel := PanelContainer.new()
	panel.size     = Vector2(300, 220)
	panel.position = Vector2(490, 250)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text                 = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# ── Buttons ───────────────────────────────────────────────────────────────
	var resume_btn := _make_button("Resume")
	resume_btn.connect("pressed", GameManager.toggle_pause)
	vbox.add_child(resume_btn)

	var restart_btn := _make_button("Restart")
	restart_btn.connect("pressed", GameManager.restart)
	vbox.add_child(restart_btn)

	var quit_btn := _make_button("Quit")
	quit_btn.connect("pressed", get_tree().quit.bind())
	vbox.add_child(quit_btn)


func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                 = label_text
	btn.custom_minimum_size  = Vector2(220, 40)
	return btn
