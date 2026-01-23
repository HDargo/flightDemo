extends Resource

class_name AircraftResource

@export_group("Identity")
@export var aircraft_name: String = "Prototype"
@export var visual_scene: PackedScene
@export var base_color: Color = Color.GRAY

@export_group("Flight Performance")
@export var max_speed: float = 60.0
@export var acceleration: float = 90.0
@export var turn_speed: float = 2.0
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var lift_factor: float = 0.00178

@export_group("Durability")
@export var parts_health: Dictionary = {
	"nose": 50.0,
	"fuselage": 150.0,
	"engine": 100.0,
	"l_wing_in": 80.0,
	"l_wing_out": 60.0,
	"r_wing_in": 80.0,
	"r_wing_out": 60.0,
	"v_tail": 60.0,
	"h_tail": 60.0
}

@export_group("Weapons")
@export var fire_rate: float = 0.1
@export var missile_lock_range: float = 2000.0
@export var default_loadout: Array[WeaponConfig] = []
