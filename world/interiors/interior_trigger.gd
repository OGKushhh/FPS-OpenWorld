extends Area3D
# ── Interior Door Trigger ─────────────────────────────────────────
# Place this Area3D inside/around a door frame.
# Set interior_scene to the matching interior .tscn.
# Player walks in → interior loads; walks out → interior unloads.

@export var interior_scene: PackedScene
@export var interior_offset: Vector3 = Vector3(0, 0, 5)

var _interior_node: Node3D = null
var _player_inside: bool   = false

func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _on_enter(body: Node3D) -> void:
	if not body.is_in_group("player"): return
	if _player_inside: return
	_player_inside = true
	if interior_scene and not _interior_node:
		_interior_node = interior_scene.instantiate()
		_interior_node.position = global_position + interior_offset
		get_tree().root.add_child(_interior_node)

func _on_exit(body: Node3D) -> void:
	if not body.is_in_group("player"): return
	_player_inside = false
	# Delay unload so player can walk back in without re-instantiate
	await get_tree().create_timer(5.0).timeout
	if not _player_inside and _interior_node:
		_interior_node.queue_free()
		_interior_node = null
