extends Node3D

# Bullet tracer — Valorant-style line from muzzle to impact
# Appears instantly, holds briefly, then fades out
# Shows exact bullet path including spread and recoil offsets


var mesh_instance: MeshInstance3D
var start_pos: Vector3
var end_pos: Vector3

# Config
var tracer_color: Color = Color(1.0, 0.7, 0.15, 1.0)  # Warm orange-yellow, Valorant-style
var tracer_radius: float = 0.005                          # Thin but visible
var hold_time: float = 0.07                               # Seconds visible before fading
var fade_time: float = 0.05                               # Seconds to fade out
var glow_energy: float = 4.0                              # Bright against muzzle flash

var age: float = 0.0
var is_built: bool = false


func setup(p_start: Vector3, p_end: Vector3, p_color: Color = Color(1.0, 0.7, 0.15, 1.0)) -> void:
        start_pos = p_start
        end_pos = p_end
        tracer_color = p_color
        _build_tracer()


func _ready() -> void:
        if not is_built and start_pos.distance_to(end_pos) > 0.01:
                _build_tracer()


func _build_tracer() -> void:
        if is_built:
                return

        var distance = start_pos.distance_to(end_pos)
        if distance < 0.01:
                queue_free()
                return

        is_built = true

        mesh_instance = MeshInstance3D.new()
        add_child(mesh_instance)

        # Thin cylinder the full length of the bullet path
        var mesh = CylinderMesh.new()
        mesh.top_radius = tracer_radius
        mesh.bottom_radius = tracer_radius
        mesh.height = distance
        mesh.radial_segments = 4
        mesh_instance.mesh = mesh

        # Bright emissive unshaded material — always visible, not affected by scene lighting
        var mat = StandardMaterial3D.new()
        mat.albedo_color = tracer_color
        mat.emission_enabled = true
        mat.emission = tracer_color
        mat.emission_energy_multiplier = glow_energy
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        mesh_instance.material_override = mat

        # Position at midpoint between start and end
        global_position = (start_pos + end_pos) / 2.0

        # Orient cylinder (Y-axis default) along bullet direction
        var direction = (end_pos - start_pos).normalized()
        var look_basis = Transform3D().looking_at(direction, Vector3.UP).basis
        global_transform.basis = look_basis * Basis(Vector3.RIGHT, -PI / 2.0)


func _process(delta: float) -> void:
        if not is_built:
                return

        age += delta

        if age < hold_time:
                return  # Still holding visible

        # Fade phase
        var fade_progress = (age - hold_time) / fade_time
        var alpha = 1.0 - clampf(fade_progress, 0.0, 1.0)

        if mesh_instance and mesh_instance.material_override:
                mesh_instance.material_override.albedo_color.a = alpha
                mesh_instance.material_override.emission_energy_multiplier = glow_energy * alpha

        if fade_progress >= 1.0:
                queue_free()
