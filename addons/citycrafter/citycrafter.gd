@tool
extends Node3D

signal generation_progress(current: int, total: int, stage: String)
signal generation_complete()

@export var city_configuration: CityConfiguration
@export var generate_city_button: bool = false : set = _on_generate_pressed
@export var clear_city_button: bool = false : set = _on_clear_pressed
@export_group("Performance Settings")
@export var blocks_per_frame: int = 10
@export var buildings_per_frame: int = 25 
@export var enable_progress_feedback: bool = true

var noise: FastNoiseLite
var active_blocks: Array[Vector2i] = []
var block_sizes: Dictionary = {}
var occupied_positions: Dictionary = {}
var is_generating: bool = false
var _heightmap_image: Image = null
var _terrain_heights: Dictionary = {}

const DISTRICT_TYPES := ["residential", "commercial", "industrial", "park"]

func _ready():
	if not city_configuration:
		city_configuration = CityConfiguration.create_default()
	noise = FastNoiseLite.new()
	noise.seed = randi()
	if city_configuration:
		noise.frequency = city_configuration.noise_scale

func _on_generate_pressed(value):
	if value:
		if not is_generating:
			generate_city_async()
		generate_city_button = false

func _on_clear_pressed(value):
	if value:
		clear_city()
		clear_city_button = false

func generate_city_async():
	if not city_configuration:
		print("Load a City Configuration Resource first!")
		return
	
	if not city_configuration.is_valid():
		print("No buildings assigned!")
		return

	if is_generating:
		print("Generation already in progress!")
		return
		
	is_generating = true
	if not noise:
		noise = FastNoiseLite.new()
		noise.seed = randi()
	noise.frequency = city_configuration.noise_scale
	clear_all_buildings()
	
	if city_configuration.enable_terrain:
		_load_heightmap()
	
	emit_progress(0, 100, "Calculating city layout...")
	generate_active_blocks()
	await get_tree().process_frame
	if city_configuration.generate_ground:
		await generate_ground_planes_async()
	if city_configuration.generate_roads:
		await generate_road_network_async()
	await generate_buildings_async()
	if city_configuration.generate_navigation:
		await generate_navigation_async()
	is_generating = false
	emit_progress(100, 100, "Generation complete!")
	generation_complete.emit()

func _load_heightmap():
	if not city_configuration.heightmap_texture:
		return
	var img: Image = city_configuration.heightmap_texture.get_image()
	if img:
		_heightmap_image = img
		_heightmap_image.resize(city_configuration.terrain_sample_resolution, city_configuration.terrain_sample_resolution, Image.INTERPOLATE_LANCZOS)

func sample_terrain_height(world_x: float, world_z: float) -> float:
	if not _heightmap_image:
		return city_configuration.terrain_base_height
	
	var cfg = city_configuration
	var world_size_x = cfg.grid_width * (cfg.block_size + cfg.street_width)
	var world_size_z = cfg.grid_height * (cfg.block_size + cfg.street_width)
	if world_size_x <= 0 or world_size_z <= 0:
		return cfg.terrain_base_height
	var u = world_x / world_size_x
	var v = world_z / world_size_z
	u = clamp(u, 0.0, 0.999)
	v = clamp(v, 0.0, 0.999)
	
	var px = int(u * _heightmap_image.get_width())
	var py = int(v * _heightmap_image.get_height())
	var pixel = _heightmap_image.get_pixel(px, py)
	return cfg.terrain_base_height + pixel.v * cfg.terrain_height_scale

func get_terrain_slope(world_x: float, world_z: float, sample_dist: float = 5.0) -> float:
	var h_center = sample_terrain_height(world_x, world_z)
	var h_dx = sample_terrain_height(world_x + sample_dist, world_z)
	var h_dz = sample_terrain_height(world_x, world_z + sample_dist)
	var slope_x = (h_dx - h_center) / sample_dist
	var slope_z = (h_dz - h_center) / sample_dist
	return rad_to_deg(atan(sqrt(slope_x * slope_x + slope_z * slope_z)))

func generate_active_blocks():
	active_blocks.clear()
	block_sizes.clear()
	occupied_positions.clear()
	
	generate_base_grid()
	
	if city_configuration.enable_edge_extensions:
		add_block_extensions(city_configuration.max_edge_extensions)

func generate_base_grid():
	for x in range(city_configuration.grid_width):
		for z in range(city_configuration.grid_height):
			var pos = Vector2i(x, z)
			if occupied_positions.has(pos):
				continue
			
			var block_size = Vector2i(1, 1)
			if city_configuration.enable_multi_size_blocks:
				block_size = determine_block_size(x, z)
			
			if block_size != Vector2i.ZERO:
				add_block(pos, block_size)

func determine_block_size(x: int, z: int) -> Vector2i:
	var available_sizes = []
	if can_place_block_size(x, z, Vector2i(2, 2)):
		available_sizes.append({"size": Vector2i(2, 2), "chance": city_configuration.large_block_chance})
	if can_place_block_size(x, z, Vector2i(2, 1)):
		available_sizes.append({"size": Vector2i(2, 1), "chance": city_configuration.wide_block_chance})
	if can_place_block_size(x, z, Vector2i(1, 2)):
		available_sizes.append({"size": Vector2i(1, 2), "chance": city_configuration.tall_block_chance})
	available_sizes.append({"size": Vector2i(1, 1), "chance": 1.0})
	
	for size_option in available_sizes:
		if randf() < size_option.chance:
			return size_option.size
	
	return Vector2i(1, 1)

func can_place_block_size(x: int, z: int, size: Vector2i) -> bool:
	if x + size.x > city_configuration.grid_width or z + size.y > city_configuration.grid_height:
		return false
	
	for bx in range(size.x):
		for bz in range(size.y):
			if occupied_positions.has(Vector2i(x + bx, z + bz)):
				return false
	
	return true

func add_block(pos: Vector2i, size: Vector2i):
	active_blocks.append(pos)
	block_sizes[pos] = size
	
	for bx in range(size.x):
		for bz in range(size.y):
			occupied_positions[Vector2i(pos.x + bx, pos.y + bz)] = true

func add_block_extensions(max_attempts: int):
	var attempts = 0
	
	while attempts < max_attempts:
		var edge_blocks = get_edge_blocks()
		if edge_blocks.is_empty():
			break
		
		var source_block = edge_blocks[randi() % edge_blocks.size()]
		
		if randf() < city_configuration.edge_extension_chance:
			if try_add_extension(source_block):
				attempts += 1
				continue
		
		attempts += 1

func try_add_extension(source_block: Vector2i) -> bool:
	var directions = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	directions.shuffle()
	
	for direction in directions:
		var new_pos = source_block + direction
		if not occupied_positions.has(new_pos):
			add_block(new_pos, Vector2i(1, 1))
			return true
	
	return false

func is_on_grid_perimeter(pos: Vector2i) -> bool:
	return pos.x == 0 or pos.x >= city_configuration.grid_width - 1 or pos.y == 0 or pos.y >= city_configuration.grid_height - 1

func get_edge_blocks() -> Array[Vector2i]:
	var edge_blocks: Array[Vector2i] = []
	
	for block_pos in active_blocks:
		var block_size = block_sizes.get(block_pos, Vector2i(1, 1))
		var is_edge = false
		
		for bx in range(block_size.x):
			for bz in range(block_size.y):
				var check_pos = Vector2i(block_pos.x + bx, block_pos.y + bz)
				var directions = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
				
				for direction in directions:
					if not occupied_positions.has(check_pos + direction):
						is_edge = true
						break
				
				if is_edge:
					break
			if is_edge:
				break
		
		if is_edge:
			edge_blocks.append(block_pos)
	
	return edge_blocks

func get_block_world_bounds(grid_x: int, grid_z: int) -> Dictionary:
	var cfg = city_configuration
	var block_size = block_sizes.get(Vector2i(grid_x, grid_z), Vector2i(1, 1))
	var world_width = block_size.x * cfg.block_size + (block_size.x - 1) * cfg.street_width
	var world_height = block_size.y * cfg.block_size + (block_size.y - 1) * cfg.street_width
	var block_center = Vector3(
		grid_x * (cfg.block_size + cfg.street_width) + world_width / 2,
		0,
		grid_z * (cfg.block_size + cfg.street_width) + world_height / 2
	)
	var terrain_y = sample_terrain_height(block_center.x, block_center.z) if cfg.enable_terrain else 0
	return {
		"center": Vector3(block_center.x, terrain_y, block_center.z),
		"size": Vector2(world_width, world_height),
		"half": Vector2(world_width / 2, world_height / 2),
		"grid_size": block_size
	}

func generate_ground_planes_async():
	emit_progress(10, 100, "Generating ground planes...")
	var total_blocks = active_blocks.size()
	var processed = 0
	
	for i in range(0, total_blocks, blocks_per_frame):
		var end_idx = min(i + blocks_per_frame, total_blocks)
		for j in range(i, end_idx):
			var block_pos = active_blocks[j]
			var bounds = get_block_world_bounds(block_pos.x, block_pos.y)
			var district_type = get_district_type(block_pos.x, block_pos.y)
			var y = bounds.center.y + city_configuration.ground_height_offset
			create_ground_plane(Vector3(bounds.center.x, y, bounds.center.z), bounds.size, district_type)
			processed += 1
		
		var progress = 10 + (processed * 20 / total_blocks)
		emit_progress(progress, 100, "Generating ground planes... (%d/%d)" % [processed, total_blocks])
		await get_tree().process_frame

func generate_road_network_async():
	emit_progress(30, 100, "Generating roads...")
	await generate_dynamic_roads_async()
	emit_progress(40, 100, "Roads complete!")

func is_avenue_grid_line(index: int) -> bool:
	if not city_configuration.enable_main_avenues:
		return false
	if index <= 0:
		return false
	return index % city_configuration.avenue_interval == 0

func get_road_width_for_line(horizontal: bool, index: int) -> float:
	if is_avenue_grid_line(index):
		return city_configuration.avenue_width
	return city_configuration.street_width

func generate_dynamic_roads_async():
	var cfg = city_configuration
	var road_positions = {}
	var roads_to_create = []
	var horizontal_roads = {}
	var vertical_roads = {}
	
	for block_pos in active_blocks:
		var block_size = block_sizes.get(block_pos, Vector2i(1, 1))
		var block_end_x = block_pos.x + block_size.x - 1
		var block_end_z = block_pos.y + block_size.y - 1
		
		var top_road_z = block_end_z + 1
		var bottom_road_z = block_pos.y
		if not horizontal_roads.has(str(top_road_z)):
			horizontal_roads[str(top_road_z)] = []
		if not horizontal_roads.has(str(bottom_road_z)):
			horizontal_roads[str(bottom_road_z)] = []
		horizontal_roads[str(top_road_z)].append({"start": block_pos.x, "end": block_end_x})
		horizontal_roads[str(bottom_road_z)].append({"start": block_pos.x, "end": block_end_x})
		
		var left_road_x = block_pos.x
		var right_road_x = block_end_x + 1
		if not vertical_roads.has(str(left_road_x)):
			vertical_roads[str(left_road_x)] = []
		if not vertical_roads.has(str(right_road_x)):
			vertical_roads[str(right_road_x)] = []
		vertical_roads[str(left_road_x)].append({"start": block_pos.y, "end": block_end_z})
		vertical_roads[str(right_road_x)].append({"start": block_pos.y, "end": block_end_z})
	
	for z_str in horizontal_roads.keys():
		var z = int(z_str)
		var merged = merge_road_segments(horizontal_roads[z_str])
		var road_w = get_road_width_for_line(true, z)
		for segment in merged:
			var key = "h_%s_%s_%s" % [segment.start, segment.end, z]
			if not road_positions.has(key):
				var seg_w = (segment.end - segment.start + 1) * cfg.block_size + (segment.end - segment.start) * cfg.street_width
				var cx = segment.start * (cfg.block_size + cfg.street_width) + seg_w / 2
				var cz = z * (cfg.block_size + cfg.street_width) - road_w / 2
				var y = sample_terrain_height(cx, cz) if cfg.enable_terrain else 0
				roads_to_create.append({
					"center": Vector3(cx, y, cz),
					"size": Vector2(seg_w, road_w),
					"type": "Avenue" if is_avenue_grid_line(z) else "Road"
				})
				road_positions[key] = true
	
	for x_str in vertical_roads.keys():
		var x = int(x_str)
		var merged = merge_road_segments(vertical_roads[x_str])
		var road_w = get_road_width_for_line(false, x)
		for segment in merged:
			var key = "v_%s_%s_%s" % [x, segment.start, segment.end]
			if not road_positions.has(key):
				var seg_h = (segment.end - segment.start + 1) * cfg.block_size + (segment.end - segment.start) * cfg.street_width
				var cx = x * (cfg.block_size + cfg.street_width) - road_w / 2
				var cz = segment.start * (cfg.block_size + cfg.street_width) + seg_h / 2
				var y = sample_terrain_height(cx, cz) if cfg.enable_terrain else 0
				roads_to_create.append({
					"center": Vector3(cx, y, cz),
					"size": Vector2(road_w, seg_h),
					"type": "Avenue" if is_avenue_grid_line(x) else "Road"
				})
				road_positions[key] = true
	
	var total = roads_to_create.size()
	for i in range(0, total, buildings_per_frame * 2):
		var end_idx = min(i + buildings_per_frame * 2, total)
		for j in range(i, end_idx):
			var rd = roads_to_create[j]
			create_road_plane(rd.center, rd.size, rd.type)
		await get_tree().process_frame
	
	if cfg.generate_intersections:
		await generate_intersections_async()
	
	if cfg.enable_roundabouts:
		await generate_roundabouts_async()
	
	if cfg.enable_diagonal_roads:
		await generate_diagonal_roads_async()

func merge_road_segments(segments: Array) -> Array:
	if segments.is_empty():
		return []
	
	segments.sort_custom(func(a, b): return a.start < b.start)
	var merged = []
	var current = segments[0]
	for i in range(1, segments.size()):
		var next_segment = segments[i]
		if next_segment.start <= current.end + 1:
			current.end = max(current.end, next_segment.end)
		else:
			merged.append(current)
			current = next_segment
	merged.append(current)
	return merged

func generate_intersections_async() -> void:
	var cfg = city_configuration
	var min_x = 999999
	var max_x = -999999
	var min_z = 999999
	var max_z = -999999
	
	for pos in active_blocks:
		var block_size = block_sizes.get(pos, Vector2i(1, 1))
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x + block_size.x - 1)
		min_z = min(min_z, pos.y)
		max_z = max(max_z, pos.y + block_size.y - 1)
	
	var interior_seams: Array[Vector2i] = []
	for block_pos in block_sizes.keys():
		var size: Vector2i = block_sizes[block_pos]
		if size.x > 1 and size.y > 1:
			for dx in range(1, size.x):
				for dz in range(1, size.y):
					interior_seams.append(Vector2i(block_pos.x + dx, block_pos.y + dz))
	
	for x in range(min_x, max_x + 2):
		for z in range(min_z, max_z + 2):
			var seam = Vector2i(x, z)
			if interior_seams.has(seam):
				continue
			
			var has_block_above = occupied_positions.has(Vector2i(x, z))
			var has_block_below = occupied_positions.has(Vector2i(x, z - 1))
			var has_block_above_left = occupied_positions.has(Vector2i(x - 1, z))
			var has_block_below_left = occupied_positions.has(Vector2i(x - 1, z - 1))
			var has_horizontal_road = has_block_above or has_block_below or has_block_above_left or has_block_below_left
			
			var has_block_left = occupied_positions.has(Vector2i(x - 1, z))
			var has_block_right = occupied_positions.has(Vector2i(x, z))
			var has_block_left_above = occupied_positions.has(Vector2i(x - 1, z - 1))
			var has_block_right_above = occupied_positions.has(Vector2i(x, z - 1))
			var has_vertical_road = has_block_left or has_block_right or has_block_left_above or has_block_right_above
			
			if has_horizontal_road and has_vertical_road:
				var road_w_h = get_road_width_for_line(true, z)
				var road_w_v = get_road_width_for_line(false, x)
				var iw = max(road_w_h, road_w_v)
				var cx = x * (cfg.block_size + cfg.street_width) - iw * 0.5
				var cz = z * (cfg.block_size + cfg.street_width) - iw * 0.5
				var y = sample_terrain_height(cx, cz) if cfg.enable_terrain else cfg.intersection_height_offset
				create_intersection_plane(Vector3(cx, y, cz), Vector2(iw, iw))
				await get_tree().process_frame

func generate_roundabouts_async():
	var cfg = city_configuration
	var center_x = cfg.grid_width / 2.0
	var center_z = cfg.grid_height / 2.0
	var major_intersections = []
	
	for x in range(1, cfg.grid_width):
		for z in range(1, cfg.grid_height):
			var is_major_h = is_avenue_grid_line(z)
			var is_major_v = is_avenue_grid_line(x)
			if is_major_h and is_major_v:
				var cx = x * (cfg.block_size + cfg.street_width) - (cfg.avenue_width + cfg.street_width) * 0.5
				var cz = z * (cfg.block_size + cfg.street_width) - (cfg.avenue_width + cfg.street_width) * 0.5
				var y = sample_terrain_height(cx, cz) if cfg.enable_terrain else cfg.intersection_height_offset
				major_intersections.append(Vector3(cx, y, cz))
	
	for pos in major_intersections:
		create_roundabout(pos)

func create_roundabout(center: Vector3):
	var cfg = city_configuration
	var r = cfg.roundabout_radius
	var d = r * 2
	
	var outer = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.3
	outer.mesh = cyl
	if cfg.roundabout_material:
		outer.material_override = cfg.roundabout_material
	else:
		outer.material_override = cfg.road_material
	outer.position = center + Vector3(0, 0.15, 0)
	outer.name = "Roundabout"
	add_child(outer)
	outer.owner = get_tree().edited_scene_root
	
	var inner = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(d - 4, d - 4)
	inner.mesh = plane
	if cfg.park_ground_material:
		inner.material_override = cfg.park_ground_material
	else:
		inner.material_override = cfg.ground_material
	inner.position = center + Vector3(0, 0.3, 0)
	inner.name = "RoundaboutCenter"
	add_child(inner)
	inner.owner = get_tree().edited_scene_root

func generate_diagonal_roads_async():
	var cfg = city_configuration
	var min_x = 999999
	var max_x = -999999
	var min_z = 999999
	var max_z = -999999
	
	for pos in active_blocks:
		var block_size = block_sizes.get(pos, Vector2i(1, 1))
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x + block_size.x - 1)
		min_z = min(min_z, pos.y)
		max_z = max(max_z, pos.y + block_size.y - 1)
	
	var x0 = min_x * (cfg.block_size + cfg.street_width)
	var z0 = min_z * (cfg.block_size + cfg.street_width)
	var x1 = (max_x + 1) * (cfg.block_size + cfg.street_width) - cfg.street_width
	var z1 = (max_z + 1) * (cfg.block_size + cfg.street_width) - cfg.street_width
	
	var diag_mid = Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var diag_len = Vector3(x1 - x0, 0, z1 - z0).length()
	var diag_angle = atan2(z1 - z0, x1 - x0)
	
	var y0 = sample_terrain_height(x0, z0) if cfg.enable_terrain else 0
	var y1 = sample_terrain_height(x1, z1) if cfg.enable_terrain else 0
	
	var mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(diag_len * 0.9, cfg.diagonal_road_width)
	mesh.mesh = plane
	if cfg.road_material:
		mesh.material_override = cfg.road_material
	mesh.position = Vector3(diag_mid.x, (y0 + y1) * 0.5, diag_mid.z)
	mesh.rotation.y = diag_angle
	mesh.name = "DiagonalRoad"
	add_child(mesh)
	mesh.owner = get_tree().edited_scene_root

func generate_buildings_async():
	if active_blocks.is_empty():
		emit_progress(90, 100, "No blocks to generate buildings for (empty city)")
		return
	
	emit_progress(40, 100, "Generating buildings...")
	var total_blocks = active_blocks.size()
	var processed_blocks = 0
	
	for block_pos in active_blocks:
		if randf() < city_configuration.empty_block_chance:
			processed_blocks += 1
			continue
		
		await generate_block_async(block_pos.x, block_pos.y)
		processed_blocks += 1
		var progress = 40 + (processed_blocks * 50 / total_blocks)
		emit_progress(progress, 100, "Generating buildings... (%d/%d blocks)" % [processed_blocks, total_blocks])

func generate_block_async(grid_x: int, grid_z: int):
	var district = get_district_type(grid_x, grid_z)
	
	if district == "park":
		await generate_park_block_async(grid_x, grid_z)
		return
	
	var available_buildings = get_buildings_for_district(district)
	if available_buildings.is_empty():
		print("No buildings assigned to district: ", district)
		return
	
	var block_pos = Vector2i(grid_x, grid_z)
	var block_size = block_sizes.get(block_pos, Vector2i(1, 1))
	
	if district == "residential" and city_configuration.enable_residential_subdivisions:
		await generate_subdivided_block_async(grid_x, grid_z, available_buildings, block_size)
	else:
		await generate_regular_block_async(grid_x, grid_z, available_buildings, district, block_size)

func generate_park_block_async(grid_x: int, grid_z: int):
	var bounds = get_block_world_bounds(grid_x, grid_z)
	var cfg = city_configuration
	var count = randi_range(cfg.park_elements_count_min, cfg.park_elements_count_max)
	
	if cfg.park_elements.is_empty():
		return
	
	for i in range(count):
		var local_pos = Vector3(
			randf_range(-bounds.half.x + 5, bounds.half.x - 5),
			0,
			randf_range(-bounds.half.y + 5, bounds.half.y - 5)
		)
		var world_pos = bounds.center + local_pos
		var terrain_y = sample_terrain_height(world_pos.x, world_pos.z) if cfg.enable_terrain else 0
		world_pos.y = terrain_y
		var element = cfg.park_elements[randi() % cfg.park_elements.size()].instantiate()
		element.position = world_pos
		element.rotation.y = randf_range(0, TAU)
		if cfg.scale_variation != 0:
			var s = 1.0 + randf_range(-cfg.scale_variation, cfg.scale_variation)
			element.scale = Vector3.ONE * s
		add_child(element)
		element.owner = get_tree().edited_scene_root
		if i % 5 == 0:
			await get_tree().process_frame

func get_floor_count(district: String) -> int:
	var cfg = city_configuration
	match district:
		"residential":
			return randi_range(cfg.residential_min_floors, cfg.residential_max_floors)
		"commercial":
			return randi_range(cfg.commercial_min_floors, cfg.commercial_max_floors)
		"industrial":
			return randi_range(cfg.industrial_min_floors, cfg.industrial_max_floors)
		_:
			return 1

func generate_regular_block_async(grid_x: int, grid_z: int, available_buildings: Array[PackedScene], district: String, block_size: Vector2i = Vector2i(1, 1)):
	var cfg = city_configuration
	var density_settings = get_district_density_settings(district)
	var bounds = get_block_world_bounds(grid_x, grid_z)
	
	var size_multiplier = block_size.x * block_size.y
	var building_count = randi_range(
		density_settings.min_buildings * size_multiplier,
		density_settings.max_buildings * size_multiplier
	)
	
	if cfg.enable_grid_aligned:
		await generate_grid_aligned_block_async(bounds, available_buildings, district, density_settings, building_count)
	else:
		await generate_random_block_async(bounds, available_buildings, district, density_settings, building_count)

func generate_grid_aligned_block_async(bounds: Dictionary, available_buildings: Array[PackedScene], district: String, density_settings: Dictionary, building_count: int):
	var cfg = city_configuration
	var half = bounds.half
	var center = bounds.center
	
	var front_s = cfg.front_setback
	var side_s = cfg.side_setback
	
	var block_w = half.x * 2
	var block_d = half.y * 2
	
	# Divide buildings among 4 edges: top(Z-), bottom(Z+), left(X-), right(X+)
	var edges = [
		{"name": "top",    "fixed_axis": "z", "fixed_val": -half.y + front_s, "span": block_w - side_s * 2, "rot": 0.0},
		{"name": "bottom", "fixed_axis": "z", "fixed_val":  half.y - front_s, "span": block_w - side_s * 2, "rot": PI},
		{"name": "left",   "fixed_axis": "x", "fixed_val": -half.x + side_s,  "span": block_d - front_s * 2, "rot": -PI / 2},
		{"name": "right",  "fixed_axis": "x", "fixed_val":  half.x - side_s,  "span": block_d - front_s * 2, "rot": PI / 2},
	]
	
	# Assign each building to a random edge
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(bounds.center.x, bounds.center.z)) % 100000
	var placed = 0
	var max_attempts = building_count * 10
	
	for i in range(building_count):
		var attempts = 0
		var valid = false
		while not valid and attempts < max_attempts:
			var edge = edges[rng.randi() % edges.size()]
			var span = edge.span
			if span < 4.0:
				attempts += 1
				continue
			var t = rng.randf_range(0.1, 0.9)
			var w_pos: Vector3
			if edge.fixed_axis == "z":
				var ex = -half.x + side_s + t * span
				w_pos = Vector3(center.x + ex, 0, center.z + edge.fixed_val)
			else:
				var ez = -half.y + front_s + t * span
				w_pos = Vector3(center.x + edge.fixed_val, 0, center.z + ez)
			
			var terrain_y = sample_terrain_height(w_pos.x, w_pos.z) if cfg.enable_terrain else center.y
			w_pos.y = terrain_y
			
			if cfg.enable_terrain:
				var slope = get_terrain_slope(w_pos.x, w_pos.z)
				if slope > cfg.max_buildable_slope:
					attempts += 1
					continue
			
			valid = true
			
			var floors = get_floor_count(district) if cfg.enable_multi_story else 1
			var bldg_h = floors * cfg.floor_height
			
			var bldg_w = rng.randf_range(6.0, min(span * 0.4, 16.0))
			var bldg_d = rng.randf_range(6.0, 12.0)
			var building_node: Node3D
			var use_prefab = floors <= 2 and not available_buildings.is_empty() and rng.randi() % 2 == 0
			
			if use_prefab:
				building_node = available_buildings[rng.randi() % available_buildings.size()].instantiate()
				building_node.position = w_pos
				building_node.rotation.y = edge.rot + rng.randf_range(-0.05, 0.05)
				if cfg.scale_variation != 0:
					var s = 1.0 + rng.randf_range(-cfg.scale_variation, cfg.scale_variation)
					building_node.scale = Vector3.ONE * s
			else:
				building_node = spawn_procedural_building(w_pos, bldg_w, bldg_d, bldg_h, floors, district)
			
			add_child(building_node)
			building_node.owner = get_tree().edited_scene_root
			
			if cfg.generate_collision:
				add_collision_to_building(building_node, bldg_w, bldg_d, bldg_h)
			
			placed += 1
			if placed % cfg.buildings_per_frame == 0:
				await get_tree().process_frame

func generate_random_block_async(bounds: Dictionary, available_buildings: Array[PackedScene], district: String, density_settings: Dictionary, building_count: int):
	var cfg = city_configuration
	var half = bounds.half
	var center = bounds.center
	
	var building_positions = []
	var buildings_to_spawn = []
	var max_attempts = building_count * 10
	
	for i in range(building_count):
		var attempts = 0
		var valid_position = false
		while not valid_position and attempts < max_attempts:
			var local_pos = Vector3(
				randf_range(-half.x + density_settings.border_margin, half.x - density_settings.border_margin),
				0,
				randf_range(-half.y + density_settings.border_margin, half.y - density_settings.border_margin)
			)
			var world_pos = center + local_pos
			var terrain_y = sample_terrain_height(world_pos.x, world_pos.z) if cfg.enable_terrain else center.y
			world_pos.y = terrain_y
			valid_position = true
			
			if cfg.enable_terrain:
				var slope = get_terrain_slope(world_pos.x, world_pos.z)
				if slope > cfg.max_buildable_slope:
					valid_position = false
			
			if valid_position:
				for existing_pos in building_positions:
					if world_pos.distance_to(existing_pos) < density_settings.spacing:
						valid_position = false
						break
			if valid_position:
				building_positions.append(world_pos)
				buildings_to_spawn.append(world_pos)
			attempts += 1
	
	for i in range(0, buildings_to_spawn.size(), cfg.buildings_per_frame):
		var end_idx = min(i + cfg.buildings_per_frame, buildings_to_spawn.size())
		for j in range(i, end_idx):
			var world_pos = buildings_to_spawn[j]
			var floors = get_floor_count(district) if cfg.enable_multi_story else 1
			var bldg_h = floors * cfg.floor_height
			var bldg_w = randf_range(8, 25)
			var bldg_d = randf_range(8, 25)
			var use_prefab = floors <= 2 and not available_buildings.is_empty() and randi() % 2 == 0
			
			var building_node: Node3D
			if use_prefab:
				building_node = available_buildings[randi() % available_buildings.size()].instantiate()
				building_node.position = world_pos
				building_node.rotation.y = [0, PI/2, PI, 3*PI/2][randi() % 4]
			else:
				building_node = spawn_procedural_building(world_pos, bldg_w, bldg_d, bldg_h, floors, district)
			
			add_child(building_node)
			building_node.owner = get_tree().edited_scene_root
			
			if cfg.generate_collision:
				add_collision_to_building(building_node, bldg_w, bldg_d, bldg_h)
		if i > 0:
			await get_tree().process_frame

func spawn_procedural_building(world_pos: Vector3, width: float, depth: float, height: float, floors: int, district: String) -> Node3D:
	var cfg = city_configuration
	var building = Node3D.new()
	building.position = world_pos
	building.name = "ProceduralBuilding_%dfl" % floors
	
	var wall_mat = cfg.procedural_wall_material
	var roof_mat = cfg.procedural_roof_material
	
	var wall_mesh = BoxMesh.new()
	wall_mesh.size = Vector3(width, height, depth)
	if wall_mat:
		wall_mesh.material = wall_mat
	
	var wall = MeshInstance3D.new()
	wall.mesh = wall_mesh
	wall.position = Vector3(0, height / 2, 0)
	building.add_child(wall)
	
	var roof = MeshInstance3D.new()
	var roof_mesh = BoxMesh.new()
	roof_mesh.size = Vector3(width * 1.02, 0.5, depth * 1.02)
	roof.mesh = roof_mesh
	if roof_mat:
		roof.material_override = roof_mat
	roof.position = Vector3(0, height + 0.25, 0)
	building.add_child(roof)
	
	var floor_band_mat = cfg.road_material
	if floor_band_mat and floors > 1:
		for floor in range(1, floors):
			var band = MeshInstance3D.new()
			var band_mesh = PlaneMesh.new()
			band_mesh.size = Vector2(width * 1.01, depth * 1.01)
			band.mesh = band_mesh
			band.material_override = floor_band_mat
			band.position = Vector3(0, floor * cfg.floor_height, 0)
			band.rotation.x = PI / 2
			building.add_child(band)
	
	return building

func add_collision_to_building(building_node: Node3D, width: float, depth: float, height: float):
	if width <= 0 or depth <= 0 or height <= 0:
		return
	var body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(width, max(height, 1.0), depth)
	collision.shape = shape
	body.add_child(collision)
	body.position = Vector3(0, height / 2, 0)
	building_node.add_child(body)

func generate_subdivided_block_async(grid_x: int, grid_z: int, available_buildings: Array[PackedScene], block_size: Vector2i = Vector2i(1, 1)):
	var cfg = city_configuration
	var bounds = get_block_world_bounds(grid_x, grid_z)
	
	var subdivision_grid = get_subdivision_grid()
	var density_settings = get_district_density_settings("residential")
	subdivision_grid.x *= block_size.x
	subdivision_grid.y *= block_size.y
	var total_internal_street_width_x = (subdivision_grid.x - 1) * cfg.subdivision_street_width
	var total_internal_street_width_z = (subdivision_grid.y - 1) * cfg.subdivision_street_width
	var subdivision_size_x = (bounds.size.x - total_internal_street_width_x) / subdivision_grid.x
	var subdivision_size_z = (bounds.size.y - total_internal_street_width_z) / subdivision_grid.y
	
	if cfg.generate_subdivision_roads:
		generate_subdivision_road_network(bounds.center, subdivision_grid, subdivision_size_x, subdivision_size_z, bounds.size.x, bounds.size.y)
	
	var processed_subdivisions = 0
	for sub_x in range(subdivision_grid.x):
		for sub_z in range(subdivision_grid.y):
			var local_x = (sub_x - subdivision_grid.x / 2.0 + 0.5) * (subdivision_size_x + cfg.subdivision_street_width)
			var local_z = (sub_z - subdivision_grid.y / 2.0 + 0.5) * (subdivision_size_z + cfg.subdivision_street_width)
			var subdivision_center = bounds.center + Vector3(local_x, 0, local_z)
			
			var terrain_y = sample_terrain_height(subdivision_center.x, subdivision_center.z) if cfg.enable_terrain else bounds.center.y
			subdivision_center.y = terrain_y
			
			if cfg.enable_terrain:
				var slope = get_terrain_slope(subdivision_center.x, subdivision_center.z)
				if slope > cfg.max_buildable_slope:
					continue
			
			var building_count = randi_range(density_settings.min_buildings, density_settings.max_buildings)
			var building_positions = []
			var buildings_to_spawn = []
			var max_attempts = building_count * 10
			
			for i in range(building_count):
				var attempts = 0
				var valid_position = false
				while not valid_position and attempts < max_attempts:
					var local_pos = Vector3(
						randf_range(-subdivision_size_x / 2 + density_settings.border_margin, subdivision_size_x / 2 - density_settings.border_margin),
						0,
						randf_range(-subdivision_size_z / 2 + density_settings.border_margin, subdivision_size_z / 2 - density_settings.border_margin)
					)
					var world_pos = subdivision_center + local_pos
					valid_position = true
					for existing_pos in building_positions:
						if world_pos.distance_to(existing_pos) < density_settings.spacing:
							valid_position = false
							break
					if valid_position:
						building_positions.append(world_pos)
						buildings_to_spawn.append(world_pos)
					attempts += 1
			
			for world_pos in buildings_to_spawn:
				var floors = get_floor_count("residential") if cfg.enable_multi_story else 1
				var bldg_h = floors * cfg.floor_height
				var use_prefab = floors <= 2 and not available_buildings.is_empty() and randi() % 2 == 0
				var building_node: Node3D
				if use_prefab:
					building_node = available_buildings[randi() % available_buildings.size()].instantiate()
					building_node.position = world_pos
					building_node.rotation.y = [0, PI/2, PI, 3*PI/2][randi() % 4]
				else:
					var bldg_w = randf_range(6, 14)
					var bldg_d = randf_range(6, 14)
					building_node = spawn_procedural_building(world_pos, bldg_w, bldg_d, bldg_h, floors, "residential")
					if cfg.generate_collision:
						add_collision_to_building(building_node, bldg_w, bldg_d, bldg_h)
				
				add_child(building_node)
				building_node.owner = get_tree().edited_scene_root
			
			processed_subdivisions += 1
			if processed_subdivisions % 4 == 0:
				await get_tree().process_frame

func emit_progress(current: int, total: int, stage: String):
	if enable_progress_feedback:
		generation_progress.emit(current, total, stage)
		print("Progress: %d%% - %s" % [current, stage])

func get_district_type(grid_x: int, grid_z: int) -> String:
	var cfg = city_configuration
	var clamped_x = clamp(grid_x, 0, cfg.grid_width - 1)
	var clamped_z = clamp(grid_z, 0, cfg.grid_height - 1)
	var district: String
	
	match cfg.district_mode:
		0:
			var noise_value = noise.get_noise_2d(clamped_x, clamped_z)
			noise_value = (noise_value + 1.0) / 2.0
			var total_ratio = cfg.residential_ratio + cfg.commercial_ratio + cfg.industrial_ratio + cfg.park_ratio
			var r_norm = cfg.residential_ratio / total_ratio
			var c_norm = cfg.commercial_ratio / total_ratio
			var i_norm = cfg.industrial_ratio / total_ratio
			if noise_value < r_norm:
				district = "residential"
			elif noise_value < r_norm + c_norm:
				district = "commercial"
			elif noise_value < r_norm + c_norm + i_norm:
				district = "industrial"
			else:
				district = "park"
		1:
			var center_x = cfg.grid_width / 2.0
			var center_z = cfg.grid_height / 2.0
			var dist_from_center = Vector2(clamped_x - center_x, clamped_z - center_z).length()
			var max_dist = Vector2(center_x, center_z).length()
			var normalized_dist = dist_from_center / max_dist if max_dist > 0 else 0
			if normalized_dist < 0.25:
				district = "commercial"
			elif normalized_dist > 0.75:
				district = "industrial"
			elif normalized_dist > 0.55 and normalized_dist < 0.65:
				if randf() < cfg.park_ratio * 2:
					district = "park"
				else:
					district = "residential"
			else:
				district = "residential"
		2:
			var seed_value = clamped_x * 1000 + clamped_z
			var rng = RandomNumberGenerator.new()
			rng.seed = seed_value
			var rand_val = rng.randf()
			var total = cfg.residential_ratio + cfg.commercial_ratio + cfg.industrial_ratio + cfg.park_ratio
			var rn = cfg.residential_ratio / total
			var cn = cfg.commercial_ratio / total
			var pin = cfg.industrial_ratio / total
			if rand_val < rn:
				district = "residential"
			elif rand_val < rn + cn:
				district = "commercial"
			elif rand_val < rn + cn + pin:
				district = "industrial"
			else:
				district = "park"
	
	if district == "park" and not cfg.park_ratio > 0:
		district = "residential"
	
	return district

func get_buildings_for_district(district: String) -> Array[PackedScene]:
	var cfg = city_configuration
	match district:
		"residential":
			return cfg.residential_buildings
		"commercial":
			return cfg.commercial_buildings
		"industrial":
			return cfg.industrial_buildings
		"park":
			return cfg.park_elements
		_:
			return cfg.residential_buildings

func get_district_density_settings(district: String) -> Dictionary:
	var cfg = city_configuration
	match district:
		"residential":
			return {
				"min_buildings": cfg.residential_buildings_min,
				"max_buildings": cfg.residential_buildings_max,
				"spacing": cfg.residential_spacing,
				"border_margin": cfg.residential_border_margin
			}
		"commercial":
			return {
				"min_buildings": cfg.commercial_buildings_min,
				"max_buildings": cfg.commercial_buildings_max,
				"spacing": cfg.commercial_spacing,
				"border_margin": cfg.commercial_border_margin
			}
		"industrial":
			return {
				"min_buildings": cfg.industrial_buildings_min,
				"max_buildings": cfg.industrial_buildings_max,
				"spacing": cfg.industrial_spacing,
				"border_margin": cfg.industrial_border_margin
			}
		_:
			return {
				"min_buildings": 1,
				"max_buildings": 4,
				"spacing": 20.0,
				"border_margin": 10.0
			}

func get_subdivision_grid() -> Vector2i:
	match city_configuration.subdivision_mode:
		0:
			match city_configuration.subdivision_layout:
				0: return Vector2i(2, 2)
				1: return Vector2i(2, 3)
				2: return Vector2i(3, 3)
				_: return Vector2i(2, 2)
		1:
			var layouts = [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3)]
			return layouts[randi() % layouts.size()]
		_:
			return Vector2i(2, 2)

func generate_subdivision_road_network(block_center: Vector3, subdivision_grid: Vector2i, subdivision_size_x: float, subdivision_size_z: float, world_width: float = 0, world_height: float = 0):
	var cfg = city_configuration
	var actual_width = world_width if world_width > 0 else cfg.block_size
	var actual_height = world_height if world_height > 0 else cfg.block_size
	if subdivision_grid.x <= 1 and subdivision_grid.y <= 1:
		return
	
	for i in range(subdivision_grid.y - 1):
		var z_offset = (i - (subdivision_grid.y - 2) / 2.0) * (subdivision_size_z + cfg.subdivision_street_width)
		var y = sample_terrain_height(block_center.x, block_center.z + z_offset) if cfg.enable_terrain else block_center.y
		var road_center = block_center + Vector3(0, cfg.intersection_height_offset * 2, z_offset)
		road_center.y = y
		create_road_plane(road_center, Vector2(actual_width, cfg.subdivision_street_width), "SubdivisionRoad")
	
	for i in range(subdivision_grid.x - 1):
		var x_offset = (i - (subdivision_grid.x - 2) / 2.0) * (subdivision_size_x + cfg.subdivision_street_width)
		var y = sample_terrain_height(block_center.x + x_offset, block_center.z) if cfg.enable_terrain else block_center.y
		var road_center = block_center + Vector3(x_offset, cfg.intersection_height_offset * 2, 0)
		road_center.y = y
		create_road_plane(road_center, Vector2(cfg.subdivision_street_width, actual_height), "SubdivisionRoad")

func spawn_building_at_position(world_pos: Vector3, available_buildings: Array[PackedScene]):
	var building_scene = available_buildings[randi() % available_buildings.size()]
	var building = building_scene.instantiate()
	building.position = world_pos
	match city_configuration.rotation_mode:
		0:
			building.rotation.y = randf_range(0, TAU)
		1:
			var rotation_steps = [0, PI / 2, PI, 3 * PI / 2]
			building.rotation.y = rotation_steps[randi() % rotation_steps.size()]
		2:
			building.rotation.y = 0
		3:
			building.rotation.y = [0, PI / 2, PI, 3 * PI / 2][randi() % 4]
	if city_configuration.scale_variation != 0:
		var scale_factor = 1.0 + randf_range(-city_configuration.scale_variation, city_configuration.scale_variation)
		building.scale = Vector3.ONE * scale_factor
	add_child(building)
	building.owner = get_tree().edited_scene_root

func create_intersection_plane(center: Vector3, size: Vector2):
	var body = StaticBody3D.new()
	body.name = "Intersection"
	body.position = center

	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size
	mesh_instance.mesh = plane_mesh
	if city_configuration.intersection_material:
		mesh_instance.material_override = city_configuration.intersection_material
	elif city_configuration.road_material:
		mesh_instance.material_override = city_configuration.road_material

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(size.x, 0.1, size.y)
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)
	body.owner = get_tree().edited_scene_root
	mesh_instance.owner = get_tree().edited_scene_root
	collision.owner = get_tree().edited_scene_root

func create_road_plane(center: Vector3, size: Vector2, road_type: String):
	var body = StaticBody3D.new()
	body.name = road_type
	body.position = center

	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size
	mesh_instance.mesh = plane_mesh
	if road_type == "SubdivisionRoad" and city_configuration.subdivision_road_material:
		mesh_instance.material_override = city_configuration.subdivision_road_material
	elif road_type == "Avenue" and city_configuration.avenue_material:
		mesh_instance.material_override = city_configuration.avenue_material
	elif city_configuration.road_material:
		mesh_instance.material_override = city_configuration.road_material

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(size.x, 0.1, size.y)
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)
	body.owner = get_tree().edited_scene_root
	mesh_instance.owner = get_tree().edited_scene_root
	collision.owner = get_tree().edited_scene_root

func create_ground_plane(center: Vector3, size: Vector2, district_type: String = ""):
	var body = StaticBody3D.new()
	body.name = "Ground_" + district_type if district_type != "" else "Ground"
	body.position = center

	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size
	mesh_instance.mesh = plane_mesh
	var material_to_use: Material = null
	match district_type:
		"residential":
			material_to_use = city_configuration.residential_ground_material
		"commercial":
			material_to_use = city_configuration.commercial_ground_material
		"industrial":
			material_to_use = city_configuration.industrial_ground_material
		"park":
			material_to_use = city_configuration.park_ground_material
	if not material_to_use:
		material_to_use = city_configuration.ground_material
	if material_to_use:
		mesh_instance.material_override = material_to_use

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(size.x, 0.1, size.y)
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)
	body.owner = get_tree().edited_scene_root
	mesh_instance.owner = get_tree().edited_scene_root
	collision.owner = get_tree().edited_scene_root

func generate_navigation_async():
	emit_progress(90, 100, "Generating navigation mesh...")
	
	var nav_region = NavigationRegion3D.new()
	nav_region.name = "CityNavigation"
	
	var nav_mesh = NavigationMesh.new()
	nav_mesh.cell_size = city_configuration.navmesh_cell_size
	
	nav_region.navigation_mesh = nav_mesh
	add_child(nav_region)
	nav_region.owner = get_tree().edited_scene_root
	
	if Engine.is_editor_hint():
		nav_region.bake_navigation_mesh()
	
	await get_tree().process_frame
	emit_progress(95, 100, "Navigation mesh generated")

func clear_city():
	if is_generating:
		print("Cannot clear city while generation is in progress!")
		return
	clear_all_buildings()
	active_blocks.clear()
	block_sizes.clear()
	occupied_positions.clear()
	_heightmap_image = null
	_terrain_heights.clear()

func clear_all_buildings():
	for child in get_children():
		child.queue_free()
