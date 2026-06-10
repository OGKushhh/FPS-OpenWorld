extends Node3D

# ══════════════════════════════════════════════════════════════════
# WEAPON.GD — Valorant-Accurate Gun System
# Exponential spread decay, circular cone distribution,
# speed-ratio movement penalty, dual-stage recoil
# ══════════════════════════════════════════════════════════════════


# ── Weapon Type Classification ──────────────────────────────────
enum WeaponClass {
        SIDEARM,    # Pistols — cheap, backup
        SMG,        # Close quarters, run-and-gun
        RIFLE,      # Core precision weapons
        SHOTGUN,    # Tight angles, pellet spread
        SNIPER,     # Long range, scope required
        HEAVY       # LMGs — suppression, wall-bang
}

@export_group("weapon settings")
@export var is_melee_weapon: bool = false
@export var weapon_class: WeaponClass = WeaponClass.SIDEARM

#NOTE: projectiles work independetly/ see below for node paths
@export var is_projectile: bool = false
@export var firing_distance: float = 100.0

@export var fps_arms_root: Node3D

@export var animation_player: AnimationPlayer
@export var animation_fire: String = "_fire"
@export var animation_reload: String = "_reload"

@export_group("bullets")
@export var bullet_type: Bullets.AmmoType = Bullets.AmmoType.PISTOL
@export var damage: float = 40.0   # Base body damage (Vandal = 40)
@export var cooldown: float = 1.0
@export var burst_mode: bool = false
@export var consume: int = 1  # bullet use per firing (shotguns > 1)
@export var reload_required: bool = true
@export var mag_capacity: int = 30
@export var reload_time: float = 1.5

@export_group("gameplay connections")
@export var focused_aim_fov: float = 60.0

# Aim transition settings
const AIM_TRANSITION_DURATION: float = 0.2

@export_group("sfx")
@export var firing_sfx: AudioStreamPlayer3D
@export var reload_sfx: AudioStreamPlayer3D
@export var empty_mag_sfx: AudioStreamPlayer3D

@export_group("vfx")
@export var firing_vfx: PackedScene
@export var muzzle_flash_position: Marker3D
@export var bullet_decal: PackedScene
@export var tracer_enabled: bool = true
@export var tracer_color: Color = Color(1.0, 0.7, 0.15, 1.0)  # Warm orange-yellow
@export var tracer_scene: PackedScene  # Optional override; if empty, spawns procedurally

@onready var standard_aim_position: Marker3D = $StandardAimPosition
@onready var focused_aim_position: Marker3D = $FocusedAimPosition

var is_aimed: bool = false

# Weapon state variables
var can_fire: bool = true
var is_reloading: bool = false
var current_mag: int = 0
var played_empty_sound_this_press: bool = false

# References
var main_camera: Camera3D
var weapon_ray_cast: RayCast3D
var ray_cast_origin: Node3D

@onready var cooldown_timer: Timer = $CooldownTimer
@onready var reload_timer: Timer = $ReloadTimer

# Aim transition tween
var aim_tween: Tween


# ══════════════════════════════════════════════════════════════════
# RECOIL SYSTEM — Dual-Stage Valorant Pattern
# ══════════════════════════════════════════════════════════════════

@export_group("recoil")
# Bullets 1-N: Deterministic vertical climb (degrees per shot)
# Vandal pattern: first 5 bullets are predictable vertical kicks
@export var recoil_vertical_pattern: Array[float] = [0.3, 0.35, 0.4, 0.45, 0.5]

# Bullets 6+: Horizontal RNG sway parameters
@export var recoil_horizontal_max: float = 0.6   # Max degrees of horizontal sway
@export var recoil_sway_burst_length: int = 4      # Bullets per sway direction before switching
@export var recoil_vertical_sustain: float = 0.15  # Continued vertical climb after pattern (deg/shot)

# Recovery: how fast the camera returns after firing stops
@export var recoil_recovery_delay: float = 0.250    # Seconds before recovery begins (250ms)
@export var recoil_recovery_speed: float = 8.0      # How fast camera returns (higher = faster)

# Recoil multipliers
@export var recoil_ads_multiplier: float = 0.7      # ADS reduces recoil to this fraction
@export var recoil_crouch_multiplier: float = 0.8   # Crouching reduces recoil to this fraction

# ── Recoil Runtime State ─────────────────────────────────────────
var bullets_fired_in_spray: int = 0       # Resets when player stops firing
var current_sway_direction: float = 1.0   # +1 or -1, flips every burst_length bullets
var sway_bullets_remaining: int = 0       # Counter for current sway direction
var recoil_accumulated_pitch: float = 0.0 # Total vertical recoil offset on camera
var recoil_accumulated_yaw: float = 0.0   # Total horizontal recoil offset on camera
var recoil_recovery_timer: float = 0.0    # Counts up after firing stops
var is_recovering: bool = false           # True when camera is returning to center
var was_firing: bool = false              # Track firing state for recovery trigger


# ══════════════════════════════════════════════════════════════════
# ACCURACY / SPREAD SYSTEM — Valorant State-Based Thresholds
# ══════════════════════════════════════════════════════════════════
# Valorant does NOT use smooth linear scaling for movement penalties.
# It uses discrete state thresholds with flat penalties per state:
#   Standing (0-30% speed): base spread only
#   Walking  (30-55% speed): base + walking_error
#   Running  (55%+ speed):   base + running_error
#   Airborne:                base + airborne_error
# Bloom accumulates while firing, recovers ONLY after you stop.
# Bullet direction: circular cone via polar (tan(spread_rad), random angle)
# ══════════════════════════════════════════════════════════════════

@export_group("accuracy")
# Base spread when stationary (degrees) — Vandal = 0.25, Guardian = 0.1
@export var base_spread_standing: float = 0.25
@export var base_spread_ads: float = 0.05       # ADS near-perfect accuracy
@export var base_spread_crouch: float = 0.15    # Crouch tighter than standing

# Movement speed thresholds
@export var max_run_speed: float = 5.6           # m/s — player max walk speed
@export var velocity_deadzone_ratio: float = 0.30 # Below 30% of max speed = standing
@export var walk_threshold_ratio: float = 0.55    # Above 55% of max speed = running

# State-based flat movement penalties (degrees added ON TOP of base)
# These match Valorant's discrete threshold system
@export var walking_error_degrees: float = 2.0    # Walking penalty (30-55% speed)
@export var running_error_degrees: float = 5.0    # Running penalty (55%+ speed)
@export var airborne_error_degrees: float = 10.0  # Airborne = can't aim

# ADS reduces movement penalties by this fraction (0.5 = halved)
@export var move_error_ads_reduction: float = 0.5

# Per-shot spread increment during sustained fire (bloom)
# Each bullet adds this to the cone WHILE FIRING
# Bloom only recovers AFTER you stop firing
@export var firing_error_per_shot: float = 0.4   # Degrees added per bullet in spray

# Maximum total spread cap (degrees)
@export var max_spread_degrees: float = 5.0

# Exponential recovery constant (k in error *= e^(-k * delta))
# Only applies when NOT firing. Higher = faster recovery.
@export var recovery_constant: float = 12.0

# ── Accuracy Runtime State ───────────────────────────────────────
var current_bloom: float = 0.0     # Accumulated spray bloom (decays ONLY when not firing)
var is_firing: bool = false        # Tracks if player is actively firing
var is_player_crouching: bool = false
var is_player_sprinting: bool = false
var player_horizontal_velocity: float = 0.0
var player_airborne: bool = false


# ══════════════════════════════════════════════════════════════════
# DAMAGE SYSTEM — Valorant Hit Zones + Falloff
# ══════════════════════════════════════════════════════════════════

@export_group("damage")
# Direct damage per hit zone (Valorant Vandal baseline)
# Head 160 (one-taps 100/125/150 HP), Body 40, Legs 33
@export var damage_head: float = 160.0
@export var damage_body: float = 40.0
@export var damage_legs: float = 33.0

# Damage falloff over distance (meters)
@export var damage_falloff_start: float = 30.0   # Full damage up to here
@export var damage_falloff_end: float = 50.0     # Minimum damage beyond here
@export var damage_falloff_min_ratio: float = 0.7 # Min damage as ratio of base

# Wall penetration rating: 0=None, 1=Low, 2=Medium, 3=High
@export var penetration_rating: int = 1

# ── Damage Runtime ───────────────────────────────────────────────
enum HitZone { HEAD, BODY, LEGS }


# ══════════════════════════════════════════════════════════════════
# CAMERA RECOIL INTEGRATION
# ══════════════════════════════════════════════════════════════════

var camera_pivot_ref: Node3D   # References to player camera nodes for recoil
var camera_holder_ref: Node3D


# ══════════════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
        Global.aim_mode_changed.connect(_on_aim_mode_changed)
        Global.player_crouching_changed.connect(_on_player_crouching_changed)
        Global.player_sprinting_changed.connect(_on_player_sprinting_changed)
        Global.player_velocity_changed.connect(_on_player_velocity_changed)

        $TestCamera.visible = false
        $TestTarget.visible = false

        # Initialize magazine
        current_mag = mag_capacity

        # Initialize bloom
        current_bloom = 0.0


func _process(delta: float) -> void:
        # ── Recoil Recovery ───────────────────────────────────────
        if is_recovering:
                recoil_recovery_timer += delta
                if recoil_recovery_timer >= recoil_recovery_delay:
                        var old_pitch = recoil_accumulated_pitch
                        var old_yaw = recoil_accumulated_yaw
                        var recovery_rate = recoil_recovery_speed * delta
                        recoil_accumulated_pitch = move_toward(recoil_accumulated_pitch, 0.0, recovery_rate)
                        recoil_accumulated_yaw = move_toward(recoil_accumulated_yaw, 0.0, recovery_rate)

                        var pitch_delta = old_pitch - recoil_accumulated_pitch
                        var yaw_delta = old_yaw - recoil_accumulated_yaw
                        _apply_recoil_to_camera(-pitch_delta, -yaw_delta)

                        if abs(recoil_accumulated_pitch) < 0.01 and abs(recoil_accumulated_yaw) < 0.01:
                                recoil_accumulated_pitch = 0.0
                                recoil_accumulated_yaw = 0.0
                                is_recovering = false

        # ── Spread Bloom Recovery (Exponential Decay) ────────────
        # CRITICAL: Bloom only decays when NOT firing.
        # In Valorant, spread accumulates during a spray and only
        # recovers after you release the trigger. This is why spraying
        # creates a visible cone — the bloom stacks up shot after shot.
        if not is_firing and current_bloom > 0.0:
                current_bloom *= exp(-recovery_constant * delta)
                if current_bloom < 0.001:
                        current_bloom = 0.0

        # ── Airborne State Check ──────────────────────────────────
        if Global.player:
                player_airborne = not Global.player.is_on_floor()


func initialize(camera: Camera3D, raycast: RayCast3D, raycast_origin: Node3D) -> void:
        main_camera = camera
        weapon_ray_cast = raycast
        self.ray_cast_origin = raycast_origin

        if Global.player:
                camera_pivot_ref = Global.player.camera_pivot
                camera_holder_ref = Global.player.camera_holder


func activate(current_aim_mode: bool = false) -> void:
        visible = true
        can_fire = true
        is_reloading = false

        if aim_tween:
                aim_tween.kill()
                aim_tween = null

        if weapon_ray_cast:
                weapon_ray_cast.target_position = Vector3(0, 0, -firing_distance)

        is_aimed = current_aim_mode
        if fps_arms_root:
                if is_aimed:
                        fps_arms_root.transform = focused_aim_position.transform
                else:
                        fps_arms_root.transform = standard_aim_position.transform

        _reset_recoil()
        _reset_spread()

        if is_aimed:
                Global.active_camera_fov_changed.emit(focused_aim_fov)


func deactivate() -> void:
        visible = false


# ══════════════════════════════════════════════════════════════════
# FIRING
# ══════════════════════════════════════════════════════════════════

func try_fire(is_initial_press: bool = false) -> bool:
        if is_initial_press:
                played_empty_sound_this_press = false

        if not can_fire or is_reloading:
                return false

        if not is_melee_weapon:
                if reload_required and current_mag < consume:
                        start_reload()
                        if empty_mag_sfx and not played_empty_sound_this_press:
                                empty_mag_sfx.play()
                                played_empty_sound_this_press = true
                        return false

                var available_ammo = Bullets._get_ammo(bullet_type)
                if available_ammo != -1 and available_ammo < consume:
                        if empty_mag_sfx and not played_empty_sound_this_press:
                                empty_mag_sfx.play()
                                played_empty_sound_this_press = true
                        return false

        fire_weapon()
        return true


func fire_weapon() -> void:
        if not is_melee_weapon:
                if reload_required:
                        current_mag -= consume
                else:
                        if not Bullets._consume_ammo(bullet_type, consume):
                                return
                Global.bullets_changed.emit()

        if animation_player and animation_fire:
                animation_player.play(animation_fire)

        if firing_sfx:
                firing_sfx.play()

        # Muzzle flash VFX (ranged weapons only)
        if not is_melee_weapon and firing_vfx and muzzle_flash_position:
                var muzzle_instance = firing_vfx.instantiate()
                muzzle_flash_position.add_child(muzzle_instance)

        # ── Calculate Recoil Offsets ──────────────────────────────
        var recoil_pitch: float = 0.0
        var recoil_yaw: float = 0.0

        if not is_melee_weapon:
                # Mark as firing — bloom will NOT decay while this is true
                is_firing = true

                recoil_pitch = _get_recoil_pitch()
                recoil_yaw = _get_recoil_yaw()

                if is_aimed:
                        recoil_pitch *= recoil_ads_multiplier
                        recoil_yaw *= recoil_ads_multiplier
                if is_player_crouching:
                        recoil_pitch *= recoil_crouch_multiplier
                        recoil_yaw *= recoil_crouch_multiplier

                recoil_accumulated_pitch += recoil_pitch
                recoil_accumulated_yaw += recoil_yaw

                _apply_recoil_to_camera(recoil_pitch, recoil_yaw)

                is_recovering = false
                recoil_recovery_timer = 0.0
                was_firing = true

                bullets_fired_in_spray += 1

        # ── Calculate Total Spread for This Shot ──────────────────
        var total_spread: float = calculate_current_spread()

        # ── Perform Hitscan with Circular Cone Distribution ───────
        if weapon_ray_cast and ray_cast_origin and main_camera:
                # Circular cone spread using polar coordinates
                # tan(spread_rad) maps the angle onto a unit disk,
                # then random polar angle + radius gives uniform distribution
                var shoot_direction = _calculate_spread_direction(total_spread)

                # Use direct space state raycast instead of rotated RayCast3D node
                # This avoids the square distribution problem entirely
                var space_state = get_world_3d().direct_space_state
                var ray_start = main_camera.global_position
                var ray_end = ray_start + shoot_direction * firing_distance

                var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
                # Exclude player collision
                if Global.player:
                        query.exclude = [Global.player.get_rid()]

                var result = space_state.intersect_ray(query)

                # For tracer: direction from muzzle toward the hit point or max range
                var bullet_dir = shoot_direction
                var tracer_start: Vector3 = muzzle_flash_position.global_position if muzzle_flash_position else ray_cast_origin.global_position
                var tracer_end: Vector3

                if result:
                        var hit_point = result.position
                        var hit_normal = result.normal if result.has("normal") else Vector3.UP
                        var collider = result.collider
                        tracer_end = hit_point

                        # Bullet decal
                        if not is_melee_weapon and bullet_decal:
                                var decal_instance = bullet_decal.instantiate()
                                get_tree().root.add_child(decal_instance)
                                decal_instance.global_position = hit_point
                                var up_vector = Vector3.UP
                                if abs(hit_normal.dot(Vector3.UP)) > 0.99:
                                        up_vector = Vector3.FORWARD
                                decal_instance.look_at(hit_point + hit_normal, up_vector)

                        # Damage
                        if collider and collider.has_method("get_damage"):
                                var direction = (hit_point - global_position).normalized()
                                var distance = global_position.distance_to(hit_point)
                                var hit_zone = HitZone.BODY  # TODO: detect from bone/collider
                                var final_damage = _calculate_damage(distance, hit_zone)
                                collider.get_damage(final_damage, direction)
                else:
                        # Miss — tracer goes to max distance
                        tracer_end = tracer_start + bullet_dir * firing_distance

                # Spawn bullet tracer
                if not is_melee_weapon and tracer_enabled:
                        _spawn_tracer(tracer_start, tracer_end)

        # ── Increase Bloom Per Shot ───────────────────────────────
        # Each bullet adds firing_error_per_shot degrees to the cone, clamped to max
        if not is_melee_weapon:
                current_bloom = min(current_bloom + firing_error_per_shot, max_spread_degrees)

        # Start cooldown
        can_fire = false
        cooldown_timer.start(cooldown)

        # Camera shake
        Global.camera_shake.emit()


func _on_cooldown_timer_timeout() -> void:
        can_fire = true

        if not Input.is_action_pressed("fire"):
                _begin_recoil_recovery()


# ══════════════════════════════════════════════════════════════════
# RECOIL CALCULATION
# ══════════════════════════════════════════════════════════════════

func _get_recoil_pitch() -> float:
        var pattern_size = recoil_vertical_pattern.size()

        if bullets_fired_in_spray < pattern_size:
                return recoil_vertical_pattern[bullets_fired_in_spray]
        else:
                return recoil_vertical_sustain


func _get_recoil_yaw() -> float:
        var pattern_size = recoil_vertical_pattern.size()

        if bullets_fired_in_spray < pattern_size:
                return randf_range(-0.05, 0.05)

        if sway_bullets_remaining <= 0:
                current_sway_direction = 1.0 if randf() > 0.5 else -1.0
                sway_bullets_remaining = recoil_sway_burst_length + randi_range(-1, 1)

        sway_bullets_remaining -= 1

        var yaw_offset = current_sway_direction * randf_range(recoil_horizontal_max * 0.3, recoil_horizontal_max)
        return yaw_offset


func _apply_recoil_to_camera(pitch_offset: float, yaw_offset: float) -> void:
        if not camera_pivot_ref or not camera_holder_ref:
                return

        camera_holder_ref.rotate_x(-pitch_offset)
        camera_pivot_ref.rotate_y(-yaw_offset)

        camera_holder_ref.rotation.x = clamp(
                camera_holder_ref.rotation.x,
                deg_to_rad(-89),
                deg_to_rad(89)
        )


func _begin_recoil_recovery() -> void:
        if abs(recoil_accumulated_pitch) > 0.01 or abs(recoil_accumulated_yaw) > 0.01:
                is_recovering = true
                recoil_recovery_timer = 0.0
        was_firing = false


func _reset_recoil() -> void:
        recoil_accumulated_pitch = 0.0
        recoil_accumulated_yaw = 0.0
        bullets_fired_in_spray = 0
        sway_bullets_remaining = 0
        current_sway_direction = 1.0
        is_recovering = false
        recoil_recovery_timer = 0.0
        was_firing = false
        is_firing = false


# ══════════════════════════════════════════════════════════════════
# ACCURACY / SPREAD CALCULATION — Valorant Math
# ══════════════════════════════════════════════════════════════════

func _get_base_spread() -> float:
        # Base first-shot error depends on stance
        if is_aimed:
                return base_spread_ads
        if is_player_crouching and not player_airborne:
                return base_spread_crouch
        return base_spread_standing


func calculate_current_spread() -> float:
        # Valorant state-based threshold system:
        #   Standing (0-30% speed):  base only
        #   Walking  (30-55% speed): base + walking_error
        #   Running  (55%+ speed):   base + running_error
        #   Airborne:                base + airborne_error
        # Bloom from sustained fire is added on top of everything.
        # This creates the instant accuracy drop on counter-strafe —
        # the moment velocity drops below 30%, penalty goes to zero.

        var base: float = _get_base_spread()

        # Calculate speed as percentage of max run speed
        var speed_percentage = player_horizontal_velocity / max_run_speed

        # State-based movement penalty (flat values per state)
        var movement_penalty: float = 0.0

        if player_airborne:
                # STATE: AIRBORNE — massive penalty regardless of speed
                movement_penalty = airborne_error_degrees
        elif speed_percentage > walk_threshold_ratio:
                # STATE: RUNNING — above 55% of max speed
                movement_penalty = running_error_degrees
        elif speed_percentage > velocity_deadzone_ratio:
                # STATE: WALKING — between 30% and 55% of max speed
                movement_penalty = walking_error_degrees
        # else: STATE: STANDING — below 30%, no movement penalty

        # ADS reduces movement penalties
        if is_aimed:
                movement_penalty *= move_error_ads_reduction

        # Crouch reduces movement penalties (separate from base spread)
        if is_player_crouching and not player_airborne:
                movement_penalty *= 0.6

        # Total = base + movement_penalty + bloom
        var total_spread = base + movement_penalty + current_bloom

        return clamp(total_spread, 0.0, max_spread_degrees)


func _calculate_spread_direction(spread_degrees: float) -> Vector3:
        # Circular cone distribution using polar coordinates
        # This replaces the old square randf_range(-spread, spread) on X and Y
        # which created a square hit distribution instead of circular
        #
        # Math: Project spread angle onto a unit disk using tan(spread_rad),
        # then pick a random point on that disk via polar coordinates.
        # This gives uniform distribution within the cone, matching Valorant.

        var camera = main_camera
        if not camera:
                camera = get_viewport().get_camera_3d()
        if not camera:
                return -global_transform.basis.z

        var forward = -camera.global_transform.basis.z  # -Z is forward in Godot
        var spread_rad = deg_to_rad(spread_degrees)

        # Random point on a disk of radius tan(spread_rad)
        var rand_radius = randf_range(0.0, tan(spread_rad))
        var rand_angle = randf_range(0.0, 2.0 * PI)

        var right = camera.global_transform.basis.x
        var up = camera.global_transform.basis.y

        # Displace the forward direction by the random disk offset
        var displacement = (right * cos(rand_angle) + up * sin(rand_angle)) * rand_radius
        return (forward + displacement).normalized()


func _reset_spread() -> void:
        current_bloom = 0.0


# ══════════════════════════════════════════════════════════════════
# DAMAGE CALCULATION — Per Hit Zone + Distance Falloff
# ══════════════════════════════════════════════════════════════════

func _calculate_damage(distance: float, hit_zone: HitZone = HitZone.BODY) -> float:
        # Pick base damage by hit zone (Valorant: head 160, body 40, legs 33)
        var base_damage: float
        match hit_zone:
                HitZone.HEAD:
                        base_damage = damage_head
                HitZone.LEGS:
                        base_damage = damage_legs
                HitZone.BODY:
                        base_damage = damage_body

        # Distance falloff
        if distance > damage_falloff_start:
                var falloff_range = damage_falloff_end - damage_falloff_start
                var falloff_t = clamp((distance - damage_falloff_start) / falloff_range, 0.0, 1.0)
                var min_damage = base_damage * damage_falloff_min_ratio
                base_damage = lerpf(base_damage, min_damage, falloff_t)

        return base_damage


# ══════════════════════════════════════════════════════════════════
# RELOAD
# ══════════════════════════════════════════════════════════════════

func start_reload() -> void:
        if is_reloading or not reload_required:
                return

        var available_ammo = Bullets._get_ammo(bullet_type)
        if available_ammo <= 0 and available_ammo != -1:
                return

        is_reloading = true

        if animation_player and animation_reload:
                animation_player.play(animation_reload)

        if reload_sfx:
                reload_sfx.play()

        reload_timer.start(reload_time)


func _on_reload_timer_timeout() -> void:
        is_reloading = false

        var ammo_needed = mag_capacity - current_mag
        var available_ammo = Bullets._get_ammo(bullet_type)

        if available_ammo == -1:
                current_mag = mag_capacity
        else:
                var ammo_to_load = min(ammo_needed, available_ammo)
                Bullets._consume_ammo(bullet_type, ammo_to_load)
                current_mag += ammo_to_load

        Global.bullets_changed.emit()


# ══════════════════════════════════════════════════════════════════
# BULLET TRACERS
# ══════════════════════════════════════════════════════════════════

func _spawn_tracer(start: Vector3, end: Vector3) -> void:
        if tracer_scene:
                var instance = tracer_scene.instantiate()
                get_tree().root.add_child(instance)
                if instance.has_method("setup"):
                        instance.setup(start, end, tracer_color)
        else:
                var tracer_script = load("res://common/vfx/bullet_tracer/bullet_tracer.gd")
                var tracer_node = Node3D.new()
                tracer_node.set_script(tracer_script)
                get_tree().root.add_child(tracer_node)
                tracer_node.setup(start, end, tracer_color)


# ══════════════════════════════════════════════════════════════════
# PLAYER STATE TRACKING
# ══════════════════════════════════════════════════════════════════

func _on_player_crouching_changed(crouching: bool) -> void:
        is_player_crouching = crouching


func _on_player_sprinting_changed(sprinting: bool) -> void:
        is_player_sprinting = sprinting


func _on_player_velocity_changed(velocity: Vector3) -> void:
        player_horizontal_velocity = Vector2(velocity.x, velocity.z).length()

        # Detect fire release for recoil recovery + bloom decay
        if was_firing and not Input.is_action_pressed("fire"):
                is_firing = false  # Bloom can now start decaying
                _begin_recoil_recovery()


# ══════════════════════════════════════════════════════════════════
# AIM MODE
# ══════════════════════════════════════════════════════════════════

func _on_aim_mode_changed(aim_mode: bool) -> void:
        if not visible:
                return

        is_aimed = aim_mode

        if aim_tween:
                aim_tween.kill()

        if fps_arms_root:
                aim_tween = create_tween()
                aim_tween.set_parallel(true)
                aim_tween.set_ease(Tween.EASE_IN_OUT)
                aim_tween.set_trans(Tween.TRANS_CUBIC)

                var target_transform = focused_aim_position.transform if aim_mode else standard_aim_position.transform
                aim_tween.tween_property(fps_arms_root, "transform", target_transform, AIM_TRANSITION_DURATION)

        if aim_mode:
                Global.active_camera_fov_changed.emit(focused_aim_fov)
                if Global.debug_mode:
                        print("AIM MODE: ", aim_mode, " - Weapon: ", name, " - FOV: ", focused_aim_fov)


# ══════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════

func get_current_mag() -> int:
        if is_melee_weapon:
                return -1
        return current_mag


func get_current_ammo() -> int:
        if is_melee_weapon:
                return -1
        return Bullets._get_ammo(bullet_type)


func get_max_ammo() -> int:
        if is_melee_weapon:
                return -1
        return Bullets._get_max_ammo(bullet_type)
