## A gamepad-navigable menu: a titled panel of rows, one highlighted.
##
## Rows are plain dictionaries so a menu is a list, not a scene. Kinds:
##   action  {label, activate: Callable}
##   toggle  {label, get: Callable, set: Callable(bool)}
##   choice  {label, values: Array, get, set(value), format: Callable}
##   slider  {label, min, max, step, get, set(float), format: Callable}
##
## Runs while the tree is paused, which is how the pause menu works at all:
## the round freezes and this keeps taking input.
class_name Menu
extends Control

signal back_requested
signal changed(id: String)

const HINT := "◄ ►  adjust      A / ENTER  select      B / ESC  back"

var title := ""
var rows: Array[Dictionary] = []
var index := 0
var closable := true

var _value_labels: Array[Label] = []
var _row_labels: Array[Label] = []


func _init(menu_title: String, menu_rows: Array[Dictionary], can_close := true) -> void:
	title = menu_title
	rows = menu_rows
	closable = can_close
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.07, 0.94)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 22
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 40)
	column.add_child(heading)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	column.add_child(spacer)

	for row in rows:
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = str(row["label"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 24)
		line.add_child(name_label)
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 24)
		line.add_child(value_label)
		column.add_child(line)
		_row_labels.append(name_label)
		_value_labels.append(value_label)

	var hint := Label.new()
	hint.text = HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(hint)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	var handled := true
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: move(-1)
			JOY_BUTTON_DPAD_DOWN: move(1)
			JOY_BUTTON_DPAD_LEFT: adjust(-1)
			JOY_BUTTON_DPAD_RIGHT: adjust(1)
			JOY_BUTTON_A: activate()
			JOY_BUTTON_B, JOY_BUTTON_START: back()
			_: handled = false
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W: move(-1)
			KEY_DOWN, KEY_S: move(1)
			KEY_LEFT, KEY_A: adjust(-1)
			KEY_RIGHT, KEY_D: adjust(1)
			KEY_ENTER, KEY_SPACE: activate()
			KEY_ESCAPE, KEY_BACKSPACE: back()
			_: handled = false
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func move(step: int) -> void:
	if rows.is_empty():
		return
	index = (index + step + rows.size()) % rows.size()
	Sfx.play("tick", 0.0)
	refresh()


## Changes the highlighted row's value one step. Actions ignore it.
func adjust(step: int) -> void:
	if rows.is_empty():
		return
	var row := rows[index]
	match str(row["kind"]):
		"toggle":
			(row["set"] as Callable).call(not bool((row["get"] as Callable).call()))
		"choice":
			var values: Array = row["values"]
			var current: int = values.find((row["get"] as Callable).call())
			var next: int = (maxi(current, 0) + step + values.size()) % values.size()
			(row["set"] as Callable).call(values[next])
		"slider":
			var value := float((row["get"] as Callable).call()) + float(row["step"]) * step
			value = clampf(value, float(row["min"]), float(row["max"]))
			(row["set"] as Callable).call(value)
		_:
			return
	Sfx.play("vote", 0.0)
	changed.emit(str(row.get("id", "")))
	refresh()


## Fires the highlighted action, or flips a toggle.
func activate() -> void:
	if rows.is_empty():
		return
	var row := rows[index]
	match str(row["kind"]):
		"action":
			Sfx.play("go", 0.0)
			(row["activate"] as Callable).call()
		"toggle":
			adjust(1)
		_:
			adjust(1)


func back() -> void:
	if closable:
		back_requested.emit()


func refresh() -> void:
	for i in rows.size():
		var row := rows[i]
		var selected := i == index
		_row_labels[i].text = ("▶  " if selected else "    ") + str(row["label"])
		var colour := Color(1, 0.85, 0.3) if selected else Color(1, 1, 1, 0.85)
		_row_labels[i].add_theme_color_override("font_color", colour)
		_value_labels[i].add_theme_color_override("font_color", colour)
		_value_labels[i].text = _value_text(row)


func _value_text(row: Dictionary) -> String:
	match str(row["kind"]):
		"toggle":
			return "ON" if bool((row["get"] as Callable).call()) else "OFF"
		"choice", "slider":
			var value: Variant = (row["get"] as Callable).call()
			if row.has("format"):
				return str((row["format"] as Callable).call(value))
			return str(value)
	return ""


func value_of(row_id: String) -> String:
	for row in rows:
		if str(row.get("id", "")) == row_id:
			return _value_text(row)
	return ""


func select(row_id: String) -> bool:
	for i in rows.size():
		if str(rows[i].get("id", "")) == row_id:
			index = i
			refresh()
			return true
	return false
