extends CharacterBody2D

@export var JUMP_IMPULSE = 400.0
@export var WALK_SPEED = 200.0

func _physics_process(delta: float) -> void:
	velocity.y += get_gravity().y * delta
	
	if is_on_floor() and Input.is_action_just_pressed('jump'):
		velocity.y -= JUMP_IMPULSE
		
	if Input.is_action_pressed("ui_left"):
		velocity.x = -WALK_SPEED
	elif Input.is_action_pressed("ui_right"):
		velocity.x =  WALK_SPEED
	else:
		velocity.x = 0
		
	move_and_slide()
