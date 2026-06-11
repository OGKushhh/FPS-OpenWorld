@tool
extends Node3D
# ── Porto Seco – Street Prop Populator ───────────────────────────
# Run once in the editor (toggle populate_button) to scatter props
# and parked vehicles along the road grid.

@export var city_config_path: String = "res://world/porto_seco_config.tres"
@export var populate_button: bool = false : set = _on_populate

const STREET_PROPS = [
	"res://resources/assetsville/StreetProps/SM_utility_pole_5.gltf",
	"res://resources/assetsville/StreetProps/SM_utility_pole_1.gltf",
	"res://resources/assetsville/StreetProps/SM_utility_pole_2.gltf",
	"res://resources/assetsville/StreetProps/SM_traffic_lights_1.gltf",
	"res://resources/assetsville/StreetProps/SM_traffic_lights_2.gltf",
	"res://resources/assetsville/StreetProps/SM_trash_bin_1.gltf",
	"res://resources/assetsville/StreetProps/SM_trash_bin_2.gltf",
	"res://resources/assetsville/StreetProps/SM_trash_bin_big.gltf",
	"res://resources/assetsville/StreetProps/SM_bench.gltf",
	"res://resources/assetsville/StreetProps/SM_bench_02.gltf",
	"res://resources/assetsville/StreetProps/SM_parking_meter.gltf",
	"res://resources/assetsville/StreetProps/SM_hydrant.gltf",
	"res://resources/assetsville/StreetProps/SM_road_sign_1.gltf",
	"res://resources/assetsville/StreetProps/SM_road_sign_3.gltf",
	"res://resources/assetsville/StreetProps/SM_road_sign_5.gltf",
	"res://resources/assetsville/StreetProps/SM_road_cone.gltf",
	"res://resources/assetsville/StreetProps/SM_sewerCover.gltf",
	"res://resources/assetsville/StreetProps/SM_mailbox_1.gltf",
	"res://resources/assetsville/StreetProps/SM_public_phone.gltf",
	"res://resources/assetsville/StreetProps/SM_speed_limit_25.gltf",
	"res://resources/assetsville/StreetProps/SM_speed_limit_50.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_Market24.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_Liquor.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_PawnShop.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_GunsAmmo.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_AutoService.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_forRent.gltf",
	"res://resources/assetsville/StreetProps/SM_billboard_jobOffers.gltf",
	"res://resources/assetsville/StreetProps/SM_blibbloardStand_01.gltf",
]

const VEHICLES = [
	"res://resources/vehicles/classic_car_9.glb",
	"res://resources/vehicles/hatchback_car_15.glb",
	"res://resources/vehicles/n_van_10.glb",
	"res://resources/vehicles/sport_car_39.glb",
	"res://resources/vehicles/pick_up_11.glb",
	"res://resources/vehicles/n_muscle_car_10.glb",
]

# Props placed near intersections — deterministic grid
const BLOCK  := 200.0
const STREET := 25.0
const STEP   := BLOCK + STREET
const GRID_W := 8
const GRID_H := 8

func _on_populate(v: bool) -> void:
	if not v: return
	populate_button = false
	if not Engine.is_editor_hint(): return
	_clear()
	_populate_props()
	_populate_vehicles()
	print("Porto Seco props populated")

func _clear() -> void:
	for c in get_children():
		c.queue_free()

func _populate_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	for gx in range(GRID_W + 1):
		for gz in range(GRID_H + 1):
			var ix := gx * STEP - STREET * 0.5
			var iz := gz * STEP - STREET * 0.5

			# Utility pole at every other intersection
			if (gx + gz) % 2 == 0:
				_spawn(STREET_PROPS[0], Vector3(ix - 2, 0, iz - 2), 0)
				_spawn(STREET_PROPS[0], Vector3(ix + BLOCK + 2, 0, iz - 2), 0)

			# Traffic light at every 3rd intersection
			if (gx + gz) % 3 == 0:
				_spawn(STREET_PROPS[3], Vector3(ix - 1, 0, iz - 1), 0)

			# Sidewalk clutter along block edges
			for side in range(4):
				var t := rng.randf_range(0.2, 0.8)
				var sx: float
				var sz: float
				match side:
					0: sx = ix + t * BLOCK;           sz = iz - 1.5
					1: sx = ix + t * BLOCK;           sz = iz + BLOCK + 1.5
					2: sx = ix - 1.5;                 sz = iz + t * BLOCK
					3: sx = ix + BLOCK + 1.5;         sz = iz + t * BLOCK
				var prop_idx := rng.randi_range(6, STREET_PROPS.size() - 1)
				var rot_y := rng.randf_range(-180, 180)
				_spawn(STREET_PROPS[prop_idx], Vector3(sx, 0, sz), rot_y)

func _populate_vehicles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	for gx in range(GRID_W):
		for gz in range(GRID_H):
			# 40% chance of a parked car per block-edge
			if rng.randf() > 0.4:
				continue
			var bx := gx * STEP
			var bz := gz * STEP
			var side := rng.randi_range(0, 3)
			var t    := rng.randf_range(0.15, 0.85)
			var vx: float
			var vz: float
			var rot: float
			match side:
				0: vx = bx + t * BLOCK; vz = bz - STREET * 0.4; rot = 0
				1: vx = bx + t * BLOCK; vz = bz + BLOCK + STREET * 0.4; rot = 180
				2: vx = bx - STREET * 0.4; vz = bz + t * BLOCK; rot = 90
				3: vx = bx + BLOCK + STREET * 0.4; vz = bz + t * BLOCK; rot = 270
			var v := VEHICLES[rng.randi_range(0, VEHICLES.size() - 1)]
			_spawn(v, Vector3(vx, 0, vz), rot)

func _spawn(path: String, pos: Vector3, rot_y: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if not scene:
		return
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.rotation_degrees.y = rot_y
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root
