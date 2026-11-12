@tool
extends EditorScript
## Runs the bot simulator from inside the Godot editor.
## Open this file, then choose File > Run (Ctrl+Shift+X). Results appear in the
## Output panel at the bottom. It takes a little while and the editor may freeze
## until it finishes. Lower GAMES for a faster, rougher answer.

const GAMES := 200


func _run() -> void:
	print(Simulator.wheel_report())
	print("")
	print(Simulator.format_report(Simulator.run_batch(GAMES, Simulator.Bot.INFORMED)))
	print("")
	print(Simulator.format_report(Simulator.run_batch(GAMES, Simulator.Bot.RANDOM)))
