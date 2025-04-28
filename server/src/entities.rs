use spacetimedb::{table, Identity, ScheduleAt, SpacetimeType, Timestamp};

use crate::reducers::spawn_cow;

// We're using this table as a singleton, so in this table
// there only be one element where the `id` is 0.
#[spacetimedb::table(name = config, public)]
pub struct Config {
    #[primary_key]
    pub id: u32,
    pub world_size: u64,
}

// This allows us to store 2D points in tables.
#[derive(SpacetimeType, Clone, Debug)]
pub struct DbVector2 {
    pub x: f32,
    pub y: f32,
}

#[derive(SpacetimeType, Clone, Debug)]
pub struct DbVector3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[spacetimedb::table(name = entity, public)]
#[derive(Debug, Clone)]
pub struct Entity {
    // The `auto_inc` attribute indicates to SpacetimeDB that
    // this value should be determined by SpacetimeDB on insert.
    #[auto_inc]
    #[primary_key]
    pub entity_id: u32,
    pub position: DbVector3,
    pub mass: u32,
}

#[spacetimedb::table(name = ufo, public)]
pub struct Ufo {
    #[primary_key]
    pub entity_id: u32,
    #[index(btree)]
    pub player_id: u32,
    pub direction: DbVector3,
    pub speed: f32,
    pub last_split_time: Timestamp,
}

#[spacetimedb::table(name = cow, public)]
pub struct Cow {
    #[primary_key]
    pub entity_id: u32,
}

#[spacetimedb::table(name = spawn_cow_timer, scheduled(spawn_cow))]
pub struct SpawnCowTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt
}

#[table(name = player, public)]
#[table(name = logged_out_player)]
pub struct Player {
    #[primary_key]
    pub identity: Identity,
    #[unique]
    #[auto_inc]
    pub player_id: u32,
    pub name: String,
}

#[table(name = message, public)]
pub struct Message {
    pub sender: Identity,
    pub sent: Timestamp,
    pub text: String,
}