# addons/spacetimedb_client/SpacetimeDBClient.gd
class_name SpacetimeDBClient extends Node

# --- Configuration ---
@export var base_url: String = "http://127.0.0.1:3000"
@export var database_name: String = "quickstart-chat" # Example
@export var schema_path: String = "res://schema"
@export var auto_connect: bool = true
@export var auto_request_token: bool = true
@export var token_save_path: String = "user://spacetimedb_token.dat" # Use a more specific name
@export var one_time_token:bool = false
@export var compression:SpacetimeDBConnection.CompressionPreference;
# --- Components ---
var _connection: SpacetimeDBConnection
var _parser: BSATNParser
var _local_db: LocalDatabase
var _rest_api: SpacetimeDBRestAPI # Optional, for token/REST calls

# --- State ---
var _token: String
var _is_initialized := false

# --- Signals ---
# Re-emit signals from components for easier use
signal connected
signal disconnected
signal connection_error(code: int, reason: String)
signal identity_received(identity_token: IdentityTokenData)
signal database_initialized # Emitted after InitialSubscription is processed
signal database_updated(table_update: TableUpdateData) # Emitted for each table update
signal row_inserted(table_name: String, row: Resource) # From LocalDatabase
signal row_updated(table_name: String, row: Resource) # From LocalDatabase
signal row_deleted(table_name: String, primary_key) # From LocalDatabase
signal reducer_call_response(response: Resource) # TODO: Define response resource
signal reducer_call_timeout(request_id: int) # TODO: Implement timeout logic
signal transaction_update_received(update: TransactionUpdateData)

func _ready():
	# Defer initialization until explicitly called or via auto_connect
	if auto_connect:
		initialize_and_connect()

func initialize_and_connect():
	if _is_initialized: return
	print("SpacetimeDBClient: Initializing...")

	# 1. Initialize Parser
	_parser = BSATNParser.new(schema_path)

	# 2. Initialize Local Database
	_local_db = LocalDatabase.new(_parser._possible_row_schemas) # Pass loaded schemas
	# Connect to LocalDatabase signals to re-emit them
	_local_db.row_inserted.connect(func(tn, r): emit_signal("row_inserted", tn, r))
	_local_db.row_updated.connect(func(tn, r): emit_signal("row_updated", tn, r))
	_local_db.row_deleted.connect(func(tn, pk): emit_signal("row_deleted", tn, pk))
	add_child(_local_db) # Add as child if it needs signals

	# 3. Initialize REST API Handler (optional, mainly for token)
	_rest_api = SpacetimeDBRestAPI.new(base_url)
	_rest_api.token_received.connect(_on_token_received)
	_rest_api.token_request_failed.connect(_on_token_request_failed)
	# Connect other REST signals if needed
	add_child(_rest_api)

	# 4. Initialize Connection Handler
	_connection = SpacetimeDBConnection.new(compression)
	_connection.connected.connect(func(): emit_signal("connected"))
	_connection.disconnected.connect(func(): emit_signal("disconnected"))
	_connection.connection_error.connect(func(c, r): emit_signal("connection_error", c, r))
	_connection.message_received.connect(_on_websocket_message_received)
	add_child(_connection)

	_is_initialized = true
	print("SpacetimeDBClient: Initialization complete.")

	# 5. Get Token and Connect
	_load_token_or_request()

func _load_token_or_request():
	
	if one_time_token == false:
	# Try loading saved token
		if FileAccess.file_exists(token_save_path):
			var file := FileAccess.open(token_save_path, FileAccess.READ)
			if file:
				var saved_token := file.get_as_text().strip_edges()
				file.close()
				if not saved_token.is_empty():
					print("SpacetimeDBClient: Using saved token.")
					_on_token_received(saved_token) # Directly use the saved token
					return

	# If no valid saved token, request a new one if auto-request is enabled
	if auto_request_token:
		print("SpacetimeDBClient: No valid saved token found, requesting new one.")
		_rest_api.request_new_token()
	else:
		printerr("SpacetimeDBClient: No token available and auto_request_token is false.")
		emit_signal("connection_error", -1, "Authentication token unavailable")

func _generate_connection_id() -> String:
	var random_bytes := PackedByteArray()
	random_bytes.resize(16)
	var rng := RandomNumberGenerator.new()
	for i in 16:
		random_bytes[i] = rng.randi_range(0, 255)
	return random_bytes.hex_encode() # Return as hex string
	
func _on_token_received(received_token: String):
	print("SpacetimeDBClient: Token acquired.")
	self._token = received_token
	_save_token(received_token)
	var conn_id = _generate_connection_id()
	# Pass token to components that need it
	_connection.set_token(self._token)
	_rest_api.set_token(self._token) # REST API might also need it

	# Now attempt to connect WebSocket
	_connection.connect_to_database(base_url, database_name, conn_id, compression)

func _on_token_request_failed(error_code: int, response_body: String):
	printerr("SpacetimeDBClient: Failed to acquire token. Cannot connect.")
	emit_signal("connection_error", error_code, "Failed to acquire authentication token")

func _save_token(token_to_save: String):
	var file := FileAccess.open(token_save_path, FileAccess.WRITE)
	if file:
		file.store_string(token_to_save)
		file.close()
	else:
		printerr("SpacetimeDBClient: Failed to save token to path: ", token_save_path)


# --- WebSocket Message Handling ---

func _on_websocket_message_received(bsatn_bytes: PackedByteArray):
	if not _parser: return # Should not happen if initialized

	var message_resource: Resource = _parser.parse_packet(bsatn_bytes)

	if _parser.has_error():
		printerr("SpacetimeDBClient: Failed to parse BSATN packet: ", _parser.get_last_error())
		return

	if message_resource == null:
		# Parsing might have returned null without setting error (e.g., unknown type)
		# Parser should ideally always set an error in this case.
		printerr("SpacetimeDBClient: Parser returned null message resource.")
		return

	# Handle known message types
	if message_resource is InitialSubscriptionData:
		var initial_sub: InitialSubscriptionData = message_resource
		print("SpacetimeDBClient: Processing Initial Subscription (Req ID: %d)" % initial_sub.request_id)
		_local_db.apply_database_update(initial_sub.database_update)
		emit_signal("database_initialized")

	elif message_resource is IdentityTokenData:
		var identity_token: IdentityTokenData = message_resource
		print("SpacetimeDBClient: Received Identity Token.")
		# Store identity if needed, maybe emit signal
		emit_signal("identity_received", identity_token)

	elif message_resource is TransactionUpdateData: 
		var tx_update: TransactionUpdateData = message_resource
		#print("SpacetimeDBClient: Processing Transaction Update (Reducer: %s, Req ID: %d)" % [tx_update.reducer_call.reducer_name, tx_update.reducer_call.request_id])
		# Apply changes to local DB only if committed
		if tx_update.status.status_type == UpdateStatusData.StatusType.COMMITTED:
			if tx_update.status.committed_update: # Check if update data exists
				_local_db.apply_database_update(tx_update.status.committed_update)
			else:
				# This might happen if a transaction committed but affected 0 rows relevant to the client
				print("SpacetimeDBClient: Committed transaction had no relevant row updates.")
		elif tx_update.status.status_type == UpdateStatusData.StatusType.FAILED:
			printerr("SpacetimeDBClient: Reducer call failed: ", tx_update.status.failure_message)
		elif tx_update.status.status_type == UpdateStatusData.StatusType.OUT_OF_ENERGY:
			printerr("SpacetimeDBClient: Reducer call ran out of energy.")

		# Emit the full transaction update signal regardless of status
		emit_signal("transaction_update_received", tx_update)

	else:
		print("SpacetimeDBClient: Received unhandled message resource type: ", message_resource.get_class())


# --- Public API ---

func connect_db():
	if not _is_initialized:
		initialize_and_connect()
	elif not _connection.is_connected_db():
		# Already initialized, just need token and connect
		_load_token_or_request()

func disconnect_db():
	if _connection:
		_connection.disconnect_from_server()

func is_connected_db() -> bool:
	return _connection and _connection.is_connected_db()

# Gets the local database instance for querying
func get_local_database() -> LocalDatabase:
	return _local_db

func subscribe(queries: PackedStringArray) -> int:
	if not is_connected_db():
		printerr("SpacetimeDBClient: Cannot subscribe, not connected.")
		return -1 # Indicate error

	# Generate a request ID (u32 range)
	var request_id := randi() & 0xFFFFFFFF

	# Construct the JSON message structure for Subscribe
	var subscribe_payload = {
		"query_strings": queries,
		"request_id": request_id
	}

	var client_message = { "Subscribe": subscribe_payload }
	var json_string := JSON.stringify(client_message)

	print("SpacetimeDBClient: Sending subscription request via WebSocket (JSON), Req ID: %d" % request_id)
	# print("SpacetimeDBClient: Queries: ", queries) # Optional debug

	# Send the JSON string as text over the WebSocket
	if _connection and _connection._websocket: # Basic check
		var err = _connection._websocket.send_text(json_string)
		if err != OK:
			printerr("SpacetimeDBClient: Error sending Subscribe JSON message: ", err)
			return -1 # Indicate error
		else:
			print("SpacetimeDBClient: Subscribe request sent successfully.")
			return request_id # Return the ID on success
	else:
		printerr("SpacetimeDBClient: Internal error - WebSocket peer not available in connection.")
		return -1

func get_properly_formatting(args: Dictionary) -> Dictionary:
	for i in args:
		match typeof(args[i]):
			TYPE_VECTOR2 : args[i] = [args[i].x, args[i].y]
			TYPE_VECTOR3 : args[i] = [args[i].x, args[i].y, args[i].z]
			_: args[i] = args[i]
	return args
	
func call_reducer(reducer_name: String, args: Dictionary, notify_on_done: bool = true) -> int:
	if not is_connected_db():
		#printerr("SpacetimeDBClient: Cannot call reducer, not connected.")
		return -1 # Indicate error

	# Generate a request ID (ensure it's u32 range if needed, but randi is fine for now)
	var request_id := randi() & 0xFFFFFFFF # Ensure positive u32 range

	# Determine flags based on notify_on_done
	# 0 = FullUpdate (default, notify caller even if no relevant subscription)
	# 1 = NoSuccessNotify (don't notify caller on success unless subscribed)
	var flags := 0 if notify_on_done else 1

	# Construct the JSON message structure expected by the server
	# IMPORTANT: The 'args' field here expects a *string* containing JSON,
	# matching the structure from your original code.
	# If the server expects args as a nested JSON object, adjust accordingly.
	
	var call_reducer_payload = {
		"reducer": reducer_name,
		"args": JSON.stringify(get_properly_formatting(args)), # Stringify the arguments dictionary
		"request_id": request_id,
		"flags": flags
	}

	var client_message = { "CallReducer": call_reducer_payload }
	var json_string := JSON.stringify(client_message)

	#print("SpacetimeDBClient: Calling reducer '%s' via WebSocket (JSON), Req ID: %d" % [reducer_name, request_id])

	# Send the JSON string as text over the WebSocket
	# Access the internal _websocket peer directly (might need adjustment if _connection API changes)
	if _connection and _connection._websocket: # Basic check
		var err = _connection._websocket.send_text(json_string)
		if err != OK:
			#printerr("SpacetimeDBClient: Error sending CallReducer JSON message: ", err)
			return -1 # Indicate error
		else:
			return request_id # Return the ID on success
	else:
		#printerr("SpacetimeDBClient: Internal error - WebSocket peer not available in connection.")
		return -1
		
# Waits asynchronously for a TransactionUpdate with a specific request ID.
# Returns the TransactionUpdateData or null if timed out.
#WARNING Not sure about this
func wait_for_reducer_response(request_id_to_match: int, timeout_seconds: float = 10.0) -> TransactionUpdateData:
	if request_id_to_match < 0:
		return null

	var signal_result: TransactionUpdateData = null
	var timeout_ms: float = timeout_seconds * 1000.0
	var start_time: float = Time.get_ticks_msec()

	while Time.get_ticks_msec() - start_time < timeout_ms:
		var received_signal = await transaction_update_received
		if _check_reducer_response(received_signal, request_id_to_match):
			signal_result = received_signal
			break

	if signal_result == null:
		printerr("SpacetimeDBClient: Timeout waiting for response for Req ID: %d" % request_id_to_match)
		#i realy need it here if i already await?
		reducer_call_timeout.emit(request_id_to_match)
		return null
	else:
		var tx_update: TransactionUpdateData = signal_result
		print("SpacetimeDBClient: Received matching response for Req ID: %d" % request_id_to_match)
		#i realy need it here if i already await?
		reducer_call_response.emit(tx_update.reducer_call)
		return tx_update

func _check_reducer_response(update: TransactionUpdateData, request_id_to_match: int) -> bool:
	return update != null and update.reducer_call != null and update.reducer_call.request_id == request_id_to_match
