extends PhysicalBone3D

# Hit zone classification for damage multipliers
# HEAD: 4.0x for rifles, 2.0-3.0x for other weapons
# BODY: 1.0x baseline
# LEGS: 0.833x (~0.85x)
enum HitZone { HEAD, BODY, LEGS }

@export var hit_zone: HitZone = HitZone.BODY
@export var damage_multiplier: float = 1.0

# Signal now includes hit zone information
signal update_damage(damage: float, direction: Vector3, zone: HitZone)


func get_damage(damage: float, direction: Vector3) -> void:
	var final_damage = damage * damage_multiplier
	update_damage.emit(final_damage, direction, hit_zone)
