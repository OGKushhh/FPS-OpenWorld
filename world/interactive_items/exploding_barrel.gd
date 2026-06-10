extends StaticBody3D

var destroyable_items_in_range:Array = []
var damage:float = 200.0
@onready var blast_radius: Area3D = $BlastRadius
@onready var explosion_vfx: Node3D = $ExplosionVFX


func get_damage(_damage: float, _direction: Vector3, _hit_point: Vector3 = Vector3.ZERO) -> void:
        destroy()


func destroy() -> void:
        $barrel.visible = false
        $CollisionShape3D.disabled = true
        explosion_vfx.activate()
        
        destroyable_items_in_range = blast_radius.get_overlapping_bodies()
        if destroyable_items_in_range.size() > 0:
                for item in destroyable_items_in_range:
                        if item.has_method("get_damage"):
                                var direction = global_position.direction_to(item.global_position)
                                
                                item.get_damage(damage, direction, global_position)

        await get_tree().create_timer(2.0).timeout
        queue_free()
