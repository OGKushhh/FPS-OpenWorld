extends Node3D

# ══════════════════════════════════════════════════════════════════
# SHOOTING_RANGE.GD — Range Builder + Target Manager + Score HUD
#
# Builds the entire shooting range in _ready():
#   - Varied terrain materials (concrete, sand, metal, wood, rubber)
#   - Multiple lanes at 15m, 30m, 50m+ distances
#   - Backstop walls, lane dividers, cover objects
#   - Moving targets with different patterns
#   - Score tracking, round management, on-screen HUD
# ══════════════════════════════════════════════════════════════════


# ── Round Modes ──────────────────────────────────────────────────
enum Mode { FREE_PLAY, TIMED, PRECISION, SURVIVAL }

@export_group("range settings")
@export var range_mode: Mode = Mode.FREE_PLAY
@export var timed_round_seconds: float = 60.0
@export var max_targets_alive: int = 8

# ── Score State ──────────────────────────────────────────────────
var total_score: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var headshots: int = 0
var round_time_remaining: float = 0.0
var round_active: bool = false
var targets: Array[Node3D] = []

# ── HUD References ───────────────────────────────────────────────
var hud_label: Label
var score_label: Label
var round_label: Label

# ── Terrain Colors ───────────────────────────────────────────────
const COLOR_CONCRETE: Color = Color(0.45, 0.45, 0.42)
const COLOR_SAND: Color = Color(0.76, 0.70, 0.50)
const COLOR_METAL: Color = Color(0.35, 0.38, 0.42)
const COLOR_WOOD: Color = Color(0.45, 0.30, 0.15)
const COLOR_RUBBER: Color = Color(0.18, 0.12, 0.12)
const COLOR_WALL: Color = Color(0.55, 0.53, 0.50)
const COLOR_LANE_LINE: Color = Color(0.9, 0.85, 0.2)


func _ready() -> void:
		_build_terrain()
		_build_targets()
		_build_hud()
		_connect_weapon_signals()
		start_round()


func _process(delta: float) -> void:
		if round_active and range_mode == Mode.TIMED:
				round_time_remaining -= delta
				if round_time_remaining <= 0.0:
						round_time_remaining = 0.0
						end_round()
				_update_hud()


# ══════════════════════════════════════════════════════════════════
# ROUND MANAGEMENT
# ══════════════════════════════════════════════════════════════════

func start_round() -> void:
		round_active = true
		total_score = 0
		shots_fired = 0
		shots_hit = 0
		headshots = 0
		round_time_remaining = timed_round_seconds
		_update_hud()


func end_round() -> void:
		round_active = false
		var accuracy = (float(shots_hit) / max(float(shots_fired), 1.0)) * 100.0
		if round_label:
				round_label.text = "ROUND OVER — Score: %d | Accuracy: %.1f%% | Headshots: %d" % [total_score, accuracy, headshots]
				round_label.visible = true


# ══════════════════════════════════════════════════════════════════
# TERRAIN BUILDER
# ══════════════════════════════════════════════════════════════════
# The range is laid out along the -Z axis (player faces -Z).
# Player stands at Z=0, targets are at negative Z distances.
#
# Layout (side view, not to scale):
#
#  Player  Firing Line  15m Lane  30m Lane  50m Lane  Backstop
#    |         |           |         |         |          |
#    Z=0     Z=-2       Z=-15     Z=-30     Z=-50     Z=-60
#
# X axis: lanes spread left-right, total width ~30m

func _build_terrain() -> void:
		_build_floor()
		_build_backstops()
		_build_side_walls()
		_build_lane_dividers()
		_build_cover_objects()
		_build_lane_markers()


func _make_static_box(size: Vector3, position: Vector3, color: Color, parent: Node = self) -> StaticBody3D:
		var body = StaticBody3D.new()
		body.position = position

		var mesh_instance = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mesh_instance.material_override = mat
		body.add_child(mesh_instance)

		var col_shape = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		col_shape.shape = shape
		body.add_child(col_shape)

		parent.add_child(body)
		return body


func _build_floor() -> void:
		# Floor slabs are 2m thick to prevent tunneling.
		# Center Y = -1.0 keeps the top surface at Y = 0.0.
		const FLOOR_H: float = 2.0
		const FLOOR_Y: float = -1.0

		# ── Firing Line (Z: 0 to -2) — Concrete ────────────────
		_make_static_box(Vector3(30, FLOOR_H, 4), Vector3(0, FLOOR_Y, -2), COLOR_CONCRETE)

		# ── Close Range (Z: -2 to -15) — Rubber mat ────────────
		_make_static_box(Vector3(30, FLOOR_H, 13), Vector3(0, FLOOR_Y, -8.5), COLOR_RUBBER)

		# ── Mid Range (Z: -15 to -30) — Sand ───────────────────
		_make_static_box(Vector3(30, FLOOR_H, 15), Vector3(0, FLOOR_Y, -22.5), COLOR_SAND)

		# ── Long Range (Z: -30 to -50) — Wood decking ─────────
		_make_static_box(Vector3(30, FLOOR_H, 20), Vector3(0, FLOOR_Y, -40), COLOR_WOOD)

		# ── Far Back (Z: -50 to -60) — Metal catwalk ───────────
		_make_static_box(Vector3(30, FLOOR_H, 10), Vector3(0, FLOOR_Y, -55), COLOR_METAL)


func _build_backstops() -> void:
		# Back wall at Z=-60 (catches all bullets)
		_make_static_box(Vector3(32, 6, 1), Vector3(0, 3, -61), COLOR_WALL)

		# Angled side deflectors
		_make_static_box(Vector3(1, 4, 5), Vector3(-15.5, 2, -58), COLOR_WALL)
		_make_static_box(Vector3(1, 4, 5), Vector3(15.5, 2, -58), COLOR_WALL)


func _build_side_walls() -> void:
		# Left wall
		_make_static_box(Vector3(1, 4, 65), Vector3(-15.5, 2, -29), COLOR_WALL)
		# Right wall
		_make_static_box(Vector3(1, 4, 65), Vector3(15.5, 2, -29), COLOR_WALL)


func _build_lane_dividers() -> void:
		# Three lanes: Left (-10 to -3), Center (-3 to 3), Right (3 to 10)
		var divider_positions = [-3.0, 3.0]
		for x in divider_positions:
				# Low barriers you can see over
				_make_static_box(Vector3(0.15, 0.6, 30), Vector3(x, 0.3, -15), COLOR_CONCRETE)
				# Extended dividers for mid+long range
				_make_static_box(Vector3(0.15, 0.6, 30), Vector3(x, 0.3, -45), COLOR_CONCRETE)


func _build_cover_objects() -> void:
		# Cover near mid-range for tactical practice
		_make_static_box(Vector3(2, 1.2, 1), Vector3(-7, 0.6, -20), COLOR_CONCRETE)
		_make_static_box(Vector3(2, 1.2, 1), Vector3(7, 0.6, -20), COLOR_CONCRETE)
		_make_static_box(Vector3(1, 1.2, 2), Vector3(0, 0.6, -25), COLOR_WOOD)

		# Elevated platform at long range
		_make_static_box(Vector3(6, 0.3, 4), Vector3(-9, 0.15, -40), COLOR_METAL)
		# Platform support
		_make_static_box(Vector3(6, 0.15, 4), Vector3(-9, -0.5, -40), COLOR_METAL)

		# Small barriers for peek practice
		_make_static_box(Vector3(1.5, 1.5, 0.3), Vector3(-5, 0.75, -35), COLOR_CONCRETE)
		_make_static_box(Vector3(1.5, 1.5, 0.3), Vector3(5, 0.75, -35), COLOR_CONCRETE)


func _build_lane_markers() -> void:
		# Distance markers on the ground at each lane
		var distances = [15, 30, 50]
		var lane_xs = [-6.5, 0.0, 6.5]

		for dist in distances:
				for x in lane_xs:
						var marker = MeshInstance3D.new()
						var plane = PlaneMesh.new()
						plane.size = Vector2(1.5, 0.3)
						marker.mesh = plane
						marker.position = Vector3(x, 0.01, -dist)
						marker.rotation.x = -PI / 2.0
						var mat = StandardMaterial3D.new()
						mat.albedo_color = COLOR_LANE_LINE
						marker.material_override = mat
						add_child(marker)


# ══════════════════════════════════════════════════════════════════
# TARGET BUILDER
# ══════════════════════════════════════════════════════════════════

func _build_targets() -> void:
		var targets_node = Node3D.new()
		targets_node.name = "Targets"
		add_child(targets_node)

		# ── Close Range (15m) — Popup targets ──────────────────
		_spawn_target(targets_node, Vector3(-6, 0, -15), MovingTarget.Pattern.POPUP, 2.0, 1.5)
		_spawn_target(targets_node, Vector3(0, 0, -15), MovingTarget.Pattern.POPUP, 2.5, 2.0)
		_spawn_target(targets_node, Vector3(6, 0, -15), MovingTarget.Pattern.POPUP, 1.8, 1.2)

		# ── Mid Range (30m) — Slide + Strafe targets ──────────
		_spawn_target(targets_node, Vector3(-8, 0, -30), MovingTarget.Pattern.SLIDE, 3.0, 8.0)
		_spawn_target(targets_node, Vector3(0, 0, -30), MovingTarget.Pattern.STRAFE, 3.5, 6.0)
		_spawn_target(targets_node, Vector3(8, 0, -30), MovingTarget.Pattern.SLIDE, 4.0, 10.0)

		# ── Long Range (50m) — Slow slide targets ─────────────
		_spawn_target(targets_node, Vector3(-8, 0, -50), MovingTarget.Pattern.SLIDE, 2.0, 12.0)
		_spawn_target(targets_node, Vector3(0, 0, -50), MovingTarget.Pattern.STRAFE, 2.5, 8.0)
		_spawn_target(targets_node, Vector3(8, 0, -50), MovingTarget.Pattern.SLIDE, 1.5, 6.0)

		# ── Charge Lane — Targets that rush you ────────────────
		_spawn_target(targets_node, Vector3(-6, 0, -45), MovingTarget.Pattern.CHARGE, 4.0, 0.0)
		_spawn_target(targets_node, Vector3(6, 0, -45), MovingTarget.Pattern.CHARGE, 5.0, 0.0)


func _spawn_target(parent: Node, pos: Vector3, pattern: MovingTarget.Pattern, speed: float, move_range: float) -> void:
		var target = CharacterBody3D.new()
		target.set_script(load("res://common/target/moving_target.gd"))
		target.position = pos
		target.set("pattern", pattern)
		target.set("move_speed", speed)
		target.set("move_range", move_range)
		target.set("max_health", 100.0)
		target.set("point_value", 100)

		# Connect signals
		target.connect("target_hit", _on_target_hit)
		target.connect("target_killed", _on_target_killed)
		target.connect("target_respawned", _on_target_respawned)

		parent.add_child(target)
		targets.append(target)


# ══════════════════════════════════════════════════════════════════
# TARGET EVENT HANDLERS
# ══════════════════════════════════════════════════════════════════

func _on_target_hit(zone: int, damage: float, points: int) -> void:
		shots_hit += 1
		total_score += points
		if zone == 0:  # HitZone.HEAD = 0
				headshots += 1


func _on_target_killed(points: int) -> void:
		total_score += points


func _on_target_respawned() -> void:
		pass  # Target is back in play


# ══════════════════════════════════════════════════════════════════
# WEAPON SHOT TRACKING
# ══════════════════════════════════════════════════════════════════

func _connect_weapon_signals() -> void:
		# Track shots fired via the camera_shake signal (fires every shot)
		# This is a simple heuristic — we count every shake as a shot
		Global.camera_shake.connect(_on_shot_fired)


func _on_shot_fired() -> void:
		shots_fired += 1


# ══════════════════════════════════════════════════════════════════
# HUD
# ══════════════════════════════════════════════════════════════════

func _build_hud() -> void:
		var canvas = CanvasLayer.new()
		canvas.layer = 10
		add_child(canvas)

		var panel = Panel.new()
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.position = Vector2(10, 10)
		panel.size = Vector2(280, 140)
		panel.self_modulate = Color(0, 0, 0, 0.6)
		canvas.add_child(panel)

		# Score
		score_label = Label.new()
		score_label.position = Vector2(15, 8)
		score_label.size = Vector2(260, 24)
		score_label.add_theme_font_size_override("font_size", 20)
		score_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		canvas.add_child(score_label)

		# Stats
		hud_label = Label.new()
		hud_label.position = Vector2(15, 35)
		hud_label.size = Vector2(260, 70)
		hud_label.add_theme_font_size_override("font_size", 14)
		hud_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		canvas.add_child(hud_label)

		# Round info
		round_label = Label.new()
		round_label.position = Vector2(15, 105)
		round_label.size = Vector2(260, 24)
		round_label.add_theme_font_size_override("font_size", 14)
		round_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		canvas.add_child(round_label)

		_update_hud()


func _update_hud() -> void:
		if not score_label:
				return

		var accuracy = 0.0
		if shots_fired > 0:
				accuracy = (float(shots_hit) / float(shots_fired)) * 100.0

		score_label.text = "SCORE: %d" % total_score

		hud_label.text = "Hits: %d / %d  (%.1f%%)\nHeadshots: %d" % [shots_hit, shots_fired, accuracy, headshots]

		match range_mode:
				Mode.FREE_PLAY:
						round_label.text = "FREE PLAY — press R to reset score"
				Mode.TIMED:
						var secs = int(round_time_remaining)
						round_label.text = "TIME: %d:%02d" % [secs / 60, secs % 60]
				Mode.PRECISION:
						round_label.text = "PRECISION — accuracy counts"
				Mode.SURVIVAL:
						round_label.text = "SURVIVAL — don't let them reach you"


func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("reload"):
				# R key resets score in free play
				if range_mode == Mode.FREE_PLAY:
						total_score = 0
						shots_fired = 0
						shots_hit = 0
						headshots = 0
						_update_hud()
