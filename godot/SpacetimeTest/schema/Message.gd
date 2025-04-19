extends Resource
class_name Message

@export var sender: PackedByteArray
@export var sent: int
@export var text: String

func _init():
	set_meta("primary_key", "identity")
