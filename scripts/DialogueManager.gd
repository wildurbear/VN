extends Node
## Autoload singleton. Loads the story script (JSON) and owns global state
## (story variables / flags). The runtime in VisualNovel.gd asks this node for
## node statements, evaluates conditions, and reads/writes variables.

const STORY_PATH := "res://dialogue/story.json"

var story: Dictionary = {}
var start_node: String = "start"
var variables: Dictionary = {}

func _ready() -> void:
	load_story(STORY_PATH)

func load_story(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("VN: could not open story file: %s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("VN: story file is not a valid JSON object")
		return
	story = data
	start_node = String(story.get("start", "start"))
	reset_variables()

func reset_variables() -> void:
	variables = {}
	var defaults: Dictionary = story.get("variables", {})
	for k in defaults.keys():
		variables[k] = defaults[k]

func get_node_statements(node_name: String) -> Array:
	var nodes: Dictionary = story.get("nodes", {})
	if not nodes.has(node_name):
		push_error("VN: missing story node '%s'" % node_name)
		return []
	return nodes[node_name]

# --- variables -------------------------------------------------------------

func get_var(var_name: String) -> Variant:
	return variables.get(var_name, 0)

func set_var(var_name: String, value: Variant) -> void:
	variables[var_name] = value

func add_var(var_name: String, amount: float) -> void:
	variables[var_name] = float(variables.get(var_name, 0)) + amount

## Replaces {var} tokens inside a line with the variable's current value.
func interpolate(text: String) -> String:
	var result := text
	for key in variables.keys():
		result = result.replace("{%s}" % key, str(variables[key]))
	return result

# --- condition evaluation --------------------------------------------------
# Supports: "flag", "!flag", "score >= 3", 'name == "Alice"', etc.

func check_condition(expr: String) -> bool:
	expr = expr.strip_edges()
	if expr == "":
		return true
	if expr.begins_with("!"):
		return not check_condition(expr.substr(1))
	for op in ["==", "!=", ">=", "<=", ">", "<"]:
		var idx := expr.find(op)
		if idx != -1:
			var lhs: Variant = _value(expr.substr(0, idx).strip_edges())
			var rhs: Variant = _value(expr.substr(idx + op.length()).strip_edges())
			return _compare(lhs, rhs, op)
	return _truthy(_value(expr))

func _value(token: String) -> Variant:
	if token == "true":
		return true
	if token == "false":
		return false
	if token.is_valid_float():
		return float(token)
	if token.begins_with("\"") and token.ends_with("\""):
		return token.substr(1, token.length() - 2)
	return variables.get(token, 0)

func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_FLOAT, TYPE_INT:
			return v != 0
		TYPE_STRING:
			return v != ""
		_:
			return v != null

func _compare(a: Variant, b: Variant, op: String) -> bool:
	match op:
		"==":
			return a == b
		"!=":
			return a != b
		">=":
			return float(a) >= float(b)
		"<=":
			return float(a) <= float(b)
		">":
			return float(a) > float(b)
		"<":
			return float(a) < float(b)
	return false
