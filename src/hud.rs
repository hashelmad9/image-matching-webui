//! Per-player heads-up display.
//!
//! Each HUD root targets one player's camera, so Bevy lays it out inside that
//! camera's viewport rather than across the whole window. A separate lobby
//! prompt covers the screen until somebody joins.

use crate::camera::{LobbyCamera, PlayerCamera};
use crate::config::*;
use crate::player::{Dead, Health, Player, Score};
use bevy::prelude::*;

/// Marks the text node belonging to one player.
#[derive(Component)]
struct HudLabel {
    player: Entity,
}

#[derive(Component)]
struct LobbyPrompt;

pub struct HudPlugin;

impl Plugin for HudPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_lobby_prompt)
            .add_systems(Update, (spawn_player_huds, update_huds, update_lobby_prompt));
    }
}

fn spawn_lobby_prompt(mut commands: Commands, lobby: Query<Entity, With<LobbyCamera>>) {
    let Some(camera) = lobby.iter().next() else {
        return;
    };
    commands.spawn((
        LobbyPrompt,
        UiTargetCamera(camera),
        Node {
            width: percent(100),
            height: percent(100),
            flex_direction: FlexDirection::Column,
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            row_gap: px(12),
            ..default()
        },
        children![
            (
                Text::new("COUCH ARENA"),
                TextFont {
                    font_size: FontSize::Px(56.0),
                    ..default()
                },
                TextColor(Color::WHITE),
            ),
            (
                Text::new("Press A or START on a controller to join"),
                TextFont {
                    font_size: FontSize::Px(24.0),
                    ..default()
                },
                TextColor(Color::srgb(0.8, 0.85, 0.95)),
            ),
            (
                Text::new("No controller? Press ENTER to play on keyboard"),
                TextFont {
                    font_size: FontSize::Px(18.0),
                    ..default()
                },
                TextColor(Color::srgb(0.55, 0.6, 0.7)),
            ),
        ],
    ));
}

fn spawn_player_huds(
    mut commands: Commands,
    cameras: Query<(Entity, &PlayerCamera), Added<PlayerCamera>>,
) {
    for (camera_entity, player_camera) in &cameras {
        commands.spawn((
            UiTargetCamera(camera_entity),
            Node {
                width: percent(100),
                height: percent(100),
                padding: UiRect::all(px(12)),
                ..default()
            },
            children![(
                HudLabel {
                    player: player_camera.player,
                },
                Text::new(""),
                TextFont {
                    font_size: FontSize::Px(20.0),
                    ..default()
                },
                TextColor(player_color(player_camera.player_index)),
            )],
        ));
    }
}

fn update_huds(
    players: Query<(&Player, &Health, &Score, Option<&Dead>)>,
    mut labels: Query<(&HudLabel, &mut Text)>,
) {
    for (label, mut text) in &mut labels {
        let Ok((player, health, score, dead)) = players.get(label.player) else {
            continue;
        };
        let status = if dead.is_some() {
            "DOWN".to_string()
        } else {
            format!("HP {}", health.current.max(0))
        };
        text.0 = format!("P{}  {}  KILLS {}", player.index + 1, status, score.0);
    }
}

fn update_lobby_prompt(
    players: Query<(), With<Player>>,
    mut prompts: Query<&mut Visibility, With<LobbyPrompt>>,
) {
    let visibility = if players.is_empty() {
        Visibility::Inherited
    } else {
        Visibility::Hidden
    };
    for mut current in &mut prompts {
        if *current != visibility {
            *current = visibility;
        }
    }
}
