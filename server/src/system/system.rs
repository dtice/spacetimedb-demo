use spacetimedb::rand::Rng;
use spacetimedb::Identity;
use spacetimedb::{reducer, ReducerContext, ScheduleAt, Table};
use spacetimedb::{table, Timestamp};
use std::time::Duration;

use crate::entity::cow::cow;
use crate::entity::ufo::mass_to_ufo_size;
use crate::util::constants::{START_PLAYER_HEIGHT, WORLD_SIZE};
use crate::util::math::DbVector2;
use crate::util::util::is_cow_in_beam;
use crate::{
    entity::cow::{
        change_cow_direction_timer, move_all_cows_timer, spawn_cows_timer, ChangeCowDirectionTimer,
        MoveAllCowsTimer, SpawnCowsTimer,
    },
    entity::entity::{entity, Entity},
    entity::ufo::{ufo, Ufo},
    system::player::{player, validate_message, validate_name, Player},
    util::math::DbVector3,
    util::util::mass_to_max_move_speed,
};

#[table(name = config, public)]
pub struct Config {
    #[primary_key]
    pub id: u32,
    pub world_size: u64,
}

#[table(name = message, public)]
pub struct Message {
    pub sender: Identity,
    pub sent: Timestamp,
    pub text: String,
}

// Timers
#[table(name = process_game_timer, scheduled(process_game))]
pub struct ProcessGameTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

// Reducers
#[reducer(init)]
pub fn init(ctx: &ReducerContext) -> Result<(), String> {
    log::info!("Initializing...");
    ctx.db.config().try_insert(Config {
        id: 0,
        world_size: WORLD_SIZE,
    })?;
    ctx.db.spawn_cows_timer().try_insert(SpawnCowsTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(500).into()),
    })?;
    ctx.db.process_game_timer().try_insert(ProcessGameTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(50).into()),
    })?;
    ctx.db
        .change_cow_direction_timer()
        .try_insert(ChangeCowDirectionTimer {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(Duration::from_millis(1000).into()),
        })?;
    ctx.db.move_all_cows_timer().try_insert(MoveAllCowsTimer {
        scheduled_id: 0,
        scheduled_at: ScheduleAt::Interval(Duration::from_millis(50).into()),
    })?;

    Ok(())
}

#[reducer]
pub fn process_game(
    ctx: &ReducerContext,
    _process_game_timer: ProcessGameTimer,
) -> Result<(), String> {
    move_all_players(ctx).expect("TODO: panic message");
    check_all_beams(ctx).expect("TODO: panic message");
    process_abductions(ctx).expect("TODO: panic message");
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
    let y: f32 = START_PLAYER_HEIGHT;
    let z = rng.gen_range(0.0..world_size as f32);
    spawn_player_at(ctx, player_id, 1, DbVector3 { x, y, z }, ctx.timestamp)?;
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
        beam_on: false,
        abducting: false,
        abducted_entity: None,
    })?;

    Ok(entity)
}

#[reducer]
fn move_all_players(ctx: &ReducerContext) -> Result<(), String> {
    let world_size = ctx
        .db
        .config()
        .id()
        .find(0)
        .ok_or("Config not found")?
        .world_size;

    // Handle player input
    for ufo in ctx.db.ufo().iter() {
        // If a UFO is abducting an enemy, can't move
        if ufo.beam_on && ufo.abducting {
            continue;
        }

        let ufo_entity = ctx.db.entity().entity_id().find(&ufo.entity_id);
        // This can happen if a circle is eaten by another circle
        if !ufo_entity.is_some() {
            continue;
        }

        let mut ufo_entity = ufo_entity.unwrap();
        let ufo_size = mass_to_ufo_size(ufo_entity.mass);
        let direction = ufo.direction * ufo.speed / 60.0;
        let new_pos = ufo_entity.position + direction * mass_to_max_move_speed(ufo_entity.mass);
        let min = ufo_size;
        let max = world_size as f32 - ufo_size;
        ufo_entity.position.x = new_pos.x.clamp(min, max);
        ufo_entity.position.z = new_pos.z.clamp(min, max);
        ctx.db.entity().entity_id().update(ufo_entity);
    }

    Ok(())
}

#[reducer]
fn check_all_beams(ctx: &ReducerContext) -> Result<(), String> {
    for mut ufo in ctx.db.ufo().iter() {
        match ctx.db.entity().entity_id().find(&ufo.entity_id) {
            None => {}
            Some(ufo_entity) => {
                if ufo.beam_on {
                    for mut cow in ctx.db.cow().iter() {
                        // If a cow is directly below ufo, it gets abducted
                        match ctx.db.entity().entity_id().find(&cow.entity_id) {
                            None => {}
                            Some(mut cow_entity) => {
                                let cow_pos = DbVector2 {
                                    x: cow_entity.position.x,
                                    y: cow_entity.position.z,
                                };
                                let ufo_pos = DbVector2 {
                                    x: ufo_entity.position.x,
                                    y: ufo_entity.position.z,
                                };
                                if is_cow_in_beam(cow_pos, ufo_pos) {
                                    cow_entity.position.x = ufo_pos.x;
                                    cow_entity.position.z = ufo_pos.y;
                                    let new_cow_entity = cow_entity.clone();
                                    cow.is_being_abducted = true;
                                    cow.abducted_by =
                                        ctx.db.entity().entity_id().find(&ufo.entity_id);
                                    ctx.db.cow().entity_id().update(cow);
                                    ctx.db.entity().entity_id().update(new_cow_entity);
                                    ufo.abducted_entity = Option::from(cow_entity);
                                }
                            }
                        }
                    }
                    ctx.db.ufo().entity_id().update(ufo);
                } else {
                    // Release all cows this player is holding
                    for cow in ctx.db.cow().iter() {
                        let mut new_cow = cow;
                        match new_cow.abducted_by {
                            None => {}
                            Some(it) => {
                                if it.entity_id == ufo_entity.entity_id {
                                    new_cow.is_being_abducted = false;
                                    new_cow.abducted_by = None;
                                    match ctx.db.entity().entity_id().find(&new_cow.entity_id) {
                                        None => {}
                                        Some(mut new_entity) => {
                                            new_entity.position.y = 0.125f32;
                                            ctx.db.entity().entity_id().update(new_entity);
                                        }
                                    }
                                    ctx.db.cow().entity_id().update(new_cow);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

#[reducer]
fn process_abductions(ctx: &ReducerContext) -> Result<(), String> {
    for cow in ctx.db.cow().iter() {
        if cow.is_being_abducted && cow.abducted_by.is_some() {
            match ctx.db.entity().entity_id().find(&cow.entity_id) {
                None => {}
                Some(mut cow_entity) => {
                    match cow.abducted_by {
                        None => {
                            cow_entity.position.y = 0.125f32;
                        }
                        Some(ref ufo) => {
                            log::info!(
                                "Cow is being abducted by UFO, height = {}",
                                cow_entity.position.y
                            );
                            if cow_entity.position.y >= ufo.position.y {
                                // Update ufo and ufo entity
                                let mut ufo =
                                    ctx.db.ufo().entity_id().find(&ufo.entity_id).unwrap();
                                ufo.abducting = false;
                                let mut ufo_entity = ctx
                                    .db
                                    .entity()
                                    .entity_id()
                                    .find(&ufo.entity_id)
                                    .ok_or("UFO entity not found")?;

                                // Add mass to ufo
                                ufo_entity.mass += cow_entity.mass;

                                // Update UFO and UFO entity
                                ctx.db.ufo().entity_id().update(ufo);
                                ctx.db.entity().entity_id().update(ufo_entity);

                                // Delete cow and cow entity
                                ctx.db.cow().delete(cow);
                                ctx.db.entity().entity_id().delete(&cow_entity.entity_id);

                                continue;
                            }
                            cow_entity.position = DbVector3 {
                                x: ufo.position.x,
                                y: cow_entity.position.y + 0.02,
                                z: ufo.position.z,
                            };
                            ctx.db.entity().entity_id().update(cow_entity);
                        }
                    };
                }
            }
        }
    }
    Ok(())
}
