use std::time::Duration;

use spacetimedb::{rand::Rng, reducer, ReducerContext, ScheduleAt, Table, Timestamp};

use crate::{
    entities::{
        config, cow, entity, logged_out_player, message, player, spawn_cow_timer, ufo, Config, Cow,
        DbVector3, Entity, Message, Player, SpawnCowTimer, Ufo,
    },
    util::{mass_to_cow_size, validate_message, validate_name},
};

const COW_MASS_MIN: u32 = 2;
const COW_MASS_MAX: u32 = 4;
const TARGET_COW_COUNT: usize = 100;

#[reducer(init)]
pub fn init(ctx: &ReducerContext) -> Result<(), String> {
    log::info!("Initializing...");
    ctx.db.config().try_insert(Config {
        id: 0,
        world_size: 1000,
    })?;
    ctx.db.spawn_cow_timer().try_insert(SpawnCowTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(500).into()),
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
    let y = rng.gen_range(0.0..world_size as f32);
    let z: f32 = 0.0;
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
            y: 1.0,
            z: 0.0,
        },
        speed: 0.0,
        last_split_time: timestamp,
    })?;

    Ok(entity)
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
        let y = rng.gen_range(cow_size..world_size as f32 - cow_size);
        let z: f32 = 0.0;
        let entity = ctx.db.entity().try_insert(Entity {
            entity_id: 0,
            position: DbVector3 { x, y, z },
            mass: cow_mass,
        })?;

        ctx.db.cow().try_insert(Cow {
            entity_id: entity.entity_id,
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
    ctx.db.logged_out_player().insert(player);
    ctx.db.player().identity().delete(&ctx.sender);

    for player in ctx.db.ufo().player_id().filter(&player_id) {
        ctx.db.entity().entity_id().delete(&player.entity_id);
        ctx.db.ufo().entity_id().delete(&player.entity_id);
    }

    Ok(())
}
