use spacetimedb::{table, Identity, ScheduleAt, Timestamp};

use crate::{math::DbVector3, reducers::{move_all_players, spawn_cow}};

#[spacetimedb::table(name = config, public)]
pub struct Config {
    #[primary_key]
    pub id: u32,
    pub world_size: u64,
}

#[spacetimedb::table(name = entity, public)]
#[derive(Debug, Clone)]
pub struct Entity {
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

// Timers
#[spacetimedb::table(name = spawn_cow_timer, scheduled(spawn_cow))]
pub struct SpawnCowTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt
}

#[spacetimedb::table(name = move_all_players_timer, scheduled(move_all_players))]
pub struct MoveAllPlayersTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: spacetimedb::ScheduleAt,
}