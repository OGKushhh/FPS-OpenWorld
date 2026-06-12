@tool
class_name CityConfiguration
extends Resource

@export_group("Grid Layout")
@export var grid_width: int = 8
@export var grid_height: int = 8
@export var block_size: float = 200.0
@export var street_width: float = 25.0

@export_group("Block Variations")
@export var enable_multi_size_blocks: bool = false
@export_range(0.0, 1.0) var large_block_chance: float = 0.15
@export_range(0.0, 1.0) var wide_block_chance: float = 0.1
@export_range(0.0, 1.0) var tall_block_chance: float = 0.1
@export var enable_edge_extensions: bool = true
@export_range(0.0, 1.0) var edge_extension_chance: float = 0.8
@export var max_edge_extensions: int = 50
@export_range(0.0, 0.5) var empty_block_chance: float = 0.01

@export_group("Districts")
@export_enum("Noise Based", "Zoned Areas", "Random Mix") var district_mode: int = 0
@export_range(0.0, 1.0) var residential_ratio: float = 0.25
@export_range(0.0, 1.0) var commercial_ratio: float = 0.30
@export_range(0.0, 1.0) var industrial_ratio: float = 0.25
@export_range(0.0, 1.0) var park_ratio: float = 0.20
@export var noise_scale: float = 0.1

@export_group("Building Scenes")
@export var residential_buildings: Array[PackedScene] = []
@export var commercial_buildings: Array[PackedScene] = []
@export var industrial_buildings: Array[PackedScene] = []
@export var park_elements: Array[PackedScene] = []

@export_group("Building Placement")
@export_enum("Free", "90 Degrees", "No Rotation", "Street Facing") var rotation_mode: int = 3
@export_range(-1.0, 1.0) var scale_variation: float = 0.2
@export var enable_grid_aligned: bool = true
@export var front_setback: float = 10.0
@export var side_setback: float = 6.0
@export var rear_setback: float = 8.0
@export var corner_lot_placement: bool = true

@export_subgroup("Residential")
@export var enable_residential_subdivisions: bool = true
@export_enum("Fixed Layout", "Random Layout") var subdivision_mode: int = 1
@export_enum("2x2", "2x3", "3x3") var subdivision_layout: int = 0
@export var subdivision_street_width: float = 8.0
@export var residential_buildings_min: int = 3
@export var residential_buildings_max: int = 6
@export var residential_spacing: float = 20.0
@export var residential_border_margin: float = 15.0

@export_subgroup("Commercial")
@export var commercial_buildings_min: int = 8
@export var commercial_buildings_max: int = 10
@export var commercial_spacing: float = 50.0
@export var commercial_border_margin: float = 25.0

@export_subgroup("Industrial")
@export var industrial_buildings_min: int = 25
@export var industrial_buildings_max: int = 30
@export var industrial_spacing: float = 35.0
@export var industrial_border_margin: float = 25.0

@export_subgroup("Park")
@export var park_elements_count_min: int = 8
@export var park_elements_count_max: int = 20
@export var park_path_width: float = 2.0

@export_group("Multi-Story Buildings")
@export var enable_multi_story: bool = true
@export var floor_height: float = 3.5
@export var procedural_wall_material: Material
@export var procedural_window_material: Material
@export var procedural_roof_material: Material

@export_subgroup("Residential Floors")
@export var residential_min_floors: int = 1
@export var residential_max_floors: int = 3

@export_subgroup("Commercial Floors")
@export var commercial_min_floors: int = 2
@export var commercial_max_floors: int = 10

@export_subgroup("Industrial Floors")
@export var industrial_min_floors: int = 1
@export var industrial_max_floors: int = 4

@export_group("Roads")
@export var generate_roads: bool = true
@export var generate_intersections: bool = true
@export var road_material: Material
@export var intersection_material: Material
@export var intersection_height_offset: float = 0.01
@export var generate_subdivision_roads: bool = true
@export var subdivision_road_material: Material

@export_subgroup("Road Hierarchy")
@export var enable_main_avenues: bool = true
@export var avenue_width: float = 40.0
@export var avenue_interval: int = 3
@export var avenue_material: Material

@export_subgroup("Roundabouts")
@export var enable_roundabouts: bool = true
@export var roundabout_radius: float = 12.0
@export var roundabout_material: Material

@export_subgroup("Diagonal Roads")
@export var enable_diagonal_roads: bool = false
@export var diagonal_road_width: float = 20.0

@export_group("Navigation & Collision")
@export var generate_collision: bool = true
@export var generate_navigation: bool = true
@export var navmesh_cell_size: float = 0.5

@export_group("Terrain")
@export var enable_terrain: bool = false
@export var heightmap_texture: Texture2D
@export var terrain_height_scale: float = 50.0
@export var terrain_base_height: float = 0.0
@export var max_buildable_slope: float = 30.0
@export var terrain_sample_resolution: int = 512

@export_group("Ground")
@export var generate_ground: bool = true
@export var ground_height_offset: float = -0.1
@export var ground_material: Material
@export var residential_ground_material: Material
@export var commercial_ground_material: Material
@export var industrial_ground_material: Material
@export var park_ground_material: Material


static func create_default() -> CityConfiguration:
	return CityConfiguration.new()

func is_valid() -> bool:
	return (residential_buildings.size() > 0 or 
			commercial_buildings.size() > 0 or 
			industrial_buildings.size() > 0)
