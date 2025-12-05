extends Control

var controls_menu_scene = preload("res://Scenes/UI/ControlsMenu.tscn")
var controls_menu: Control = null

@onready var pause_container: CenterContainer = $CenterContainer
@onready var background: ColorRect = $ColorRect

func _ready() -> void:
	show()  # Keep Control visible
	pause_container.hide()
	background.hide()
	
	# Instance controls menu
	controls_menu = controls_menu_scene.instantiate()
	add_child(controls_menu)
	controls_menu.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if controls_menu and controls_menu.visible:
			controls_menu.hide_menu()
		elif pause_container.visible:
			resume()
		else:
			pause()

func pause() -> void:
	pause_container.show()
	background.show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func resume() -> void:
	pause_container.hide()
	background.hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_button_pressed() -> void:
	resume()

func _on_controls_button_pressed() -> void:
	print("Controls button pressed!")
	print("controls_menu exists: ", controls_menu != null)
	pause_container.hide()
	background.hide()
	if controls_menu:
		print("Calling show_menu()")
		controls_menu.show_menu()
	else:
		print("ERROR: controls_menu is null!")

func _on_restart_button_pressed() -> void:
	resume()
	get_tree().reload_current_scene()

func _on_exit_button_pressed() -> void:
	get_tree().quit()
