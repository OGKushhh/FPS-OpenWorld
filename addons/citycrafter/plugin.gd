@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type("CityCrafter", "Node3D", preload("citycrafter.gd"), null)

func _exit_tree():
	remove_custom_type("CityCrafter")
