extends Node3D

# ══════════════════════════════════════════════════════════════════
# SHOOTING_RANGE.GD — Gunplay Test Range
#
# Five distinct stations, each testing a specific mechanic:
#
#   STATION 1 — RECOIL WALL (Z -8)
#     One static target 8m away. Spray into it and watch your
#     recoil pattern imprint on it visually. Teaches the rifle
#     pattern before distance makes it hard.
#
#   STATION 2 — FIRST SHOT ACCURACY (Z -20)
#     Popup targets. They appear for 0.8s — not enough time to
#     spray. Forces you to stop moving, wait for crosshair to
#     settle, then land a single clean shot. Rewards patience.
#
#   STATION 3 — TRACKING (Z -35)
#     Targets slide horizontally at varying speeds. Tests whether
#     you can maintain aim on a moving target while controlling
#     recoil. Headshots on moving targets.
#
#   STATION 4 — COUNTER-STRAFE (Z -35, side corridor)
#     You must move left, stop, shoot, move right, stop, shoot.
#     A wide target only visible from specific positions forces
#     lateral movement between shots. Tests movement accuracy.
#
#   STATION 5 — PRESSURE (Z -50)
#     Charge targets rush you from 50m. Multiple incoming.
#     Tests: can you headshot under pressure? Do you panic-spray?
#
# Controls:
#   TAB   — cycle stations
#   Q     — weapon wheel
#   R     — reset current station score
#   F1    — toggle hit feedback overlay
# ══════════════════════════════════════════════════════════════════


# ── Station definitions ──────────────────────────────────────────
enum Station {
    RECOIL_WALL,
    FIRST_SHOT,
    TRACKING,
    COUNTER_STRAFE,
    PRESSURE
}

const STATION_NAMES: Dictionary = {
    Station.RECOIL_WALL:     "STATION 1 — RECOIL WALL",
    Station.FIRST_SHOT:      "STATION 2 — FIRST SHOT",
    Station.TRACKING:        "STATION 3 — TRACKING",
    Station.COUNTER_STRAFE:  "STATION 4 — COUNTER-STRAFE",
    Station.PRESSURE:        "STATION 5 — PRESSURE",
}

const STATION_TIPS: Dictionary = {
    Station.RECOIL_WALL:     "Spray full mag. Watch the pattern. Learn to pull down-left to control it.",
    Station.FIRST_SHOT:      "Targets show for 0.8s. Stop moving first. One clean shot per target.",
    Station.TRACKING:        "Keep crosshair on the moving target. Aim for the yellow head.",
    Station.COUNTER_STRAFE:  "Move left → STOP → shoot. Move right → STOP → shoot. Repeat.",
    Station.PRESSURE:        "They're charging. Headshots. Don't spray. Stay calm.",
}

# Player spawn positions per station
const STATION_SPAWNS: Dictionary = {
    Station.RECOIL_WALL:     Vector3(0, 1.0, 2),
    Station.FIRST_SHOT:      Vector3(0, 1.0, 2),
    Station.TRACKING:        Vector3(0, 1.0, 2),
    Station.COUNTER_STRAFE:  Vector3(0, 1.0, 2),
    Station.PRESSURE:        Vector3(0, 1.0, 2),
}

var current_station: Station = Station.RECOIL_WALL
var station_targets: Dictionary = {}   # Station -> Array[Node3D]

# ── Per-station stats ────────────────────────────────────────────
var stats: Dictionary = {}             # Station -> { shots, hits, heads, bodies, legs, kills }

# ── Hit feedback ring buffer ─────────────────────────────────────
# Last N hits shown as floating labels on HUD
const MAX_FEED_ENTRIES: int = 6
var hit_feed: Array[Dictionary] = []   # [{text, color, age}]
var show_hit_feed: bool = true

# ── HUD nodes ────────────────────────────────────────────────────
var station_label: Label
var tip_label: Label
var stats_label: Label
var feed_labels: Array[Label] = []
var accuracy_bar: ColorRect
var accuracy_fill: ColorRect

# ── Terrain ──────────────────────────────────────────────────────
const COLOR_CONCRETE: Color = Color(0.45, 0.45, 0.42)
const COLOR_SAND:     Color = Color(0.76, 0.70, 0.50)
const COLOR_METAL:    Color = Color(0.35, 0.38, 0.42)
const COLOR_WOOD:     Color = Color(0.45, 0.30, 0.15)
const COLOR_RUBBER:   Color = Color(0.18, 0.12, 0.12)
const COLOR_WALL:     Color = Color(0.55, 0.53, 0.50)
const COLOR_ACCENT:   Color = Color(0.20, 0.55, 0.90)


func _ready() -> void:
    var player = get_node_or_null("Player")
    if player:
        player.process_mode = Node.PROCESS_MODE_DISABLED

    _init_stats()
    _build_terrain()
    _build_all_stations()
    _build_hud()
    _connect_signals()

    if player:
        call_deferred("_enable_player", player)


func _enable_player(player: Node) -> void:
    player.process_mode = Node.PROCESS_MODE_INHERIT


func _process(delta: float) -> void:
    _update_hit_feed(delta)
    _update_hud()


# ══════════════════════════════════════════════════════════════════
# STATS
# ══════════════════════════════════════════════════════════════════

func _init_stats() -> void:
    for s in Station.values():
        stats[s] = { "shots": 0, "hits": 0, "heads": 0, "bodies": 0, "legs": 0, "kills": 0 }


func _reset_station_stats() -> void:
    var s = current_station
    stats[s] = { "shots": 0, "hits": 0, "heads": 0, "bodies": 0, "legs": 0, "kills": 0 }


func _get_accuracy() -> float:
    var s = stats[current_station]
    if s.shots == 0:
        return 0.0
    return float(s.hits) / float(s.shots) * 100.0


func _get_hs_ratio() -> float:
    var s = stats[current_station]
    if s.hits == 0:
        return 0.0
    return float(s.heads) / float(s.hits) * 100.0


# ══════════════════════════════════════════════════════════════════
# STATION MANAGEMENT
# ══════════════════════════════════════════════════════════════════

func _cycle_station() -> void:
    var stations = Station.values()
    var idx = stations.find(current_station)
    current_station = stations[(idx + 1) % stations.size()]
    _update_hud()


# ══════════════════════════════════════════════════════════════════
# TERRAIN
# ══════════════════════════════════════════════════════════════════

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


func _build_terrain() -> void:
    # One continuous floor, 2m thick, top surface at Y=0
    _make_static_box(Vector3(30, 2.0, 70), Vector3(0, -1.0, -33), COLOR_CONCRETE)

    # Side walls
    _make_static_box(Vector3(1, 5, 70), Vector3(-15, 2.5, -33), COLOR_WALL)
    _make_static_box(Vector3(1, 5, 70), Vector3(15, 2.5, -33),  COLOR_WALL)

    # Back wall
    _make_static_box(Vector3(32, 6, 1), Vector3(0, 3, -68), COLOR_WALL)

    # Station floor zone colours (cosmetic slabs on top of concrete)
    _make_static_box(Vector3(28, 0.02, 10), Vector3(0, 0.01, -5),   COLOR_RUBBER)   # S1 recoil
    _make_static_box(Vector3(28, 0.02, 10), Vector3(0, 0.01, -15),  COLOR_SAND)     # S2 first shot
    _make_static_box(Vector3(28, 0.02, 10), Vector3(0, 0.01, -28),  COLOR_WOOD)     # S3 tracking
    _make_static_box(Vector3(28, 0.02, 10), Vector3(0, 0.01, -28),  COLOR_METAL)    # S4 (same row)
    _make_static_box(Vector3(28, 0.02, 12), Vector3(0, 0.01, -44),  COLOR_SAND)     # S5 pressure

    # Distance markers — thin raised strips at 10, 20, 35, 50m
    for z_dist in [10, 20, 35, 50]:
        _make_static_box(Vector3(28, 0.05, 0.1), Vector3(0, 0.03, -z_dist), COLOR_ACCENT)

    # Cover blocks for counter-strafe station
    _make_static_box(Vector3(1.5, 1.2, 1.5), Vector3(-6, 0.6, -22), COLOR_CONCRETE)
    _make_static_box(Vector3(1.5, 1.2, 1.5), Vector3(6,  0.6, -22), COLOR_CONCRETE)


# ══════════════════════════════════════════════════════════════════
# TARGET SPAWNING
# ══════════════════════════════════════════════════════════════════

func _build_all_stations() -> void:
    for s in Station.values():
        station_targets[s] = []

    _build_station_recoil_wall()
    _build_station_first_shot()
    _build_station_tracking()
    _build_station_counter_strafe()
    _build_station_pressure()


func _spawn_target(station: Station, pos: Vector3, pattern: MovingTarget.Pattern,
        speed: float = 0.0, move_range: float = 0.0,
        popup_show: float = 2.0, popup_hide: float = 1.5,
        respawn: float = 3.0, points: int = 100) -> MovingTarget:

    var target = CharacterBody3D.new()
    target.set_script(load("res://common/target/moving_target.gd"))
    target.position = pos
    target.set("pattern", pattern)
    target.set("move_speed", speed)
    target.set("move_range", move_range)
    target.set("popup_show_time", popup_show)
    target.set("popup_hide_time", popup_hide)
    target.set("max_health", 100.0)
    target.set("respawn_time", respawn)
    target.set("point_value", points)

    target.connect("target_hit",      _on_target_hit.bind(station))
    target.connect("target_killed",   _on_target_killed.bind(station))
    target.connect("target_respawned", _on_target_respawned)

    add_child(target)
    station_targets[station].append(target)
    return target


# ── Station 1: Recoil Wall ───────────────────────────────────────
# One static target close up. Full-magazine spray reveals recoil
# pattern via per-zone flashes — head/body/legs light up where
# bullets land, building muscle memory for pull-down correction.

func _build_station_recoil_wall() -> void:
    # Three targets side by side — try each with a different gun
    _spawn_target(Station.RECOIL_WALL, Vector3(-3, 0, -8),  MovingTarget.Pattern.STATIC, 0, 0, 0, 0, 1.5, 50)
    _spawn_target(Station.RECOIL_WALL, Vector3(0,  0, -8),  MovingTarget.Pattern.STATIC, 0, 0, 0, 0, 1.5, 50)
    _spawn_target(Station.RECOIL_WALL, Vector3(3,  0, -8),  MovingTarget.Pattern.STATIC, 0, 0, 0, 0, 1.5, 50)


# ── Station 2: First Shot Accuracy ──────────────────────────────
# Short popup window forces deliberate single shots.
# popup_hide gives time to stop moving and let bloom settle.

func _build_station_first_shot() -> void:
    # Left lane: slow popup, forgiving timing
    _spawn_target(Station.FIRST_SHOT, Vector3(-6, 0, -20), MovingTarget.Pattern.POPUP, 0, 0, 0.8, 2.2, 0.1, 150)
    # Center lane: medium
    _spawn_target(Station.FIRST_SHOT, Vector3(0,  0, -20), MovingTarget.Pattern.POPUP, 0, 0, 0.8, 1.8, 0.1, 150)
    # Right lane: tight timing
    _spawn_target(Station.FIRST_SHOT, Vector3(6,  0, -20), MovingTarget.Pattern.POPUP, 0, 0, 0.8, 1.5, 0.1, 150)

    # Back row at 30m: harder distance, same popup timing
    _spawn_target(Station.FIRST_SHOT, Vector3(-4, 0, -30), MovingTarget.Pattern.POPUP, 0, 0, 0.8, 2.0, 0.1, 200)
    _spawn_target(Station.FIRST_SHOT, Vector3(4,  0, -30), MovingTarget.Pattern.POPUP, 0, 0, 0.8, 2.0, 0.1, 200)


# ── Station 3: Tracking ──────────────────────────────────────────
# Sliding targets at varying speeds and ranges.
# Mix of horizontal (SLIDE) and depth (STRAFE) movement.

func _build_station_tracking() -> void:
    # Close: slow slide, large movement range — warming up
    _spawn_target(Station.TRACKING, Vector3(0, 0, -25), MovingTarget.Pattern.SLIDE, 2.5, 8.0, 0, 0, 2.0, 100)

    # Mid: faster, tighter range — requires tighter tracking
    _spawn_target(Station.TRACKING, Vector3(-4, 0, -35), MovingTarget.Pattern.SLIDE,  4.0, 6.0, 0, 0, 2.0, 150)
    _spawn_target(Station.TRACKING, Vector3(4,  0, -35), MovingTarget.Pattern.SLIDE,  4.5, 5.0, 0, 0, 2.0, 150)

    # Depth mover — harder to judge distance, tests tracking on Z axis
    _spawn_target(Station.TRACKING, Vector3(0, 0, -40), MovingTarget.Pattern.STRAFE, 3.0, 7.0, 0, 0, 2.0, 200)


# ── Station 4: Counter-Strafe ────────────────────────────────────
# Targets peek from behind the cover blocks built in terrain.
# Popup windows are short — you must move into position, STOP,
# let the crosshair settle, then fire. Moving while firing is
# punished by spread and the narrow window.

func _build_station_counter_strafe() -> void:
    # Left peek target: visible only from left side of center
    _spawn_target(Station.COUNTER_STRAFE, Vector3(-9, 0, -30), MovingTarget.Pattern.POPUP, 0, 0, 1.2, 1.8, 0.2, 200)
    # Right peek target: visible only from right side
    _spawn_target(Station.COUNTER_STRAFE, Vector3(9,  0, -30), MovingTarget.Pattern.POPUP, 0, 0, 1.2, 1.8, 0.2, 200)
    # Center target: always visible but offset popup timing
    _spawn_target(Station.COUNTER_STRAFE, Vector3(0,  0, -35), MovingTarget.Pattern.POPUP, 0, 0, 1.0, 2.5, 0.2, 150)


# ── Station 5: Pressure ──────────────────────────────────────────
# Chargers come from 50m. Multiple waves. Tests whether panic
# causes you to spray wildly or stay composed for headshots.
# Short respawn so pressure is constant.

func _build_station_pressure() -> void:
    _spawn_target(Station.PRESSURE, Vector3(-5, 0, -50), MovingTarget.Pattern.CHARGE, 4.5, 0, 0, 0, 2.0, 300)
    _spawn_target(Station.PRESSURE, Vector3(0,  0, -55), MovingTarget.Pattern.CHARGE, 4.0, 0, 0, 0, 2.5, 300)
    _spawn_target(Station.PRESSURE, Vector3(5,  0, -50), MovingTarget.Pattern.CHARGE, 5.0, 0, 0, 0, 1.8, 300)
    # Flankers come from wider angles
    _spawn_target(Station.PRESSURE, Vector3(-10, 0, -45), MovingTarget.Pattern.CHARGE, 3.5, 0, 0, 0, 3.0, 400)
    _spawn_target(Station.PRESSURE, Vector3(10,  0, -45), MovingTarget.Pattern.CHARGE, 3.5, 0, 0, 0, 3.0, 400)


# ══════════════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════════════

func _connect_signals() -> void:
    Global.camera_shake.connect(_on_shot_fired)


func _on_shot_fired() -> void:
    stats[current_station].shots += 1


func _on_target_hit(zone: MovingTarget.HitZone, damage: float, points: int, station: Station) -> void:
    if station != current_station:
        return

    stats[current_station].hits += 1

    match zone:
        MovingTarget.HitZone.HEAD:
            stats[current_station].heads += 1
            _add_feed("HEADSHOT  +%d" % points, Color(1.0, 0.75, 0.0))
        MovingTarget.HitZone.BODY:
            stats[current_station].bodies += 1
            _add_feed("Body  +%d" % points, Color(0.85, 0.85, 0.85))
        MovingTarget.HitZone.LEGS:
            stats[current_station].legs += 1
            _add_feed("Leg  +%d" % points, Color(0.55, 0.65, 1.0))


func _on_target_killed(points: int, station: Station) -> void:
    if station != current_station:
        return
    stats[current_station].kills += 1
    _add_feed("KILL  +%d" % points, Color(0.3, 1.0, 0.4))


func _on_target_respawned() -> void:
    pass


# ══════════════════════════════════════════════════════════════════
# HIT FEED
# ══════════════════════════════════════════════════════════════════

func _add_feed(text: String, color: Color) -> void:
    if not show_hit_feed:
        return
    hit_feed.push_front({ "text": text, "color": color, "age": 0.0 })
    if hit_feed.size() > MAX_FEED_ENTRIES:
        hit_feed.resize(MAX_FEED_ENTRIES)


func _update_hit_feed(delta: float) -> void:
    for i in hit_feed.size():
        hit_feed[i].age += delta

    # Remove entries older than 2 seconds
    hit_feed = hit_feed.filter(func(e): return e.age < 2.0)

    # Sync to labels
    for i in feed_labels.size():
        if i < hit_feed.size():
            var entry = hit_feed[i]
            var alpha = clamp(1.0 - (entry.age - 1.2) / 0.8, 0.0, 1.0)
            var c = entry.color
            feed_labels[i].text = entry.text
            feed_labels[i].add_theme_color_override("font_color", Color(c.r, c.g, c.b, alpha))
        else:
            feed_labels[i].text = ""


# ══════════════════════════════════════════════════════════════════
# HUD
# ══════════════════════════════════════════════════════════════════

func _build_hud() -> void:
    var canvas = CanvasLayer.new()
    canvas.layer = 10
    add_child(canvas)

    # ── Station name + tip (top centre) ─────────────────────────
    station_label = Label.new()
    station_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
    station_label.position = Vector2(0, 14)
    station_label.size = Vector2(0, 32)
    station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    station_label.add_theme_font_size_override("font_size", 22)
    station_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    canvas.add_child(station_label)

    tip_label = Label.new()
    tip_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
    tip_label.position = Vector2(0, 42)
    tip_label.size = Vector2(0, 22)
    tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    tip_label.add_theme_font_size_override("font_size", 13)
    tip_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
    canvas.add_child(tip_label)

    # ── Stats panel (top left) ───────────────────────────────────
    var panel = Panel.new()
    panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
    panel.position = Vector2(12, 12)
    panel.size = Vector2(210, 130)
    panel.self_modulate = Color(0, 0, 0, 0.55)
    canvas.add_child(panel)

    stats_label = Label.new()
    stats_label.position = Vector2(20, 18)
    stats_label.size = Vector2(190, 108)
    stats_label.add_theme_font_size_override("font_size", 13)
    stats_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
    canvas.add_child(stats_label)

    # ── Accuracy bar (below stats panel) ────────────────────────
    accuracy_bar = ColorRect.new()
    accuracy_bar.position = Vector2(12, 148)
    accuracy_bar.size = Vector2(210, 8)
    accuracy_bar.color = Color(0.2, 0.2, 0.2, 0.7)
    canvas.add_child(accuracy_bar)

    accuracy_fill = ColorRect.new()
    accuracy_fill.position = Vector2(12, 148)
    accuracy_fill.size = Vector2(0, 8)
    accuracy_fill.color = Color(0.3, 0.9, 0.3, 0.85)
    canvas.add_child(accuracy_fill)

    # ── Hit feed (right side) ────────────────────────────────────
    var feed_x = 0.75  # 75% of screen width
    for i in MAX_FEED_ENTRIES:
        var lbl = Label.new()
        lbl.set_anchor(SIDE_LEFT, feed_x)
        lbl.set_anchor(SIDE_RIGHT, 1.0)
        lbl.position = Vector2(0, 80 + i * 26)
        lbl.size = Vector2(0, 24)
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        lbl.add_theme_font_size_override("font_size", 15)
        lbl.text = ""
        canvas.add_child(lbl)
        feed_labels.append(lbl)

    # ── Controls reminder (bottom) ───────────────────────────────
    var ctrl_label = Label.new()
    ctrl_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    ctrl_label.position = Vector2(0, -26)
    ctrl_label.size = Vector2(0, 22)
    ctrl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ctrl_label.add_theme_font_size_override("font_size", 12)
    ctrl_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
    ctrl_label.text = "TAB — next station    Q — weapon wheel    R — reset stats    F1 — toggle hit feed"
    canvas.add_child(ctrl_label)


func _update_hud() -> void:
    if not stats_label:
        return

    var s = stats[current_station]
    var acc = _get_accuracy()
    var hs = _get_hs_ratio()

    station_label.text = STATION_NAMES[current_station]
    tip_label.text = STATION_TIPS[current_station]

    stats_label.text = (
        "Shots:    %d\n" % s.shots +
        "Hits:     %d  (%.0f%%)\n" % [s.hits, acc] +
        "Head:     %d  (%.0f%% of hits)\n" % [s.heads, hs] +
        "Body:     %d\n" % s.bodies +
        "Legs:     %d\n" % s.legs +
        "Kills:    %d" % s.kills
    )

    # Accuracy bar width
    if accuracy_fill:
        accuracy_fill.size.x = (acc / 100.0) * 210.0
        # Colour: red → yellow → green based on accuracy
        if acc >= 60.0:
            accuracy_fill.color = Color(0.3, 0.9, 0.3, 0.85)
        elif acc >= 35.0:
            accuracy_fill.color = Color(0.9, 0.75, 0.1, 0.85)
        else:
            accuracy_fill.color = Color(0.9, 0.25, 0.15, 0.85)


# ══════════════════════════════════════════════════════════════════
# INPUT
# ══════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
    # TAB — cycle station
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_TAB:
                _cycle_station()
            KEY_R:
                _reset_station_stats()
            KEY_F1:
                show_hit_feed = not show_hit_feed
                if not show_hit_feed:
                    for lbl in feed_labels:
                        lbl.text = ""
