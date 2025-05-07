use crate::util::constants::{START_PLAYER_MASS, START_PLAYER_SPEED};
use crate::util::math::DbVector2;

pub fn mass_to_max_move_speed(mass: u32) -> f32 {
    2.0 * START_PLAYER_SPEED as f32 / (1.0 + (mass as f32 / START_PLAYER_MASS as f32).sqrt())
}

pub fn is_cow_in_beam(cow_pos: DbVector2, ufo_pos: DbVector2) -> bool {
    let x_low = ufo_pos.x * 0.9;
    let x_high = ufo_pos.x * 1.1;
    let z_low = ufo_pos.y * 0.9;
    let z_high = ufo_pos.y * 1.1;

    let is_close_x = x_low <= cow_pos.x && cow_pos.x <= x_high;
    let is_close_z = z_low <= cow_pos.y && cow_pos.y <= z_high;

    is_close_x && is_close_z
}
