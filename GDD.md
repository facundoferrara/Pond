# Pond — Game Design Document (v1.0)

## Concept
**Genre:** Chill party game / Indirect RTS  
**Players:** 2 (local, 2 game controllers)  
**Session length:** 3–10 minutes  
**Platform:** Windows / Linux (Godot 4.6, GL Compatibility renderer)

---

## Core Loop
1. **Energy recharges** slowly for each player (8 units/sec, cap 100).
2. **Player selects** a fish species (left/right on D-pad, analog stick, or L1/R1).
3. **Player spawns** fish by pressing A (hold A for continuous stream); energy cost is deducted.
4. Fish **swim downstream** toward the exit at the bottom of the screen.
   - *Feeder fish* (Carp, Catfish) detour to floating plants, eat detritus, and grow biomass while restoring a little energy to their owner.
   - *Predator fish* (Bass, Pike) hunt and consume the closest opposite-colour fish within detection range.
5. When a fish **exits the pond at the bottom**, its final biomass is scored:
   - **Player 1 fish** subtract from the Victory Meter.
   - **Player 2 fish** add to the Victory Meter.
6. **Win condition:** Victory Meter reaches 0 (Player 1 wins) or 100 (Player 2 wins).

---

## Fish Species

| Species  | Energy Cost | Base Biomass | Speed | Role      | Special             |
|----------|-------------|--------------|-------|-----------|---------------------|
| Guppy    | 10          | 1.0          | 90    | Swimmer   | —                   |
| Carp     | 20          | 3.0          | 50    | Feeder    | Eats detritus (+E)  |
| Bass     | 35          | 5.0          | 70    | Predator  | Hunts 120 px range  |
| Catfish  | 25          | 4.0          | 40    | Feeder    | Heavy detritus (+E) |
| Pike     | 50          | 8.0          | 110   | Predator  | Hunts 200 px range  |

---

## Controls

| Action              | Player 1 (Device 0)            | Player 2 (Device 1)            |
|---------------------|--------------------------------|--------------------------------|
| Select prev species | D-pad Left / L1 / Analog ←    | D-pad Left / L1 / Analog ←    |
| Select next species | D-pad Right / R1 / Analog →   | D-pad Right / R1 / Analog →   |
| Spawn fish (tap)    | A button / Space               | A button / Enter               |
| Spawn fish (hold)   | Hold A / Hold Space            | Hold A / Hold Enter            |
| Pause / Resume      | Start / Escape                 | Start / Escape                 |

---

## Scene Tree Plan

```
Game (Node2D)               — Game.gd: wires all systems, spawns plants
├── Background (ColorRect)  — pond background colour
├── PondArea (ColorRect)    — water body colour
├── P1SpawnLabel (Label)    — spawn zone hint
├── P2SpawnLabel (Label)    — spawn zone hint
├── Plants (Node2D)         — FloatingPlant instances added at runtime
├── FishContainer (Node2D)  — Fish instances added at runtime
├── Players (Node2D)
│   ├── Player1 (Node)      — Player.gd, player_id=1, device_id=0
│   └── Player2 (Node)      — Player.gd, player_id=2, device_id=1
├── SpawnSystem (Node)      — SpawnSystem.gd
├── UI (CanvasLayer)        — UI.gd: victory meter, energy bars, species labels
└── PauseMenu (CanvasLayer) — PauseMenu.gd: resume / restart / quit
```

Fish scene (instanced into FishContainer):
```
Fish (Node2D)               — FishBase.gd
└── Polygon2D               — procedural fish body (created in code)
```

FloatingPlant scene (instanced into Plants):
```
FloatingPlant (Node2D)      — FloatingPlant.gd
└── Polygon2D               — lily-pad shape (created in code)
```

---

## InputMap Plan

Actions are split per player so each device gets independent bindings:

| Action            | Bindings (device 0 / device 1)                          |
|-------------------|---------------------------------------------------------|
| `p1_select_left`  | JoypadButton DPad Left (dev 0), L1 (dev 0), Axis0 < 0  |
| `p1_select_right` | JoypadButton DPad Right (dev 0), R1 (dev 0), Axis0 > 0 |
| `p1_spawn`        | JoypadButton A (dev 0), Key Space                       |
| `p1_pause`        | JoypadButton Start (dev 0), Key Escape                  |
| `p2_select_left`  | JoypadButton DPad Left (dev 1), L1 (dev 1), Axis0 < 0  |
| `p2_select_right` | JoypadButton DPad Right (dev 1), R1 (dev 1), Axis0 > 0 |
| `p2_spawn`        | JoypadButton A (dev 1), Key Enter                       |
| `p2_pause`        | JoypadButton Start (dev 1), Key Escape                  |

In GDScript, `Player.gd` filters events by `event.device` so each player only
reacts to its own controller (keyboard events have `device == -1` and pass
both players; different key bindings prevent conflicts).

---

## Implementation Milestones

1. **M1 – Project skeleton:** `project.godot`, autoloads, scene stubs, input map.
2. **M2 – Fish swimming:** Fish spawn at player positions and swim downstream with wobble; exit scoring triggers victory meter.
3. **M3 – Plant feeding:** Floating plants accumulate detritus; feeder fish divert and eat, growing biomass.
4. **M4 – Predator hunting:** Predator fish detect and consume opposite-colour fish nearby.
5. **M5 – UI & victory flow:** Victory meter reacts; game-over screen; pause menu; restart.
6. **M6 – Polish:** Sound placeholder nodes, colour tuning, balance pass on energy/costs.

---

## Technical Notes
- **Renderer:** GL Compatibility — runs on any OpenGL 3.3+ GPU (no Vulkan required).
- **Resolution:** 1280 × 720, stretch mode `canvas_items`, aspect `keep`.
- **Fish are Node2D** with procedural Polygon2D visuals; no physics engine overhead.
- **Pause** uses `get_tree().paused`; PauseMenu CanvasLayer has `process_mode = ALWAYS`.
- **Autoloads:** `GameManager` (game state) and `FishData` (species table) are globally accessible.
