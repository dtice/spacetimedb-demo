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

## How to run the SampleScene
1. Run `scripts/publish.bat` to publish the module to SpacetimeDB
2. Run `scrips/generate.bat` to generate the types for Unity
3. Run the `SampleScene` Scene

## How to deploy
1. Deploy EC2Stack/CloudfrontStack
2. Change Route53 record for spacetime.dilltice.com to server public dns

## TODO:
 - Make the inputs for the UFOs better
 - Scale the UFOs and Cows better
  - We probably need to calculate the UFO bounding box as a cylinder, and the cow as a box
 - Abduct cows
~~- Handle the camera better~~
 - Score/Map UI
~~- Figure out why so many UFOs get created when only 1 player is present~~
~~- Hide the initial prefabs?~~

## Bugs:
 - Player bounding box w.r.t. walls is calculated incorrectly in system.rs:move_all_players
 - Bug where player gets too big and cow is not abducted