extends Node

class_name DamageSystem

## Static utility class for aircraft damage calculations
## Handles part damage, performance degradation, and destruction logic

## Calculate performance factors from part health
static func calculate_performance_factors(parts_health: Dictionary, max_healths: Dictionary) -> Dictionary:
	var engine_health_factor = parts_health["engine"] / max_healths["engine"]
	
	var l_wing_in_factor = parts_health["l_wing_in"] / max_healths["l_wing_in"]
	var l_wing_out_factor = parts_health["l_wing_out"] / max_healths["l_wing_out"]
	var r_wing_in_factor = parts_health["r_wing_in"] / max_healths["r_wing_in"]
	var r_wing_out_factor = parts_health["r_wing_out"] / max_healths["r_wing_out"]
	
	var l_lift = (l_wing_in_factor * 0.7) + (l_wing_out_factor * 0.3)
	var r_lift = (r_wing_in_factor * 0.7) + (r_wing_out_factor * 0.3)
	
	var h_tail_factor = parts_health["h_tail"] / max_healths["h_tail"]
	var v_tail_factor = parts_health["v_tail"] / max_healths["v_tail"]
	
	var l_roll_authority = (l_wing_in_factor * 0.3) + (l_wing_out_factor * 0.7)
	var r_roll_authority = (r_wing_in_factor * 0.3) + (r_wing_out_factor * 0.7)
	
	return {
		"engine_factor": engine_health_factor,
		"lift_factor": (l_lift + r_lift) / 2.0,
		"h_tail_factor": h_tail_factor,
		"v_tail_factor": v_tail_factor,
		"roll_authority": (l_roll_authority + r_roll_authority) / 2.0,
		"wing_imbalance": r_lift - l_lift
	}

## Determine which part was hit based on local position
static func determine_hit_part(hit_pos_local: Vector3) -> String:
	# Z: Forward is -Z, Back is +Z
	# X: Right is +X, Left is -X
	# Aircraft spans roughly Z: [-2.0, 2.3]
	if hit_pos_local.z < -1.3:
		# Nose and Engine are both in the front. 
		# Engine is slightly further forward (-1.8) than Nose (-1.5) in this model.
		if hit_pos_local.z < -1.7:
			return "engine"
		return "nose"
	elif hit_pos_local.z > 1.3:
		# Tail section
		if abs(hit_pos_local.x) < 0.5:
			return "v_tail"
		else:
			return "h_tail"
	elif abs(hit_pos_local.x) > 0.5:
		# Wings
		if hit_pos_local.x < -2.0:
			return "l_wing_out"
		elif hit_pos_local.x < -0.5:
			return "l_wing_in"
		elif hit_pos_local.x > 2.0:
			return "r_wing_out"
		elif hit_pos_local.x > 0.5:
			return "r_wing_in"
	
	return "fuselage"

## Check if wing is critically damaged (triggers crash)
static func check_wing_destruction(parts_health: Dictionary) -> Dictionary:
	var l_wing_total = parts_health["l_wing_in"] + parts_health["l_wing_out"]
	var r_wing_total = parts_health["r_wing_in"] + parts_health["r_wing_out"]
	
	var destruction_threshold = 30.0
	
	if l_wing_total < destruction_threshold or r_wing_total < destruction_threshold:
		var spin_direction = 1.0 if l_wing_total < r_wing_total else -1.0
		return {
			"destroyed": true,
			"spin_factor": spin_direction
		}
	
	return {"destroyed": false, "spin_factor": 0.0}

## Map part name to node name in scene tree
static func get_part_node_name(part: String) -> String:
	match part:
		"nose": return "Nose"
		"engine": return "Engine"
		"fuselage": return "Fuselage"
		"l_wing_in": return "LeftWingIn"
		"l_wing_out": return "LeftWingOut"
		"r_wing_in": return "RightWingIn"
		"r_wing_out": return "RightWingOut"
		"v_tail": return "VerticalTail"
		"h_tail": return "HorizontalTail"
	return ""

## Check if aircraft should be destroyed
static func check_critical_damage(parts_health: Dictionary) -> bool:
	# Fuselage or Engine destruction is critical
	return parts_health["fuselage"] <= 0 or parts_health["engine"] <= 0

## Calculate visual damage effects (smoke intensity, etc.)
static func calculate_damage_severity(parts_health: Dictionary, max_healths: Dictionary) -> float:
	var total_health = 0.0
	var total_max = 0.0
	
	for part in parts_health:
		total_health += parts_health[part]
		total_max += max_healths[part]
	
	if total_max <= 0:
		return 1.0
	
	var health_ratio = total_health / total_max
	return 1.0 - health_ratio # 0.0 = no damage, 1.0 = critical

## Get recommended repair priority (returns array of part names sorted by priority)
static func get_repair_priority(parts_health: Dictionary, max_healths: Dictionary) -> Array:
	var damaged_parts = []
	
	# Calculate damage ratios
	for part in parts_health:
		var ratio = parts_health[part] / max_healths[part]
		if ratio < 1.0:
			damaged_parts.append({"part": part, "ratio": ratio})
	
	# Sort by damage ratio (most damaged first)
	damaged_parts.sort_custom(func(a, b): return a.ratio < b.ratio)
	
	# Return just the part names
	var result = []
	for item in damaged_parts:
		result.append(item.part)
	
	return result
