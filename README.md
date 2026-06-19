# Visual Novel Template (Godot 4.7)

A small, data-driven visual novel engine. You write the story in a JSON file —
no code changes needed for new scenes, branches, characters, or endings.

## Run it

1. Open the project in Godot 4.7 (this lets it import the `.svg` assets).
2. Press **F5** (the main scene is `scenes/VisualNovel.tscn`).
3. Click or press **Space/Enter** to advance. Click a choice to branch.

Top-right buttons: **Auto** (auto-advance), **Skip** (fast-forward),
**Log** (backlog of everything said), **Save** / **Load**.

## Project layout

| Path | What it is |
|------|------------|
| `scripts/DialogueManager.gd` | Autoload singleton: loads the story, holds variables, evaluates conditions. |
| `scripts/VisualNovel.gd` | Runtime: executes a node's statements, drives the UI. |
| `scripts/TypewriterLabel.gd` | RichTextLabel that reveals text character-by-character. |
| `scenes/VisualNovel.tscn` | The screen (background, portraits, dialogue box, buttons). |
| `dialogue/story.json` | **The story.** Edit this to make your own VN. |
| `assets/backgrounds/*.svg` | Background art (referenced by name, e.g. `"bg": "classroom"`). |
| `assets/portraits/*.svg` | Character art, named `<name>_<mood>.svg` (e.g. `alice_happy.svg`). |

## Writing a story

A story is a set of named **nodes**. Each node is a list of **statements** that
run top to bottom. `say` and `choice` pause for the player; everything else runs
instantly and flow continues.

```json
{
  "start": "intro",
  "variables": { "affection": 0 },
  "nodes": {
    "intro": [
      { "bg": "classroom" },
      { "show": "Alice", "at": "left", "mood": "neutral" },
      { "say": "Alice", "text": "Hello, {affection}!", "mood": "happy" },
      { "choice": [
        { "text": "Be nice",  "goto": "route_a", "add": { "affection": 1 } },
        { "text": "Be aloof", "goto": "route_b", "if": "affection >= 0" }
      ] }
    ]
  }
}
```

### Statement reference

| Statement | Effect |
|-----------|--------|
| `{ "bg": "name" }` | Crossfade to `assets/backgrounds/name.svg`. |
| `{ "show": "Alice", "at": "left", "mood": "happy" }` | Show a character. `at` = `left`/`center`/`right`. |
| `{ "hide": "Alice" }` | Remove a character (by name or by slot). |
| `{ "say": "Alice", "text": "...", "mood": "sad" }` | A line. Empty `say` = narration (no name box). `mood` is optional. |
| `{ "set": { "flag": true } }` | Assign variables. |
| `{ "add": { "score": 1 } }` | Add to a numeric variable. |
| `{ "choice": [ ... ] }` | Show buttons. Each option: `text`, `goto`, optional `if`, `set`, `add`. |
| `{ "goto": "node", "if": "cond" }` | Jump to another node, optionally only if `cond` is true. |
| `{ "end": true }` | End the route (click restarts). |

### Conditions

Used by `if` on `goto` and `choice` options:

- `"met_alice"` — truthy check (missing vars are `0`/false)
- `"!met_alice"` — negation
- `"affection >= 2"` — `==`, `!=`, `>`, `<`, `>=`, `<=`
- `'name == "Alice"'` — string compares (quote the literal)

### Text interpolation

Any `{var}` inside `text` is replaced with that variable's current value.

## Adding art

- **Background:** drop `myroom.svg` (or `.png`) into `assets/backgrounds/`, then
  `{ "bg": "myroom" }`.
- **Character:** add `bob_neutral.svg` (and optional `bob_happy.svg`, etc.) to
  `assets/portraits/`. Reference with `{ "show": "Bob", "mood": "happy" }`.
  If a mood file is missing it falls back to `<name>_neutral`.

Art is plain SVG so it's easy to swap for your own PNGs.
