# Porto Seco — World Setup Guide

## What's included

| Folder | Contents |
|---|---|
| `world/porto_seco.tscn` | Main world scene — open this to play |
| `world/porto_seco_config.tres` | CityСrafter configuration resource |
| `world/buildings/residential/` | 5 residential building scenes |
| `world/buildings/commercial/` | 5 commercial building scenes |
| `world/buildings/industrial/` | 4 industrial building scenes |
| `world/interiors/` | 6 furnished interior scenes (bedroom, kitchen, living room, office, gym, bathroom) |
| `world/props/street_populator.gd` | Street prop + vehicle scattering tool |
| `autoloads/world_stream.gd` | Chunk streaming system (4×4, 500m chunks) |
| `addons/citycrafter/` | CityСrafter v1.1 plugin |
| `resources/assetsville/` | All Assetsville GLTF assets (340+ files) |
| `resources/furniture/` | 40 furniture GLBs |
| `resources/vehicles/` | 8 vehicle GLBs |

---

## Step 1 — Enable the plugin

1. Open **Project → Project Settings → Plugins**
2. Enable **CityСrafter3D**

---

## Step 2 — Register the autoload

In `project.godot` add under `[autoload]`:
```
WorldStream="*res://autoloads/world_stream.gd"
```

---

## Step 3 — Generate the city

1. Open `world/porto_seco.tscn`
2. Select the **CityCrafter** node in the scene tree
3. In the Inspector, the `city_configuration` field is already set to `porto_seco_config.tres`
4. Click **Generate City Button** → watch it build

The generator places buildings across an 8×8 block grid (~1800×1800m):
- **Center** → commercial (The Strip, shops, gas stations, motels)
- **Middle ring** → residential (Highlands, apartments, cottages)
- **Outer ring** → industrial (The Yards, warehouses, scrapyards, barns)

---

## Step 4 — Scatter street props

1. Add a `Node3D` to `porto_seco.tscn`
2. Attach `world/props/street_populator.gd`
3. In the Inspector, toggle **Populate Button**
4. Props + parked vehicles appear along all street edges

---

## Step 5 — Accessible interiors

Each building that should have an accessible interior needs an `Area3D` child node at its door:

1. Add `Area3D` + `CollisionShape3D` (box, ~2×2×1m) at the door position
2. Attach `world/interiors/interior_trigger.gd`
3. Set `interior_scene` to one of the interior `.tscn` files:
   - `bedroom.tscn` — for houses/apartments
   - `living_room.tscn` — for houses
   - `kitchen.tscn` — for houses/shops
   - `office.tscn` — for commercial buildings
   - `gym.tscn` — for motel/residential
   - `bathroom.tscn` — for any building

When the player walks through the door, the interior loads. It unloads 5 seconds after the player leaves.

---

## City layout — Porto Seco

```
       N
       ↑
  ┌─────────────────────┐
  │  HIGHLANDS          │  ← Winding residential, cottages, apartments
  │  (winding roads)    │
  ├─────────────────────┤
  │  THE STRIP    MIDTOWN│  ← Commercial core, shops, motels, gas stations
  │  (dense blocks)     │
  ├─────────────────────┤
  │  CANALES            │  ← Trailer parks, pawn shops, tight alleys
  ├─────────────────────┤
  │  THE YARDS          │  ← Warehouses, barns, scrapyards, industrial
  └─────────────────────┘
       ↓ (peninsula tip — water)
```

**Design principles applied:**
- Roads bend every ~225m (block + street) — no straight sightlines across the map
- Density contrast: tight commercial core → open industrial yards → residential subdivisions
- Vertical billboard billboards mark district identity
- Parked vehicles on 40% of block edges (randomized per block seed)
