extends RefCounted
class_name SpeciesDB

const GUPPY: StringName = &"guppy"
const SABALO: StringName = &"sabalo"
const DIENTUDO: StringName = &"dientudo"

const DATA: Dictionary = {
	GUPPY: {
		"texture_path": "res://assets/mojarrita.png",
		"starting_energy": 60.0,
		"starting_weight": 40.0,
		"spawn_weight_min_g": 30.0,
		"spawn_weight_max_g": 50.0,
		"base_points": 2.0,
		"top_speed": 78.0,
		"is_predator": false,
		"vision_radius": 120.0,
		"predator_detection_radius": 130.0,
		"separation_radius": 30.0,
		"max_force": 170.0,
		"life_span_seconds": 110.0,
		"age_exit_bias": 300.0,
		"hunger_rate": 0.1,
		"flee_energy_drain_rate": 5.0,
		"despawner_avoid_radius": 220.0,
		"despawner_avoid_force_multiplier": 2.1,
		"turn_rate_rad_per_sec": 9.0,
		"eat_radius": 15.0,
		"boid_weights": {
			"separation": 0.875,
			"alignment": 0.75,
			"cohesion": 0.18
		}
	},
	SABALO: {
		"texture_path": "res://assets/sabalo.png",
		"starting_energy": 32.0,
		"starting_weight": 225.0,
		"spawn_weight_min_g": 200.0,
		"spawn_weight_max_g": 250.0,
		"base_points": 12.0,
		"top_speed": 80.0,
		"is_predator": false,
		"vision_radius": 120.0,
		"separation_radius": 26.0,
		"max_force": 168.0,
		"life_span_seconds": 84.0,
		"age_exit_bias": 400.0,
		"hunger_rate": 0.72,
		"eat_radius": 0.0,
		"feeding_start_distance": 54.0,
		"feeding_chance_per_second": 0.8,
		"feeding_energy_ratio": 0.92,
		"feeding_energy_gain": 1.35,
		"feed_lock_seconds": 8.0,
		"spawn_egress_lock_seconds": 3.4,
		"repel_zone_feed_margin": 24.0,
		"upper_zone_ratio": 0.34,
		"stall_speed_ratio_threshold": 0.16,
		"stall_trigger_seconds": 1.0,
		"unstuck_boost_seconds": 2.0,
		"unstuck_force_multiplier": 1.7,
		"turn_rate_rad_per_sec": 2.8,
		"turn_slow_min_speed_factor": 1.0,
		"local_separation_strength": 2.2,
		"local_separation_radius": 42.0,
		"panic_duration_seconds": 1.0,
		"panic_cooldown_seconds": 5.0,
		"panic_speed_multiplier": 2.0,
		"boid_weights": {
			"separation": 0.0,
			"alignment": 0.0,
			"cohesion": 0.0
		}
	},
	DIENTUDO: {
		"texture_path": "res://assets/dientudo.png",
		"starting_energy": 50.0,
		"starting_weight": 425.0,
		"spawn_weight_min_g": 400.0,
		"spawn_weight_max_g": 450.0,
		"base_points": 10.0,
		"top_speed": 100.0,
		"is_predator": true,
		"prey_weight_ratio_limit": 0.5,
		"digestion_speed_g_per_sec": 30.0,
		"vision_radius": 140.0,
		"separation_radius": 32.0,
		"max_force": 175.0,
		"life_span_seconds": 80.0,
		"age_exit_bias": 350.0,
		"hunger_rate": 0.35,
		"eat_radius": 16.0,
		"max_size_growth_ratio": 1.2,
		"dart_wind_up_seconds": 0.5,
		"dart_duration_seconds": 1.0,
		"dart_cooldown_seconds": 5.0,
		"dash_speed_multiplier": 3.0,
		"dash_turn_rate_factor": 0.25,
		"boid_weights": {
			"separation": 1.6,
			"alignment": 0.6,
			"cohesion": 0.25
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
