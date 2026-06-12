@tool
extends Node3D
# ── Porto Seco – Street Prop Populator ───────────────────────────
# Run once in the editor (toggle populate_button) to scatter props
# and parked vehicles along the road grid.

@export var city_config_path: String = "res://world/porto_seco_config.tres"
@export var populate_button: bool = false : set = _on_populate

const STREET_PROPS = [
	"res://resources/props/SM_utility_pole_5.gltf",
	"res://resources/props/SM_utility_pole_1.gltf",
	"res://resources/props/SM_utility_pole_2.gltf",
	"res://resources/props/SM_traffic_lights_1.gltf",
	"res://resources/props/SM_traffic_lights_2.gltf",
	"res://resources/props/SM_trash_bin_1.gltf",
	"res://resources/props/SM_trash_bin_2.gltf",
	"res://resources/props/SM_trash_bin_big.gltf",
	"res://resources/props/SM_bench.gltf",
	"res://resources/props/SM_bench_02.gltf",
	"res://resources/props/SM_parking_meter.gltf",
	"res://resources/props/SM_hydrant.gltf",
	"res://resources/props/SM_road_sign_1.gltf",
	"res://resources/props/SM_road_sign_3.gltf",
	"res://resources/props/SM_road_sign_5.gltf",
	"res://resources/props/SM_road_cone.gltf",
	"res://resources/props/SM_sewerCover.gltf",
	"res://resources/props/SM_mailbox_1.gltf",
	"res://resources/props/SM_public_phone.gltf",
	"res://resources/props/SM_speed_limit_25.gltf",
	"res://resources/props/SM_speed_limit_50.gltf",
	"res://resources/props/SM_billboard_Market24.gltf",
	"res://resources/props/SM_billboard_Liquor.gltf",
	"res://resources/props/SM_billboard_PawnShop.gltf",
	"res://resources/props/SM_billboard_GunsAmmo.gltf",
	"res://resources/props/SM_billboard_AutoService.gltf",
	"res://resources/props/SM_billboard_forRent.gltf",
	"res://resources/props/SM_billboard_jobOffers.gltf",
	"res://resources/props/SM_blibbloardStand_01.gltf",
]

const VEHICLES = [
	"res://resources/vehicles/classic_car.glb",
	"res://resources/vehicles/hatchback.glb",
	"res://resources/vehicles/van.glb",
	"res://resources/vehicles/sports_car.glb",
	"res://resources/vehicles/pickup_truck.glb",
	"res://resources/vehicles/muscle_car.glb",
]

func _on_populate(v: bool) -> void:
	if not v: return
	populate_button = false
	if not Engine.is_editor_hint(): return
	_clear()
	
	var cfg := load(city_config_path) as CityConfiguration
	if not cfg:
		print("Failed to load city config from ", city_config_path)
		return
	
	_populate_props(cfg)
	_populate_vehicles(cfg)
	print("Porto Seco props populated")

func _clear() -> void:
	for c in get_children():
		c.queue_free()

func _populate_props(cfg: CityConfiguration) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var step := cfg.block_size + cfg.street_width
	var grid_w := cfg.grid_width
	var grid_h := cfg.grid_height

	for gx in range(grid_w + 1):
		for gz in range(grid_h + 1):
			var ix := gx * step - cfg.street_width * 0.5
			var iz := gz * step - cfg.street_width * 0.5

			if (gx + gz) % 2 == 0:
				_spawn(STREET_PROPS[0], Vector3(ix - 2, 0, iz - 2), 0)
				_spawn(STREET_PROPS[0], Vector3(ix + cfg.block_size + 2, 0, iz - 2), 0)

			if (gx + gz) % 3 == 0:
				_spawn(STREET_PROPS[3], Vector3(ix - 1, 0, iz - 1), 0)

			for side in range(4):
				var t := rng.randf_range(0.2, 0.8)
				var sx: float
				var sz: float
				match side:
					0: sx = ix + t * cfg.block_size; sz = iz - 1.5
					1: sx = ix + t * cfg.block_size; sz = iz + cfg.block_size + 1.5
					2: sx = ix - 1.5; sz = iz + t * cfg.block_size
					3: sx = ix + cfg.block_size + 1.5; sz = iz + t * cfg.block_size
				var prop_idx := rng.randi_range(6, STREET_PROPS.size() - 1)
				var rot_y := rng.randf_range(-180, 180)
				_spawn(STREET_PROPS[prop_idx], Vector3(sx, 0, sz), rot_y)

func _populate_vehicles(cfg: CityConfiguration) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var step := cfg.block_size + cfg.street_width
	var grid_w := cfg.grid_width
	var grid_h := cfg.grid_height

	for gx in range(grid_w):
		for gz in range(grid_h):
			if rng.randf() > 0.4:
				continue
			var bx := gx * step
			var bz := gz * step
			var side := rng.randi_range(0, 3)
			var t    := rng.randf_range(0.15, 0.85)
			var vx: float
			var vz: float
			var rot: float
			match side:
				0: vx = bx + t * cfg.block_size; vz = bz - cfg.street_width * 0.4; rot = 0
				1: vx = bx + t * cfg.block_size; vz = bz + cfg.block_size + cfg.street_width * 0.4; rot = 180
				2: vx = bx - cfg.street_width * 0.4; vz = bz + t * cfg.block_size; rot = 90
				3: vx = bx + cfg.block_size + cfg.street_width * 0.4; vz = bz + t * cfg.block_size; rot = 270
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
