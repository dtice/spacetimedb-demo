use spacetimedb::{reducer, table, Identity, ReducerContext};
use crate::{
    entity::ufo::ufo,
    util::math::{DbVector2, DbVector3}
};
use crate::entity::cow::cow;

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

// Reducers
#[reducer]
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

#[reducer]
pub fn update_player_beam(ctx: &ReducerContext, beam_on: bool) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(&ctx.sender)
        .ok_or("Player not found")?;
    for mut ufo in ctx.db.ufo().player_id().filter(&player.player_id) {
        ufo.beam_on = beam_on;
        if !ufo.beam_on {
            if let Some(entity) = ufo.abducted_entity {
                if let Some(mut cow) = ctx.db.cow().entity_id().find(entity.entity_id) {
                    cow.is_being_abducted = false;
                    cow.abducted_by = None;
                    ctx.db.cow().entity_id().update(cow);
                }
            }
            ufo.abducted_entity = None;
        }
        ctx.db.ufo().entity_id().update(ufo);
    }
    Ok(())
}

pub fn update_player_abducting(ctx: &ReducerContext, abducting: bool) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(&ctx.sender)
        .ok_or("Player not found")?;
    for mut ufo in ctx.db.ufo().player_id().filter(&player.player_id) {
        ufo.abducting = abducting;
        ctx.db.ufo().entity_id().update(ufo);
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

pub fn validate_name(name: String) -> Result<String, String> {
    if name.is_empty() {
        Err("Names must not be empty".to_string())
    } else {
        Ok(name)
    }
}

pub fn validate_message(text: String) -> Result<String, String> {
    if text.is_empty() {
        Err("Messages must not be empty".to_string())
    } else {
        Ok(text)
    }
}