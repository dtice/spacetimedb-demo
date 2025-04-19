# Spacetime DB Demo

## Links
 - [SpacetimeDB Github](https://github.com/clockworklabs/SpacetimeDB)
 - [SpacetimeDB Rust Quickstart](https://spacetimedb.com/docs/modules/rust/quickstart)
 - [Godot SpacetimeDB SDK](https://github.com/flametime/Godot-SpacetimeDB-SDK)

## Requirements
 - Godot v4.3
 - Rust 1.86
 - SpacetimeDB 1.1

## Commands
 - `spacetime start` - Run Spacetime DB locally
 - `spacetime publish --project-path <path_to_project> --server local <project_name>` - Publish the module to the local Spacetime instance
 - `spacetime call <module_name> <reducer_name> <args>` - Call a reducer from a spacetime module
 - `spacetime logs <module_name>` - View logs from a module
 - `spacetime sql <module_name> "SELECT * FROM my_table"` - Execute queries in SQL syntax


