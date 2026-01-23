extends Resource
class_name WeaponConfig

enum WeaponType { GUN, MISSILE }

@export var name: String = "Weapon"
@export var type: WeaponType = WeaponType.GUN
@export var damage: float = 10.0
@export var fire_rate: float = 0.1 # Seconds between shots
@export var range_val: float = 2000.0
@export var muzzle_name_prefix: String = "muzzle"
@export var ammo_max: int = -1 # -1 = Infinite
@export var projectile_speed: float = 200.0 # For guns
@export var projectile_color: Color = Color(1, 1, 0.5) # For guns shader
