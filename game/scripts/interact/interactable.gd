## Anything the boy can use: sit on, swing on, pick up, buy from, climb...
## Every interaction in the game is one of these, so props, mini-games and
## (later) other players all talk to the boy the same way:
##
## * the boy asks InteractionDirector for the best interactable near him
##   (in reach, in front of him, `can_interact`), shows its `prompt`, and on
##   the use button calls `interact(kid)`;
## * an interaction that holds the boy (a seat, a swing, the slide) calls
##   `kid.attach(self, mode, transform)`; while attached the boy calls
##   `drive(kid, intent, delta)` every physics frame instead of walking, and
##   `release(kid)` when he gets off.
##
## `state` holds what a network game would have to share (who is on it, the
## swing's angle...), kept as plain values.
class_name Interactable
extends Node3D

signal used(kid: Node3D)

@export var prompt := "Use"
@export var reach := 1.4                  ## metres from the boy to `focus_point()`
@export var needs_facing := true          ## the boy must roughly face it
var state := {}
var user: Node3D = null                   ## the boy using it now (one at a time)


func _enter_tree() -> void:
	add_to_group("interactable")


func can_interact(_kid: Node3D) -> bool:
	return user == null


func focus_point() -> Vector3:
	return global_position


func interact(kid: Node3D) -> void:
	used.emit(kid)


func drive(_kid: Node3D, _intent: Dictionary, _delta: float) -> void:
	pass


func release(kid: Node3D) -> void:
	if user == kid:
		user = null


## For the prompt: what pressing use does right now.
func prompt_for(_kid: Node3D) -> String:
	return prompt
