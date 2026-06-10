class_name MovingTarget
extends CharacterBody3D

# ══════════════════════════════════════════════════════════════════
# MOVING_TARGET.GD — Shooting Range Target with Hit Zones
# ══════════════════════════════════════════════════════════════════

enum Pattern { SLIDE, POPUP, STRAFE, CHARGE, STATIC }
enum HitZone { HEAD, BODY, LEGS }

@export_group("movement")
@export var pattern: Pattern = Pattern.SLIDE
@export var move_speed: float = 3.0
@export var move_range: float = 10.0
@export var popup_show_time: float = 2.0
@export var popup_hide_time: float = 1.5
@export var charge_speed: float = 5.0

@export_group("target")
@export var max_health: float = 100.0
@export var respawn_time: float = 3.0
@export var point_value: int = 100
@export var auto_start: bool = true

# Hit zone thresholds (local Y, metres)
const HEAD_Y: float = 1.5
const BODY_Y: float = 0.8

const HEAD_MULTIPLIER: float = 4.0
const BODY_MULTIPLIER: float = 1.0
const LEGS_MULTIPLIER: float = 0.825

var current_health: float
var start_position: Vector3
var move_direction: float = 1.0
var is_active: bool = true
var is_dead: bool = false
var is_hidden: bool = false
var popup_timer: float = 0.0
var respawn_timer: float = 0.0

# Visuals
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var legs_mesh: MeshInstance3D
var collision_shape: CollisionShape3D
var hit_flash_timer: float = 0.0

# Hit zone flash: each zone flashes independently
var head_flash: float = 0.0
var body_flash: float = 0.0
var legs_flash: float = 0.0

const COLOR_BODY: Color = Color(0.85, 0.15, 0.15)
const COLOR_HEAD: Color = Color(1.0, 0.85, 0.0)
const COLOR_LEGS: Color = Color(0.25, 0.25, 0.4)
const COLOR_HIT_HEAD: Color = Color(1.0, 0.5, 0.0)   # Orange — headshot flash
const COLOR_HIT_BODY: Color = Color(1.0, 1.0, 1.0)   # White  — body flash
const COLOR_HIT_LEGS: Color = Color(0.6, 0.6, 1.0)   # Blue   — leg flash
const COLOR_DEAD: Color = Color(0.2, 0.2, 0.2, 0.5)

signal target_hit(zone: HitZone, damage: float, points: int)
signal target_killed(points: int)
signal target_respawned


func _ready() -> void:
	start_position = global_position
	current_health = max_health
	_build_visuals()
	if auto_start:
		is_active = true


func _physics_process(delta: float) -> void:
	if is_dead:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn()
		return

	if not is_active:
		return

	# Per-zone flash decay
	if head_flash > 0.0:
		head_flash -= delta / 0.12
		if head_flash <= 0.0:
			head_flash = 0.0
			if head_mesh and head_mesh.material_override:
				head_mesh.material_override.albedo_color = COLOR_HEAD
	if body_flash > 0.0:
		body_flash -= delta / 0.08
		if body_flash <= 0.0:
			body_flash = 0.0
			if body_mesh and body_mesh.material_override:
				body_mesh.material_override.albedo_color = COLOR_BODY
	if legs_flash > 0.0:
		legs_flash -= delta / 0.08
		if legs_flash <= 0.0:
			legs_flash = 0.0
			if legs_mesh and legs_mesh.material_override:
				legs_mesh.material_override.albedo_color = COLOR_LEGS

	match pattern:
		Pattern.SLIDE:   _move_slide(delta)
		Pattern.POPUP:   _move_popup(delta)
		Pattern.STRAFE:  _move_strafe(delta)
		Pattern.CHARGE:  _move_charge(delta)
		Pattern.STATIC:  velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()


# ══════════════════════════════════════════════════════════════════
# HIT ZONE DETECTION + DAMAGE
# ══════════════════════════════════════════════════════════════════

func get_damage(damage: float, _direction: Vector3, hit_point: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	var local_hit_y = to_local(hit_point).y
	var zone: HitZone
	var multiplier: float

	if local_hit_y > HEAD_Y:
		zone = HitZone.HEAD
		multiplier = HEAD_MULTIPLIER
	elif local_hit_y > BODY_Y:
		zone = HitZone.BODY
		multiplier = BODY_MULTIPLIER
	else:
		zone = HitZone.LEGS
		multiplier = LEGS_MULTIPLIER

	var actual_damage = damage * multiplier
	current_health -= actual_damage

	_flash_zone(zone)

	var points = point_value
	match zone:
		HitZone.HEAD: points = point_value * 3
		HitZone.LEGS: points = int(point_value * 0.5)

	target_hit.emit(zone, actual_damage, points)

	if current_health <= 0.0:
		die(points)


func die(points: int) -> void:
	is_dead = true
	respawn_timer = 0.0
	target_killed.emit(points)
	_set_color_all(COLOR_DEAD)
	collision_shape.set_deferred("disabled", true)


func respawn() -> void:
	is_dead = false
	current_health = max_health
	respawn_timer = 0.0
	global_position = start_position
	move_direction = 1.0
	is_hidden = false
	popup_timer = 0.0
	_reset_colors()
	collision_shape.set_deferred("disabled", false)
	visible = true
	target_respawned.emit()


# ══════════════════════════════════════════════════════════════════
# MOVEMENT PATTERNS
# ══════════════════════════════════════════════════════════════════

func _move_slide(delta: float) -> void:
	var offset = global_position.x - start_position.x
	if abs(offset) >= move_range:
		move_direction *= -1.0
	velocity.x = move_speed * move_direction
	velocity.z = 0.0


func _move_popup(delta: float) -> void:
	popup_timer += delta
	velocity.x = 0.0
	velocity.z = 0.0

	if not is_hidden:
		if popup_timer >= popup_show_time:
			is_hidden = true
			popup_timer = 0.0
			visible = false
			collision_shape.set_deferred("disabled", true)
	else:
		if popup_timer >= popup_hide_time:
			is_hidden = false
			popup_timer = 0.0
			visible = true
			collision_shape.set_deferred("disabled", false)


func _move_strafe(delta: float) -> void:
	var offset = global_position.z - start_position.z
	if abs(offset) >= move_range:
		move_direction *= -1.0
	velocity.x = 0.0
	velocity.z = move_speed * move_direction


func _move_charge(delta: float) -> void:
	if not Global.player:
		velocity = Vector3.ZERO
		return
	var to_player = Global.player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() < 2.0:
		global_position = start_position
		move_direction = 1.0
		velocity = Vector3.ZERO
		return
	velocity = to_player.normalized() * charge_speed


# ══════════════════════════════════════════════════════════════════
# VISUAL CONSTRUCTION
# ══════════════════════════════════════════════════════════════════

func _build_visuals() -> void:
	legs_mesh = MeshInstance3D.new()
	var legs_box = BoxMesh.new()
	legs_box.size = Vector3(0.35, 0.8, 0.25)
	legs_mesh.mesh = legs_box
	legs_mesh.position = Vector3(0.0, 0.4, 0.0)
	var legs_mat = StandardMaterial3D.new()
	legs_mat.albedo_color = COLOR_LEGS
	legs_mesh.material_override = legs_mat
	add_child(legs_mesh)

	body_mesh = MeshInstance3D.new()
	var body_box = BoxMesh.new()
	body_box.size = Vector3(0.45, 0.7, 0.25)
	body_mesh.mesh = body_box
	body_mesh.position = Vector3(0.0, 1.15, 0.0)
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mesh.material_override = body_mat
	add_child(body_mesh)

	head_mesh = MeshInstance3D.new()
	var head_box = BoxMesh.new()
	head_box.size = Vector3(0.25, 0.3, 0.25)
	head_mesh.mesh = head_box
	head_mesh.position = Vector3(0.0, 1.65, 0.0)
	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = COLOR_HEAD
	head_mesh.material_override = head_mat
	add_child(head_mesh)

	collision_shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(collision_shape)


# ══════════════════════════════════════════════════════════════════
# VISUAL FEEDBACK
# ══════════════════════════════════════════════════════════════════

func _flash_zone(zone: HitZone) -> void:
	match zone:
		HitZone.HEAD:
			head_flash = 1.0
			if head_mesh and head_mesh.material_override:
				head_mesh.material_override.albedo_color = COLOR_HIT_HEAD
		HitZone.BODY:
			body_flash = 1.0
			if body_mesh and body_mesh.material_override:
				body_mesh.material_override.albedo_color = COLOR_HIT_BODY
		HitZone.LEGS:
			legs_flash = 1.0
			if legs_mesh and legs_mesh.material_override:
				legs_mesh.material_override.albedo_color = COLOR_HIT_LEGS


func _reset_colors() -> void:
	if body_mesh and body_mesh.material_override:
		body_mesh.material_override.albedo_color = COLOR_BODY
	if head_mesh and head_mesh.material_override:
		head_mesh.material_override.albedo_color = COLOR_HEAD
	if legs_mesh and legs_mesh.material_override:
		legs_mesh.material_override.albedo_color = COLOR_LEGS


func _set_color_all(color: Color) -> void:
	if body_mesh and body_mesh.material_override:
		body_mesh.material_override.albedo_color = color
	if head_mesh and head_mesh.material_override:
		head_mesh.material_override.albedo_color = color
	if legs_mesh and legs_mesh.material_override:
		legs_mesh.material_override.albedo_color = color
