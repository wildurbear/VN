extends Control
## Visual novel runtime.
##
## Executes the list of "statements" that make up the current story node.
## Each statement is a small dictionary keyed by its type:
##
##   {"bg": "classroom"}                          change background (crossfade)
##   {"show": "Alice", "at": "left", "mood": "x"} bring a character on stage
##   {"hide": "Ken"}                              remove a character (by name or slot)
##   {"say": "Alice", "text": "Hi", "mood": "x"}  a line of dialogue (waits for input)
##   {"set": {"flag": true}}                      assign variables
##   {"add": {"score": 1}}                        add to a numeric variable
##   {"choice": [ {"text": "...", "goto": "node", "if": "cond", "add": {...}} ]}
##   {"goto": "node", "if": "cond"}               jump (optionally conditional)
##   {"end": true}                                end of route
##
## Statements run top-to-bottom; `say` and `choice` pause for the player.

@onready var background: TextureRect = $Background
@onready var fade: ColorRect = $Fade
@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var name_label: Label = $DialoguePanel/VBox/NameLabel
@onready var dialogue_text: RichTextLabel = $DialoguePanel/VBox/DialogueText
@onready var continue_arrow: Label = $ContinueArrow
@onready var choices_box: VBoxContainer = $Choices
@onready var auto_button: Button = $TopBar/Auto
@onready var skip_button: Button = $TopBar/Skip
@onready var log_button: Button = $TopBar/Log
@onready var save_button: Button = $TopBar/Save
@onready var load_button: Button = $TopBar/Load
@onready var history_panel: PanelContainer = $HistoryPanel
@onready var history_text: RichTextLabel = $HistoryPanel/VBox/Scroll/HistoryText
@onready var history_close: Button = $HistoryPanel/VBox/Header/Close

const SAVE_PATH := "user://savegame.json"
const PORTRAIT_DIR := "res://assets/portraits/"
const BG_DIR := "res://assets/backgrounds/"

const TYPE_SPEED := 45.0
const TYPE_SPEED_SKIP := 1000.0
const AUTO_DELAY := 1.4
const SKIP_DELAY := 0.06

var statements: Array = []
var current_node: String = ""
var index: int = 0

var showing_choices: bool = false
var auto_enabled: bool = false
var skip_enabled: bool = false
var _ended: bool = false
var _busy: bool = false           # true while a background crossfade is in progress
var _line_token: int = 0
var history: Array = []

# Visual state, tracked so we can highlight the active speaker and save/restore.
var current_bg: String = ""
var stage: Dictionary = {}        # slot -> {"name": String, "mood": String}
var slot_nodes: Dictionary = {}   # slot -> TextureRect

func _ready() -> void:
	slot_nodes = {
		"left": $Characters/Left,
		"center": $Characters/Center,
		"right": $Characters/Right,
	}
	_apply_theme()

	dialogue_text.line_shown.connect(_on_line_finished)
	auto_button.toggle_mode = true
	skip_button.toggle_mode = true
	auto_button.toggled.connect(_on_auto_toggled)
	skip_button.toggled.connect(_on_skip_toggled)
	log_button.pressed.connect(_open_history)
	save_button.pressed.connect(save_game)
	load_button.pressed.connect(load_game)
	history_close.pressed.connect(func() -> void: history_panel.visible = false)

	history_panel.visible = false
	choices_box.visible = false
	continue_arrow.visible = false
	choices_box.add_theme_constant_override("separation", 14)

	start_story()

# --- flow ------------------------------------------------------------------

func start_story() -> void:
	DialogueManager.reset_variables()
	history.clear()
	stage.clear()
	_clear_portraits()
	_ended = false
	_set_node(DialogueManager.start_node)
	_process_statements()

func _set_node(node_name: String) -> void:
	current_node = node_name
	statements = DialogueManager.get_node_statements(node_name)
	index = 0

func _process_statements() -> void:
	while index < statements.size():
		var st: Dictionary = statements[index]
		index += 1
		if st.has("bg"):
			_busy = true
			await _change_background(String(st["bg"]))
			_busy = false
		elif st.has("show"):
			_show_character(st)
		elif st.has("hide"):
			_hide_character(String(st["hide"]))
		elif st.has("set"):
			for k in st["set"].keys():
				DialogueManager.set_var(k, st["set"][k])
		elif st.has("add"):
			for k in st["add"].keys():
				DialogueManager.add_var(k, float(st["add"][k]))
		elif st.has("say"):
			_show_say(st)
			return
		elif st.has("choice"):
			_show_choices(st["choice"])
			return
		elif st.has("goto"):
			if st.has("if") and not DialogueManager.check_condition(String(st["if"])):
				continue
			_set_node(String(st["goto"]))
			continue
		elif st.has("end"):
			_show_end()
			return
	_show_end()  # ran off the end of a node with no explicit end

func _on_advance() -> void:
	if showing_choices or history_panel.visible or _busy:
		return
	if dialogue_text.is_typing():
		dialogue_text.skip()
		return
	if _ended:
		start_story()
		return
	continue_arrow.visible = false
	_process_statements()

func _unhandled_input(event: InputEvent) -> void:
	if showing_choices or history_panel.visible:
		return
	var advance := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	elif event.is_action_pressed("ui_accept"):
		advance = true
	if advance:
		_on_advance()

# --- dialogue --------------------------------------------------------------

func _show_say(st: Dictionary) -> void:
	_ended = false
	var speaker := String(st.get("say", ""))
	var line := DialogueManager.interpolate(String(st.get("text", "")))
	if st.has("mood"):
		_set_mood(speaker, String(st["mood"]))
	_highlight_speaker(speaker)
	name_label.text = speaker
	name_label.visible = speaker != ""
	dialogue_panel.visible = true
	continue_arrow.visible = false
	history.append({"name": speaker, "text": line})
	_line_token += 1
	dialogue_text.characters_per_second = TYPE_SPEED_SKIP if skip_enabled else TYPE_SPEED
	dialogue_text.show_line(line)

func _on_line_finished() -> void:
	if showing_choices or _ended:
		return
	continue_arrow.visible = true
	if skip_enabled or auto_enabled:
		var token := _line_token
		await get_tree().create_timer(SKIP_DELAY if skip_enabled else AUTO_DELAY).timeout
		if token == _line_token and not showing_choices and (skip_enabled or auto_enabled):
			_on_advance()

func _show_end() -> void:
	_ended = true
	showing_choices = false
	name_label.visible = false
	dialogue_panel.visible = true
	continue_arrow.visible = false
	dialogue_text.characters_per_second = TYPE_SPEED_SKIP
	dialogue_text.show_line("[center][i]The End[/i]\n\nClick to start over.[/center]")

# --- choices ---------------------------------------------------------------

func _show_choices(options: Array) -> void:
	showing_choices = true
	_ended = false
	continue_arrow.visible = false
	for c in choices_box.get_children():
		c.queue_free()
	for opt in options:
		if opt.has("if") and not DialogueManager.check_condition(String(opt["if"])):
			continue
		var b := Button.new()
		b.text = DialogueManager.interpolate(String(opt.get("text", "")))
		b.custom_minimum_size = Vector2(560, 58)
		b.focus_mode = Control.FOCUS_NONE
		_style_choice(b)
		b.pressed.connect(_on_choice_selected.bind(opt))
		choices_box.add_child(b)
	choices_box.visible = true

func _on_choice_selected(opt: Dictionary) -> void:
	choices_box.visible = false
	showing_choices = false
	history.append({"name": "", "text": "→ " + DialogueManager.interpolate(String(opt.get("text", "")))})
	if opt.has("set"):
		for k in opt["set"].keys():
			DialogueManager.set_var(k, opt["set"][k])
	if opt.has("add"):
		for k in opt["add"].keys():
			DialogueManager.add_var(k, float(opt["add"][k]))
	_set_node(String(opt.get("goto", current_node)))
	_process_statements()

# --- backgrounds & characters ----------------------------------------------

func _change_background(bg_name: String) -> void:
	current_bg = bg_name
	var tex := _load_tex(BG_DIR + bg_name + ".svg")
	var t1 := create_tween()
	t1.tween_property(fade, "color:a", 1.0, 0.25)
	await t1.finished
	background.texture = tex
	var t2 := create_tween()
	t2.tween_property(fade, "color:a", 0.0, 0.25)
	await t2.finished

func _show_character(st: Dictionary) -> void:
	var char_name := String(st["show"])
	var slot := String(st.get("at", "center"))
	var mood := String(st.get("mood", "neutral"))
	if not slot_nodes.has(slot):
		slot = "center"
	stage[slot] = {"name": char_name, "mood": mood}
	var node: TextureRect = slot_nodes[slot]
	node.texture = _portrait_tex(char_name, mood)
	node.visible = node.texture != null
	node.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, 0.25)

func _hide_character(slot_or_name: String) -> void:
	for slot in slot_nodes.keys():
		var match_slot: bool = slot == slot_or_name
		var match_name: bool = stage.has(slot) and stage[slot]["name"] == slot_or_name
		if match_slot or match_name:
			var node: TextureRect = slot_nodes[slot]
			var tw := create_tween()
			tw.tween_property(node, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func() -> void: node.visible = false)
			stage.erase(slot)

func _set_mood(char_name: String, mood: String) -> void:
	for slot in stage.keys():
		if stage[slot]["name"] == char_name:
			stage[slot]["mood"] = mood
			slot_nodes[slot].texture = _portrait_tex(char_name, mood)

func _highlight_speaker(speaker: String) -> void:
	for slot in slot_nodes.keys():
		var node: TextureRect = slot_nodes[slot]
		if not node.visible:
			continue
		var is_speaker: bool = stage.has(slot) and stage[slot]["name"] == speaker
		var c := Color(1, 1, 1, 1) if (speaker == "" or is_speaker) else Color(0.5, 0.5, 0.58, 1)
		var tw := create_tween()
		tw.tween_property(node, "modulate", c, 0.2)

func _clear_portraits() -> void:
	for slot in slot_nodes.keys():
		slot_nodes[slot].texture = null
		slot_nodes[slot].visible = false

func _portrait_tex(char_name: String, mood: String) -> Texture2D:
	var base := char_name.to_lower().strip_edges().replace(" ", "_")
	var tex := _load_tex(PORTRAIT_DIR + "%s_%s.svg" % [base, mood])
	if tex == null:
		tex = _load_tex(PORTRAIT_DIR + "%s_neutral.svg" % base)
	return tex

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

# --- history / auto / skip -------------------------------------------------

func _open_history() -> void:
	var s := ""
	for h in history:
		if String(h["name"]) != "":
			s += "[b]%s[/b]  %s\n\n" % [h["name"], h["text"]]
		else:
			s += "%s\n\n" % h["text"]
	history_text.text = s
	history_panel.visible = true

func _on_auto_toggled(pressed: bool) -> void:
	auto_enabled = pressed
	if pressed:
		skip_button.button_pressed = false
		if not dialogue_text.is_typing() and not showing_choices and not _ended:
			_on_line_finished()

func _on_skip_toggled(pressed: bool) -> void:
	skip_enabled = pressed
	if pressed:
		auto_button.button_pressed = false
		if dialogue_text.is_typing():
			dialogue_text.skip()
		elif not showing_choices and not _ended:
			_on_advance()

# --- save / load -----------------------------------------------------------

func save_game() -> void:
	var data := {
		"node": current_node,
		"index": index,
		"vars": DialogueManager.variables,
		"bg": current_bg,
		"stage": stage,
		"name": name_label.text,
		"text": dialogue_text.text,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		_flash(save_button, "Saved")

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_flash(load_button, "No save")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return

	DialogueManager.variables = data.get("vars", {})
	current_node = String(data.get("node", ""))
	statements = DialogueManager.get_node_statements(current_node)
	index = int(data.get("index", 0))

	current_bg = String(data.get("bg", ""))
	background.texture = _load_tex(BG_DIR + current_bg + ".svg") if current_bg != "" else null
	fade.color.a = 0.0

	_clear_portraits()
	stage = {}
	var saved_stage: Dictionary = data.get("stage", {})
	for slot in saved_stage.keys():
		var info: Dictionary = saved_stage[slot]
		stage[slot] = info
		var node: TextureRect = slot_nodes[slot]
		node.texture = _portrait_tex(String(info["name"]), String(info.get("mood", "neutral")))
		node.visible = node.texture != null
		node.modulate = Color(1, 1, 1, 1)

	showing_choices = false
	choices_box.visible = false
	for c in choices_box.get_children():
		c.queue_free()
	_ended = false

	name_label.text = String(data.get("name", ""))
	name_label.visible = name_label.text != ""
	dialogue_panel.visible = true
	dialogue_text.characters_per_second = TYPE_SPEED_SKIP
	dialogue_text.show_line(String(data.get("text", "")))
	_highlight_speaker(name_label.text)
	_flash(load_button, "Loaded")

func _flash(btn: Button, msg: String) -> void:
	var original := btn.text
	btn.text = msg
	await get_tree().create_timer(0.8).timeout
	btn.text = original

# --- styling (done in code to keep the .tscn lightweight) ------------------

func _apply_theme() -> void:
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.06, 0.07, 0.12, 0.88)
	panel_sb.set_corner_radius_all(14)
	panel_sb.set_content_margin_all(24)
	panel_sb.set_border_width_all(2)
	panel_sb.border_color = Color(0.5, 0.6, 0.95, 0.5)
	dialogue_panel.add_theme_stylebox_override("panel", panel_sb)

	dialogue_text.add_theme_font_size_override("normal_font_size", 24)
	dialogue_text.add_theme_font_size_override("italics_font_size", 24)
	dialogue_text.add_theme_font_size_override("bold_font_size", 24)
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0))
	continue_arrow.add_theme_font_size_override("font_size", 22)
	continue_arrow.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))

	var hist_sb := StyleBoxFlat.new()
	hist_sb.bg_color = Color(0.04, 0.05, 0.09, 0.97)
	hist_sb.set_corner_radius_all(12)
	hist_sb.set_content_margin_all(18)
	hist_sb.set_border_width_all(2)
	hist_sb.border_color = Color(0.4, 0.5, 0.8, 0.6)
	history_panel.add_theme_stylebox_override("panel", hist_sb)
	history_text.add_theme_font_size_override("normal_font_size", 20)

func _style_choice(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.12, 0.2, 0.92)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(12)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.4, 0.5, 0.8, 0.6)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.2, 0.26, 0.42, 0.96)
	hover.border_color = Color(0.7, 0.8, 1.0, 0.9)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
