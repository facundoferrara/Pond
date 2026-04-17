extends Control
class_name ProductivityHud

## Lightweight productivity HUD scaffold for edge modules.
## Keeps placeholders visible during normal mode and updates clock/timer labels.

@onready var clock_value: Label = $ClockPanel/ClockValue
@onready var timer_value: Label = $TimerPanel/TimerValue
@onready var habit_body: Label = $HabitTrackerPanel/Body

@export_group("HUD: Timer Placeholder")
## Default timer shown when no session is running (seconds).
@export var default_timer_seconds: int = 25 * 60
## Writes running timer state every N seconds to avoid disk writes every frame.
@export_range(1, 30, 1) var timer_autosave_interval_seconds: int = 5

var _timer_remaining_seconds: int = 0
var _timer_running: bool = false
var _clock_accum_seconds: float = 0.0
var _habit_refresh_accum_seconds: float = 0.0
var _timer_save_accum_seconds: float = 0.0
var _timer_last_duration_seconds: int = 0


func _ready() -> void:
	set_process(true)
	_timer_remaining_seconds = maxi(default_timer_seconds, 0)
	_timer_last_duration_seconds = _timer_remaining_seconds
	_restore_timer_from_save()
	_update_habit_panel()
	_update_clock_label()
	_update_timer_label()


func _process(delta: float) -> void:
	_clock_accum_seconds += delta
	if _clock_accum_seconds >= 1.0:
		_clock_accum_seconds = 0.0
		_update_clock_label()
		_tick_timer_once()
		_habit_refresh_accum_seconds += 1.0
		if _habit_refresh_accum_seconds >= 5.0:
			_habit_refresh_accum_seconds = 0.0
			_update_habit_panel()

	if _timer_running:
		_timer_save_accum_seconds += delta
		if _timer_save_accum_seconds >= float(maxi(timer_autosave_interval_seconds, 1)):
			_timer_save_accum_seconds = 0.0
			_persist_timer_state()


## Shows or hides all productivity modules (used by screensaver mode).
func set_modules_visible(visible_modules: bool) -> void:
	visible = visible_modules


## Placeholder API for starting a focus timer.
func start_timer(duration_seconds: int) -> void:
	_timer_remaining_seconds = maxi(duration_seconds, 0)
	_timer_running = _timer_remaining_seconds > 0
	_timer_last_duration_seconds = _timer_remaining_seconds
	_timer_save_accum_seconds = 0.0
	_update_timer_label()
	_persist_timer_state()


## Placeholder API for stopping the timer.
func stop_timer() -> void:
	_timer_running = false
	_timer_save_accum_seconds = 0.0
	_update_timer_label()
	_persist_timer_state()


func _tick_timer_once() -> void:
	if not _timer_running:
		return
	if _timer_remaining_seconds <= 0:
		_timer_running = false
		_update_timer_label()
		return
	_timer_remaining_seconds -= 1
	if _timer_remaining_seconds <= 0:
		_timer_remaining_seconds = 0
		_timer_running = false
		_persist_timer_state()
	_update_timer_label()


func _exit_tree() -> void:
	_persist_timer_state()


func _update_clock_label() -> void:
	if clock_value == null:
		return
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var hh: String = str(int(dt.get("hour", 0))).pad_zeros(2)
	var mm: String = str(int(dt.get("minute", 0))).pad_zeros(2)
	var ss: String = str(int(dt.get("second", 0))).pad_zeros(2)
	clock_value.text = "%s:%s:%s" % [hh, mm, ss]


func _update_timer_label() -> void:
	if timer_value == null:
		return
	var total: int = maxi(_timer_remaining_seconds, 0)
	var minutes_total: int = int(floor(float(total) / 60.0))
	var mm: String = str(minutes_total).pad_zeros(2)
	var ss: String = str(total % 60).pad_zeros(2)
	if _timer_running:
		timer_value.text = "%s:%s running" % [mm, ss]
	else:
		timer_value.text = "%s:%s placeholder" % [mm, ss]


func _restore_timer_from_save() -> void:
	if get_node_or_null("/root/SaveService") == null:
		return
	var timer_state: Dictionary = SaveService.get_timer_state()
	_timer_remaining_seconds = maxi(int(timer_state.get("remaining_seconds", default_timer_seconds)), 0)
	_timer_running = bool(timer_state.get("running", false)) and _timer_remaining_seconds > 0
	_timer_last_duration_seconds = maxi(int(timer_state.get("last_duration_seconds", _timer_remaining_seconds)), 0)


func _persist_timer_state() -> void:
	if get_node_or_null("/root/SaveService") == null:
		return
	SaveService.set_timer_state(_timer_remaining_seconds, _timer_running, _timer_last_duration_seconds)


func _update_habit_panel() -> void:
	if habit_body == null:
		return
	if get_node_or_null("/root/HabitTrackerService") == null:
		habit_body.text = "Habit service unavailable"
		return

	var summary: Dictionary = HabitTrackerService.get_summary()
	var total_habits: int = int(summary.get("active_habit_count", 0))
	var done_today: int = int(summary.get("completed_today_count", 0))
	var streak: int = int(summary.get("daily_all_done_streak", 0))

	if total_habits <= 0:
		habit_body.text = "No habits yet\nAdd your first routine soon"
		return

	habit_body.text = "Today: %d/%d complete\nFull-day streak: %d" % [done_today, total_habits, streak]
