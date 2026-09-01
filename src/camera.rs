//! Split-screen camera rig.
//!
//! Each player owns a third-person camera whose viewport is recomputed from
//! the *live* player count, so the screen re-partitions itself as people join
//! and drop out mid-match. A lobby camera covers the window while nobody has
//! joined yet, otherwise the first frames would render to a black screen.

use crate::config::*;
use crate::player::{Aim, Player, PLAYER_CENTER_Y};
use bevy::{camera::Viewport, prelude::*};

/// A camera bound to one player. `player_index` mirrors `Player::index` so the
/// rig can order viewports without touching the player entity.
#[derive(Component)]
pub struct PlayerCamera {
    pub player: Entity,
    pub player_index: usize,
}

/// Fallback camera, active only while there are no players.
#[derive(Component)]
pub struct LobbyCamera;

pub struct SplitScreenPlugin;

impl Plugin for SplitScreenPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_lobby_camera).add_systems(
            Update,
            (
                spawn_player_cameras,
                despawn_orphaned_cameras,
                toggle_lobby_camera,
                assign_viewports,
                follow_players,
            ),
        );
    }
}

fn spawn_lobby_camera(mut commands: Commands) {
    commands.spawn((
        Name::new("Lobby Camera"),
        LobbyCamera,
        Camera3d::default(),
        Camera {
            // Below every player camera so it never draws over a live view.
            order: -1,
            ..default()
        },
        Transform::from_xyz(0.0, 26.0, 34.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

/// Computes the camera placement that trails a player at a given facing.
fn desired_camera_transform(player_position: Vec3, yaw: f32) -> (Vec3, Vec3) {
    let rotation = Quat::from_rotation_y(yaw);
    let eye = player_position + rotation * Vec3::new(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE);
    let forward = rotation * Vec3::NEG_Z;
    let focus = player_position + forward * CAMERA_LOOK_AHEAD + Vec3::Y;
    (eye, focus)
}

fn spawn_player_cameras(
    mut commands: Commands,
    players: Query<(Entity, &Player, &Transform, &Aim), Added<Player>>,
) {
    for (entity, player, transform, aim) in &players {
        let (eye, focus) = desired_camera_transform(transform.translation, aim.yaw);
        commands.spawn((
            Name::new(format!("Camera P{}", player.index + 1)),
            PlayerCamera {
                player: entity,
                player_index: player.index,
            },
            Camera3d::default(),
            Camera {
                // Replaced with the real slot by `assign_viewports`; a distinct
                // starting order keeps cameras unambiguous in the meantime.
                order: player.index as isize,
                ..default()
            },
            Transform::from_translation(eye).looking_at(focus, Vec3::Y),
        ));
    }
}

fn despawn_orphaned_cameras(
    mut commands: Commands,
    cameras: Query<(Entity, &PlayerCamera)>,
    players: Query<(), With<Player>>,
) {
    for (entity, camera) in &cameras {
        if players.get(camera.player).is_err() {
            commands.entity(entity).despawn();
        }
    }
}

fn toggle_lobby_camera(
    players: Query<(), With<Player>>,
    mut lobby: Query<&mut Camera, With<LobbyCamera>>,
) {
    let has_players = !players.is_empty();
    for mut camera in &mut lobby {
        let should_be_active = !has_players;
        if camera.is_active != should_be_active {
            camera.is_active = should_be_active;
        }
    }
}

/// Slot layout for `count` players. Slot 0 is top-left and slots fill left to
/// right, top to bottom; with three players the fourth quadrant stays empty.
fn viewport_for(slot: usize, count: usize, window: UVec2) -> (UVec2, UVec2) {
    match count {
        0 | 1 => (UVec2::ZERO, window),
        2 => {
            let size = UVec2::new(window.x / 2, window.y);
            (UVec2::new(slot as u32 * size.x, 0), size)
        }
        _ => {
            let size = window / 2;
            let column = slot as u32 % 2;
            let row = slot as u32 / 2;
            (UVec2::new(column * size.x, row * size.y), size)
        }
    }
}

fn assign_viewports(
    windows: Query<&Window>,
    mut cameras: Query<(&PlayerCamera, &mut Camera)>,
) {
    let Some(window) = windows.iter().next() else {
        return;
    };
    let window_size = window.physical_size();
    // A minimised window reports a zero dimension, and a zero-sized viewport
    // is invalid; leave the previous layout in place until it comes back.
    if window_size.x == 0 || window_size.y == 0 {
        return;
    }

    // Order by stable player index so a given player keeps the same corner for
    // as long as the set of players is unchanged.
    let mut ordered: Vec<usize> = cameras.iter().map(|(pc, _)| pc.player_index).collect();
    ordered.sort_unstable();
    let count = ordered.len();

    for (player_camera, mut camera) in &mut cameras {
        let Some(slot) = ordered
            .iter()
            .position(|index| *index == player_camera.player_index)
        else {
            continue;
        };
        let (position, size) = viewport_for(slot, count, window_size);
        if size.x == 0 || size.y == 0 {
            continue;
        }

        let order = slot as isize;
        if camera.order != order {
            camera.order = order;
        }

        // Only write when it actually changed, to avoid marking the camera
        // dirty for the renderer on every single frame.
        let unchanged = camera.viewport.as_ref().is_some_and(|viewport| {
            viewport.physical_position == position && viewport.physical_size == size
        });
        if !unchanged {
            camera.viewport = Some(Viewport {
                physical_position: position,
                physical_size: size,
                ..default()
            });
        }
    }
}

fn follow_players(
    time: Res<Time>,
    players: Query<(&Transform, &Aim), With<Player>>,
    mut cameras: Query<(&PlayerCamera, &mut Transform), Without<Player>>,
) {
    let dt = time.delta_secs();
    if dt <= 0.0 {
        return;
    }
    // Framerate-independent exponential smoothing.
    let t = 1.0 - (-CAMERA_FOLLOW_RATE * dt).exp();

    for (player_camera, mut camera_transform) in &mut cameras {
        let Ok((player_transform, aim)) = players.get(player_camera.player) else {
            continue;
        };
        let mut anchor = player_transform.translation;
        anchor.y = PLAYER_CENTER_Y;

        let (eye, focus) = desired_camera_transform(anchor, aim.yaw);
        camera_transform.translation = camera_transform.translation.lerp(eye, t);
        // Re-aiming from the smoothed position each frame gives a stable look
        // without having to interpolate rotations separately.
        camera_transform.look_at(focus, Vec3::Y);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every slot must stay inside the window, whatever the player count.
    fn assert_within_window(slots: &[(UVec2, UVec2)], window: UVec2) {
        for (position, size) in slots {
            assert!(position.x + size.x <= window.x, "slot overflows width");
            assert!(position.y + size.y <= window.y, "slot overflows height");
            assert!(size.x > 0 && size.y > 0, "slot must be non-empty");
        }
    }

    /// No two players may be handed overlapping pixels.
    fn assert_disjoint(slots: &[(UVec2, UVec2)]) {
        for (i, (pos_a, size_a)) in slots.iter().enumerate() {
            for (pos_b, size_b) in slots.iter().skip(i + 1) {
                let separated_x =
                    pos_a.x + size_a.x <= pos_b.x || pos_b.x + size_b.x <= pos_a.x;
                let separated_y =
                    pos_a.y + size_a.y <= pos_b.y || pos_b.y + size_b.y <= pos_a.y;
                assert!(separated_x || separated_y, "viewports overlap");
            }
        }
    }

    #[test]
    fn single_player_fills_the_window() {
        let window = UVec2::new(1280, 720);
        assert_eq!(viewport_for(0, 1, window), (UVec2::ZERO, window));
    }

    #[test]
    fn layouts_are_disjoint_and_inside_the_window() {
        let window = UVec2::new(1280, 720);
        for count in 1..=MAX_PLAYERS {
            let slots: Vec<_> = (0..count).map(|s| viewport_for(s, count, window)).collect();
            assert_within_window(&slots, window);
            assert_disjoint(&slots);
        }
    }

    #[test]
    fn two_players_split_left_and_right() {
        let window = UVec2::new(1280, 720);
        assert_eq!(
            viewport_for(0, 2, window),
            (UVec2::ZERO, UVec2::new(640, 720))
        );
        assert_eq!(
            viewport_for(1, 2, window),
            (UVec2::new(640, 0), UVec2::new(640, 720))
        );
    }

    #[test]
    fn four_players_take_a_quadrant_each() {
        let window = UVec2::new(1280, 720);
        let quarter = UVec2::new(640, 360);
        assert_eq!(viewport_for(0, 4, window), (UVec2::ZERO, quarter));
        assert_eq!(viewport_for(3, 4, window), (UVec2::new(640, 360), quarter));
    }

    /// Odd window sizes round down, which may leave a one-pixel seam, but must
    /// never produce an out-of-bounds or overlapping viewport.
    #[test]
    fn odd_window_sizes_stay_valid() {
        let window = UVec2::new(1281, 721);
        for count in 1..=MAX_PLAYERS {
            let slots: Vec<_> = (0..count).map(|s| viewport_for(s, count, window)).collect();
            assert_within_window(&slots, window);
            assert_disjoint(&slots);
        }
    }

    #[test]
    fn camera_sits_behind_and_above_the_player() {
        // Facing yaw 0 means looking down -Z, so the camera belongs at +Z.
        let (eye, focus) = desired_camera_transform(Vec3::ZERO, 0.0);
        assert!(eye.z > 0.0, "camera should trail the player");
        assert!(eye.y > 0.0, "camera should sit above the player");
        assert!(focus.z < 0.0, "camera should look ahead of the player");
    }
}
