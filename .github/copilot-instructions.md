# Copilot instructions for this Godot project (Godot 4.5)

Purpose: Guide AI agents in developing a 3D Flight Simulation game (War Thunder style).

## Architecture
- **Engine**: Godot 4.5 (3D).
- **Main Scene**: `res://Scenes/Levels/MainLevel.tscn`.
- **Folder Structure**:
  - `Scenes/`: Tscn files (Levels, Entities, UI).
  - `Scripts/`: Gd scripts (Flight, Ground, UI).
  - `Assets/`: Models, Textures, Audio.

## Core Systems
- **Flight Physics**:
  - Use `CharacterBody3D` or `RigidBody3D` for aircraft.
  - Implement 6-DOF movement (Pitch, Yaw, Roll) + Throttle.
  - Lift and Drag calculations based on speed and angle of attack.
- **Camera**:
  - Chase camera with smooth follow and mouse look.
  - Cockpit view (optional later).
- **Input**:
  - Mouse: Pitch/Yaw (or Roll).
  - Keyboard: WASD/Arrows for control, Shift/Ctrl for throttle.
  - Left Click: Fire weapons.
  - Esc: Toggle mouse capture.
  - F : Fire missiles.

## Conventions
- **Scripts**:
  - Use `class_name` for reusable components (e.g., `class_name Aircraft`).
  - Use typed variables (`var speed: float = 0.0`).
  - Use `_physics_process` for movement logic.
- **Scenes**:
  - Root node of an entity should be `CharacterBody3D` or `RigidBody3D`.
  - Use `MeshInstance3D` for visuals and `CollisionShape3D` for physics.
  - Use `CameraRig` (Node3D) for smooth camera following.

## Workflow
- **Testing**: Run `MainLevel.tscn` to test flight mechanics.
- **Debugging**: Use `print()` or `DebugDraw` (if implemented) for physics vectors.

## Current Status
- Project initialized.
- `MainLevel` created with ground and sky.
- `Aircraft` implemented with Mouse Control and Shooting.
- `HUD` displays speed/throttle.
- `GroundTarget` implemented with health system.

필요시 mcp context7을 사용.