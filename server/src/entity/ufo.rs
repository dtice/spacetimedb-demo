use crate::entity::entity::Entity;
use crate::util::math::DbVector3;
use spacetimedb::Timestamp;

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
    pub abducted_entity: Option<Entity>,
}

pub fn mass_to_ufo_size(mass: u32) -> f32 {
    mass as f32 * 0.01f32
}
