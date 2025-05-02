use std::time::Duration;

use spacetimedb::{rand::Rng, reducer, ReducerContext, ScheduleAt, Table, Timestamp};

use crate::{
    constants::{COW_MASS_MAX, COW_MASS_MIN, TARGET_COW_COUNT}, entities::{
        config, cow, entity, message, move_all_players_timer, player, spawn_cow_timer, move_all_cows_timer, change_cow_direction_timer, ufo, Config, Cow, Entity, Message, MoveAllPlayersTimer, MoveAllCowsTimer, Player, SpawnCowTimer, Ufo, ChangeCowDirectionTimer
    }, math::{DbVector2, DbVector3}, util::{mass_to_cow_size, mass_to_max_move_speed, validate_message, validate_name}
};

#[reducer(init)]
pub fn init(ctx: &ReducerContext) -> Result<(), String> {
    log::info!("Initializing...");
    ctx.db.config().try_insert(Config {
        id: 0,
        world_size: 10,
    })?;
    ctx.db
    .spawn_cow_timer().try_insert(SpawnCowTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(500).into()),
    })?;
    ctx.db
    .move_all_players_timer()
    .try_insert(MoveAllPlayersTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(50).into()),
    })?;
    ctx.db
    .change_cow_direction_timer()
    .try_insert(ChangeCowDirectionTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(1000).into()),
    })?;
    ctx.db
    .move_all_cows_timer()
    .try_insert(MoveAllCowsTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(50).into()),
    })?;

    Ok(())
}

#[reducer]
pub fn enter_game(ctx: &ReducerContext, name: String) -> Result<(), String> {
    log::info!("Creating player with name {}", name);
    let mut player: Player = ctx.db.player().identity().find(ctx.sender).ok_or("")?;
    let player_id = player.player_id;
    player.name = validate_name(name)?;
    ctx.db.player().identity().update(player);
    spawn_player(ctx, player_id)?;

    Ok(())
}

fn spawn_player(ctx: &ReducerContext, player_id: u32) -> Result<(), String> {
    let world_size = ctx
        .db
        .config()
        .id()
        .find(0)
        .ok_or("Config not found")?
        .world_size;
    let mut rng = ctx.rng();
    let x = rng.gen_range(0.0..world_size as f32);
    let y: f32 = 0.125f32;
    let z = rng.gen_range(0.0..world_size as f32);
    spawn_player_at(
        ctx,
        player_id,
        1,
        DbVector3 { x, y, z },
        ctx.timestamp,
    )?;
    Ok(())
}

fn spawn_player_at(
    ctx: &ReducerContext,
    player_id: u32,
    mass: u32,
    position: DbVector3,
    timestamp: Timestamp,
) -> Result<Entity, String> {
    let entity = ctx.db.entity().try_insert(Entity {
        entity_id: 0,
        position,
        mass,
    })?;

    ctx.db.ufo().try_insert(Ufo {
        entity_id: entity.entity_id,
        player_id,
        direction: DbVector3 {
            x: 0.0,
            y: 0.0,
            z: 0.0,
        },
        speed: 0.0,
        last_split_time: timestamp,
    })?;

    Ok(entity)
}

#[spacetimedb::reducer]
pub fn update_player_input(ctx: &ReducerContext, direction: DbVector2) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(&ctx.sender)
        .ok_or("Player not found")?;
    for mut ufo in ctx.db.ufo().player_id().filter(&player.player_id) {
        let norm = direction.normalized();
        ufo.direction = DbVector3 {
            x: norm.x,
            y: ufo.direction.y,
            z: norm.y
        };
        ufo.speed = direction.magnitude().clamp(0.0, 1.0);
        ctx.db.ufo().entity_id().update(ufo);
    }
    Ok(())
}

#[spacetimedb::reducer]
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

#[spacetimedb::reducer]
pub fn move_all_players(ctx: &ReducerContext, _timer: MoveAllPlayersTimer) -> Result<(), String> {
    let world_size = ctx
        .db
        .config()
        .id()
        .find(0)
        .ok_or("Config not found")?
        .world_size;

    // Handle player input
    for ufo in ctx.db.ufo().iter() {
        let ufo_entity = ctx.db.entity().entity_id().find(&ufo.entity_id);
        if !ufo_entity.is_some() {
            // This can happen if a circle is eaten by another circle
            continue;
        }
        let mut ufo_entity = ufo_entity.unwrap();
        let ufo_size = mass_to_cow_size(ufo_entity.mass);
        let direction = ufo.direction * ufo.speed / 60.0;
        let new_pos =
            ufo_entity.position + direction * mass_to_max_move_speed(ufo_entity.mass);
        let min = ufo_size;
        let max = world_size as f32 - ufo_size;
        ufo_entity.position.x = new_pos.x.clamp(min, max);
        ufo_entity.position.z = new_pos.z.clamp(min, max);
        ctx.db.entity().entity_id().update(ufo_entity);
    }

    Ok(())
}

#[spacetimedb::reducer]
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

#[reducer]
pub fn set_name(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let name = validate_name(name)?;
    if let Some(user) = ctx.db.player().identity().find(ctx.sender) {
        ctx.db.player().identity().update(Player { name, ..user });
        Ok(())
    } else {
        Err("Cannot set name for unknown user".to_string())
    }
}

#[reducer]
pub fn send_message(ctx: &ReducerContext, text: String) -> Result<(), String> {
    let text = validate_message(text)?;
    log::info!("{}", text);
    ctx.db.message().insert(Message {
        sender: ctx.sender,
        text,
        sent: ctx.timestamp,
    });
    Ok(())
}

#[reducer(client_connected)]
pub fn connect(ctx: &ReducerContext) {
    if let Some(user) = ctx.db.player().identity().find(ctx.sender) {
        // Set online if we have already seen this user
        ctx.db.player().identity().update(Player { ..user });
    } else {
        // Create new user for this identity
        ctx.db.player().insert(Player {
            name: ctx.sender.to_string(),
            identity: ctx.sender,
            player_id: 0,
        });
    }
}

#[reducer(client_disconnected)]
pub fn disconnect(ctx: &ReducerContext) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(&ctx.sender)
        .ok_or("Player not found")?;
    let player_id = player.player_id;
    ctx.db.player().identity().delete(&ctx.sender);

    for ufo in ctx.db.ufo().player_id().filter(&player_id) {
        log::info!("Deleting UFO");
        ctx.db.entity().entity_id().delete(&ufo.entity_id);
        ctx.db.ufo().entity_id().delete(&ufo.entity_id);
    }

    Ok(())
}
