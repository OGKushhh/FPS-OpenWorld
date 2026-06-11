extends Node3D

@onready var ray_cast_origin: Node3D = $RayCastOrigin
@onready var weapon_ray_cast: RayCast3D = $RayCastOrigin/WeaponRayCast
@onready var main_camera: Camera3D = %MainCamera

# Smooth follow settings
@export var follow_speed: float = 60.0

# Weapon index for switching
#INFO: AVAILABLE_WEAPONS - Pistol is index 0 (default starting weapon)
@export var weapons_array: Array[Node3D] = []
var current_weapon_index: int = 0
var current_weapon: Node3D

# Track aim mode state
var current_aim_mode: bool = false

# Weapon switch state
var is_switching: bool = false
var switch_tween: Tween

# Track fire input for spray reset detection
var was_firing_last_frame: bool = false

# Weapon wheel HUD
var weapon_wheel: Control

# ── Strafe Tilt ──────────────────────────────────────────────────
# Weapon rolls on Z when strafing left/right — purely visual,
# does not affect the raycast or accuracy math.
const TILT_MAX_DEGREES: float = 4.0     # Max roll angle at full strafe speed
const TILT_SPEED: float = 8.0           # How fast tilt tracks input
var current_tilt: float = 0.0           # Current smoothed tilt value (degrees)

# ── Idle Breathing ───────────────────────────────────────────────
# Slow sinusoidal drift on the weapon rig local position.
# Purely cosmetic — muzzle_flash_position and raycast are unaffected.
const BREATHE_FREQ: float = 0.4         # Cycles per second (slow, relaxed)
const BREATHE_AMP_Y: float = 0.0018    # Vertical drift amplitude (metres)
const BREATHE_AMP_X: float = 0.0010    # Horizontal drift amplitude (metres)
var breathe_time: float = 0.0           # Running timer
var breathe_active: bool = true         # Disabled during ADS


func _ready() -> void:
        # Start with pistol (index 0)
        current_weapon_index = 0
        _setup_current_weapon()

        # Connect to input signals
        Global.fire_input.connect(_on_fire_input)
        Global.reload_input.connect(_on_reload_input)
        Global.weapon_switch_next.connect(switch_to_next_weapon)
        Global.weapon_switch_prev.connect(switch_to_previous_weapon)
        Global.aim_mode_changed.connect(_on_aim_mode_changed)

        # Create weapon wheel and add to viewport so it renders as overlay
        _create_weapon_wheel()


func _setup_current_weapon() -> void:
        current_weapon = weapons_array[current_weapon_index]

        # Initialize all weapons
        for weapon in weapons_array:
                weapon.initialize(main_camera, weapon_ray_cast, ray_cast_origin)
                weapon.deactivate()

        # Activate current weapon (pistol) with current aim mode
        current_weapon.activate(current_aim_mode)


func _create_weapon_wheel() -> void:
        # Instantiate the weapon wheel control and add it to the root viewport
        # so it renders as a full-screen overlay independent of the 3D scene
        var wheel_script = load("res://common/hud/weapon_wheel.gd")
        weapon_wheel = Control.new()
        weapon_wheel.set_script(wheel_script)
        weapon_wheel.name = "WeaponWheel"
        # Full-rect anchors to cover entire screen
        weapon_wheel.anchor_right = 1.0
        weapon_wheel.anchor_bottom = 1.0
        get_tree().root.add_child(weapon_wheel)
        # Connect the wheel's selection signal to our switch_weapon method
        weapon_wheel.weapon_selected.connect(switch_weapon)


func _process(_delta: float) -> void:
        # Smoothly interpolate position and rotation to follow camera
        var target_transform = main_camera.global_transform

        # Lerp position
        global_position = global_position.lerp(target_transform.origin, follow_speed * _delta)

        # Slerp rotation (spherical linear interpolation for smooth rotation)
        var current_basis = global_transform.basis
        var target_basis = target_transform.basis
        global_transform.basis = current_basis.slerp(target_basis, follow_speed * _delta)

        # ── Strafe Tilt (Fix 2) ───────────────────────────────────────
        # Roll the weapon rig on Z based on horizontal input direction.
        # Left strafe → positive roll (weapon tilts right), right → negative.
        # Purely visual: the raycast origin is a child of the camera, not
        # this node, so accuracy math is completely unaffected.
        var strafe_input = Input.get_action_strength("left") - Input.get_action_strength("right")
        var target_tilt = strafe_input * TILT_MAX_DEGREES
        # Snap to zero faster in ADS so tilt doesn't fight with the clean ADS look
        var tilt_speed = TILT_SPEED * (0.5 if current_aim_mode else 1.0)
        current_tilt = lerp(current_tilt, target_tilt, _delta * tilt_speed)
        rotation_degrees.z = current_tilt

        # ── Idle Breathing (Fix 5) ────────────────────────────────────
        # Slow sinusoidal drift on the rig's local position while standing.
        # Disabled in ADS (would visually fight the locked sight picture)
        # and during weapon switch (tween owns rotation during that window).
        if breathe_active and not is_switching:
                breathe_time += _delta
                var drift_y = sin(breathe_time * breathe_freq_scaled() * TAU) * BREATHE_AMP_Y
                var drift_x = cos(breathe_time * breathe_freq_scaled() * TAU * 0.5) * BREATHE_AMP_X
                # Apply as a local position offset — doesn't touch rotation or the
                # follow lerp above because we write to position directly each frame.
                position += Vector3(drift_x, drift_y, 0.0) * 0.016  # scale by nominal dt
        elif not breathe_active:
                # Decay any residual drift back to zero when ADS
                pass  # Follow lerp above already pulls position to camera origin

        # Continuous firing for automatic weapons (burst mode)
        # Pass false to indicate this is NOT the initial press
        if Input.is_action_pressed("fire") and current_weapon.burst_mode:
                current_weapon.try_fire(false)

        # Detect when player stops holding fire for spray counter reset
        var fire_held = Input.is_action_pressed("fire")
        if was_firing_last_frame and not fire_held:
                # Player just released fire — reset spray counter and begin recoil recovery
                current_weapon.bullets_fired_in_spray = 0
                current_weapon.sway_bullets_remaining = 0
                current_weapon._begin_recoil_recovery()
        was_firing_last_frame = fire_held


func breathe_freq_scaled() -> float:
        # Slightly faster breathing when moving (exertion) — subtle but natural
        if Global.player and Global.player.velocity.length() > 1.0:
                return BREATHE_FREQ * 1.4
        return BREATHE_FREQ


func _on_fire_input() -> void:
        # This is called on initial press, so pass true
        current_weapon.try_fire(true)


func _on_reload_input() -> void:
        if current_weapon.is_melee_weapon:
                return
        current_weapon.start_reload()


func _on_aim_mode_changed(aim_mode: bool) -> void:
        # Update tracked aim mode
        current_aim_mode = aim_mode

        # Disable idle breathing in ADS — drift looks wrong against a locked sight picture
        breathe_active = not aim_mode

        # The weapon will handle its own animation through its connected signal
        # No need to do anything else here as each weapon is connected to the global signal


# Weapon switching functions
func switch_to_next_weapon() -> void:
        if current_weapon.is_reloading:
                return
        var next_index = (current_weapon_index + 1) % weapons_array.size()
        switch_weapon(next_index)


func switch_to_previous_weapon() -> void:
        if current_weapon.is_reloading:
                return
        var prev_index = (current_weapon_index - 1 + weapons_array.size()) % weapons_array.size()
        switch_weapon(prev_index)


func switch_weapon(index: int) -> void:
        if index < 0 or index >= weapons_array.size():
                return
        if index == current_weapon_index and not is_switching:
                return

        # Kill any in-progress tween to prevent stale callbacks running
        if switch_tween:
                switch_tween.kill()

        # Deactivate ALL weapons immediately — prevents double-visibility on rapid scroll
        for weapon in weapons_array:
                weapon.deactivate()

        # Update the reference now so rapid calls always operate on the correct weapon
        current_weapon_index = index
        current_weapon = weapons_array[current_weapon_index]
        is_switching = true

        switch_tween = create_tween()
        switch_tween.set_ease(Tween.EASE_IN_OUT)
        switch_tween.set_trans(Tween.TRANS_SINE)

        # Rotate down to -30 degrees (0.2s)
        switch_tween.tween_property(self, "rotation_degrees:x", -30.0, 0.2)

        # Activate the new weapon at the lowest point of the animation
        switch_tween.tween_callback(func():
                current_weapon.activate(current_aim_mode)
                Global.bullets_changed.emit()
        )

        # Rotate up to 10 degrees (0.2s)
        switch_tween.tween_property(self, "rotation_degrees:x", 10.0, 0.2)

        # Return to 0 degrees (0.1s)
        switch_tween.tween_property(self, "rotation_degrees:x", 0.0, 0.1)

        switch_tween.tween_callback(func():
                is_switching = false
        )


# Helper functions to get weapon state
func get_current_mag() -> int:
        return current_weapon.get_current_mag()


func get_current_ammo() -> int:
        return current_weapon.get_current_ammo()


func get_max_ammo() -> int:
        return current_weapon.get_max_ammo()
