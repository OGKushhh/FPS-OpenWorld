extends Control

var is_visible: bool = false
var weapons_manager: Node3D = null
var hovered_index: int = -1
var weapon_names: Array[String] = ["Knife", "Pistol", "Rifle", "Burst Rifle", "LMG"]
var weapon_icons: Array[String] = ["Melee", "Sidearm", "Rifle", "Burst", "Heavy"]

const WHEEL_RADIUS: float = 200.0
const SEGMENT_GAP: float = 0.03  # Radians gap between segments
const HIGHLIGHT_COLOR: Color = Color(1.0, 0.85, 0.3, 0.8)  # Gold
const NORMAL_COLOR: Color = Color(0.2, 0.2, 0.25, 0.7)
const BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)

signal weapon_selected(index: int)


func _ready():
    # Connect to global signal bus
    if Global.has_signal("weapon_wheel_toggled"):
        Global.weapon_wheel_toggled.connect(_on_weapon_wheel_toggled)

    # Full-rect anchors so we cover the entire viewport
    anchor_right = 1.0
    anchor_bottom = 1.0

    # Don't process or draw when hidden
    visible = false
    set_process(false)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_weapon_wheel_toggled(show: bool):
    if show:
        _show_wheel()
    else:
        _hide_wheel()


func _show_wheel():
    is_visible = true
    visible = true
    set_process(true)
    mouse_filter = Control.MOUSE_FILTER_STOP

    # Find weapons manager (for potential future use like ammo display)
    if not weapons_manager and Global.player:
        weapons_manager = Global.player.get_node("WeaponsManager")

    # Dynamically match weapon count from the manager
    if weapons_manager and weapons_manager.weapons_array.size() != weapon_names.size():
        var count = weapons_manager.weapons_array.size()
        while weapon_names.size() < count:
            weapon_names.append("Weapon %d" % weapon_names.size())
            weapon_icons.append("?")
        weapon_names = weapon_names.slice(0, count)
        weapon_icons = weapon_icons.slice(0, count)

    # Free mouse so the player can point at segments
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _hide_wheel():
    if hovered_index >= 0:
        weapon_selected.emit(hovered_index)

    is_visible = false
    visible = false
    set_process(false)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    hovered_index = -1

    # Recapture mouse for FPS gameplay
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta):
    # Calculate which segment the mouse is hovering over
    var center = size / 2.0
    var mouse_pos = get_local_mouse_position()
    var to_mouse = mouse_pos - center
    var dist = to_mouse.length()

    if dist > WHEEL_RADIUS * 0.3 and dist < WHEEL_RADIUS * 1.2:
        var angle = atan2(to_mouse.y, to_mouse.x)
        if angle < 0:
            angle += TAU
        # Calculate segment
        var segment_angle = TAU / weapon_names.size()
        hovered_index = int(angle / segment_angle) % weapon_names.size()
    else:
        hovered_index = -1

    queue_redraw()


func _draw():
    var center = size / 2.0
    var segment_angle = TAU / weapon_names.size()

    # Draw semi-transparent background overlay
    draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)

    # Draw each arc segment
    for i in range(weapon_names.size()):
        var start_angle = i * segment_angle + SEGMENT_GAP / 2.0
        var end_angle = (i + 1) * segment_angle - SEGMENT_GAP / 2.0
        var color = HIGHLIGHT_COLOR if i == hovered_index else NORMAL_COLOR

        # Draw arc segment (donut slice)
        draw_arc_segment(center, WHEEL_RADIUS * 0.3, WHEEL_RADIUS, start_angle, end_angle, color)

        # Draw weapon icon/label in the middle of the segment
        var label_angle = (start_angle + end_angle) / 2.0
        var label_radius = WHEEL_RADIUS * 0.65
        var label_pos = center + Vector2(cos(label_angle), sin(label_angle)) * label_radius

        var label_color = Color.BLACK if i == hovered_index else Color.WHITE
        draw_string(
            ThemeDB.fallback_font,
            label_pos - Vector2(30, 0),
            weapon_names[i],
            HORIZONTAL_ALIGNMENT_CENTER,
            60,
            16,
            label_color
        )

        # Draw icon text below the name
        var icon_pos = label_pos + Vector2(0, 18)
        var icon_color = Color(0.4, 0.4, 0.4) if i == hovered_index else Color(0.7, 0.7, 0.7)
        draw_string(
            ThemeDB.fallback_font,
            icon_pos - Vector2(20, 0),
            weapon_icons[i],
            HORIZONTAL_ALIGNMENT_CENTER,
            40,
            12,
            icon_color
        )

    # Draw inner circle (center hub)
    draw_circle(center, WHEEL_RADIUS * 0.25, Color(0.15, 0.15, 0.18, 0.9))
    draw_circle(center, WHEEL_RADIUS * 0.25, Color(0.3, 0.3, 0.35, 0.3))

    # Show hovered weapon name in the center
    if hovered_index >= 0:
        draw_string(
            ThemeDB.fallback_font,
            center - Vector2(40, -8),
            weapon_names[hovered_index],
            HORIZONTAL_ALIGNMENT_CENTER,
            80,
            20,
            Color(1, 0.85, 0.3)
        )
    else:
        draw_string(
            ThemeDB.fallback_font,
            center - Vector2(30, -5),
            "Select",
            HORIZONTAL_ALIGNMENT_CENTER,
            60,
            14,
            Color(0.5, 0.5, 0.5)
        )


func draw_arc_segment(center: Vector2, inner_r: float, outer_r: float, start_a: float, end_a: float, color: Color):
    var points = PackedVector2Array()
    var steps = 32
    # Outer arc
    for j in range(steps + 1):
        var a = lerpf(start_a, end_a, float(j) / steps)
        points.append(center + Vector2(cos(a), sin(a)) * outer_r)
    # Inner arc (reversed)
    for j in range(steps, -1, -1):
        var a = lerpf(start_a, end_a, float(j) / steps)
        points.append(center + Vector2(cos(a), sin(a)) * inner_r)
    draw_colored_polygon(points, color)
