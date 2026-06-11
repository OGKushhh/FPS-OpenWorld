extends Node
# ── Porto Seco – Chunk Streaming ─────────────────────────────────
# 2000×2000m world  |  4×4 grid  |  500×500m per chunk

const CHUNK_SIZE   := 500.0
const GRID_W       := 4
const GRID_H       := 4
const LOAD_RADIUS  := 1
const CHUNK_PATH   := "res://world/scenes/chunk_%d_%d.tscn"

var _loaded : Dictionary = {}   # Vector2i → Node3D
var _pending : Dictionary = {}  # Vector2i → bool
var _player  : Node3D    = null

func _ready() -> void:
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		set_process(true)
	else:
		push_warning("WorldStream: no node in group 'player' — streaming disabled")

func _process(_d: float) -> void:
	_update_chunks(_world_to_chunk(_player.global_position))

func _world_to_chunk(p: Vector3) -> Vector2i:
	return Vector2i(int(p.x / CHUNK_SIZE), int(p.z / CHUNK_SIZE))

func _origin(c: Vector2i) -> Vector3:
	return Vector3(c.x * CHUNK_SIZE, 0.0, c.y * CHUNK_SIZE)

func _update_chunks(center: Vector2i) -> void:
	var want: Dictionary = {}
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var c := Vector2i(center.x + dx, center.y + dz)
			if c.x >= 0 and c.x < GRID_W and c.y >= 0 and c.y < GRID_H:
				want[c] = true
	for c in _loaded.keys():
		if not want.has(c): _unload(c)
	for c in want.keys():
		if not _loaded.has(c) and not _pending.has(c): _request(c)

func _request(c: Vector2i) -> void:
	var path := CHUNK_PATH % [c.x, c.y]
	if not ResourceLoader.exists(path): return
	_pending[c] = true
	ResourceLoader.load_threaded_request(path)
	_poll.call_deferred(c, path)

func _poll(c: Vector2i, path: String) -> void:
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		_poll.call_deferred(c, path)
	elif st == ResourceLoader.THREAD_LOAD_LOADED:
		_pending.erase(c)
		if not _loaded.has(c):
			var node: Node3D = (ResourceLoader.load_threaded_get(path) as PackedScene).instantiate()
			node.position = _origin(c)
			get_tree().root.add_child(node)
			_loaded[c] = node
	else:
		_pending.erase(c)
		push_warning("WorldStream: failed chunk %s" % str(c))

func _unload(c: Vector2i) -> void:
	if _loaded.has(c):
		_loaded[c].queue_free()
		_loaded.erase(c)
