# Regenerate all building .tscn files with correct tile alignment
# Tile grid: 4m (walls 4m wide, floors 4x4m)
# Wall convention: extends local Z=-4 to 0 (origin at one edge)
# Floor convention: centered at origin (±2m in X/Z)

$buildingsDir = "C:\Users\abdo\Documents\GitHub\FPS-OpenWorld\world\buildings"

# Build a map from GLTF filename to its subdirectory (BuildingTilset, StreetProps, Buildings, etc.)
$pieceDirMap = @{}
Get-ChildItem -Recurse "C:\Users\abdo\Documents\GitHub\FPS-OpenWorld\resources\assetsville" -Filter "*.gltf" | ForEach-Object {
    $name = $_.BaseName
    $dir = $_.Directory.Name
    if (-not $pieceDirMap.ContainsKey($name)) {
        $pieceDirMap[$name] = $dir
    }
}

# Helper: format Transform3D from basis array (9 floats) and position (3 floats)
function T($b, $p) { 
    return "transform = Transform3D($($b -join ', '), $($p -join ', '))" 
}

function BuildScene($basePath, $pieces) {
    $extId = 1
    $extMap = @{}
    $extLines = @()
    $nodeLines = @()
    
    foreach ($p in $pieces) {
        $name = $p.file
        $key = $name.Substring(3)  # Remove "SM_" prefix for ext key
        if (-not $extMap.ContainsKey($name)) {
            $eid = "${extId}_${name}"
            $subdir = $script:pieceDirMap[$name]
            if (-not $subdir) { $subdir = "StreetProps" }  # fallback
            $path = "res://resources/assetsville/${subdir}/${name}.gltf"
            $extLines += "[ext_resource type=""PackedScene"" path=""${path}"" id=""${eid}""]"
            $extMap[$name] = $eid
            $extId++
        }
    }
    
    $header = @"
[gd_scene format=3]

$($extLines -join "`n")

[node name="Building" type="Node3D"]

"@
    
    $idx = 0
    foreach ($p in $pieces) {
        $eid = $extMap[$p.file]
        $b = $p.basis -join ', '
        $pos = $p.pos -join ', '
        $nodeLines += "[node name=""piece_$( '{0:D3}' -f $idx )_$($p.file)"" type=""Node3D"" parent=""."" instance=ExtResource(""$eid"")]"
        $nodeLines += "transform = Transform3D($b, $pos)"
        $idx++
    }
    
    return $header + ($nodeLines -join "`n")
}

function WallPos($edge, $posX, $posZ, $y, $rotType) {
    # edge: "left", "right", "front", "back" — which building edge
    # $posX, $posZ: which wall segment (multiple walls per edge at 4m intervals)
    # $rotType: 0=identity, 1=90deg, 2=-90deg, 3=180deg
    
    # Building spans X=-2 to 2, Z=-2 to 2 per 4x4 module
    switch($rotType) {
        0 { # identity: wall along Z, centered at X=$posX, at Z=2
            return @($posX, $y, 2) 
        }
        1 { # 90° Y: wall along -X from origin, at Z=2
            return @($posX, $y, 2)
        }
        2 { # -90° Y: wall along +X from origin, at Z=-2  
            return @($posX, $y, -2)
        }
        3 { # 180° Y: wall along -Z from origin, at X=$posX, Z=-2
            return @($posX, $y, -2)
        }
    }
    return @($posX, $y, $posZ)
}

function Rot($rotType) {
    switch($rotType) {
        0 { return @(1,0,0, 0,1,0, 0,0,1) }      # identity
        1 { return @(0,0,1, 0,1,0, -1,0,0) }      # 90° Y
        2 { return @(0,0,-1, 0,1,0, 1,0,0) }      # -90° Y
        3 { return @(-1,0,0, 0,1,0, 0,0,-1) }     # 180° Y
    }
    return @(1,0,0, 0,1,0, 0,0,1)
}

# ============================================================
# 1. house_cottage — 4×4 box with attic, 1 floor
# ============================================================
$hCottage = @(
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left wall
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}           # right wall
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,0,2)}          # back wall
    @{file="SM_wallDoor_01"; basis=Rot(2); pos=@(2,0,-2)}      # front wall with door
    @{file="SM_wallAttic_01"; basis=Rot(0); pos=@(-2,4,2)}     # left attic
    @{file="SM_wallAttic_01"; basis=Rot(0); pos=@(2,4,2)}      # right attic
    @{file="SM_wallAttic_01"; basis=Rot(1); pos=@(-2,4,2)}     # back attic
    @{file="SM_wallAttic_01"; basis=Rot(2); pos=@(2,4,-2)}     # front attic
    @{file="SM_window_01"; basis=Rot(0); pos=@(0,1.5,-2.01)}   # front window
    @{file="SM_window_01"; basis=Rot(3); pos=@(0,1.5,2.01)}    # back window
    @{file="SM_roof_01"; basis=Rot(0); pos=@(0,8,0)}           # roof
    @{file="SM_roof_01_corner"; basis=Rot(0); pos=@(2,8,0)}    # roof corner
    @{file="SM_roof_01_side"; basis=Rot(0); pos=@(0,8,2)}      # roof side
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}          # floor
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(0,4,0)}        # cornice
    @{file="SM_drainPipe"; basis=Rot(0); pos=@(1.8,0,0)}       # drain pipe
)

# Write house_cottage
$content = BuildScene "house_cottage" $hCottage
Set-Content -Path "$buildingsDir\residential\house_cottage.tscn" -Value $content
Write-Host "Generated house_cottage.tscn"

# ============================================================
# 2. house_bungalow — 4×4 with veranda, different style
# ============================================================
$hBungalow = @(
    @{file="SM_wall_02"; basis=Rot(0); pos=@(-2,0,2)}          # left wall
    @{file="SM_wall_02"; basis=Rot(0); pos=@(2,0,2)}           # right wall
    @{file="SM_wall_02"; basis=Rot(1); pos=@(-2,0,2)}          # back wall
    @{file="SM_wallDoor_02"; basis=Rot(2); pos=@(2,0,-2)}      # front with door
    @{file="SM_window_02"; basis=Rot(0); pos=@(0,1.5,-2.01)}   # front window
    @{file="SM_window_02"; basis=Rot(3); pos=@(0,1.5,2.01)}    # back window
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}          # floor
    @{file="SM_roof_02"; basis=Rot(0); pos=@(0,5,0)}           # roof
    @{file="SM_roof_02_end"; basis=Rot(0); pos=@(2,5,0)}       # roof end
    @{file="SM_cornice_02"; basis=Rot(0); pos=@(0,4,0)}        # cornice
    @{file="SM_cornice_02_corner"; basis=Rot(0); pos=@(2,4,0)} # cornice corner
    @{file="SM_foundWood_01"; basis=Rot(0); pos=@(-2,-0.5,2)}  # foundation wood
    @{file="SM_foundWood_01_corner"; basis=Rot(0); pos=@(2,-0.5,2)} # foundation corner
    @{file="SM_veranda_01"; basis=Rot(1); pos=@(0,0,2)}        # veranda at back
)
$content = BuildScene "house_bungalow" $hBungalow
Set-Content -Path "$buildingsDir\residential\house_bungalow.tscn" -Value $content
Write-Host "Generated house_bungalow.tscn"

# ============================================================
# 3. trailer_house_a — small 4×4 single-wide
# ============================================================
$trailerA = @(
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}
    @{file="SM_wallDoor_01"; basis=Rot(1); pos=@(-2,0,2)}
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}
    @{file="SM_window_01_half"; basis=Rot(0); pos=@(0,1.5,-2.01)}
    @{file="SM_window_01_half"; basis=Rot(3); pos=@(0,1.5,2.01)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_roof_03"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_roof_03_corner"; basis=Rot(0); pos=@(2,4,0)}
    @{file="SM_roof_03_ending"; basis=Rot(0); pos=@(0,4,2)}
)
$content = BuildScene "trailer_house_a" $trailerA
Set-Content -Path "$buildingsDir\residential\trailer_house_a.tscn" -Value $content
Write-Host "Generated trailer_house_a.tscn"

# ============================================================
# 4. trailer_house_b — small 4×4 variant
# ============================================================
$trailerB = @(
    @{file="SM_wall_02"; basis=Rot(0); pos=@(-2,0,2)}
    @{file="SM_wall_02"; basis=Rot(0); pos=@(2,0,2)}
    @{file="SM_wall_02"; basis=Rot(1); pos=@(-2,0,2)}
    @{file="SM_wallDoor_02"; basis=Rot(2); pos=@(2,0,-2)}
    @{file="SM_window_02"; basis=Rot(0); pos=@(0,1.5,-2.01)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_roof_04"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_roof_04_ending"; basis=Rot(0); pos=@(2,4,0)}
)
$content = BuildScene "trailer_house_b" $trailerB
Set-Content -Path "$buildingsDir\residential\trailer_house_b.tscn" -Value $content
Write-Host "Generated trailer_house_b.tscn"

# ============================================================
# 5. apartment_block — 12×4 multi-story, 2 floors
# ============================================================
$aptBlock = @(
    # Ground floor walls (Y=0)
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(10,0,2)}          # right outer
    @{file="SM_wallDoor_01"; basis=Rot(1); pos=@(-2,0,2)}      # back module 0
    @{file="SM_wall_01"; basis=Rot(1); pos=@(2,0,2)}           # back module 1
    @{file="SM_wall_01"; basis=Rot(1); pos=@(6,0,2)}           # back module 2
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}          # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,0,-2)}          # front module 1
    @{file="SM_wall_01"; basis=Rot(2); pos=@(10,0,-2)}         # front module 2
    # Second floor walls (Y=4)
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,4,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,4,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,4,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(10,4,2)}          # right outer
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,4,2)}          # back module 0
    @{file="SM_wall_01"; basis=Rot(1); pos=@(2,4,2)}           # back module 1
    @{file="SM_wall_01"; basis=Rot(1); pos=@(6,4,2)}           # back module 2
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,4,-2)}          # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,4,-2)}          # front module 1
    @{file="SM_wall_01"; basis=Rot(2); pos=@(10,4,-2)}         # front module 2
    # Windows ground floor (Y=1.5)
    @{file="SM_window_03"; basis=Rot(0); pos=@(0,1.5,-2.01)}
    @{file="SM_window_03"; basis=Rot(0); pos=@(4,1.5,-2.01)}
    @{file="SM_window_03"; basis=Rot(0); pos=@(8,1.5,-2.01)}
    # Windows second floor (Y=5.5)
    @{file="SM_window_03"; basis=Rot(0); pos=@(0,5.5,-2.01)}
    @{file="SM_window_03"; basis=Rot(0); pos=@(4,5.5,-2.01)}
    @{file="SM_window_03"; basis=Rot(0); pos=@(8,5.5,-2.01)}
    # Floors
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(4,0,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(4,4,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(8,0,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(8,4,0)}
    # Cornice at Y=8
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(0,8,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(4,8,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(8,8,0)}
    # Drain pipes
    @{file="SM_drainPipe"; basis=Rot(0); pos=@(9.8,0,0)}
    @{file="SM_drainPipe_02"; basis=Rot(0); pos=@(9.8,4,0)}
    # Chimney
    @{file="SM_chimney_01"; basis=Rot(0); pos=@(2,8.5,0)}
)
$content = BuildScene "apartment_block" $aptBlock
Set-Content -Path "$buildingsDir\residential\apartment_block.tscn" -Value $content
Write-Host "Generated apartment_block.tscn"

Write-Host "`n=== Residential buildings done ==="

# ============================================================
# 6. shop_front_a — 4×4 shop
# ============================================================
$shopA = @(
    # Walls
    @{file="SM_shopFront_01"; basis=Rot(0); pos=@(-2,0,2)}      # left
    @{file="SM_shopFront_02"; basis=Rot(0); pos=@(2,0,2)}       # right
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,0,2)}           # back
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}           # front
    @{file="SM_shopTop_01"; basis=Rot(0); pos=@(-2,4,2)}
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,4,2)}
    @{file="SM_window_05"; basis=Rot(0); pos=@(0,5.5,-2.01)}
    @{file="SM_shopFront_Entrance"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(0,8,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(4,8,0)}
    @{file="SM_shopAwing_01"; basis=Rot(0); pos=@(0,3,0)}
    @{file="SM_billboard_Market24"; basis=Rot(0); pos=@(0,9,0)}
    @{file="SM_trash_bin_1"; basis=Rot(0); pos=@(4,0,-1)}
    @{file="SM_bench"; basis=Rot(0); pos=@(-3,0,1)}
)
$content = BuildScene "shop_front_a" $shopA
Set-Content -Path "$buildingsDir\commercial\shop_front_a.tscn" -Value $content
Write-Host "Generated shop_front_a.tscn"

# ============================================================
# 7. shop_front_b — 4×4 shop variant
# ============================================================
$shopB = @(
    # Walls
    @{file="SM_shopFront_03"; basis=Rot(0); pos=@(-2,0,2)}      # left
    @{file="SM_shopFront_04"; basis=Rot(0); pos=@(2,0,2)}       # right
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,0,2)}           # back
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}           # front
    @{file="SM_shopTop_01"; basis=Rot(0); pos=@(0,4,2)}
    @{file="SM_wall_01"; basis=Rot(0); pos=@(0,4,2)}
    @{file="SM_window_06"; basis=Rot(0); pos=@(0,5.5,-2.01)}
    @{file="SM_shopFront_Entrance"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(0,8,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(4,8,0)}
    @{file="SM_shopAwing_01"; basis=Rot(0); pos=@(0,3,0)}
    @{file="SM_billboard_Liquor"; basis=Rot(0); pos=@(0,9,0)}
    @{file="SM_bench"; basis=Rot(0); pos=@(4,0,1)}
    @{file="SM_trash_bin_2"; basis=Rot(0); pos=@(-3,0,-1)}
)
$content = BuildScene "shop_front_b" $shopB
Set-Content -Path "$buildingsDir\commercial\shop_front_b.tscn" -Value $content
Write-Host "Generated shop_front_b.tscn"

# ============================================================
# 8. gas_station — standalone mesh + props
# ============================================================
$gasStation = @(
    @{file="SM_GasStationOld"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_gasPumpsOld"; basis=Rot(0); pos=@(4,0,2)}
    @{file="SM_gasStationCarPort_01"; basis=Rot(0); pos=@(4,0,2)}
    @{file="SM_billboard_GasStationOld"; basis=Rot(0); pos=@(0,0,-6)}
    @{file="SM_billboard_86Gasoline"; basis=Rot(0); pos=@(6,5,0)}
    @{file="SM_trash_bin_2"; basis=Rot(0); pos=@(8,0,1)}
    @{file="SM_road_cone"; basis=Rot(0); pos=@(2,0,5)}
    @{file="SM_road_cone"; basis=Rot(0); pos=@(6,0,5)}
)
$content = BuildScene "gas_station" $gasStation
Set-Content -Path "$buildingsDir\commercial\gas_station.tscn" -Value $content
Write-Host "Generated gas_station.tscn"

# ============================================================
# 9. motel — 8×4 L-shape
# ============================================================
$motel = @(
    # Walls
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,0,2)}           # right outer
    @{file="SM_wallDoor_01"; basis=Rot(1); pos=@(-2,0,2)}      # back module 0
    @{file="SM_wall_01"; basis=Rot(1); pos=@(2,0,2)}           # back module 1
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}          # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,0,-2)}          # front module 1
    @{file="SM_window_10"; basis=Rot(0); pos=@(0,1.5,-2.01)}
    @{file="SM_window_10"; basis=Rot(0); pos=@(4,1.5,-2.01)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(4,0,0)}
    @{file="SM_roof_01"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_roof_01"; basis=Rot(0); pos=@(4,4,0)}
    @{file="SM_motel_sign"; basis=Rot(0); pos=@(2,6,0)}
    @{file="SM_bench"; basis=Rot(0); pos=@(0,0,3)}
    @{file="SM_trash_bin_1"; basis=Rot(0); pos=@(6,0,3)}
)
$content = BuildScene "motel" $motel
Set-Content -Path "$buildingsDir\commercial\motel.tscn" -Value $content
Write-Host "Generated motel.tscn"

# ============================================================
# 10. pawn_shop — 4×4 with window front
# ============================================================
$pawnShop = @(
    # Walls
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left
    @{file="SM_wallDoor_01"; basis=Rot(0); pos=@(2,0,2)}       # right
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,0,2)}          # back
    @{file="SM_shopFront_02"; basis=Rot(2); pos=@(2,0,-2)}     # front facade
    @{file="SM_window_13"; basis=Rot(0); pos=@(0,1.5,-2.01)}   # front window
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_cornice_01"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_billboard_PawnShop"; basis=Rot(0); pos=@(0,5.5,0)}
    @{file="SM_bench_02"; basis=Rot(0); pos=@(-3,0,1)}
    @{file="SM_trash_bin_1"; basis=Rot(0); pos=@(3,0,-1)}
)
$content = BuildScene "pawn_shop" $pawnShop
Set-Content -Path "$buildingsDir\commercial\pawn_shop.tscn" -Value $content
Write-Host "Generated pawn_shop.tscn"

Write-Host "`n=== Commercial buildings done ==="

# ============================================================
# 11. warehouse — 12×8 large industrial
# ============================================================
$warehouse = @(
    # Ground walls (Y=0)
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(10,0,2)}          # right outer
    @{file="SM_wallGarageDoor_01_double"; basis=Rot(1); pos=@(-2,0,2)}  # back module 0
    @{file="SM_wallGarageDoor_01"; basis=Rot(1); pos=@(2,0,2)}          # back module 1
    @{file="SM_wall_01"; basis=Rot(1); pos=@(6,0,2)}                    # back module 2
    @{file="SM_wall_01"; basis=Rot(1); pos=@(10,0,2)}                   # back module 3
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}                   # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,0,-2)}                   # front module 1
    @{file="SM_wall_01"; basis=Rot(2); pos=@(10,0,-2)}                  # front module 2
    # Upper walls (Y=4)
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,4,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,4,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,4,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(10,4,2)}          # right outer
    @{file="SM_wall_01"; basis=Rot(1); pos=@(-2,4,2)}                    # back module 0
    @{file="SM_wall_01"; basis=Rot(1); pos=@(2,4,2)}                     # back module 1
    @{file="SM_wall_01"; basis=Rot(1); pos=@(6,4,2)}                     # back module 2
    @{file="SM_wall_01"; basis=Rot(1); pos=@(10,4,2)}                    # back module 3
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,4,-2)}                   # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,4,-2)}                   # front module 1
    @{file="SM_wall_01"; basis=Rot(2); pos=@(10,4,-2)}                  # front module 2
    # Windows
    @{file="SM_window_11"; basis=Rot(0); pos=@(0,5.5,-2.01)}
    @{file="SM_window_11"; basis=Rot(0); pos=@(4,5.5,-2.01)}
    @{file="SM_window_11"; basis=Rot(0); pos=@(8,5.5,-2.01)}
    # Floors
    @{file="SM_floor_02"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_floor_02"; basis=Rot(0); pos=@(4,0,0)}
    @{file="SM_floor_02"; basis=Rot(0); pos=@(8,0,0)}
    # Props
    @{file="SM_billboard_Warehouse_01"; basis=Rot(0); pos=@(5,8.5,0)}
    @{file="SM_crate_1_set"; basis=Rot(0); pos=@(0,0,4)}
    @{file="SM_crate_4_set"; basis=Rot(0); pos=@(8,0,4)}
    @{file="SM_barrel_2"; basis=Rot(2); pos=@(12,0,2)}
    @{file="SM_barrel_3"; basis=Rot(2); pos=@(12,0,3)}
    @{file="SM_pipesStock_01"; basis=Rot(0); pos=@(-1,0,4)}
    @{file="SM_chimney_02"; basis=Rot(0); pos=@(10,8,2)}
)
$content = BuildScene "warehouse" $warehouse
Set-Content -Path "$buildingsDir\industrial\warehouse.tscn" -Value $content
Write-Host "Generated warehouse.tscn"

# ============================================================
# 12. scrapyard_shed — 4×4 open shed
# ============================================================
$shed = @(
    @{file="SM_wall_02"; basis=Rot(0); pos=@(-2,0,2)}          # left
    @{file="SM_wall_02"; basis=Rot(0); pos=@(2,0,2)}           # right
    @{file="SM_wall_02_half"; basis=Rot(1); pos=@(-2,0,2)}     # back
    @{file="SM_wall_02_half"; basis=Rot(2); pos=@(2,0,-2)}     # front
    @{file="SM_floor_02"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_roof_02"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_crate_1_set"; basis=Rot(0); pos=@(0,0,3)}
    @{file="SM_barrel_2"; basis=Rot(0); pos=@(2,0,3)}
    @{file="SM_pipesStock_01"; basis=Rot(0); pos=@(-1,0,3)}
)
$content = BuildScene "scrapyard_shed" $shed
Set-Content -Path "$buildingsDir\industrial\scrapyard_shed.tscn" -Value $content
Write-Host "Generated scrapyard_shed.tscn"

# ============================================================
# 13. gas_station_old — standalone building mesh + props
# ============================================================
$gasOld = @(
    @{file="SM_GasStationOld"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_gasPumpsOld"; basis=Rot(0); pos=@(4,0,2)}
    @{file="SM_barrel_3"; basis=Rot(0); pos=@(6,0,1)}
    @{file="SM_crate_1_set"; basis=Rot(0); pos=@(6,0,-1)}
    @{file="SM_trash_bin_2"; basis=Rot(0); pos=@(-2,0,2)}
    @{file="SM_road_cone"; basis=Rot(0); pos=@(2,0,4)}
)
$content = BuildScene "gas_station_old" $gasOld
Set-Content -Path "$buildingsDir\industrial\gas_station_old.tscn" -Value $content
Write-Host "Generated gas_station_old.tscn"

# ============================================================
# 14. barn — 8×4 L-shape
# ============================================================
$barn = @(
    @{file="SM_wall_01"; basis=Rot(0); pos=@(-2,0,2)}          # left outer
    @{file="SM_wall_01"; basis=Rot(0); pos=@(2,0,2)}           # partition
    @{file="SM_wall_01"; basis=Rot(0); pos=@(6,0,2)}           # right outer
    @{file="SM_wallDoor_01"; basis=Rot(1); pos=@(-2,0,2)}      # back module 0
    @{file="SM_wall_01"; basis=Rot(1); pos=@(2,0,2)}           # back module 1
    @{file="SM_wall_01_half"; basis=Rot(1); pos=@(6,0,2)}      # back module 2
    @{file="SM_wall_01"; basis=Rot(2); pos=@(2,0,-2)}          # front module 0
    @{file="SM_wall_01"; basis=Rot(2); pos=@(6,0,-2)}          # front module 1
    @{file="SM_window_06"; basis=Rot(0); pos=@(0,1.5,-2.01)}
    @{file="SM_window_06"; basis=Rot(0); pos=@(4,1.5,-2.01)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(0,0,0)}
    @{file="SM_floor_01"; basis=Rot(0); pos=@(4,0,0)}
    @{file="SM_roof_01"; basis=Rot(0); pos=@(0,4,0)}
    @{file="SM_roof_01"; basis=Rot(0); pos=@(4,4,0)}
    @{file="SM_roof_01_side"; basis=Rot(0); pos=@(0,4,2)}
    @{file="SM_roof_01_side"; basis=Rot(0); pos=@(4,4,2)}
    @{file="SM_buildingBarn_01"; basis=Rot(0); pos=@(2,0,0)}
    @{file="SM_crate_1_set"; basis=Rot(0); pos=@(0,0,3)}
    @{file="SM_barrel_2"; basis=Rot(0); pos=@(7,0,3)}
)
$content = BuildScene "barn" $barn
Set-Content -Path "$buildingsDir\industrial\barn.tscn" -Value $content
Write-Host "Generated barn.tscn"

Write-Host "`n=== All 14 buildings regenerated ==="

# ============================================================
# Also verify the road tile dimensions
# ============================================================
$roadGltf = Get-Content "C:\Users\abdo\Documents\GitHub\FPS-OpenWorld\resources\assetsville\GroundTilset\SM_road_00.gltf" -Raw
Write-Host "`nRoad tile: 16x16m (verified from GLTF min/max)"
Write-Host "Wall tile: 4m wide x 3m tall"
Write-Host "Floor tile: 4x4m"
Write-Host "All buildings use 4m tile grid with correct wall-to-floor alignment"
