extends Control

# Dynamic crosshair elements
@onready var crosshair_top: ColorRect = $CrosshairTop
@onready var crosshair_bottom: ColorRect = $CrosshairBottom
@onready var crosshair_left: ColorRect = $CrosshairLeft
@onready var crosshair_right: ColorRect = $CrosshairRight
@onready var crosshair_center: ColorRect = $CrosshairCenter


# Crosshair settings
const LINE_WIDTH: float = 3.0
const LINE_LENGTH: float = 10.0
const CENTER_DOT_SIZE: float = 2.0

# Spread-to-pixel mapping
# 0.25° (Valorant first-shot) ≈ 10px from center at 1080p
# 5.0° (max spread) ≈ 100px from center
const MIN_SPREAD: float = 8.0    # Minimum pixel distance (near-perfect accuracy)
const MAX_SPREAD: float = 100.0  # Maximum pixel distance (full sprint + spray)
const SPREAD_DEGREES_MIN: float = 0.05  # Degrees that maps to MIN_SPREAD
const SPREAD_DEGREES_MAX: float = 5.0   # Degrees that maps to MAX_SPREAD

var current_spread: float = 20.0  # Current pixel spread
var target_spread: float = 20.0
var is_aiming: bool = false


func _ready() -> void:
        Global.aim_mode_changed.connect(_on_aim_mode_changed)
        Global.player_velocity_changed.connect(_on_player_velocity_changed)
        _setup_crosshair()


func _setup_crosshair() -> void:
        _update_crosshair_positions()


func _process(delta: float) -> void:
        # Smoothly interpolate to target spread
        current_spread = lerp(current_spread, target_spread, delta * 12.0)
        _update_crosshair_positions()


func _on_player_velocity_changed(velocity: Vector3) -> void:
        if is_aiming:
                return

        # Calculate horizontal velocity magnitude
        var horizontal_velocity = Vector2(velocity.x, velocity.z).length()

        # Get the current weapon's spread from the weapons manager
        var weapon_spread_degrees = _get_current_weapon_spread()

        # Map the weapon's actual spread angle to pixel spread
        if weapon_spread_degrees >= 0:
                var t = clamp(
                        (weapon_spread_degrees - SPREAD_DEGREES_MIN) / (SPREAD_DEGREES_MAX - SPREAD_DEGREES_MIN),
                        0.0, 1.0
                )
                target_spread = lerpf(MIN_SPREAD, MAX_SPREAD, t)
        else:
                # Fallback: velocity-based only
                var velocity_factor = clamp(horizontal_velocity / 10.0, 0.0, 1.0)
                target_spread = lerpf(15.0, MAX_SPREAD, velocity_factor)


func _get_current_weapon_spread() -> float:
        # Get the current weapon's calculated spread angle from the weapons manager
        if not Global.player:
                return -1.0

        var weapons_manager = Global.player.get_node_or_null("WeaponsManager")
        if not weapons_manager or not weapons_manager.current_weapon:
                return -1.0

        var weapon = weapons_manager.current_weapon
        if weapon.is_melee_weapon:
                return -1.0

        # Access the weapon's current spread calculation
        return weapon.calculate_current_spread()


func _update_crosshair_positions() -> void:
        var center_x = size.x / 2.0
        var center_y = size.y / 2.0

        # Top line
        crosshair_top.position = Vector2(center_x - LINE_WIDTH / 2.0, center_y - current_spread - LINE_LENGTH)
        crosshair_top.size = Vector2(LINE_WIDTH, LINE_LENGTH)

        # Bottom line
        crosshair_bottom.position = Vector2(center_x - LINE_WIDTH / 2.0, center_y + current_spread)
        crosshair_bottom.size = Vector2(LINE_WIDTH, LINE_LENGTH)

        # Left line
        crosshair_left.position = Vector2(center_x - current_spread - LINE_LENGTH, center_y - LINE_WIDTH / 2.0)
        crosshair_left.size = Vector2(LINE_LENGTH, LINE_WIDTH)

        # Right line
        crosshair_right.position = Vector2(center_x + current_spread, center_y - LINE_WIDTH / 2.0)
        crosshair_right.size = Vector2(LINE_LENGTH, LINE_WIDTH)

        # Center dot
        crosshair_center.position = Vector2(center_x - CENTER_DOT_SIZE / 2.0, center_y - CENTER_DOT_SIZE / 2.0)
        crosshair_center.size = Vector2(CENTER_DOT_SIZE, CENTER_DOT_SIZE)


func _on_aim_mode_changed(aim_mode: bool) -> void:
        is_aiming = aim_mode
        if aim_mode:
                # Hide crosshair when aiming down sights
                crosshair_top.visible = false
                crosshair_bottom.visible = false
                crosshair_left.visible = false
                crosshair_right.visible = false
                crosshair_center.visible = false
        else:
                crosshair_top.visible = true
                crosshair_bottom.visible = true
                crosshair_left.visible = true
                crosshair_right.visible = true
                crosshair_center.visible = true
