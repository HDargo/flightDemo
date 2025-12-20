# Spawn Logic Update (North vs South)

## Overview
The spawn logic for both Mass AI and standard Aircraft has been updated to establish clear battle lines.

## Team Positions
We have defined the Z-axis as the North-South axis:
-   **North (-Z):** Enemy Territory
-   **South (+Z):** Ally Territory

### 1. Aircraft Spawning
-   **Enemies (North Team):**
    -   **Position:** Spawn in the North (Negative Z).
    -   **Facing:** South (Rotation Y = 180° / PI).
    -   **Zone:** `Z < -spawn_radius`
-   **Allies (South Team):**
    -   **Position:** Spawn in the South (Positive Z).
    -   **Facing:** North (Rotation Y = 0°).
    -   **Zone:** `Z > spawn_radius`

### 2. Ground Vehicle Spawning
Ground units now align with their respective air superiority zones:
-   **Enemy Tanks:** Spawn in `[-ground_spawn_radius, 0]` (North side).
-   **Ally Tanks:** Spawn in `[0, ground_spawn_radius]` (South side).

## Result
This configuration ensures that both teams spawn facing each other, creating a "Front Line" at `Z=0` where the initial engagement will occur. This replaces the previous random/mixed spawn logic which caused chaotic, directionless dogfights immediately upon start.
