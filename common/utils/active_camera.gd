extends Node3D

# Camera shake — flows through player's rotation accumulators
# Instead of tweening camera_holder.rotation directly (which fights with
# the accumulator pipeline in player.gd), we set shake offsets on the
# player node. These get applied in player.gd's _input() alongside
# rotation_pitch/rotation_yaw, so there's zero conflict.
@export var shake_intensity: float = 0.02
@export var shake_duration: float = 0.1

# FOV management
const BASE_FOV: float = 71.0  # 71° vertical ≈ 103° horizontal at 16:9 (Valorant default)
const SPRINT_FOV: float = 82.0  # Slight FOV increase on sprint
const CROUCH_FOV: float = 68.0  # Slightly tighter FOV when crouching
var target_fov: float = BASE_FOV
var is_sprinting: bool = false
var is_aiming: bool = false
var is_crouching: bool = false
var weapon_aim_fov: float = 60.0

@onready var camera_holder: Node3D = $CameraHolder
@onready var main_camera: Camera3D = %MainCamera


func _ready() -> void:
        Global.camera_shake.connect(_on_camera_shake)
        Global.active_camera_fov_changed.connect(_on_weapon_aim_fov_changed)
        Global.player_sprinting_changed.connect(_on_player_sprinting_changed)
        Global.player_crouching_changed.connect(_on_player_crouching_changed)
        Global.aim_mode_changed.connect(_on_aim_mode_changed)


func _process(delta: float) -> void:
        # Smoothly interpolate camera FOV
        main_camera.fov = lerp(main_camera.fov, target_fov, delta * 15.0)  # 15.0 = Valorant-style fast FOV transition

        # Decay camera shake offset toward zero
        # Uses the player's shake_pitch/shake_yaw so it flows through
        # the same accumulator pipeline as mouse look and recoil.
        if Global.player:
                var shake_decay_rate = shake_intensity / max(shake_duration, 0.001)
                Global.player.shake_pitch = move_toward(Global.player.shake_pitch, 0.0, delta * shake_decay_rate)
                Global.player.shake_yaw = move_toward(Global.player.shake_yaw, 0.0, delta * shake_decay_rate)


func _on_weapon_aim_fov_changed(fov_angle: float) -> void:
        # Store weapon aim FOV for when we're in aim mode
        weapon_aim_fov = fov_angle
        _update_target_fov()


func _on_player_sprinting_changed(sprinting: bool) -> void:
        is_sprinting = sprinting
        _update_target_fov()


func _on_player_crouching_changed(crouching: bool) -> void:
        is_crouching = crouching
        _update_target_fov()


func _on_aim_mode_changed(aim_mode: bool) -> void:
        is_aiming = aim_mode
        _update_target_fov()


func _update_target_fov() -> void:
        # Priority: Aim mode > Sprint > Crouch > Base
        if is_aiming:
                target_fov = weapon_aim_fov
        elif is_sprinting:
                target_fov = SPRINT_FOV
        elif is_crouching:
                target_fov = CROUCH_FOV
        else:
                target_fov = BASE_FOV


func _on_camera_shake() -> void:
        # Set shake offset on the player's accumulator variables.
        # These get applied in player.gd's _input() alongside rotation_pitch/yaw,
        # so the shake is purely additive and never fights with mouse look or recoil.
        # Decay happens in _process() above.
        if Global.player:
                Global.player.shake_pitch = randf_range(-shake_intensity, shake_intensity)
                Global.player.shake_yaw = randf_range(-shake_intensity, shake_intensity)
