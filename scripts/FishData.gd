# FishData.gd
# Autoload singleton — provides read-only species definitions.
# Access from any script as:  FishData.get_species(index)
extends Node

# ── Species index constants ───────────────────────────────────────────────────
const GUPPY   := 0
const CARP    := 1
const BASS    := 2
const CATFISH := 3
const PIKE    := 4

# ── Species table ─────────────────────────────────────────────────────────────
# Each entry is a plain Dictionary so scripts can use .get() with a fallback.
#
# Fields:
#   name             display name
#   energy_cost      energy deducted on spawn
#   base_biomass     starting biomass (grows when eating)
#   speed            pixels per second downstream
#   wobble_amp       lateral wobble amplitude (px)
#   wobble_freq      wobble cycles per second
#   is_predator      hunts opposite-colour fish
#   eats_detritus    diverts to floating plants
#   energy_reward    energy restored to owner per detritus eat
#   detection_radius radius (px) for hunting / plant detection
#   color_p1         body colour when owned by Player 1
#   color_p2         body colour when owned by Player 2
#   size             half-length of fish body (px)
const SPECIES: Array = [
	{   # 0 — Guppy
		"name": "Guppy",
		"energy_cost": 10,
		"base_biomass": 1.0,
		"speed": 90.0,
		"wobble_amp": 14.0,
		"wobble_freq": 3.0,
		"is_predator": false,
		"eats_detritus": false,
		"energy_reward": 0.0,
		"detection_radius": 0.0,
		"color_p1": Color(0.40, 0.72, 1.00),
		"color_p2": Color(1.00, 0.52, 0.40),
		"size": 8.0,
	},
	{   # 1 — Carp
		"name": "Carp",
		"energy_cost": 20,
		"base_biomass": 3.0,
		"speed": 50.0,
		"wobble_amp": 6.0,
		"wobble_freq": 1.5,
		"is_predator": false,
		"eats_detritus": true,
		"energy_reward": 5.0,
		"detection_radius": 40.0,
		"color_p1": Color(0.30, 0.70, 0.50),
		"color_p2": Color(0.90, 0.70, 0.20),
		"size": 16.0,
	},
	{   # 2 — Bass
		"name": "Bass",
		"energy_cost": 35,
		"base_biomass": 5.0,
		"speed": 70.0,
		"wobble_amp": 8.0,
		"wobble_freq": 2.0,
		"is_predator": true,
		"eats_detritus": false,
		"energy_reward": 0.0,
		"detection_radius": 120.0,
		"color_p1": Color(0.20, 0.50, 0.90),
		"color_p2": Color(0.90, 0.30, 0.20),
		"size": 20.0,
	},
	{   # 3 — Catfish
		"name": "Catfish",
		"energy_cost": 25,
		"base_biomass": 4.0,
		"speed": 40.0,
		"wobble_amp": 4.0,
		"wobble_freq": 1.0,
		"is_predator": false,
		"eats_detritus": true,
		"energy_reward": 8.0,
		"detection_radius": 60.0,
		"color_p1": Color(0.20, 0.40, 0.60),
		"color_p2": Color(0.60, 0.40, 0.20),
		"size": 18.0,
	},
	{   # 4 — Pike
		"name": "Pike",
		"energy_cost": 50,
		"base_biomass": 8.0,
		"speed": 110.0,
		"wobble_amp": 10.0,
		"wobble_freq": 2.5,
		"is_predator": true,
		"eats_detritus": false,
		"energy_reward": 0.0,
		"detection_radius": 200.0,
		"color_p1": Color(0.10, 0.30, 0.80),
		"color_p2": Color(0.80, 0.20, 0.10),
		"size": 26.0,
	},
]


## Returns the species Dictionary for the given index, or an empty dict.
static func get_species(index: int) -> Dictionary:
	if index < 0 or index >= SPECIES.size():
		return {}
	return SPECIES[index]


## Total number of available species.
static func count() -> int:
	return SPECIES.size()
