//! All gameplay tuning lives here so balance changes never require hunting
//! through systems. Every value is used by exactly one subsystem, noted below.

use bevy::prelude::*;

/// Hard cap on local players. Bumping this also needs a viewport layout in
/// `camera::viewport_for` — see the match on `count` there.
pub const MAX_PLAYERS: usize = 4;

// --- arena ---------------------------------------------------------------
/// Floor spans [-ARENA_HALF_EXTENT, +ARENA_HALF_EXTENT] on X and Z.
pub const ARENA_HALF_EXTENT: f32 = 24.0;
pub const WALL_HEIGHT: f32 = 3.0;
pub const WALL_THICKNESS: f32 = 1.0;

// --- player --------------------------------------------------------------
pub const PLAYER_RADIUS: f32 = 0.5;
/// Length of the capsule's cylindrical section, excluding the two hemispheres.
pub const PLAYER_BODY_LENGTH: f32 = 1.0;
pub const PLAYER_SPEED: f32 = 9.0;
/// Higher turns the player toward the aim stick faster. Units: 1/seconds.
pub const PLAYER_TURN_RATE: f32 = 14.0;
pub const STICK_DEADZONE: f32 = 0.22;
pub const PLAYER_MAX_HEALTH: i32 = 100;
pub const RESPAWN_SECONDS: f32 = 2.5;

// --- combat --------------------------------------------------------------
pub const FIRE_COOLDOWN: f32 = 0.16;
/// Analog trigger pull past this counts as firing.
pub const TRIGGER_THRESHOLD: f32 = 0.3;
pub const PROJECTILE_SPEED: f32 = 42.0;
pub const PROJECTILE_RADIUS: f32 = 0.18;
pub const PROJECTILE_LIFETIME: f32 = 1.6;
pub const PROJECTILE_DAMAGE: i32 = 12;
/// Spawn offset ahead of the muzzle so shots never collide with the shooter.
pub const MUZZLE_FORWARD: f32 = 1.0;
pub const MUZZLE_HEIGHT: f32 = 0.9;

// --- camera --------------------------------------------------------------
pub const CAMERA_DISTANCE: f32 = 11.0;
pub const CAMERA_HEIGHT: f32 = 7.5;
/// How far ahead of the player the camera aims, in metres.
pub const CAMERA_LOOK_AHEAD: f32 = 3.0;
/// Higher snaps the camera to the player faster. Units: 1/seconds.
pub const CAMERA_FOLLOW_RATE: f32 = 9.0;

/// Stable per-player identity colour, shared by the capsule, its projectiles
/// and its HUD so a glance at any of the three tells you whose it is.
pub fn player_color(index: usize) -> Color {
    match index % MAX_PLAYERS {
        0 => Color::srgb(0.95, 0.30, 0.32),
        1 => Color::srgb(0.30, 0.58, 0.95),
        2 => Color::srgb(0.35, 0.85, 0.42),
        _ => Color::srgb(0.96, 0.78, 0.25),
    }
}

/// Evenly spaced spawn points around the arena, so no two players start on
/// top of each other regardless of join order.
pub fn spawn_point(index: usize) -> Vec3 {
    let inset = ARENA_HALF_EXTENT * 0.6;
    match index % MAX_PLAYERS {
        0 => Vec3::new(-inset, 0.0, -inset),
        1 => Vec3::new(inset, 0.0, inset),
        2 => Vec3::new(inset, 0.0, -inset),
        _ => Vec3::new(-inset, 0.0, inset),
    }
}
