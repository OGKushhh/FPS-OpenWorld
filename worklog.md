# SIGNAL — Porto Seco FPS Project Worklog

## Project Overview
Godot 4.6 tactical FPS prototype ("SIGNAL") with Valorant-accurate gunplay, procedural city generation (CityCrafter), shooting range, and undead enemies. 200 files across weapons, world, player, HUD, VFX, and AI systems.

**Note:** Resource files (textures, models, audio — ~220MB) were excluded from the upload. All improvements below assume resources will be re-linked or procedurally generated.

---

## Improvement Backlog — Easiest to Hardest

### Task 1: District Color Palettes (#7)
- **Effort:** Trivial (~10 lines of code)
- **Priority:** Low
- **Status:** Not Started

**Why it's easy:** Ground materials per district already exist (`ground_commercial.tres`, `ground_residential.tres`, `ground_industrial.tres`, `ground_park.tres`). Extending district tinting to buildings is a matter of reading the district type and applying a color modulation to the building's MeshInstance3D material override.

**What to do:**
- In `citycrafter.gd`, after placing a building, read the current district type
- Apply a subtle color tint via `material_override` or `modulate` on the building root
- Define a `Dictionary` mapping district → Color (e.g., commercial = warm amber, residential = soft blue, industrial = grey-green)
- Reuse the same district noise/zone lookup already used for ground materials

**Files to modify:** `addons/citycrafter/citycrafter.gd`

**Dependencies:** None — can be done immediately.

---

### Task 2: Fallback Procedural Textures (#6)
- **Effort:** Low (one function, plug in once)
- **Priority:** Medium
- **Status:** Not Started

**Why it's easy:** This is a single defensive function that catches the case where external texture resources fail to load (missing .import files, broken UID references, etc.). Without it, buildings render as pink/magenta — the Godot default for missing textures. One function, called once per material creation, prevents a whole class of visual bugs.

**What to do:**
- Write a `func _get_safe_texture(path: String) -> Texture2D` in `citycrafter.gd`
- Try `load(path)`, if null, generate a procedural `GradientTexture2D` or `NoiseTexture2D` as fallback
- For walls: simple plaster/concrete gradient (light grey with slight variation)
- For roofs: dark flat color
- For windows: dark rectangle on light background
- Call this function everywhere textures are loaded for building materials
- Optionally log a warning when fallback is triggered

**Files to modify:** `addons/citycrafter/citycrafter.gd`

**Dependencies:** None — can be done immediately.

---

### Task 3: Streetlights + Street Props (#2)
- **Effort:** Low
- **Priority:** Medium-High
- **Status:** Not Started

**Why it's easy:** `world/props/street_populator.gd` already exists as a `@tool` script with logic for scattering props along roads. 205 prop references are already defined. The gap is that it's an editor-only tool that needs to be triggered automatically after CityCrafter finishes generating a block, and streetlights need to be added to the prop pool.

**What to do:**
- Add streetlight scenes to the prop pool in `street_populator.gd` or `city_configuration.gd`
- In `citycrafter.gd`, after each block is generated, call `street_populator.populate(block_area, road_data)` (or equivalent)
- Ensure prop placement respects road edges, sidewalks, and doesn't overlap buildings
- Add a light source (OmniLight3D or SpotLight3D) to each streetlight scene
- Consider night/day toggle for streetlight activation
- Validate that props don't spawn inside building footprints

**Files to modify:**
- `world/props/street_populator.gd`
- `addons/citycrafter/citycrafter.gd`
- `addons/citycrafter/city_configuration.gd`
- New: `world/props/streetlight.tscn`

**Dependencies:** None — can be done immediately, though LOD (Task 4) will help with prop performance later.

---

### Task 4: LOD System (#5) — Critical Performance
- **Effort:** Medium
- **Priority:** Critical
- **Status:** Not Started

**Why it's critical, not optional:** An open world with 35 building types placed hundreds of times will kill FPS without LOD. Each building is currently full-detail at any distance. Godot's `VisibilityRangeFadeMode` is built-in and makes this straightforward, but it needs to be applied systematically to every building wrapper scene.

**What to do:**
- For each building scene in `world/buildings/` (residential, commercial, industrial, scaled), create LOD variants:
  - **LOD0** (0–80m): Full detail — all geometry, windows, interior detail
  - **LOD1** (80–200m): Reduced — simplified mesh, baked texture, no interior props
  - **LOD2** (200m+): Billboard or very low-poly box with baked facade texture
- Use Godot's `visibility_range_begin` / `visibility_range_end` on each LOD child node
- Set `VisibilityRangeFadeMode = VISIBILITY_RANGE_FADE_SELF` for smooth transitions
- The `world/buildings/scaled/` wrapper scenes are ideal insertion points — they already wrap building instances
- For the scaled buildings (which reference other scenes via instance placeholders), add LOD children alongside the existing reference
- Test with 50+ buildings visible simultaneously to verify performance gain
- Add `visibility_range_begin_margin` and `visibility_range_end_margin` (5–10m) to prevent pop-in

**Files to modify:**
- All 30+ scenes in `world/buildings/scaled/`
- All 12+ scenes in `world/buildings/residential/`, `commercial/`, `industrial/`
- New: LOD mesh variants (can be generated by decimating source meshes)
- Optionally: `addons/citycrafter/citycrafter.gd` to auto-generate LOD wrappers

**Dependencies:** None technically, but doing this before the city grows larger is strongly recommended.

---

### Task 5: MultiMesh Instancing for Trees/Props
- **Effort:** Medium
- **Priority:** High
- **Status:** Not Started

**Why it matters:** Spawning 1000 individual tree nodes will tank performance. Each Node3D has overhead — transform, processing, physics integration. `MultiMeshInstance3D` collapses thousands of identical meshes into a single draw call. This is essential before adding significant vegetation or prop density.

**What to do:**
- Create a `MultiMeshManager` autoload or utility class
- For each repeated prop type (trees, streetlights, trash cans, benches), collect all placement positions during generation
- Create a `MultiMesh` per prop type, set `mesh` and `instance_count`
- Set transforms via `set_instance_transform(i, transform)` in a loop
- Use `MultiMesh.transform_format = MULTIMESH_TRANSFORM_3D` for full 3D placement
- For trees: add randomized scale/rotation per instance for variety
- Replace individual node spawning in `street_populator.gd` with position collection + MultiMesh batch
- For streetlights with lights: keep OmniLight3D as separate nodes (lights can't be MultiMeshed), but batch the visual mesh
- Consider `Multimesh.loD_bias` for distance-based rendering
- Profile before/after with 500+ instances

**Files to modify:**
- `world/props/street_populator.gd` — switch from individual nodes to position arrays
- `addons/citycrafter/citycrafter.gd` — collect tree positions during generation
- New: `common/utils/multimesh_manager.gd`

**Dependencies:** Should be done alongside or before Task 3 (street props) to avoid rework.

---

### Task 6: Green Spaces Between Buildings (#4)
- **Effort:** Medium
- **Priority:** Medium
- **Status:** Not Started

**Why medium effort:** Requires post-placement space scanning — after buildings are placed, scan for gaps between them that are large enough for a park/garden but too small for another building. This is a secondary pass over the already-generated block layout.

**What to do:**
- After CityCrafter places all buildings in a block, run a secondary pass:
  1. Collect all building footprints as `Rect2` or `AABB` on the ground plane
  2. Expand each footprint by a margin (e.g., 3m) for minimum building spacing
  3. Subtract expanded footprints from the block area to find residual spaces
  4. Filter residual spaces by minimum area threshold (e.g., 25m² = small garden, 100m² = park)
  5. For qualifying spaces, place a green-space scene (grass, trees, benches, fence)
- Use the existing `ground_park.tres` material for the ground plane under green spaces
- Tree placement within green spaces should use MultiMesh (Task 5)
- Consider district-aware rules: residential gets more gardens, industrial gets fewer, commercial gets plazas
- Add park district type to `city_configuration.gd`

**Files to modify:**
- `addons/citycrafter/citycrafter.gd` — add post-placement scanning pass
- `addons/citycrafter/city_configuration.gd` — add green space config
- New: `world/buildings/parks/` directory with park/garden/plaza scenes

**Dependencies:** Task 5 (MultiMesh) should be done first for tree performance.

---

### Task 7: Voronoi Districts
- **Effort:** Medium-High
- **Priority:** Medium
- **Status:** Not Started

**Why it's worth doing:** Real cities don't have clean concentric ring districts. They have organic, irregular boundaries shaped by geography, history, and infrastructure. The current noise-based zoning creates predictable concentric rings (commercial center → residential ring → industrial outer). Voronoi diagrams produce natural-looking, irregular district boundaries that feel much more believable.

**What to do:**
- Replace the noise-based district assignment in `citycrafter.gd` with Voronoi-based zoning:
  1. Generate N seed points (one per district) using Poisson disk sampling or random placement
  2. For each cell in the grid, assign it to the nearest seed point (Voronoi assignment)
  3. Optionally relax the Voronoi diagram (Lloyd's algorithm — move each seed to the centroid of its cell, repeat 2-3 times) for more even district sizes
  4. Assign district types to Voronoi cells using weighted rules:
     - Central cells → commercial
     - Cells adjacent to main roads → mixed commercial/residential
     - Peripheral cells → industrial
     - Cells near green spaces → residential
  5. Smooth boundaries slightly to avoid single-cell jagged edges
- The existing district noise can be kept as a secondary modifier for sub-district variation
- Ensure `city_configuration.gd` still controls district ratios (what % commercial, residential, etc.)

**Code reference (from user's snippet):**
```gdscript
# Voronoi district assignment
var district_seeds: Array[Vector2] = []
for i in num_districts:
    district_seeds.append(Vector2(randf() * city_width, randf() * city_depth))

func get_district(cell_x: int, cell_z: int) -> String:
    var closest_seed: int = 0
    var closest_dist: float = INF
    for i in district_seeds.size():
        var d = Vector2(cell_x, cell_z).distance_squared_to(district_seeds[i])
        if d < closest_dist:
            closest_dist = d
            closest_seed = i
    return district_types[closest_seed]
```

**Files to modify:**
- `addons/citycrafter/citycrafter.gd` — replace district noise with Voronoi
- `addons/citycrafter/city_configuration.gd` — add district seed count, relaxation iterations

**Dependencies:** None — this is a self-contained change to the district logic.

---

### Task 8: Heightmap-Based Terrain (The Terrain Canvas)
- **Effort:** High
- **Priority:** Medium-High
- **Status:** Not Started

**Why it's hard:** This replaces the current flat+noise terrain with a designer-controlled heightmap system. It requires new assets (heightmap textures), integration with the city generator to ensure buildings sit on terrain correctly, road generation that follows elevation, and navigation mesh that respects height. It's a foundational change that affects nearly every world system.

**What to do:**
- Create or source heightmap textures for the city's base terrain shape (e.g., `city_base_canvas.png`)
- Load the heightmap in `citycrafter.gd` and sample it to determine terrain height at each point
- Blend the heightmap with seed-based noise for variety (warp coordinates using noise)
- When placing buildings, snap their Y position to the terrain height at their location
- Adjust road generation to follow terrain contours (no floating roads on steep slopes)
- Flatten terrain under building footprints to prevent clipping
- Add slope constraints: don't place buildings on slopes > 15°, don't place roads on slopes > 30°
- Generate `NavigationRegion3D` bake mesh that respects terrain height
- Update `world_stream.gd` chunk loading to account for terrain height variance
- Consider water level: cells below sea level become water features

**Code reference (from user's snippet):**
```gdscript
var base_heightmap = load("res://assets/heightmaps/city_base_canvas.png")
# Warp coordinates with seed noise for variety
var warped_x = x + noise.get_noise_2d(x * 0.1, z * 0.1) * warp_strength
var warped_z = z + noise.get_noise_2d(x * 0.1 + 100, z * 0.1 + 100) * warp_strength
var height = sample_heightmap(base_heightmap, warped_x, warped_z)
```

**Files to modify:**
- `addons/citycrafter/citycrafter.gd` — heightmap sampling, terrain generation
- `addons/citycrafter/city_configuration.gd` — heightmap path, terrain params
- `autoloads/world_stream.gd` — height-aware chunk loading
- New: `assets/heightmaps/` directory with heightmap textures
- Potentially: all building scenes need Y-snapping logic

**Dependencies:** Should be done after Task 7 (Voronoi districts) since district boundaries may be influenced by terrain features.

---

### Task 9: District Rules (Biome Painting)
- **Effort:** High
- **Priority:** Medium
- **Status:** Not Started

**Why it's hard:** This introduces a rule-based placement system that considers context (road proximity, neighbor types, open space, terrain) when assigning district types and placing buildings. It's a significant logic layer on top of the existing generation pipeline, requiring careful rule definition and testing to produce sensible cities.

**What to do:**
- Define a rule system in `citycrafter.gd` or a new `district_rules.gd`:
  - Each rule is a condition → action pair
  - Conditions can check: distance to highway, number of adjacent open spaces, current terrain slope, neighbor district types, distance to city center
  - Actions: assign district type, place landmark building, create green space, mark as water
- Example rules:
  - Commercial only if within 5 cells of a main road AND >8 adjacent open spaces
  - Residential avoids cells adjacent to industrial
  - Industrial prefers cells far from city center AND near roads
  - Parks placed near residential clusters with >4 adjacent residential cells
- Rules should be configurable via `city_configuration.gd` for different city styles
- Implement as a constraint solver: generate candidate assignments, score them by rule satisfaction, pick the best
- This replaces or supplements the Voronoi district assignment (Task 7)
- Add validation pass: check that no rule-violating district assignments exist, re-roll if needed

**Code reference (from user's snippet):**
```gdscript
if highway_distance < 5 and open_adjacencies > 8:
    district_type = "commercial"
```

**Files to modify:**
- `addons/citycrafter/citycrafter.gd` — rule-based district assignment
- `addons/citycrafter/city_configuration.gd` — rule definitions
- New: `addons/citycrafter/district_rules.gd` (optional, for separation)

**Dependencies:** Task 7 (Voronoi districts) should be done first — rules can then refine Voronoi boundaries.

---

### Task 10: Location Filters (Smart Placement)
- **Effort:** High
- **Priority:** Medium
- **Status:** Not Started

**Why it's hard:** This is Valheim-style placement filtering — before placing any building, check its surroundings for logical consistency. This requires a spatial query system, building footprint database, and a set of placement rules that prevent nonsensical combinations. Each building type needs its own filter criteria.

**What to do:**
- Create a `PlacementFilter` system:
  - Before placing any building, run it through all applicable filters
  - Filters check: biome/district compatibility, distance to road, proximity to similar buildings, terrain slope, space availability
  - Each building type defines its own filter criteria (e.g., police station requires: commercial district, within 100m of road intersection, not adjacent to park)
- Implement spatial queries:
  - Maintain a grid/tree of placed buildings for fast neighbor lookups
  - Raycast or grid-check for road proximity
  - AABB intersection test for space availability
- If a placement is rejected, try the next candidate from the building pool
- Add fallback: if no building passes filters for a slot, place a generic filler (empty lot, parking area)
- Support "landmark" buildings that have stricter filters but are guaranteed placement somewhere
- Log filter rejections for debugging city generation

**Code reference (from user's snippet):**
```gdscript
if not (biome == "commercial" and distance_to_road < 50):
    continue  # Reject the placement
```

**Files to modify:**
- `addons/citycrafter/citycrafter.gd` — filter integration
- `addons/citycrafter/city_configuration.gd` — per-building filter criteria
- New: `addons/citycrafter/placement_filter.gd`

**Dependencies:** Task 9 (District rules) should be done first — location filters build on top of district assignments.

---

### Task 11: Occlusion Culling
- **Effort:** Low-Medium
- **Priority:** High
- **Status:** Not Started

**Why it matters for a single-map game:** For a fixed map, you don't need chunked streaming — you need rendering efficiency. Occlusion culling is the single biggest performance win for a dense city. Buildings behind other buildings simply don't render. No code, no architecture changes — Godot 4 has this built-in, it just needs to be enabled and baked.

**What to do:**
- Enable occlusion culling in Project Settings → Rendering → Occlusion Culling → Use Occlusion Culling = `true`
- Add an `OccluderInstance3D` node to the city root scene (`world/porto_seco.tscn`)
- In the editor, select the `OccluderInstance3D` and click **Bake** — this creates a voxel-based occlusion map of the entire city
- Adjust `bake_resolution` (start with 256, increase if artifacts) — higher = more accurate but more memory
- Test: walk through the city and verify that buildings behind the current view are culled (use the Debug → Visible Collision Shapes or Frame Profiler to confirm)
- Combine with LOD (Task 4) for maximum performance:
  - Near: Full detail, occluded by occlusion culling
  - Mid: LOD1, occluded by occlusion culling
  - Far: LOD2, always visible but cheap
- Optional: Add `OccluderInstance3D` nodes inside individual building scenes for per-building interior occlusion (prevents rendering rooms behind walls)
- Verify navmesh still works after occlusion bake (should be unaffected)

**How it works:**
- Godot divides the scene into voxels and pre-computes which cells are visible from which other cells
- At runtime, the camera position is matched to a voxel cell, and only objects in visible cells are sent to the GPU
- This eliminates entire blocks of buildings from rendering when the player is on the opposite side of the city
- For Porto Seco (1800×1800m), this can reduce draw calls by 60-80% depending on viewpoint

**Files to modify:**
- `world/porto_seco.tscn` — add OccluderInstance3D node
- `project.godot` — enable occlusion culling setting
- Optionally: individual building scenes for interior occluders

**Dependencies:** None — can be done immediately. Most effective after Task 4 (LOD) is in place since both systems complement each other.

---

### Task 12: Runtime Chunked Generation (If Going Procedural)
- **Effort:** Very High
- **Priority:** Future / On Hold
- **Status:** Not Started — Only needed if the game switches from a single fixed map to procedural seed-based generation

**When this becomes relevant:** This task is for a future scenario where the game becomes a procedural, seed-based open world (like No Man's Sky or Minecraft) rather than a single designed map. If that never happens, this task stays on hold permanently. If the dev decides to go procedural, this becomes the architectural capstone.

**What changes when going procedural:**
- CityCrafter currently runs as a `@tool` in the editor — generate once, save the scene, ship it
- A procedural game needs CityCrafter to run at runtime, generating chunks on demand as the player explores
- The city is no longer a fixed scene file — it's generated from a seed, meaning the same seed always produces the same city
- Players can share seeds, and the world is effectively infinite (or very large)

**What to do (if activated):**
- Refactor `citycrafter.gd` to support partial generation:
  - `generate_chunk(chunk_coords: Vector2i)` — generate a single chunk
  - Chunks share context (district assignments, road network) but generate independently
  - District assignment (Voronoi/rules) must be computed for the entire city first, then applied per-chunk
- Create a `CityChunk` resource that stores:
  - Generated nodes for the chunk
  - References to neighboring chunks (for seam handling)
  - Building/prop placement data
- Road network must be generated globally first, then each chunk renders its portion
- Implement async generation with `Thread` or `WorkerThreadPool`:
  - Player enters a new area → check if chunk exists → if not, queue generation
  - Show a loading placeholder (low-LOD box) while generating
  - Swap in full chunk when ready
- Chunk unloading: when player is far enough, free chunk nodes and resources
- Add chunk priority: chunks closer to the player generate first
- Handle chunk seams: buildings and roads at chunk edges must align with neighbors
- Persist generated chunks to disk (optional) to avoid regenerating on re-entry
- Seed-based determinism: all random calls must use a seeded `RandomNumberGenerator` derived from the world seed + chunk coordinates
- The existing `world_stream.gd` (4×4 grid, 500m chunks) provides a starting framework but needs deep integration with CityCrafter's generation pipeline

**Files to modify (if activated):**
- `addons/citycrafter/citycrafter.gd` — major refactor for partial generation + seed determinism
- `autoloads/world_stream.gd` — integrate with CityCrafter chunk generation
- `addons/citycrafter/city_configuration.gd` — chunk size, generation params, seed
- New: `addons/citycrafter/city_chunk.gd` — chunk resource class
- New: `addons/citycrafter/chunk_manager.gd` — chunk lifecycle management

**Dependencies:** Tasks 7 (Voronoi), 8 (Heightmap), 9 (District rules), and 10 (Location filters) should all be done first — they need to operate on the full city context before chunked rendering can work correctly.

---

## Task Dependency Graph

```
Task 1 (Palettes) ──────────────────────────────── standalone
Task 2 (Fallback Textures) ─────────────────────── standalone
Task 3 (Street Props) ──────── can reference Task 5
Task 4 (LOD System) ────────────────────────────── standalone (but urgent)
Task 5 (MultiMesh) ──────────── enables Task 6
Task 6 (Green Spaces) ──────── depends on Task 5
Task 7 (Voronoi) ────────────── enables Task 8, 9
Task 8 (Heightmap) ──────────── benefits from Task 7
Task 9 (District Rules) ─────── depends on Task 7
Task 10 (Location Filters) ──── depends on Task 9
Task 11 (Occlusion Culling) ──── standalone, best after Task 4
Task 12 (Chunked Gen) ──────── ON HOLD — only if going procedural
```

## Recommended Execution Order

| Phase | Tasks | Rationale |
|-------|-------|-----------|
| **Phase 1 — Quick Wins** | 1, 2 | Trivial effort, immediate visual improvement |
| **Phase 2 — Performance** | 4, 11, 5, 3 | LOD + Occlusion Culling are the critical FPS pair; MultiMesh before adding props |
| **Phase 3 — World Quality** | 6, 7 | Green spaces and Voronoi districts dramatically improve believability |
| **Phase 4 — Terrain & Rules** | 8, 9 | Heightmap terrain and district rules are foundational for the final city |
| **Phase 5 — Intelligence** | 10 | Smart placement builds on everything above |
| **Phase 6 — If Procedural** | 12 | Only if the game switches to seed-based procedural generation |

---

## Known Issues (from initial review, not part of city generation improvements)

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| 1 | "assualt" typo in filenames/code | Low | `assualt_rifle.tscn`, `assualt_burst.tscn` |
| 2 | No game-over/respawn flow | Medium | `player_dead` signal has no listener |
| 3 | Burst fire is continuous auto-fire | Medium | No 3-round burst limiter |
| 4 | Damage overlay race condition | Low | `await` timers stack on rapid damage |
| 5 | Unreachable dead state in enemy.gd | Low | Dead code after early return |
| 6 | Spawner never speeds up | Low | min == max default spawn time |
| 7 | No weapon audio streams configured | Medium | Export slots exist, no resources |
| 8 | project_additions.txt outdated | Low | References Godot 4.3 |
| 9 | Vehicle system stub | Low | `in_vehicle` flag never set |
| 10 | Missing resource files (~220MB) | Critical | Models, textures, audio absent |
