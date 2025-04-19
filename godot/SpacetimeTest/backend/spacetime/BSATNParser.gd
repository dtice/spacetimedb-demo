# bsatn_parser.gd
class_name BSATNParser extends RefCounted

var _last_error: String = ""
# Stores loaded table row schema scripts: { "table_name_lower": Script }
var _possible_row_schemas: Dictionary = {}
var _decompressor := DataDecompressor.new()
# --- Initialization ---

func _init(schema_path: String = "res://schema") -> void:
	_load_row_schemas(schema_path)

# Loads table row schema scripts (e.g., User.gd, Message.gd)
func _load_row_schemas(path: String) -> void:
	_possible_row_schemas.clear()
	var files = DirAccess.get_files_at(path)
	for file_name in files:
		if file_name.ends_with(".remap"): file_name = file_name.replace(".remap", "");
		if file_name.ends_with(".gd") == false:continue;
		var script_path := path.path_join(file_name)
		var script: GDScript = load(script_path)
		if script and script.can_instantiate():
			# Determine table name (metadata, function, or filename fallback)
			var instance_for_name = script.new()
			var table_name := file_name.get_basename().get_file() # Fallback
			if instance_for_name:
				if instance_for_name.has_meta("table_name"):
					table_name = instance_for_name.get_meta("table_name")
				elif instance_for_name.has_method("get_table_name"):
					table_name = instance_for_name.get_table_name()
				if not table_name.is_empty():
						#print("Loaded row schema for table: '", table_name, "' from ", script_path)
					_possible_row_schemas[table_name.to_lower()] = script
				else:
					printerr("BSATNParser: Could not determine table name for schema: ", script_path)
		else:
			printerr("BSATNParser: Failed to load or instantiate script: ", script_path)

# --- Error Handling ---

func has_error() -> bool:
	return _last_error != ""

func get_last_error() -> String:
	var err := _last_error
	_last_error = "" # Clear error after getting
	return err

func clear_error() -> void:
	_last_error = ""

# Sets the error message if not already set.
func _set_error(msg: String, position: int = -1) -> void:
	if _last_error == "":
		var pos_str := " (at approx. position %d)" % position if position >= 0 else ""
		_last_error = "BSATNParser Error: %s%s" % [msg, pos_str]
		printerr(_last_error)

# Checks if enough bytes are available to read. Sets error if not.
func _check_read(spb: StreamPeerBuffer, bytes_needed: int) -> bool:
	if has_error(): return false
	if spb.get_position() + bytes_needed > spb.get_size():
		_set_error("Attempted to read %d bytes past end of buffer (size: %d)." % [bytes_needed, spb.get_size()], spb.get_position())
		return false
	return true

# --- Primitive Reading Functions ---
# Reads i8.
func read_i8(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 1): return 0
	var uval = spb.get_u8()
	# Convert u8 to i8
	if uval >= 128:
		return uval - 256
	else:
		return uval

# Reads i16 LE.
func read_i16_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 2): return 0
	spb.big_endian = false
	var uval = spb.get_u16()
	# Convert u16 to i16
	if uval >= 32768:
		return uval - 65536
	else:
		return uval

# Reads i32 LE.
func read_i32_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 4): return 0
	spb.big_endian = false
	var uval = spb.get_u32()
	# Convert u32 to i32
	if uval >= 2147483648:
		return uval - 4294967296
	else:
		return uval

func read_u8(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 1): return -1
	return spb.get_u8()

func read_u16_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 2): return 0
	spb.big_endian = false
	return spb.get_u16()

func read_u32_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 4): return 0
	spb.big_endian = false
	return spb.get_u32()

func read_u64_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 8): return 0
	spb.big_endian = false
	return spb.get_u64()

# Reads i64 by reading u64 and converting manually.
func read_i64_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 8): return 0
	spb.big_endian = false
	var uval := spb.get_u64()
	# Convert u64 to i64 (two's complement)
	if uval >= (1 << 63):
		return uval - (1 << 64)
	else:
		return uval
func read_f32_le(spb: StreamPeerBuffer) -> float:
	if not _check_read(spb, 4): return 0.0
	# StreamPeerBuffer has get_float() which reads f32 LE by default
	spb.big_endian = false # Ensure little-endian (usually default)
	return spb.get_float()

# Reads a 64-bit float (f64) in little-endian format.
func read_f64_le(spb: StreamPeerBuffer) -> float:
	if not _check_read(spb, 8): return 0.0
	spb.big_endian = false # Ensure little-endian
	return spb.get_double()
	
func read_bool(spb: StreamPeerBuffer) -> bool:
	var byte := read_u8(spb)
	if has_error(): return false
	if byte != 0 and byte != 1:
		_set_error("Invalid boolean value: %d (expected 0 or 1)" % byte, spb.get_position() - 1)
		return false
	return byte == 1

# Reads a specific number of bytes.
func read_bytes(spb: StreamPeerBuffer, num_bytes: int) -> PackedByteArray:
	if num_bytes < 0:
		_set_error("Attempted to read negative number of bytes: %d" % num_bytes, spb.get_position())
		return PackedByteArray()
	if num_bytes == 0:
		return PackedByteArray()
	if not _check_read(spb, num_bytes): return PackedByteArray()
	var result := spb.get_data(num_bytes)
	if result[0] != OK:
		_set_error("StreamPeerBuffer.get_data failed with code %d" % result[0], spb.get_position() - num_bytes)
		return PackedByteArray()
	return result[1]

# Reads a string prefixed with its u32 length.
func read_string_with_u32_len(spb: StreamPeerBuffer) -> String:
	var start_pos := spb.get_position()
	var length := read_u32_le(spb)
	if has_error(): return ""
	if length == 0: return ""

	# Reasonable limit to prevent huge allocations
	const MAX_STRING_LEN = 4 * 1024 * 1024 # 4 MB limit
	if length > MAX_STRING_LEN:
		_set_error("String length %d exceeds maximum limit %d" % [length, MAX_STRING_LEN], start_pos)
		return ""

	var str_bytes := read_bytes(spb, length)
	if has_error(): return ""

	var str_result := str_bytes.get_string_from_utf8()
	if str_result == "" and length > 0:
		# Check if it was really an empty string or a decoding error
		if str_bytes.find(0) != -1 or str_bytes.get_string_from_ascii() == "":
			# Contains null bytes or isn't valid ASCII -> likely UTF8 error
			_set_error("Failed to decode UTF-8 string of length %d (invalid encoding?)" % length, start_pos)
			# Return "" as per the error condition
		# else: it might have been a valid empty string, which is unusual but possible

	return str_result

# Reads a 32-byte SpacetimeDB Identity.
func read_identity(spb: StreamPeerBuffer) -> PackedByteArray:
	var id_bytes := read_bytes(spb, 32)
	if has_error(): return PackedByteArray()
	return id_bytes

# Reads an i64 nanosecond Timestamp.
func read_timestamp(spb: StreamPeerBuffer) -> int:
	return read_i64_le(spb)

# Reads a vector (array) of elements using a provided reader function.
func read_vec(spb: StreamPeerBuffer, element_reader_func: Callable) -> Array:
	var length := read_u32_le(spb)
	if has_error(): return []
	if length == 0: return []

	# Reasonable limit
	const MAX_VEC_LEN = 131072 # Increased limit
	if length > MAX_VEC_LEN:
		_set_error("Vector length %d exceeds maximum limit %d" % [length, MAX_VEC_LEN], spb.get_position() - 4)
		return []

	var result_array : Array = []
	result_array.resize(length)
	for i in range(length):
		if has_error():
			_set_error("Error occurred before reading element %d of vector." % i, spb.get_position())
			return [] # Return empty on error during loop

		var element = element_reader_func.call(spb)

		if has_error():
			_set_error("Failed to read element %d of vector." % i, spb.get_position())
			return [] # Return empty on error during loop

		result_array[i] = element
	return result_array

# --- BsatnRowList Reading ---

# Reads a BSATN-encoded list of rows (Array[PackedByteArray]).
func read_bsatn_row_list(spb: StreamPeerBuffer) -> Array[PackedByteArray]:
	var start_pos := spb.get_position()
	# RowSizeHint enum tag (u8)
	var size_hint_type := read_u8(spb)
	if has_error(): return []

	var rows: Array[PackedByteArray] = []

	match size_hint_type:
		0: # FixedSize(RowSize)
			var row_size := read_u16_le(spb)
			# Data length (u32)
			var data_len := read_u32_le(spb)
			if has_error(): return []

			if row_size == 0:
				if data_len != 0:
					_set_error("FixedSize row list has row_size 0 but data_len %d" % data_len, start_pos)
					# Try to recover by skipping data if possible, but return error state
					read_bytes(spb, data_len)
					return []
				return [] # Valid empty list

			# Read the bulk data
			var data := read_bytes(spb, data_len)
			if has_error(): return []

			if data_len % row_size != 0:
				_set_error("FixedSize data length %d is not divisible by row size %d" % [data_len, row_size], start_pos)
				return []

			var num_rows := data_len / row_size
			rows.resize(num_rows)
			for i in range(num_rows):
				rows[i] = data.slice(i * row_size, (i + 1) * row_size)

		1: # RowOffsets(Vec<u64>)
			# Number of offsets (u32)
			var num_offsets := read_u32_le(spb)
			if has_error(): return []

			# Read offsets (Vec<u64>)
			var offsets: Array[int] = []
			offsets.resize(num_offsets)
			for i in range(num_offsets):
				offsets[i] = read_u64_le(spb)
				if has_error(): return []

			# Read data length (u32)
			var data_len := read_u32_le(spb)
			if has_error(): return []

			# Read bulk data
			var data := read_bytes(spb, data_len)
			if has_error(): return []

			# Slice data based on offsets
			rows.resize(num_offsets)
			for i in range(num_offsets):
				var start_offset : int = offsets[i]
				# End is start of next offset, or data_len for the last row
				var end_offset : int = data_len
				if i + 1 < num_offsets:
					end_offset = offsets[i+1]

				# Validate offsets make sense
				if start_offset < 0 or end_offset < start_offset or end_offset > data_len:
					_set_error("Invalid row offsets: start=%d, end=%d, data_len=%d for row %d" % [start_offset, end_offset, data_len, i], start_pos)
					return []

				rows[i] = data.slice(start_offset, end_offset)

		_:
			_set_error("Unknown RowSizeHint type: %d" % size_hint_type, start_pos)
			return []

	return rows

# --- Row Deserialization into Resource ---
# Populates an existing Resource instance from raw BSATN bytes based on its exported properties.
# Assumes the order of @export properties matches the BSATN field order.
# Uses metadata "bsatn_type_PROPERTYNAME" for integer types (u8, i8, u16, i16, u32, i32, u64, i64).
# Reads f32 for float properties by default.
func _populate_resource_from_bytes(resource: Resource, raw_bytes: PackedByteArray) -> bool:
	if not resource:
		_set_error("Cannot populate null resource", -1)
		return false
	if not resource.get_script():
		_set_error("Cannot populate resource without a script", -1)
		return false

	var temp_spb := StreamPeerBuffer.new()
	temp_spb.data_array = raw_bytes

	var properties : Array = resource.get_script().get_script_property_list()

	for prop in properties:
		# Skip non-storage properties
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue

		var value = null
		var prop_type : Variant.Type = prop.type

		match prop_type:
			TYPE_PACKED_BYTE_ARRAY:
				# Logic for PackedByteArray (Identity, ConnectionId, etc.)
				if prop.name == &"identity" or prop.name == &"sender":
					value = read_identity(temp_spb) # Reads 32 bytes
				elif prop.name == &"connection_id":
					value = read_bytes(temp_spb, 16) # Reads 16 bytes
				else:
					# Default assumption or require metadata
					push_warning("Assuming PackedByteArray property '%s' is an Identity (32 bytes)." % prop.name)
					value = read_identity(temp_spb)

			TYPE_INT:
				# Logic for int using metadata "bsatn_type_..."
				var meta_key = "bsatn_type_" + prop.name
				if resource.has_meta(meta_key):
					var bsatn_type : String = resource.get_meta(meta_key)
					match bsatn_type.to_lower():
						"u64": value = read_u64_le(temp_spb)
						"i64": value = read_i64_le(temp_spb)
						"u32": value = read_u32_le(temp_spb)
						"i32": value = read_i32_le(temp_spb) 
						"u16": value = read_u16_le(temp_spb)
						"i16": value = read_i16_le(temp_spb) 
						"u8": value = read_u8(temp_spb)
						"i8": value = read_i8(temp_spb)    
						_:
							_set_error("Unknown BSATN type '%s' in metadata for int property '%s'" % [bsatn_type, prop.name], temp_spb.get_position())
							return false
				else:
					# Default if no metadata for int
					push_warning("Integer property '%s' in '%s' has no 'bsatn_type_' metadata. Assuming i64 (Timestamp)." % [prop.name, resource.get_script().resource_path])
					value = read_i64_le(temp_spb)

			TYPE_FLOAT: # <--- Added case for float
				# Read f32 by default.
				# If f64 support is needed later, check for metadata like:
				# var meta_key = "bsatn_type_" + prop.name
				# if resource.has_meta(meta_key) and resource.get_meta(meta_key) == "f64":
				#     value = read_f64_le(temp_spb) # Assuming read_f64_le exists
				# else:
				#     value = read_f32_le(temp_spb)
				value = read_f32_le(temp_spb) # Use the function added previously

			TYPE_STRING:
				value = read_string_with_u32_len(temp_spb)
				
			TYPE_BOOL:
				value = read_bool(temp_spb)
				
			TYPE_VECTOR3:
				var x = read_f32_le(temp_spb)
				var y = read_f32_le(temp_spb)
				var z = read_f32_le(temp_spb)
				if not has_error(): value = Vector3(x, y, z)
			TYPE_VECTOR2:
				var x = read_f32_le(temp_spb)
				var y = read_f32_le(temp_spb)
				if not has_error(): value = Vector2(x, y)

			_:
				_set_error("Unsupported property type '%s' for BSATN deserialization of property '%s' in resource '%s'" % [type_string(prop_type), prop.name, resource.get_script().resource_path], temp_spb.get_position())
				return false

		# Check for errors during reading the value
		if has_error():
			_set_error("Failed reading value for property '%s' in '%s'. Cause: %s" % [prop.name, resource.get_script().resource_path, get_last_error()], temp_spb.get_position())
			return false

		# Set the property on the resource instance
		resource.set(prop.name, value)

	# Check if all bytes in the row were consumed
	if temp_spb.get_position() < temp_spb.get_size():
		push_warning("Extra %d bytes remaining after parsing resource '%s'" % [temp_spb.get_size() - temp_spb.get_position(), resource.get_script().resource_path])

	return true


# --- Top-Level Message Parsing ---

# Entry point: Parses the entire byte buffer into a top-level message Resource.
func parse_packet(buffer: PackedByteArray) -> Resource:
	clear_error()
	var spb := StreamPeerBuffer.new()
	spb.data_array = buffer

	if buffer.is_empty():
		_set_error("Input buffer is empty", 0)
		return null
		
	var compression_tag := read_u8(spb)
	if has_error(): return null
	
	#print("DEBUG: Received compression_tag type: 0x%02X" % compression_tag)
	#if compression_tag == 0x02:
	#	print("DEBUG: Detected GZIP stream (first byte 0x1F). Attempting decompression...")
	#	print("IN GZIP : ", buffer.hex_encode())
	#	spb.data_array = _decompressor.decompress(buffer, DataDecompressor.CompressionType.GZIP)
	#	if _decompressor.has_error() or spb.data_array == null:
	#		_set_error("Failed to decompress GZIP data received from server. Cause: %s" % _decompressor.get_last_error(), 0)
	#		return null
	#	print("DEBUG: GZIP Decompression successful.")
	
	##TODO: Compression tag for inserts or whole message?
	if compression_tag != 0:
		_set_error("Compression not supported! Compressed messages (tag %d) are not supported yet." % compression_tag, 0)
		return null

	# Read the ServerMessage enum tag (u8)
	var msg_type := read_u8(spb)
	
	if has_error(): return null

	# Call the specific parser function based on the message type
	var result_resource: Resource = null

	match msg_type:
		0x00: # InitialSubscription
			result_resource = read_initial_subscription_data(spb)
		0x01: # TransactionUpdate
			result_resource = read_transaction_update_data(spb) 
		# 0x02: # TransactionUpdateLight # TODO
		#	 result_resource = read_transaction_update_light_data(spb)
		0x03: # IdentityToken
			result_resource = read_identity_token_data(spb)
		# Add cases for other ServerMessage types (SubscribeApplied, etc.)
		_:
			_set_error("Unknown server message type: 0x%02X" % msg_type, 1)
			return null

	# Check for errors during the specific message parsing
	if has_error():
		return null # Error already set and printed

	# Optional: Check if all bytes were consumed
	var remaining_bytes := spb.get_size() - spb.get_position()
	if remaining_bytes > 0:
		push_warning("Bytes remaining after parsing message type 0x%02X: %d" % [msg_type, remaining_bytes])
		# print("Remaining bytes: ", spb.get_data(remaining_bytes)[1].hex_encode())

	return result_resource

# --- Specific Message Data Readers ---

# Reads data for IdentityToken message. Returns IdentityTokenData resource.
func read_identity_token_data(spb: StreamPeerBuffer) -> IdentityTokenData:
	var resource := IdentityTokenData.new()
	resource.identity = read_identity(spb)
	resource.token = read_string_with_u32_len(spb)
	resource.connection_id = read_bytes(spb, 16) # ConnectionId is 16 bytes

	if has_error(): return null
	return resource

# Reads data for InitialSubscription message. Returns InitialSubscriptionData resource.
func read_initial_subscription_data(spb: StreamPeerBuffer) -> InitialSubscriptionData:
	var resource := InitialSubscriptionData.new()
	resource.database_update = read_database_update(spb)
	resource.request_id = read_u32_le(spb) # request_id is u32
	resource.total_host_execution_duration_ns = read_i64_le(spb) # duration is i64

	if has_error(): return null
	return resource

func read_transaction_update_data(spb: StreamPeerBuffer) -> TransactionUpdateData:
	var resource := TransactionUpdateData.new()

	resource.status = read_update_status(spb)
	if has_error(): return null

	resource.timestamp_ns = read_timestamp(spb) # i64
	resource.caller_identity = read_identity(spb) # 32 bytes
	resource.caller_connection_id = read_bytes(spb, 16) # 16 bytes
	resource.reducer_call = read_reducer_call_info(spb)
	resource.energy_quanta_used = read_u64_le(spb) # u64
	resource.total_host_execution_duration_ns = read_i64_le(spb) # i64

	if has_error(): return null
	return resource

func read_update_status(spb: StreamPeerBuffer) -> UpdateStatusData:
	var resource := UpdateStatusData.new()
	var tag := read_u8(spb) # Enum tag
	if has_error(): return null

	match tag:
		0: # Committed(DatabaseUpdate<F>)
			resource.status_type = UpdateStatusData.StatusType.COMMITTED
			resource.committed_update = read_database_update(spb)
		1: # Failed(Box<str>)
			resource.status_type = UpdateStatusData.StatusType.FAILED
			resource.failure_message = read_string_with_u32_len(spb)
		2: # OutOfEnergy
			resource.status_type = UpdateStatusData.StatusType.OUT_OF_ENERGY
			# No data associated with OutOfEnergy
		_:
			_set_error("Unknown UpdateStatus tag: %d" % tag, spb.get_position() - 1)
			return null

	if has_error(): return null
	return resource
	
func read_reducer_call_info(spb: StreamPeerBuffer) -> ReducerCallInfoData:
	var resource := ReducerCallInfoData.new()
	resource.reducer_name = read_string_with_u32_len(spb)
	resource.reducer_id = read_u32_le(spb) # u32
	# Read args as raw bytes (length prefixed u32)
	var args_len := read_u32_le(spb)
	if has_error(): return null
	resource.args = read_bytes(spb, args_len)
	resource.request_id = read_u32_le(spb) # u32
	resource.execution_time = read_f64_le(spb)
	if has_error(): return null
	return resource
	
# Reads DatabaseUpdate structure. Returns DatabaseUpdateData resource.
func read_database_update(spb: StreamPeerBuffer) -> DatabaseUpdateData:
	var resource := DatabaseUpdateData.new()
	# DatabaseUpdate contains Vec<TableUpdate>
	# Need a Callable to the read_table_update method of *this* instance
	var generic_tables_array: Array = read_vec(spb, Callable(self, "read_table_update"))
	resource.tables.assign(generic_tables_array)

	if has_error(): return null
	return resource

# Reads TableUpdate structure. Returns TableUpdateData resource.
##TODO: Compression support for inserts? 
func read_table_update(spb: StreamPeerBuffer) -> TableUpdateData:
	var resource := TableUpdateData.new()
	resource.table_id = read_u32_le(spb)
	resource.table_name = read_string_with_u32_len(spb)
	resource.num_rows = read_u64_le(spb)

	var updates_count := read_u32_le(spb)
	if has_error(): return null

	var all_parsed_deletes: Array[Resource] = []
	var all_parsed_inserts: Array[Resource] = []

	var row_schema_script : Script = _possible_row_schemas.get(resource.table_name.to_lower())
	if not row_schema_script and updates_count > 0:
		push_warning("No row schema found for table '%s', cannot deserialize rows." % resource.table_name)

	# Loop through each CompressableQueryUpdate
	for i in range(updates_count):
		var update_start_pos := spb.get_position()
		# Read CompressableQueryUpdate tag (u8)
		var compression_tag_raw := read_u8(spb)
		if has_error(): break

		var query_update_bytes: PackedByteArray
		var query_update_spb: StreamPeerBuffer = null # Will hold the final data to parse

		match compression_tag_raw:
			0: # Uncompressed (SERVER_MSG_COMPRESSION_TAG_NONE)
				# Data follows directly, use the main spb for reading QueryUpdate parts
				query_update_spb = spb
				pass # Continue below to read deletes/inserts from main spb

			1: # Brotli (SERVER_MSG_COMPRESSION_TAG_BROTLI)
				# Read length-prefixed compressed data
				var compressed_len := read_u32_le(spb)
				if has_error(): break
				var compressed_data := read_bytes(spb, compressed_len)
				if has_error(): break

				# Attempt decompression using the DataDecompressor
				var decompressed_data := _decompressor.decompress(compressed_data, DataDecompressor.CompressionType.BROTLI)

				if _decompressor.has_error():
					# Propagate error from decompressor
					_set_error("Failed to decompress Brotli data for table '%s'. Cause: %s" % [resource.table_name, _decompressor.get_last_error()], update_start_pos)
					break # Stop processing updates for this table
				elif decompressed_data == null: # Should not happen if error is set, but check anyway
					_set_error("Brotli decompression returned null unexpectedly for table '%s'." % resource.table_name, update_start_pos)
					break

				# Create a *new* StreamPeerBuffer with the decompressed data
				query_update_spb = StreamPeerBuffer.new()
				query_update_spb.data_array = decompressed_data
				# Now deletes/inserts will be read from this temp buffer

			2: # Gzip (SERVER_MSG_COMPRESSION_TAG_GZIP)
				# Read length-prefixed compressed data
				var compressed_len_gzip := read_u32_le(spb)
				if has_error(): break
				var compressed_data_gzip := read_bytes(spb, compressed_len_gzip)
				if has_error(): break

				# Attempt decompression using the DataDecompressor
				var decompressed_data_gzip := _decompressor.decompress(compressed_data_gzip, DataDecompressor.CompressionType.GZIP)

				if _decompressor.has_error():
					_set_error("Failed to decompress Gzip data for table '%s'. Cause: %s" % [resource.table_name, _decompressor.get_last_error()], update_start_pos)
					break
				elif decompressed_data_gzip == null:
					_set_error("Gzip decompression returned null unexpectedly for table '%s'." % resource.table_name, update_start_pos)
					break

				# Create a *new* StreamPeerBuffer with the decompressed data
				query_update_spb = StreamPeerBuffer.new()
				query_update_spb.data_array = decompressed_data_gzip

			_:
				_set_error("Unknown QueryUpdate compression tag %d for table '%s'" % [compression_tag_raw, resource.table_name], update_start_pos)
				break # Stop processing updates for this table

		# Check for errors after handling compression/decompression attempt
		if has_error(): break
		if query_update_spb == null: # Should have been set if no error occurred
			_set_error("Internal error: query_update_spb not set after compression handling for table '%s'." % resource.table_name, update_start_pos)
			break

		# --- Read QueryUpdate { deletes: BsatnRowList, inserts: BsatnRowList } ---
		# Read from the appropriate buffer (original spb or the new decompressed one)
		var raw_deletes := read_bsatn_row_list(query_update_spb)
		if has_error(): break
		var raw_inserts := read_bsatn_row_list(query_update_spb)
		if has_error(): break

		# If we have a schema, deserialize the raw row bytes
		if row_schema_script:
			for raw_row_bytes in raw_deletes:
				var row_resource = row_schema_script.new()
				if _populate_resource_from_bytes(row_resource, raw_row_bytes):
					all_parsed_deletes.append(row_resource)
				else:
					_set_error("Failed parsing delete row for table '%s'. Cause: %s" % [resource.table_name, get_last_error()], -1) # Position context lost here
					break # Stop parsing rows for this update

			if has_error(): break # Stop parsing updates for this table

			for raw_row_bytes in raw_inserts:
				var row_resource = row_schema_script.new()
				if _populate_resource_from_bytes(row_resource, raw_row_bytes):
					all_parsed_inserts.append(row_resource)
				else:
					_set_error("Failed parsing insert row for table '%s'. Cause: %s" % [resource.table_name, get_last_error()], -1)
					break

			if has_error(): break # Stop parsing updates for this table
		# else: If no schema, rows remain raw bytes (already handled by read_bsatn_row_list)

	# After the loop, check for errors again
	if has_error():
		return null # Indicate failure to parse this TableUpdate

	# Populate the final resource
	resource.deletes = all_parsed_deletes
	resource.inserts = all_parsed_inserts

	return resource


	# After the loop, check for errors again
	if has_error():
		return null # Indicate failure to parse this TableUpdate

	# Populate the final resource
	resource.deletes = all_parsed_deletes
	resource.inserts = all_parsed_inserts

	return resource
