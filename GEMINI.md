# GEMINI.md - Project Context & Guidelines

## 🚁 Project Overview
This is a **High-Performance Flight Combat Simulation** built with **Godot 4**.
The core goal is to support **1,000+ aircraft and 5,000+ ground units** simultaneously at **60 FPS** on mid-range hardware (GTX 1060).

## 🛠️ Key Technical Architecture (CRITICAL)
**Strict adherence to these patterns is required for performance.**

### 1. Data-Oriented Design (DOD)
- **Do NOT** use individual Nodes (`CharacterBody3D`, `Area3D`, etc.) for mass units (enemies, missiles, ground units).
- **MUST** use `PackedVector3Array`, `PackedFloat32Array`, etc., managed by centralized Systems (e.g., `MassAircraftSystem`, `FlightManager`).
- **Entity ID** = Array Index.

### 2. Rendering
- **MUST** use `MultiMeshInstance3D` for all mass entities.
- Implement **LOD (Level of Detail)** (3 levels: High, Mid, Low/Billboard).
- Use **Frustum Culling** and **Occlusion Culling**.

### 3. Physics & Logic
- **Compute Shaders (GLSL)** are used for:
  - Collision Detection (Spatial Hashing/Grid).
  - Particle Systems (Smoke, Explosions).
  - Heavy Physics calculations.
- **GDScript** manages high-level logic and inputs for the Player.
- **Player Aircraft** is the *only* exception allowed to be a fully detailed Node hierarchy for precise control.

## 📅 Current Status & Roadmap
**Current Phase:** Phase 2 (Scale-up & Modularization) / Phase 5 (Polishing)

### ✅ Completed
- **Phase 1 Modularization:** `Aircraft` component separation.
- **Phase 2 Modularization:** `FlightManager` split (`ProjectilePoolSystem`, `MissilePoolSystem`, `AircraftRegistry`, `AIThreadScheduler`).
- **Phase 3 Modularization:** `MassAircraftSystem` split (`MassRenderSystem`, `MassPhysicsEngine`).
- **Core Physics:** Basic flight model, "Death Spiral" fix.
- **Optimization:** Initial `MultiMesh` implementation.

### 🚀 Next Steps (Priority)
1.  **Verification:**
    -   Verify integration of `MassAircraftSystem` refactor.
    -   Test `MassPhysicsEngine` (CPU/GPU switching).
2.  **Performance:**
    -   Full integration of Compute Shaders for collision (currently CPU raycast in `ProjectilePoolSystem`).
    -   Optimize `MassAISystem` (it still needs modularization or tuning).
3.  **Gameplay:**
    -   Implement "Capture Zone" logic with Mass AI.

## 📂 Project Structure Highlights
- `Scripts/Flight/`: Core flight logic. `FlightManager.gd` is the central coordinator.
- `Scripts/Flight/Systems/`: Modular systems (to be populated).
- `Assets/Shaders/Compute/`: GLSL compute shaders (`.glsl`).
- `Scenes/`: Godot scenes (`.tscn`).
- `Documentation/`: **READ THESE BEFORE MAJOR CHANGES.**
    -   `flight_combat_game_spec.md`: The "Bible" of this project's spec.
    -   `MODULARIZATION_*.md`: Current refactoring guides.

## 📝 Documentation Map
- **New to project?** Read `Documentation/flight_combat_game_spec.md`.
- **Refactoring?** Read `Documentation/MODULARIZATION_SUMMARY_KR.md`.
- **Optimization?** Read `Documentation/OPTIMIZATION_RECOMMENDATIONS_DETAILED.md`.

---
*This file is for AI Agents (Gemini, Copilot, etc.) to understand the project context quickly.*
