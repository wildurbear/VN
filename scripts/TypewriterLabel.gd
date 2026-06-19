extends RichTextLabel
## A RichTextLabel that reveals its (BBCode) text one character at a time.
## Call show_line() to start; listen to `finished`; skip() reveals it instantly.

signal line_shown

@export var characters_per_second: float = 45.0

var _typing: bool = false
var _accum: float = 0.0

func _ready() -> void:
	bbcode_enabled = true
	visible_characters = 0

func show_line(content: String) -> void:
	text = content
	visible_characters = 0
	_accum = 0.0
	_typing = get_total_character_count() > 0
	if not _typing:
		line_shown.emit()

func _process(delta: float) -> void:
	if not _typing:
		return
	_accum += delta * characters_per_second
	var total := get_total_character_count()
	if _accum >= 1.0:
		visible_characters = mini(total, visible_characters + int(_accum))
		_accum -= int(_accum)
	if visible_characters >= total:
		visible_characters = -1  # -1 shows everything
		_typing = false
		line_shown.emit()

func is_typing() -> bool:
	return _typing

func skip() -> void:
	if _typing:
		visible_characters = -1
		_typing = false
		line_shown.emit()
