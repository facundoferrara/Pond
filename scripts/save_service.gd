extends Node

## Shared persistence service for productivity modules.
## Stores JSON in user:// so progress survives app restarts.

const SAVE_PATH: String = "user://pond_save.json"
const SCHEMA_VERSION: int = 1

signal save_loaded(data: Dictionary)
signal save_persisted(path: String)

var _save_data: Dictionary = {}


func _ready() -> void:
	_load_or_create()


## Returns a deep copy of the current save payload.
func get_all_data() -> Dictionary:
	return _save_data.duplicate(true)


## Gets a named section (timer/habits/shop/music/settings).
func get_section(section_name: StringName) -> Dictionary:
	var key: String = str(section_name)
	if not _save_data.has(key):
		return {}
	var section: Variant = _save_data[key]
	if section is Dictionary:
		return (section as Dictionary).duplicate(true)
	return {}


## Replaces a section and optionally writes to disk immediately.
func set_section(section_name: StringName, section_data: Dictionary, autosave: bool = true) -> void:
	_save_data[str(section_name)] = section_data.duplicate(true)
	if autosave:
		save_now()


## Timer helpers keep one canonical shape for timer persistence.
func get_timer_state() -> Dictionary:
	var timer_state: Dictionary = get_section(&"timer")
	if timer_state.is_empty():
		timer_state = _default_timer_state()
	return timer_state


func set_timer_state(remaining_seconds: int, running: bool, last_duration_seconds: int) -> void:
	set_section(&"timer", {
		"remaining_seconds": maxi(remaining_seconds, 0),
		"running": running and remaining_seconds > 0,
		"last_duration_seconds": maxi(last_duration_seconds, 0)
	}, true)


## Writes save payload to disk.
func save_now() -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveService: Failed to open %s for writing." % SAVE_PATH)
		return false

	_save_data["schema_version"] = SCHEMA_VERSION
	_save_data["updated_unix"] = Time.get_unix_time_from_system()
	file.store_string(JSON.stringify(_save_data, "\t"))
	file.close()
	save_persisted.emit(SAVE_PATH)
	return true


func _load_or_create() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_save_data = _default_save_data()
		save_now()
		save_loaded.emit(get_all_data())
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveService: Failed to open %s for reading. Using defaults." % SAVE_PATH)
		_save_data = _default_save_data()
		save_loaded.emit(get_all_data())
		return

	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_warning("SaveService: Save file is invalid JSON. Rebuilding defaults.")
		_save_data = _default_save_data()
		save_now()
		save_loaded.emit(get_all_data())
		return

	_save_data = (parsed as Dictionary).duplicate(true)
	_apply_missing_defaults()
	save_loaded.emit(get_all_data())


func _apply_missing_defaults() -> void:
	var defaults: Dictionary = _default_save_data()
	for key: Variant in defaults.keys():
		if not _save_data.has(key):
			_save_data[key] = defaults[key]

	if not (_save_data.get("timer", {}) is Dictionary):
		_save_data["timer"] = _default_timer_state()
	else:
		var timer_state: Dictionary = _save_data["timer"] as Dictionary
		if not timer_state.has("remaining_seconds"):
			timer_state["remaining_seconds"] = 25 * 60
		if not timer_state.has("running"):
			timer_state["running"] = false
		if not timer_state.has("last_duration_seconds"):
			timer_state["last_duration_seconds"] = 25 * 60
		_save_data["timer"] = timer_state


func _default_timer_state() -> Dictionary:
	return {
		"remaining_seconds": 25 * 60,
		"running": false,
		"last_duration_seconds": 25 * 60
	}


func _default_save_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"created_unix": Time.get_unix_time_from_system(),
		"updated_unix": Time.get_unix_time_from_system(),
		"timer": _default_timer_state(),
		"habits": {
			"items": [],
			"completions_by_day": {}
		},
		"shop": {
			"currency": 0,
			"owned_cosmetics": []
		},
		"music": {
			"volume": 0.6,
			"last_track": ""
		},
		"settings": {
			"notifications_enabled": true
		}
	}