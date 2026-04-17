extends Node

## Habit tracker domain service backed by SaveService.
## Keeps CRUD + completion/streak logic centralized for UI modules.

signal habits_changed(summary: Dictionary)


func _ready() -> void:
	_bootstrap_habits_payload()


func get_habits() -> Array[Dictionary]:
	var habits: Dictionary = SaveService.get_section(&"habits")
	var raw_items: Array = habits.get("items", []) as Array
	var items: Array[Dictionary] = []
	for entry: Variant in raw_items:
		if entry is Dictionary:
			items.append((entry as Dictionary).duplicate(true))
	return items


func add_habit(title: String) -> StringName:
	var clean_title: String = title.strip_edges()
	if clean_title.is_empty():
		return StringName("")

	var habit_id: String = "habit_%d" % int(Time.get_unix_time_from_system())
	var habits: Dictionary = SaveService.get_section(&"habits")
	var items: Array = habits.get("items", []) as Array
	items.append({
		"id": habit_id,
		"title": clean_title,
		"created_unix": Time.get_unix_time_from_system(),
		"active": true
	})
	habits["items"] = items
	SaveService.set_section(&"habits", habits, true)
	habits_changed.emit(get_summary())
	return StringName(habit_id)


func complete_habit_today(habit_id: StringName) -> bool:
	var id_text: String = str(habit_id)
	if id_text.is_empty():
		return false

	var habits: Dictionary = SaveService.get_section(&"habits")
	var completions_by_day: Dictionary = habits.get("completions_by_day", {}) as Dictionary
	var day_key: String = _today_key()
	var completed_today: Array = completions_by_day.get(day_key, []) as Array
	if completed_today.has(id_text):
		return false

	completed_today.append(id_text)
	completions_by_day[day_key] = completed_today
	habits["completions_by_day"] = completions_by_day
	SaveService.set_section(&"habits", habits, true)
	habits_changed.emit(get_summary())
	return true


func get_summary() -> Dictionary:
	var habits: Dictionary = SaveService.get_section(&"habits")
	var items: Array = habits.get("items", []) as Array
	var active_habit_ids: Array[String] = []
	for entry: Variant in items:
		if not (entry is Dictionary):
			continue
		var habit_entry: Dictionary = entry as Dictionary
		if bool(habit_entry.get("active", true)):
			active_habit_ids.append(str(habit_entry.get("id", "")))

	var completions_by_day: Dictionary = habits.get("completions_by_day", {}) as Dictionary
	var today_key: String = _today_key()
	var completed_today_raw: Array = completions_by_day.get(today_key, []) as Array
	var completed_today: int = 0
	for habit_id: String in active_habit_ids:
		if completed_today_raw.has(habit_id):
			completed_today += 1

	return {
		"active_habit_count": active_habit_ids.size(),
		"completed_today_count": completed_today,
		"daily_all_done_streak": _compute_daily_all_done_streak(active_habit_ids, completions_by_day)
	}


func _bootstrap_habits_payload() -> void:
	var habits: Dictionary = SaveService.get_section(&"habits")
	if habits.is_empty():
		habits = {
			"items": [],
			"completions_by_day": {}
		}
		SaveService.set_section(&"habits", habits, true)
		return

	if not habits.has("items"):
		habits["items"] = []
	if not habits.has("completions_by_day"):
		habits["completions_by_day"] = {}
	SaveService.set_section(&"habits", habits, false)


func _compute_daily_all_done_streak(active_habit_ids: Array[String], completions_by_day: Dictionary) -> int:
	if active_habit_ids.is_empty():
		return 0

	var now_unix: int = int(Time.get_unix_time_from_system())
	var day_seconds: int = 86400
	var streak: int = 0

	# Walk backward in full-day steps while all active habits are completed for the day.
	for day_offset: int in range(0, 365):
		var day_unix: int = now_unix - (day_offset * day_seconds)
		var day_key: String = _date_key_from_unix(day_unix)
		var completed_ids: Array = completions_by_day.get(day_key, []) as Array
		var all_done: bool = true
		for habit_id: String in active_habit_ids:
			if not completed_ids.has(habit_id):
				all_done = false
				break
		if not all_done:
			break
		streak += 1

	return streak


func _today_key() -> String:
	return _date_key_from_unix(int(Time.get_unix_time_from_system()))


func _date_key_from_unix(unix_time: int) -> String:
	var date: Dictionary = Time.get_date_dict_from_unix_time(unix_time)
	var year_text: String = str(int(date.get("year", 1970))).pad_zeros(4)
	var month_text: String = str(int(date.get("month", 1))).pad_zeros(2)
	var day_text: String = str(int(date.get("day", 1))).pad_zeros(2)
	return "%s-%s-%s" % [year_text, month_text, day_text]