extends Control

# ══════════════════════════════════════════════════════════════════
# CROSSHAIR.GD — Valorant Dynamic Crosshair + ADS Reticle Snap
#
# Hipfire: Crosshair stays fixed at screen center; bullets stray
#          away from it via spread/recoil math.
# ADS:     Crosshair DETACHES from center and SNAPS to the active
#          spray coordinates — acts as a red-dot sight showing
#          exactly where the next bullet will land.
# ══════════════════════════════════════════════════════════════════


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

# ADS crosshair settings (thinner lines, smaller dot — red-dot sight look)
const ADS_LINE_WIDTH: float = 2.0
const ADS_LINE_LENGTH: float = 6.0
const ADS_CENTER_DOT_SIZE: float = 3.0  # Slightly larger dot for visibility

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

# ── Reticle Snap State ───────────────────────────────────────────
# When ADS, the crosshair offset tracks the weapon's accumulated
# recoil pitch and yaw, converting them to 2D pixel displacements.
# This makes the crosshair act as a red-dot sight: it shows
# EXACTLY where the next bullet will land.
var snap_offset_x: float = 0.0   # Horizontal pixel offset from spray yaw
var snap_offset_y: float = 0.0   # Vertical pixel offset from spray pitch
var snap_lerp_speed: float = 20.0  # How fast the crosshair snaps to spray


func _ready() -> void:
        Global.aim_mode_changed.connect(_on_aim_mode_changed)
        Global.player_velocity_changed.connect(_on_player_velocity_changed)
        _setup_crosshair()


func _setup_crosshair() -> void:
        _update_crosshair_positions()


func _process(delta: float) -> void:
        # Smoothly interpolate to target spread
        current_spread = lerp(current_spread, target_spread, delta * 12.0)

        # Update reticle snap offset from weapon recoil when ADS
        _update_snap_offset(delta)

        _update_crosshair_positions()


func _update_snap_offset(delta: float) -> void:
        if not is_aiming:
                # When not ADS, snap offset decays back to zero
                snap_offset_x = lerp(snap_offset_x, 0.0, delta * snap_lerp_speed)
                snap_offset_y = lerp(snap_offset_y, 0.0, delta * snap_lerp_speed)
                return

        # Get the current weapon's recoil offsets
        var weapon = _get_current_weapon()
        if not weapon:
                return

        # Convert recoil degrees to pixel offset
        var pixels_per_degree = _get_pixels_per_degree()

        # The recoil_accumulated_pitch moves the crosshair UP (negative Y)
        # because vertical recoil kicks the camera up, so the bullet
        # impact point is above the center.
        # The recoil_accumulated_yaw moves the crosshair left/right.
        var target_y = -weapon.recoil_accumulated_pitch * pixels_per_degree
        var target_x = weapon.recoil_accumulated_yaw * pixels_per_degree

        # Smoothly interpolate snap for fluid feel
        snap_offset_x = lerp(snap_offset_x, target_x, delta * snap_lerp_speed)
        snap_offset_y = lerp(snap_offset_y, target_y, delta * snap_lerp_speed)


func _get_pixels_per_degree() -> float:
        # Calculate pixels per degree based on viewport and camera FOV.
        # For perspective projection:
        #   pixels_per_radian = viewport_height / (2 * tan(fov/2))
        #   pixels_per_degree = pixels_per_radian * (PI / 180)
        var camera = get_viewport().get_camera_3d()
        if not camera:
                # Fallback: assume 71° FOV at 1080p ≈ 15.2 px/deg
                return size.y / 71.0

        var fov_rad = deg_to_rad(camera.fov)
        # Explicit grouping prevents left-to-right evaluation traps:
        #   (viewport / denominator) * radians_to_degrees_factor
        var pixels_per_degree = (size.y / (2.0 * tan(fov_rad / 2.0))) * (PI / 180.0)
        return pixels_per_degree


func _get_current_weapon():
        if not Global.player:
                return null

        var weapons_manager = Global.player.get_node_or_null("WeaponsManager")
        if not weapons_manager or not weapons_manager.current_weapon:
                return null

        var weapon = weapons_manager.current_weapon
        if weapon.is_melee_weapon:
                return null

        return weapon


func _on_player_velocity_changed(velocity: Vector3) -> void:
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

        # ── ADS Reticle Snap ─────────────────────────────────────
        # When ADS, offset the crosshair center by the spray coordinates.
        # The crosshair detaches from screen center and snaps to
        # where the next bullet will actually land.
        center_x += snap_offset_x
        center_y += snap_offset_y

        # ── ADS Visual Style ─────────────────────────────────────
        # Use thinner lines and different dot size when ADS
        var line_w = ADS_LINE_WIDTH if is_aiming else LINE_WIDTH
        var line_l = ADS_LINE_LENGTH if is_aiming else LINE_LENGTH
        var dot_s = ADS_CENTER_DOT_SIZE if is_aiming else CENTER_DOT_SIZE

        # Top line
        crosshair_top.position = Vector2(center_x - line_w / 2.0, center_y - current_spread - line_l)
        crosshair_top.size = Vector2(line_w, line_l)

        # Bottom line
        crosshair_bottom.position = Vector2(center_x - line_w / 2.0, center_y + current_spread)
        crosshair_bottom.size = Vector2(line_w, line_l)

        # Left line
        crosshair_left.position = Vector2(center_x - current_spread - line_l, center_y - line_w / 2.0)
        crosshair_left.size = Vector2(line_l, line_w)

        # Right line
        crosshair_right.position = Vector2(center_x + current_spread, center_y - line_w / 2.0)
        crosshair_right.size = Vector2(line_l, line_w)

        # Center dot
        crosshair_center.position = Vector2(center_x - dot_s / 2.0, center_y - dot_s / 2.0)
        crosshair_center.size = Vector2(dot_s, dot_s)


func _on_aim_mode_changed(aim_mode: bool) -> void:
        is_aiming = aim_mode
        # NOTE: Crosshair stays VISIBLE in ADS mode now.
        # Instead of hiding, it snaps to spray coordinates (reticle snap).
        # The _update_crosshair_positions() function handles the visual
        # offset based on the weapon's accumulated recoil.
