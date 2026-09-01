//! Player lifecycle and locomotion.
//!
//! Players join by pressing a button on an unclaimed gamepad, so controllers
//! can come and go mid-match without restarting. A keyboard source is offered
//! as well, which makes the game testable on a machine with no pads attached.

use crate::arena::Obstacle;
use crate::config::*;
use bevy::prelude::*;
use std::f32::consts::{PI, TAU};

/// Height of the capsule's centre above the floor, so it rests on the ground.
pub const PLAYER_CENTER_Y: f32 = PLAYER_RADIUS + PLAYER_BODY_LENGTH * 0.5;

/// Where a player's controls come from. Keyboard is always available as a
/// single extra seat; every other seat is a physical gamepad entity.
#[derive(Component, Clone, Copy, PartialEq, Eq, Debug)]
pub enum InputSource {
    Gamepad(Entity),
    Keyboard,
}

/// A joined player. `index` is stable identity (colour, spawn point) and is
/// deliberately *not* the split-screen slot — see `camera::assign_viewports`.
#[derive(Component)]
pub struct Player {
    pub index: usize,
}

#[derive(Component)]
pub struct Health {
    pub current: i32,
    pub max: i32,
}

#[derive(Component, Default)]
pub struct Score(pub u32);

/// Facing angle in radians about +Y, smoothed toward the aim stick.
#[derive(Component, Default)]
pub struct Aim {
    pub yaw: f32,
}

#[derive(Component)]
pub struct FireCooldown(pub Timer);

/// Present only while a player is down and waiting to respawn.
#[derive(Component)]
pub struct Dead(pub Timer);

/// Occupied seats. Position in the vector is the player index, so a player
/// who leaves frees their colour and spawn point for the next joiner.
#[derive(Resource)]
pub struct Roster {
    pub seats: [Option<InputSource>; MAX_PLAYERS],
}

impl Default for Roster {
    fn default() -> Self {
        Self {
            seats: [None; MAX_PLAYERS],
        }
    }
}

impl Roster {
    pub fn is_taken(&self, source: InputSource) -> bool {
        self.seats.contains(&Some(source))
    }

    fn claim(&mut self, source: InputSource) -> Option<usize> {
        let seat = self.seats.iter().position(|s| s.is_none())?;
        self.seats[seat] = Some(source);
        Some(seat)
    }

    fn release(&mut self, index: usize) {
        if let Some(slot) = self.seats.get_mut(index) {
            *slot = None;
        }
    }
}

/// One frame of control input, normalised across gamepad and keyboard.
#[derive(Default, Clone, Copy)]
pub struct PlayerInput {
    pub move_axis: Vec2,
    pub aim_axis: Vec2,
    pub firing: bool,
}

pub struct PlayerPlugin;

impl Plugin for PlayerPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Roster>().add_systems(
            Update,
            (
                join_players,
                drop_disconnected_players,
                move_players,
                respawn_players,
            ),
        );
    }
}

/// Rescales a stick vector so the deadzone does not produce a jump from 0 to
/// `STICK_DEADZONE` the moment the stick starts registering.
fn apply_deadzone(raw: Vec2) -> Vec2 {
    let len = raw.length();
    if len < STICK_DEADZONE {
        return Vec2::ZERO;
    }
    let scaled = ((len - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)).clamp(0.0, 1.0);
    raw / len * scaled
}

/// Reads the current frame's input for one source. Returns zeroed input if a
/// gamepad has vanished, which keeps callers from having to special-case it.
pub fn read_input(
    source: InputSource,
    gamepads: &Query<&Gamepad>,
    keys: &ButtonInput<KeyCode>,
) -> PlayerInput {
    match source {
        InputSource::Gamepad(entity) => {
            let Ok(pad) = gamepads.get(entity) else {
                return PlayerInput::default();
            };
            let trigger = pad.get(GamepadButton::RightTrigger2).unwrap_or(0.0);
            PlayerInput {
                move_axis: apply_deadzone(pad.left_stick()),
                aim_axis: apply_deadzone(pad.right_stick()),
                firing: trigger > TRIGGER_THRESHOLD
                    || pad.pressed(GamepadButton::RightTrigger)
                    || pad.pressed(GamepadButton::South),
            }
        }
        InputSource::Keyboard => {
            let axis = |neg: KeyCode, pos: KeyCode| -> f32 {
                (keys.pressed(pos) as i32 - keys.pressed(neg) as i32) as f32
            };
            PlayerInput {
                move_axis: apply_deadzone(Vec2::new(
                    axis(KeyCode::KeyA, KeyCode::KeyD),
                    axis(KeyCode::KeyS, KeyCode::KeyW),
                )),
                aim_axis: apply_deadzone(Vec2::new(
                    axis(KeyCode::ArrowLeft, KeyCode::ArrowRight),
                    axis(KeyCode::ArrowDown, KeyCode::ArrowUp),
                )),
                firing: keys.pressed(KeyCode::Space),
            }
        }
    }
}

/// Converts a stick direction into a yaw about +Y.
///
/// A zero-yaw transform faces -Z, and rotating by `yaw` maps that to
/// `(-sin yaw, 0, -cos yaw)`. Pushing the stick up should mean "away from the
/// camera", i.e. -Z, so the desired forward is `(stick.x, 0, -stick.y)`.
fn yaw_from_stick(stick: Vec2) -> f32 {
    f32::atan2(-stick.x, stick.y)
}

/// Shortest-path interpolation between two angles, respecting wraparound.
fn lerp_angle(from: f32, to: f32, t: f32) -> f32 {
    let delta = (to - from + PI).rem_euclid(TAU) - PI;
    from + delta * t
}

fn join_players(
    mut commands: Commands,
    mut roster: ResMut<Roster>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    gamepads: Query<(Entity, &Gamepad)>,
    keys: Res<ButtonInput<KeyCode>>,
) {
    let mut wants_to_join: Vec<InputSource> = Vec::new();

    for (entity, pad) in &gamepads {
        let source = InputSource::Gamepad(entity);
        if roster.is_taken(source) {
            continue;
        }
        if pad.just_pressed(GamepadButton::South) || pad.just_pressed(GamepadButton::Start) {
            wants_to_join.push(source);
        }
    }

    if !roster.is_taken(InputSource::Keyboard) && keys.just_pressed(KeyCode::Enter) {
        wants_to_join.push(InputSource::Keyboard);
    }

    for source in wants_to_join {
        let Some(index) = roster.claim(source) else {
            // All seats full; ignore further join presses.
            break;
        };
        spawn_player(
            &mut commands,
            &mut meshes,
            &mut materials,
            index,
            source,
        );
        info!("player {} joined via {:?}", index + 1, source);
    }
}

fn spawn_player(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    index: usize,
    source: InputSource,
) {
    let colour = player_color(index);
    let spawn = spawn_point(index) + Vec3::Y * PLAYER_CENTER_Y;

    commands.spawn((
        Name::new(format!("Player {}", index + 1)),
        Player { index },
        source,
        Health {
            current: PLAYER_MAX_HEALTH,
            max: PLAYER_MAX_HEALTH,
        },
        Score::default(),
        Aim {
            // Face the arena centre on spawn rather than an arbitrary axis.
            yaw: yaw_from_stick(Vec2::new(-spawn.x, spawn.z).normalize_or_zero()),
        },
        FireCooldown(Timer::from_seconds(FIRE_COOLDOWN, TimerMode::Once)),
        Mesh3d(meshes.add(Capsule3d::new(PLAYER_RADIUS, PLAYER_BODY_LENGTH))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: colour,
            perceptual_roughness: 0.6,
            ..default()
        })),
        Transform::from_translation(spawn),
    ));
}

/// Frees the seat of any player whose gamepad was unplugged.
fn drop_disconnected_players(
    mut commands: Commands,
    mut roster: ResMut<Roster>,
    gamepads: Query<(), With<Gamepad>>,
    players: Query<(Entity, &Player, &InputSource)>,
) {
    for (entity, player, source) in &players {
        if let InputSource::Gamepad(pad) = source
            && gamepads.get(*pad).is_err()
        {
            info!("player {} disconnected", player.index + 1);
            roster.release(player.index);
            commands.entity(entity).despawn();
        }
    }
}

fn move_players(
    time: Res<Time>,
    gamepads: Query<&Gamepad>,
    keys: Res<ButtonInput<KeyCode>>,
    obstacles: Query<(&Transform, &Obstacle), Without<Player>>,
    mut players: Query<(&InputSource, &mut Transform, &mut Aim), (With<Player>, Without<Dead>)>,
) {
    let dt = time.delta_secs();
    if dt <= 0.0 {
        return;
    }

    for (source, mut transform, mut aim) in &mut players {
        let input = read_input(*source, &gamepads, &keys);

        // Aim stick wins; otherwise face the direction of travel so the player
        // is never left facing backwards while running.
        let target_yaw = if input.aim_axis != Vec2::ZERO {
            Some(yaw_from_stick(input.aim_axis))
        } else if input.move_axis != Vec2::ZERO {
            Some(yaw_from_stick(input.move_axis))
        } else {
            None
        };
        if let Some(target) = target_yaw {
            // Framerate-independent smoothing: the fraction of the remaining
            // angle covered this frame approaches 1 as dt grows.
            let t = 1.0 - (-PLAYER_TURN_RATE * dt).exp();
            aim.yaw = lerp_angle(aim.yaw, target, t);
        }
        transform.rotation = Quat::from_rotation_y(aim.yaw);

        if input.move_axis == Vec2::ZERO {
            continue;
        }
        // Movement is camera-relative, and the camera shares the player's yaw.
        let direction =
            Quat::from_rotation_y(aim.yaw) * Vec3::new(input.move_axis.x, 0.0, -input.move_axis.y);
        let mut position = transform.translation + direction * PLAYER_SPEED * dt;

        for (obstacle_transform, obstacle) in &obstacles {
            position = push_out_of_box(
                position,
                PLAYER_RADIUS,
                obstacle_transform.translation,
                obstacle.half_extents,
            );
        }

        let limit = ARENA_HALF_EXTENT - PLAYER_RADIUS;
        position.x = position.x.clamp(-limit, limit);
        position.z = position.z.clamp(-limit, limit);
        position.y = PLAYER_CENTER_Y;
        transform.translation = position;
    }
}

/// Resolves a vertical circle (the player) against an axis-aligned box, in the
/// XZ plane only — nothing in the game leaves the ground plane.
fn push_out_of_box(position: Vec3, radius: f32, box_centre: Vec3, half: Vec3) -> Vec3 {
    let min_x = box_centre.x - half.x;
    let max_x = box_centre.x + half.x;
    let min_z = box_centre.z - half.z;
    let max_z = box_centre.z + half.z;

    let closest_x = position.x.clamp(min_x, max_x);
    let closest_z = position.z.clamp(min_z, max_z);
    let offset_x = position.x - closest_x;
    let offset_z = position.z - closest_z;
    let distance_sq = offset_x * offset_x + offset_z * offset_z;

    if distance_sq >= radius * radius {
        return position;
    }

    if distance_sq > 1e-6 {
        let distance = distance_sq.sqrt();
        let push = radius - distance;
        return Vec3::new(
            position.x + offset_x / distance * push,
            position.y,
            position.z + offset_z / distance * push,
        );
    }

    // Dead centre inside the box: eject along whichever face is nearest.
    let out_min_x = position.x - min_x;
    let out_max_x = max_x - position.x;
    let out_min_z = position.z - min_z;
    let out_max_z = max_z - position.z;
    let nearest = out_min_x.min(out_max_x).min(out_min_z).min(out_max_z);

    if nearest == out_min_x {
        Vec3::new(min_x - radius, position.y, position.z)
    } else if nearest == out_max_x {
        Vec3::new(max_x + radius, position.y, position.z)
    } else if nearest == out_min_z {
        Vec3::new(position.x, position.y, min_z - radius)
    } else {
        Vec3::new(position.x, position.y, max_z + radius)
    }
}

fn respawn_players(
    mut commands: Commands,
    time: Res<Time>,
    mut players: Query<(
        Entity,
        &Player,
        &mut Dead,
        &mut Health,
        &mut Transform,
        &mut Visibility,
    )>,
) {
    for (entity, player, mut dead, mut health, mut transform, mut visibility) in &mut players {
        if !dead.0.tick(time.delta()).just_finished() {
            continue;
        }
        health.current = health.max;
        transform.translation = spawn_point(player.index) + Vec3::Y * PLAYER_CENTER_Y;
        *visibility = Visibility::Inherited;
        commands.entity(entity).remove::<Dead>();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The direction a player faces at a given yaw, matching how Bevy applies
    /// `Quat::from_rotation_y` to the default -Z forward axis.
    fn forward_at(yaw: f32) -> Vec3 {
        Quat::from_rotation_y(yaw) * Vec3::NEG_Z
    }

    #[test]
    fn stick_up_faces_away_from_the_camera() {
        let forward = forward_at(yaw_from_stick(Vec2::new(0.0, 1.0)));
        assert!((forward - Vec3::NEG_Z).length() < 1e-5, "got {forward:?}");
    }

    #[test]
    fn stick_right_faces_positive_x() {
        let forward = forward_at(yaw_from_stick(Vec2::new(1.0, 0.0)));
        assert!((forward - Vec3::X).length() < 1e-5, "got {forward:?}");
    }

    #[test]
    fn stick_down_faces_positive_z() {
        let forward = forward_at(yaw_from_stick(Vec2::new(0.0, -1.0)));
        assert!((forward - Vec3::Z).length() < 1e-5, "got {forward:?}");
    }

    #[test]
    fn deadzone_suppresses_stick_drift_but_keeps_full_range() {
        assert_eq!(apply_deadzone(Vec2::new(0.05, 0.0)), Vec2::ZERO);
        // A fully deflected stick must still reach magnitude 1.
        let full = apply_deadzone(Vec2::new(1.0, 0.0));
        assert!((full.length() - 1.0).abs() < 1e-5, "got {full:?}");
    }

    #[test]
    fn deadzone_output_is_continuous_at_the_threshold() {
        let just_inside = apply_deadzone(Vec2::new(STICK_DEADZONE + 1e-4, 0.0));
        assert!(just_inside.length() < 1e-3, "expected a smooth ramp from zero");
    }

    #[test]
    fn angle_lerp_takes_the_short_way_around() {
        // From just below +PI to just above -PI is a short hop across the seam,
        // not a near-full turn the other way.
        let from = 3.0;
        let to = -3.0;
        let stepped = lerp_angle(from, to, 0.5);
        let delta = (stepped - from).abs();
        assert!(delta < 0.3, "wrapped the long way: {stepped}");
    }

    #[test]
    fn angle_lerp_is_a_no_op_at_zero_and_exact_at_one() {
        assert!((lerp_angle(0.5, 1.5, 0.0) - 0.5).abs() < 1e-6);
        assert!((lerp_angle(0.5, 1.5, 1.0) - 1.5).abs() < 1e-6);
    }

    #[test]
    fn approaching_a_box_stops_at_its_surface() {
        let half = Vec3::new(1.0, 1.0, 1.0);
        // Overlapping the +X face by 0.2.
        let position = Vec3::new(1.0 + PLAYER_RADIUS - 0.2, PLAYER_CENTER_Y, 0.0);
        let resolved = push_out_of_box(position, PLAYER_RADIUS, Vec3::ZERO, half);
        assert!(
            (resolved.x - (1.0 + PLAYER_RADIUS)).abs() < 1e-5,
            "expected to rest on the face, got {resolved:?}"
        );
        assert_eq!(resolved.z, position.z, "should not slide along the face");
    }

    #[test]
    fn clear_of_a_box_is_left_untouched() {
        let half = Vec3::new(1.0, 1.0, 1.0);
        let position = Vec3::new(5.0, PLAYER_CENTER_Y, 5.0);
        assert_eq!(
            push_out_of_box(position, PLAYER_RADIUS, Vec3::ZERO, half),
            position
        );
    }

    #[test]
    fn a_player_stuck_inside_a_box_is_ejected() {
        let half = Vec3::new(1.0, 1.0, 2.0);
        // Dead centre: the nearest face is on X, since the box is deeper in Z.
        let resolved = push_out_of_box(
            Vec3::new(0.0, PLAYER_CENTER_Y, 0.0),
            PLAYER_RADIUS,
            Vec3::ZERO,
            half,
        );
        assert!(
            resolved.x.abs() >= 1.0,
            "should be pushed clear on X, got {resolved:?}"
        );
    }

    #[test]
    fn every_spawn_point_is_inside_the_arena_and_distinct() {
        let limit = ARENA_HALF_EXTENT - PLAYER_RADIUS;
        let points: Vec<Vec3> = (0..MAX_PLAYERS).map(spawn_point).collect();
        for point in &points {
            assert!(point.x.abs() <= limit && point.z.abs() <= limit);
        }
        for (i, a) in points.iter().enumerate() {
            for b in points.iter().skip(i + 1) {
                assert!(a.distance(*b) > PLAYER_RADIUS * 4.0, "spawns too close");
            }
        }
    }

    #[test]
    fn a_seat_freed_by_a_leaver_is_reused() {
        let mut roster = Roster::default();
        let first = roster.claim(InputSource::Keyboard).unwrap();
        roster.release(first);
        let reclaimed = roster.claim(InputSource::Gamepad(Entity::from_raw(7))).unwrap();
        assert_eq!(first, reclaimed, "the freed seat should be handed out again");
    }

    #[test]
    fn the_roster_refuses_more_than_max_players() {
        let mut roster = Roster::default();
        for slot in 0..MAX_PLAYERS {
            assert_eq!(
                roster.claim(InputSource::Gamepad(Entity::from_raw(slot as u32))),
                Some(slot)
            );
        }
        assert_eq!(roster.claim(InputSource::Keyboard), None);
    }
}
