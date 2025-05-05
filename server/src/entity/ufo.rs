use spacetimedb::Timestamp;
use crate::entity::entity::Entity;
use crate::util::math::DbVector3;

#[spacetimedb::table(name = ufo, public)]
pub struct Ufo {
    #[primary_key]
    pub entity_id: u32,
    #[index(btree)]
    pub player_id: u32,
    pub direction: DbVector3,
    pub speed: f32,
    pub last_split_time: Timestamp,
    pub beam_on: bool,
    pub abducting: bool,
    pub abducted_entity: Option<Entity>
}