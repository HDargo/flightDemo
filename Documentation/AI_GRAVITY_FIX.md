# AI Gravity Reaction & Crash Fix

## Issue
AI aircraft were frequently crashing into the ground. The root cause was identified as:
1.  **Static Altitude Thresholds:** The AI only reacted when altitude was absolutely low (e.g., < 200m), without considering vertical velocity (sink rate).
2.  **Unsafe Stall Recovery:** When stalling, the AI would nose down to gain speed even if it was already too close to the ground.
3.  **Target Fixation:** AI would dive after ground targets or low-flying enemies without checking for ground collision.
4.  **Mass AI Simplification:** The Mass AI system completely lacked ground avoidance logic.

## Solution

### 1. Predictive Ground Avoidance (`AIController.gd`)
We implemented a predictive system that calculates `time_to_impact`.
- **Dynamic Floor:** The safety altitude floor now increases based on descent rate. If an aircraft is diving at 100m/s, it will start pulling up at ~500m instead of waiting for 200m.
- **Panic Mode:** If `time_to_impact` is less than 4 seconds, the AI enters a "Panic" state:
    - Maximize Throttle.
    - Level Wings (roll to 0).
    - Hard Pull Up (Target Pitch 1.0) *only if upright*.
    - Ignores all combat and target logic.

### 2. Roll-Gated Pitch Control (New)
A critical flaw was identified where AI would pull up (pitch +1.0) even while inverted or heavily banked, causing them to accelerate into the ground.
- **Upright Check:** We now calculate the dot product of the aircraft's local `UP` vector with the global `UP` vector.
- **Logic:**
    - If `upright_dot < 0.5` (Banked > 60° or Inverted): **Pitch = 0.0**. The AI focuses 100% on rolling level. Pulling up is forbidden.
    - If `upright_dot >= 0.5`: **Pitch = 1.0**. The AI is upright enough that pulling back on the stick effectively moves it away from the ground.

### 5. Inverted Flight Fix (New)
Users reported AI stabilizing in "inverted level" flight. This was due to a mathematical flaw in the roll calculation:
- **Bug:** The previous formula `atan2(right.y, right.length())` calculated a roll error of `0` when the aircraft was perfectly inverted (`right.y = 0`). This caused the AI to think it was flying level when it was actually upside down.
- **Fix:**
    - Replaced angle calculation with direct vector component checks.
    - **Inverted Check:** Explicitly checks `Up.y < 0`. If true, the AI forces a full roll (`roll = +/- 1.0`) regardless of "level" wing status to exit the inverted state immediately.
    - **Direction:** Uses `Right.y` to determine the shortest direction to roll upright.

### 6. Safe Stall Recovery
- **Altitude Check:** The AI is now forbidden from diving to recover speed if altitude is below **400m**.
- **Low Altitude Recovery:** If stalling at low altitude, the AI will level off (`pitch = 0`) and use max throttle instead of diving.

### 7. Mass AI Safety (`MassAISystem.gd`)
We added lightweight safety checks to the mass processing loop:
- **Critical Altitude (< 120m):** Overrides all behavior to force a pull-up and level roll.
- **Roll-Gating:** Mass AI also respects the "Roll First, Then Pull" rule.
- **Inverted Fix:** Mass AI also incorporates the anti-inverted vector logic.
- **Low Altitude Warning (< 250m):** Prevents negative pitch inputs (diving) even if the target is below the aircraft.
- **Idle Climb:** Idle aircraft now maintain a slight positive pitch to prevent gradual altitude loss.

## Validation
These changes ensure that AI aircraft prioritize survival over combat when near the terrain, significantly reducing unforced crashes.
