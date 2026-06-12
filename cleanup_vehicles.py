import os
import re

# Run from your project root (where project.godot is)
# python cleanup_vehicles.py

VEHICLES_DIR = r"resources\vehicles"

def main():
    if not os.path.isfile("project.godot"):
        print("ERROR: Run this script from your Godot project root (where project.godot is).")
        return

    if not os.path.isdir(VEHICLES_DIR):
        print(f"ERROR: Directory not found: {VEHICLES_DIR}")
        return

    # Match any .glb whose stem ends with an underscore + number (e.g. classic_car_9, sport_car_39)
    pattern = re.compile(r'^.+_\d+\.glb(\.import)?$', re.IGNORECASE)

    deleted = []

    for filename in os.listdir(VEHICLES_DIR):
        if pattern.match(filename):
            path = os.path.join(VEHICLES_DIR, filename)
            os.remove(path)
            deleted.append(filename)

    if deleted:
        print(f"✅ Deleted {len(deleted)} files:")
        for f in sorted(deleted):
            print(f"   {f}")
    else:
        print("Nothing matched.")

if __name__ == "__main__":
    main()
