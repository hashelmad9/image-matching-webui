//! Couch Arena — a local-multiplayer split-screen arena shooter.
//!
//! Up to four players share one window, each with their own viewport. Players
//! join by pressing a button on any connected gamepad; a keyboard seat is
//! available too so the game can be exercised without hardware.

// Bevy opens its own window on Windows; without this the game would also pop
// a console behind it in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

// Bevy's query types are unavoidably deep in generics, and naming each one
// behind an alias hurts readability more than it helps.
#![allow(clippy::type_complexity)]

mod arena;
mod camera;
mod combat;
mod config;
mod hud;
mod player;

use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Couch Arena".into(),
                        resolution: (1280u32, 720u32).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(ImagePlugin::default_nearest()),
        )
        .insert_resource(ClearColor(Color::srgb(0.05, 0.06, 0.09)))
        .add_plugins((
            arena::ArenaPlugin,
            player::PlayerPlugin,
            camera::SplitScreenPlugin,
            combat::CombatPlugin,
            hud::HudPlugin,
        ))
        .run();
}
