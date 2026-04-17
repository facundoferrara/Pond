extends Node2D

@onready var zoo: Node2D = $Zoo

@export_group("Screensaver")
## Idle time before entering screensaver fullscreen mode (seconds).
@export var screensaver_idle_seconds: float = 30.0
## Default max FPS during active mode.
@export var active_max_fps: int = 60
## Reduced max FPS while screensaver is active.
@export var screensaver_max_fps: int = 30

var _idle_elapsed_seconds: float = 0.0
var _screensaver_active: bool = false
var _restore_pending: bool = false
var _window_mode_before_screensaver: int = DisplayServer.WINDOW_MODE_WINDOWED


func _ready() -> void:
	set_process(true)
	set_process_input(true)
	Engine.max_fps = maxi(active_max_fps, 0)


func _process(delta: float) -> void:
	_idle_elapsed_seconds += delta
	if not _screensaver_active and _idle_elapsed_seconds >= maxf(screensaver_idle_seconds, 1.0):
		_enter_screensaver_mode()


func _input(event: InputEvent) -> void:
	var is_keyboard_press: bool = event is InputEventKey and (event as InputEventKey).pressed
	var is_mouse_button_press: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	var is_mouse_motion: bool = event is InputEventMouseMotion
	if not (is_keyboard_press or is_mouse_button_press or is_mouse_motion):
		return

	_idle_elapsed_seconds = 0.0

	if _restore_pending:
		if is_keyboard_press and (event as InputEventKey).keycode == KEY_SPACE:
			_restore_from_minimized()
			get_viewport().set_input_as_handled()
		return

	if _screensaver_active and is_mouse_motion:
		_minimize_after_screensaver_activity()
		get_viewport().set_input_as_handled()


func _enter_screensaver_mode() -> void:
	_screensaver_active = true
	_restore_pending = false
	_window_mode_before_screensaver = DisplayServer.window_get_mode()
	if _window_mode_before_screensaver == DisplayServer.WINDOW_MODE_MINIMIZED:
		_window_mode_before_screensaver = DisplayServer.WINDOW_MODE_WINDOWED

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	Engine.max_fps = maxi(screensaver_max_fps, 0)
	_set_productivity_ui_visible(false)


func _minimize_after_screensaver_activity() -> void:
	if not _screensaver_active:
		return
	_restore_pending = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _restore_from_minimized() -> void:
	_restore_pending = false
	_screensaver_active = false
	DisplayServer.window_set_mode(_window_mode_before_screensaver)
	Engine.max_fps = maxi(active_max_fps, 0)
	_set_productivity_ui_visible(true)


func _set_productivity_ui_visible(should_show: bool) -> void:
	if zoo != null and zoo.has_method("set_productivity_ui_visible"):
		zoo.call("set_productivity_ui_visible", should_show)
