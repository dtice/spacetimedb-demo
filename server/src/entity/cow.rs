use spacetimedb::{reducer, ReducerContext, ScheduleAt, Table};
use spacetimedb::rand::Rng;
use crate::entity::entity::{entity, Entity};
use crate::player::player::player;
use crate::system::system::config;
use crate::util::constants::{COW_MASS_MAX, COW_MASS_MIN, TARGET_COW_COUNT};
use crate::util::math::DbVector3;
use crate::util::util::{mass_to_cow_size, mass_to_max_move_speed};

#[spacetimedb::table(name = cow, public)]
pub struct Cow {
    #[primary_key]
    pub entity_id: u32,
    pub direction: DbVector3,
    pub speed: f32,
    pub is_being_abducted: bool
}

// Reducers
#[reducer]
pub fn change_cow_directions(ctx: &ReducerContext, _timer: ChangeCowDirectionTimer) -> Result<(), String> {
    // IDK WHAT IM DOING
    log::info!("Cows changing direction");
    for mut cow in ctx.db.cow().iter() {
        let entity = ctx.db.entity().entity_id().find(&cow.entity_id);
        if !entity.is_some() || cow.is_being_abducted {
            continue;
        }
        let entity = entity.unwrap();
        let mut rng = ctx.rng();
        let rand_x = rng.gen_range(-100..100) as f32;
        let rand_z = rng.gen_range(-100..100) as f32;
        cow.direction = DbVector3 {
            x: rand_x,
            y: 0.0,
            z: rand_z
        }.normalized();
        ctx.db.entity().entity_id().update(entity);
        ctx.db.cow().entity_id().update(cow);
    }
    Ok(())
}

#[reducer]
pub fn move_all_cows(ctx: &ReducerContext, _timer: MoveAllCowsTimer) -> Result<(), String> {
    // IDK WHAT IM DOING
    log::info!("Cows moving");
    let world_size = ctx
        .db
        .config()
        .id()
        .find(0)
        .ok_or("Config not found")?
        .world_size;

    for cow in ctx.db.cow().iter() {
        let cow_entity = ctx.db.entity().entity_id().find(&cow.entity_id);
        if !cow_entity.is_some() || cow.is_being_abducted {
            continue;
        }
        let mut cow_entity = cow_entity.unwrap();
        let direction = cow.direction * cow.speed / 60.0;
        let new_pos = cow_entity.position + direction * mass_to_max_move_speed(cow_entity.mass);
        let size = mass_to_cow_size(cow_entity.mass);
        let max = world_size as f32 - size;
        cow_entity.position.x = new_pos.x.clamp(size, max);
        cow_entity.position.z = new_pos.z.clamp(size, max);
        ctx.db.entity().entity_id().update(cow_entity);
    }
    Ok(())
}

#[reducer]
pub fn spawn_cow(ctx: &ReducerContext, _timer: SpawnCowTimer) -> Result<(), String> {
    if ctx.db.player().count() == 0 {
        return Ok(());
    }

    let world_size = ctx
        .db
        .config()
        .id()
        .find(0)
        .ok_or("Config not found")?
        .world_size;

    let mut rng = ctx.rng();
    let mut cow_count = ctx.db.cow().count();

    while cow_count < TARGET_COW_COUNT as u64 {
        let cow_mass = rng.gen_range(COW_MASS_MIN..COW_MASS_MAX);
        let cow_size = mass_to_cow_size(cow_mass);

        let x = rng.gen_range(cow_size..world_size as f32 - cow_size);
        let y: f32 = 0.125;
        let z = rng.gen_range(cow_size..world_size as f32 - cow_size);
        let entity = ctx.db.entity().try_insert(Entity {
            entity_id: 0,
            position: DbVector3 { x, y, z },
            mass: cow_mass,
        })?;
        let rand_x = rng.gen_range(1.0..100.0) as f32;
        let rand_z = rng.gen_range(1.0..100.0) as f32;
        let direction = DbVector3 {
            x: rand_x,
            y: 0.0,
            z: rand_z,
        };
        log::info!("Direction: {:?}", direction);
        ctx.db.cow().try_insert(Cow {
            entity_id: entity.entity_id,
            direction: direction,
            is_being_abducted: false,
            speed: 1.0,
        })?;
        cow_count += 1;
        log::info!("Spawned cow! {}", entity.entity_id);
    }
    Ok(())
}

// Timers
#[spacetimedb::table(name = spawn_cow_timer, scheduled(spawn_cow))]
pub struct SpawnCowTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt
}

#[spacetimedb::table(name = move_all_cows_timer, scheduled(move_all_cows))]
pub struct MoveAllCowsTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt
}

#[spacetimedb::table(name = change_cow_direction_timer, scheduled(change_cow_directions))]
pub struct ChangeCowDirectionTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt
}