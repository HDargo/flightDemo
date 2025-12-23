extends Area3D

signal base_captured(capturing_team: int)

@export var owning_team: GlobalEnums.Team = GlobalEnums.Team.NEUTRAL

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Only tanks (GroundVehicle) can capture
	if body.has_method("get_faction"):
		var faction = body.get_faction()
		
		# If an enemy enters this zone, they capture it!
		if faction != owning_team and faction != GlobalEnums.Team.NEUTRAL:
			print("Base captured by team: ", faction)
			base_captured.emit(faction)
