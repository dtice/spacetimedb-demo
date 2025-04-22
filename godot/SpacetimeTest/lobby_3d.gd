extends Node3D

@onready var spacetimedb_client: SpacetimeDBClient = $SpacetimeDBClient

func _ready():
	spacetimedb_client.connected.connect(_on_spacetimedb_connected)
	#spacetimedb_client.disconnected.connect(_on_spacetimedb_disconnected)
	#spacetimedb_client.connection_error.connect(_on_spacetimedb_connection_error)
	spacetimedb_client.identity_received.connect(_on_spacetimedb_identity_received)
	spacetimedb_client.database_initialized.connect(_on_spacetimedb_database_initialized)
	#spacetimedb_client.transaction_update_received.connect(_on_transaction_update)
	# Local DB signals for direct UI/game state updates
	spacetimedb_client.row_inserted.connect(_on_spacetimedb_row_inserted)
	spacetimedb_client.row_updated.connect(_on_spacetimedb_row_updated)
	spacetimedb_client.row_deleted.connect(_on_spacetimedb_row_deleted)
	
func _on_spacetimedb_connected():
	print("Game: Connected!")
	# Subscribe to desired tables
	spacetimedb_client.subscribe(["SELECT * FROM user", "SELECT * FROM message"])

func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
	print("Game: My Identity: 0x", identity_token.identity.hex_encode())
	# Store identity if needed

func _on_spacetimedb_database_initialized():
	print("Game: Local database ready.")
	# Initial game state setup using the local DB
	var db = spacetimedb_client.get_local_database()
	var initial_users = db.get_all_rows("user")
	print("Initial online users: ", initial_users.filter(func(u): return u.online).size())

func _on_spacetimedb_row_inserted(table_name: String, row: Resource):
	if table_name == 'user' and row.online:
		print("Spawning player", row)
	
	if table_name == 'message':
		print("Message sent: ", row)
		# _spawn_player(row) # Your function to create a player node

func _on_spacetimedb_row_updated(table_name: String, row: Resource):
	if table_name == 'user':
		#_update_player(row) # Your function to update position, state, etc.
		print("Updating player", row)
		
	if table_name == 'message':
		print("Message updated", row)

func _on_spacetimedb_row_deleted(table_name: String, primary_key):
	if table_name == "user":
		print("Despawning player: ", primary_key)
		# _despawn_player(primary_key) # Your function to remove player node
		
	if table_name == "message":
		print("Message deleted: ", primary_key)
