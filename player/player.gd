extends CharacterBody3D


# ── Movement Speeds (Valorant-inspired) ──────────────────────────
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 10.0
@export var crouch_speed: float = 2.2      # Valorant crouch speed
@export var jump_velocity: float = 6.0
var speed: float = 0.0
const GRAVITY: float = -20

# ── Mouse Look System (Native Godot) ───────────────────────────
# Sensitivity is in native radians-per-pixel — no engine conversion needed.
# Default 0.0015 ≈ comfortable mid-range sensitivity for 800–1600 DPI.
# Adjust this value directly; it maps 1:1 to Godot's rotation math.
@export_group("Mouse Look")
@export var sensitivity: float = 0.0015

# Sub-pixel rotation accumulators
# These prevent rounding micro-stutters by caching the full-precision
# rotation state in raw floats, then applying to nodes once per frame.
# Without accumulators, repeated rotate_y()/rotate_x() calls compound
# floating-point errors that feel like pixel-skipping at high DPI.
var rotation_yaw: float = 0.0
var rotation_pitch: float = 0.0

# Pitch limits (radians) — 89° prevents camera flipping
const PITCH_LIMIT: float = deg_to_rad(89.0)

# Hipfire FOV reference for focal length scaling
# Reads from active_camera.gd's BASE_FOV constant
var hipfire_fov: float = 71.0

# Camera shake offset (set by active_camera.gd, applied by accumulators)
# This replaces the old Tween-based shake that fought with the accumulator
# pipeline. Now shake flows through the same rotation path as mouse + recoil.
var shake_pitch: float = 0.0
var shake_yaw: float = 0.0

var inertia_air: float = 7.5
var inertia_ground: float = 10.0

# ── Crouch Parameters ────────────────────────────────────────────
const CROUCH_TRANSITION_SPEED: float = 10.0   # How fast the player crouches/uncrouches
const STANDING_HEIGHT: float = 1.7            # Camera pivot Y when standing
const CROUCHING_HEIGHT: float = 1.0           # Camera pivot Y when crouching
const STANDING_COLLISION_HEIGHT: float = 1.8  # Collision capsule height standing
const CROUCHING_COLLISION_HEIGHT: float = 1.1 # Collision capsule height crouching

var is_crouching: bool = false
var crouch_input_held: bool = false

# ── Head Bob ─────────────────────────────────────────────────────
# Subtle bob for movement feedback. Disabled entirely during ADS
# because even tiny position shifts at zoom feel like aim flicking.
# Smoothly decays to zero when not moving so camera never freezes
# at a weird offset.
const BOB_FREQ: float = 2.0
const BOB_AMP: float = 0.03     # 3cm — subtle, tactical shooter feel
var t_bob: float = 0.0
var bob_active: bool = false   # Tracks whether bob should be running

var is_aiming: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_holder: Node3D = $CameraPivot/CameraHolder
@onready var camera: Camera3D = %MainCamera
@onready var audio_manager: Node3D = $AudioManager
@onready var weapons_manager: Node3D = $WeaponsManager
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@export var weapon: Node3D
var walk_anim: float = 0.0
var sprint_anim: float = 0.0

# Animation blend speeds
const ANIM_BLEND_SPEED: float = 20.0

# Audio tracking
var was_on_floor: bool = false
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL_WALK: float = 0.5
const FOOTSTEP_INTERVAL_SPRINT: float = 0.3
const FOOTSTEP_INTERVAL_CROUCH: float = 0.7

# ── Health ───────────────────────────────────────────────────────
const MAX_HEALTH: float = 100.0
var current_health: float = 100.0
var is_alive: bool = true
const HIT_STAGGER: float = 40.0

# ── Velocity Tracking (for weapon accuracy system) ───────────────
var horizontal_velocity: float = 0.0  # Magnitude of XZ velocity
const VELOCITY_DEADZONE: float = 1.65 # Below this = "stationary" for accuracy (27.5% of sprint)


func _ready() -> void:
        Global.player = self
        Global.aim_mode_changed.connect(_on_aim_mode_changed)

        # Initialize rotation accumulators from current node rotations
        # This prevents a snap/jump on first mouse move
        rotation_yaw = camera_pivot.rotation.y
        rotation_pitch = camera_holder.rotation.x


func _input(event: InputEvent) -> void:
        # Mouse look runs in _input() — NOT _physics_process().
        # _input() fires asynchronously from the OS event queue, independent
        # of the game's framerate or physics tick rate. A player on 240Hz
        # gets 240 camera updates/sec even though physics runs at 128Hz.
        # This is the #1 requirement for smooth competitive aim feel.
        if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
                # Calculate effective sensitivity with focal length scaling
                var effective_sensitivity = sensitivity

                if is_aiming:
                        # Focal Length Sensitivity Scaling (0% Monitor Distance Match)
                        # When zoomed, objects traverse more screen pixels per degree.
                        # If sensitivity stayed the same, aim would feel too fast.
                        # This formula slows the mouse to perfectly match the visual
                        # compression of the new FOV — muscle memory stays 1:1.
                        #
                        #   coefficient = tan(ADS_FOV / 2) / tan(Hip_FOV / 2)
                        #
                        # Reading live camera.fov means sensitivity transitions
                        # smoothly during the FOV lerp — no sudden snap.
                        var current_fov = camera.fov
                        if current_fov > 0.0 and hipfire_fov > 0.0:
                                var ads_fov_rad = deg_to_rad(current_fov)
                                var hip_fov_rad = deg_to_rad(hipfire_fov)
                                var focal_coefficient = tan(ads_fov_rad / 2.0) / tan(hip_fov_rad / 2.0)
                                effective_sensitivity = sensitivity * focal_coefficient

                # 1. Accumulate into raw float variables FIRST
                #    This preserves sub-pixel precision that would be lost
                #    if we called rotate_y()/rotate_x() directly each frame.
                rotation_yaw -= event.relative.x * effective_sensitivity
                rotation_pitch -= event.relative.y * effective_sensitivity

                # 2. Clamp vertical pitch to prevent camera flipping
                rotation_pitch = clamp(rotation_pitch, -PITCH_LIMIT, PITCH_LIMIT)

                # 3. Apply the precise accumulated values + shake offset to camera nodes
                camera_pivot.rotation.y = rotation_yaw + shake_yaw
                camera_holder.rotation.x = rotation_pitch + shake_pitch


func _physics_process(delta: float) -> void:
        # Add the gravity
        if not is_on_floor():
                velocity.y += GRAVITY * delta

        # Detect landing from air
        if is_on_floor() and not was_on_floor:
                if audio_manager:
                        audio_manager.play_footstep(true)

        # Update floor state tracker
        was_on_floor = is_on_floor()

        # Handle jump (can't jump while crouching)
        if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
                velocity.y = jump_velocity

        # Handle crouch input
        crouch_input_held = Input.is_action_pressed("crouch")

        # Handle sprint (can't sprint while crouching or aiming)
        if Input.is_action_pressed("sprint") and not is_crouching:
                handle_sprint()
        else:
                handle_walk()

        # Handle crouch state transitions
        _handle_crouch(delta)

        # Movement direction
        var input_dir := Input.get_vector("left", "right", "forward", "backward")
        var direction := (camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

        if is_on_floor():
                if direction:
                        velocity.x = direction.x * speed
                        velocity.z = direction.z * speed
                else:
                        # BUG FIX: Was using direction.x for Z axis deceleration
                        velocity.x = lerp(velocity.x, direction.x * speed, delta * inertia_ground)
                        velocity.z = lerp(velocity.z, direction.z * speed, delta * inertia_ground)
        else:
                velocity.x = lerp(velocity.x, direction.x * speed, delta * inertia_air)
                velocity.z = lerp(velocity.z, direction.z * speed, delta * inertia_air)

        # Head bob — disabled during ADS, decays to zero when stopped.
        # We lerp the OUTPUT position toward zero rather than the timer —
        # lerping t_bob caused sin() phase jumps that looked like a camera
        # hiccup when entering ADS mid-stride.
        var should_bob = is_on_floor() and velocity.length() > 0.5 and not is_aiming

        if should_bob:
                var bob_multiplier = 0.5 if is_crouching else 1.0
                t_bob += velocity.length() * delta * bob_multiplier
                bob_active = true
                camera_holder.transform.origin = _headbob(t_bob)
        else:
                # Smoothly decay the camera position back to zero.
                # Decay speed 12 feels fast enough to not linger but slow enough
                # to not snap — important when entering ADS while running.
                var current_bob = camera_holder.transform.origin
                camera_holder.transform.origin = current_bob.lerp(Vector3.ZERO, delta * 12.0)
                if camera_holder.transform.origin.length() < 0.0005:
                        camera_holder.transform.origin = Vector3.ZERO
                        bob_active = false
                        t_bob = 0.0

        # Handle footstep sounds
        _handle_footsteps(delta)

        # Track horizontal velocity for weapon accuracy calculations
        horizontal_velocity = Vector2(velocity.x, velocity.z).length()

        # Emit velocity for crosshair + weapon accuracy
        Global.player_velocity_changed.emit(velocity)

        move_and_slide()


func _handle_crouch(delta: float) -> void:
        # Determine desired crouch state
        var wants_crouch = crouch_input_held

        if wants_crouch and not is_crouching:
                # Enter crouch
                is_crouching = true
                Global.player_crouching_changed.emit(true)
        elif not wants_crouch and is_crouching:
                # Try to stand up — check if there's room above
                if not _is_head_blocked():
                        is_crouching = false
                        Global.player_crouching_changed.emit(false)

        # Smooth camera height transition
        var target_height = CROUCHING_HEIGHT if is_crouching else STANDING_HEIGHT
        camera_pivot.position.y = lerp(camera_pivot.position.y, target_height, delta * CROUCH_TRANSITION_SPEED)

        # Smooth collision shape height transition
        if collision_shape and collision_shape.shape is CapsuleShape3D:
                var target_collision_height = CROUCHING_COLLISION_HEIGHT if is_crouching else STANDING_COLLISION_HEIGHT
                var capsule = collision_shape.shape as CapsuleShape3D
                capsule.height = lerp(capsule.height, target_collision_height, delta * CROUCH_TRANSITION_SPEED)


func _is_head_blocked() -> bool:
        # Raycast upward to check if we can stand up
        var space_state = get_world_3d().direct_space_state
        var ray_origin = global_position + Vector3.UP * CROUCHING_COLLISION_HEIGHT * 0.5
        var ray_end = global_position + Vector3.UP * STANDING_COLLISION_HEIGHT
        var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
        query.exclude = [self.get_rid()]
        var result = space_state.intersect_ray(query)
        return result.size() > 0


func _handle_footsteps(delta: float) -> void:
        # Only play footsteps when on ground and moving
        if is_on_floor() and velocity.length() > 0.1:
                footstep_timer -= delta

                if footstep_timer <= 0.0:
                        # Determine interval based on movement state
                        var interval: float
                        if is_crouching:
                                interval = FOOTSTEP_INTERVAL_CROUCH
                        elif Input.is_action_pressed("sprint"):
                                interval = FOOTSTEP_INTERVAL_SPRINT
                        else:
                                interval = FOOTSTEP_INTERVAL_WALK
                        footstep_timer = interval

                        # Play footstep (not a jump landing)
                        if audio_manager:
                                audio_manager.play_footstep(false)
        else:
                # Reset timer when not moving
                footstep_timer = 0.0


func handle_walk() -> void:
        if is_crouching:
                speed = crouch_speed
        else:
                speed = walk_speed
        Global.player_sprinting_changed.emit(false)


func handle_sprint() -> void:
        # Prohibit sprinting when in aim mode or crouching
        if is_aiming or is_crouching:
                handle_walk()
                return

        speed = sprint_speed
        Global.player_sprinting_changed.emit(true)


func _on_aim_mode_changed(aim_mode: bool) -> void:
        is_aiming = aim_mode
        # If we were sprinting and now aiming, revert to walk speed
        if aim_mode and Input.is_action_pressed("sprint"):
                handle_walk()


func _headbob(time) -> Vector3:
        var pos = Vector3.ZERO
        pos.y = sin(time * BOB_FREQ) * BOB_AMP
        pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
        return pos


func get_damage(damage: float, direction: Vector3, is_enemy_damage: bool = false) -> void:
        current_health -= damage
        if current_health < 0.0:
                current_health = 0.0
                is_alive = false
                Global.player_dead.emit()
        else:
                velocity += direction * HIT_STAGGER
        Global.player_health_changed.emit(-damage, current_health, MAX_HEALTH, is_enemy_damage)
