extends RefCounted
class_name SpeciesDB

const GUPPY: StringName = &"guppy"
const SABALO: StringName = &"sabalo"
const DIENTUDO: StringName = &"dientudo"
const PELLET: StringName = &"pellet"
const DETRITUS: StringName = &"detritus"

const DATA: Dictionary = {
	GUPPY: {
		"texture_path": "res://assets/mojarrita.png",
		"starting_energy": 30.0,
		"starting_saturation_ratio": 0.75,
		"top_speed": 250,
		"is_predator": false,
		"vision_radius": 120.0,
		"predator_detection_radius": 130.0,
		"separation_radius": 30.0,
		"max_force": 450.0,
		"life_span_seconds": 120.0,
		"despawn_bias_start_ratio": 0.75,
		"age_exit_bias": 300.0,
		"hunger_rate": 1.0,
		"flee_energy_drain_rate": 5.0,
		"turn_rate_rad_per_sec": 9.0,
		"age_whiten_max_ratio": 0.7,
		"flee_override_predator_ratio": 2.0,
		"eat_radius": 15.0,
		"boid_weights": {
			"separation": 0.875,
			"alignment": 0.75,
			"cohesion": 0.18
		}
	},
	SABALO: {
		"texture_path": "res://assets/sabalo.png",
		"starting_energy": 10.0,
		"starting_saturation_ratio": 0.75,
		"top_speed": 150.0,
		"is_predator": false,
		"vision_radius": 200.0,
		"predator_detection_radius": 130.0,
		"separation_radius": 26.0,
		"max_force": 180.0,
		"life_span_seconds": 100.0,
		"despawn_bias_start_ratio": 0.75,
		"age_exit_bias": 400.0,
		"hunger_rate": 1.0,
		"eat_radius": 12.0,
		"feeding_energy_gain": 1.0,
		"feeding_consume_radius": 12.0,
		"detritus_consume_tick_seconds": 1.0,
		"flee_energy_drain_rate": 5.0,
		"turn_rate_rad_per_sec": 9.0,
		"wander_speed_factor": 0.7,
		"descend_bias_strength_multiplier": 1.3,
		"age_whiten_max_ratio": 0.7,
		"flee_override_predator_ratio": 2.0,
		"boid_weights": {
			"separation": 0.0,
			"alignment": 0.0,
			"cohesion": 0.0
		}
	},
	DIENTUDO: {
		"texture_path": "res://assets/dientudo.png",
		"starting_energy": 50.0,
		"starting_saturation_ratio": 0.75,
		"top_speed": 180,
		"is_predator": true,
		"digestion_speed_g_per_sec": 25.0,
		"vision_radius": 270.0,
		"predator_detection_radius": 270.0,
		"separation_radius": 32.0,
		"max_force": 420.0,
		"life_span_seconds": 50.0,
		"despawn_bias_start_ratio": 0.75,
		"age_exit_bias": 350.0,
		"hunger_rate": 0.5,
		"eat_radius": 16.0,
		"prey_mass_absorption_ratio": 0.5,
		"chase_steering_multiplier": 2.3,
		"search_wander_center_bias_strength": 0.1,
		"search_wander_speed_factor": 0.95,
		"search_wander_steer_multiplier": 0.95,
		"search_wander_turn_rate_rad_per_sec": 0.8,
		"descend_wander_center_bias_strength": 0.45,
		"descend_wander_speed_factor": 0.6,
		"descend_wander_steer_multiplier": 0.7,
		"descend_wander_turn_rate_rad_per_sec": 1.8,
		"descend_bias_strength_multiplier": 1.15,
		"age_whiten_max_ratio": 0.7,
		"flee_override_predator_ratio": 2.0,
		"boid_weights": {
			"separation": 1.6,
			"alignment": 0.6,
			"cohesion": 0.25
		}
	},
	PELLET: {
		"texture_path": "res://assets/pellet.png",
		"starting_energy": 100.0,
		"starting_saturation_ratio": 0.75,
		"top_speed": 36.0,
		"is_predator": false,
		"prey_weight_ratio_limit": 0.0,
		"vision_radius": 56.0,
		"predator_detection_radius": 0.0,
		"separation_radius": 18.0,
		"max_force": 70.0,
		"life_span_seconds": 9999.0,
		"age_exit_bias": 0.0,
		"hunger_rate": 0.0,
		"eat_radius": 0.0,
		"boid_weights": {
			"separation": 0.2,
			"alignment": 0.2,
			"cohesion": 0.0
		}
	},
	DETRITUS: {
		"texture_path": "res://assets/pellet.png",
		"starting_energy": 100.0,
		"starting_saturation_ratio": 0.75,
		"top_speed": 5.0,
		"is_predator": false,
		"prey_weight_ratio_limit": 0.0,
		"vision_radius": 0.0,
		"predator_detection_radius": 0.0,
		"separation_radius": 0.0,
		"max_force": 0.0,
		"life_span_seconds": 9999.0,
		"age_exit_bias": 0.0,
		"hunger_rate": 0.0,
		"eat_radius": 0.0,
		"boid_weights": {
			"separation": 0.0,
			"alignment": 0.0,
			"cohesion": 0.0
		}
	}
}


static func has_species(species_name: StringName) -> bool:
	return DATA.has(species_name)


static func get_species(species_name: StringName) -> Dictionary:
	var source: Dictionary = DATA[GUPPY] as Dictionary
	if DATA.has(species_name):
		source = DATA[species_name] as Dictionary
	return source.duplicate(true)
