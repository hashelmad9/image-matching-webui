//! Shooting, projectile flight and scoring.
//!
//! Movement, expiry and both kinds of collision are resolved in a single
//! system, `update_projectiles`. Splitting them would let two systems queue a
//! despawn for the same projectile in one frame, which Bevy warns about.

use crate::arena::Obstacle;
use crate::config::*;
use crate::player::{read_input, Dead, FireCooldown, Health, InputSource, Player, Score};
use bevy::prelude::*;

#[derive(Component)]
pub struct Projectile {
    pub owner: Entity,
    pub damage: i32,
}

#[derive(Component)]
pub struct Velocity(pub Vec3);

#[derive(Component)]
pub struct Lifetime(pub Timer);

/// Pre-built projectile mesh and per-player materials. Shots are frequent, so
/// these are created once rather than per trigger pull.
#[derive(Resource)]
pub struct CombatAssets {
    mesh: Handle<Mesh>,
    materials: Vec<Handle<StandardMaterial>>,
}

pub struct CombatPlugin;

impl Plugin for CombatPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, load_combat_assets)
            .add_systems(Update, (fire_weapons, update_projectiles).chain());
    }
}

fn load_combat_assets(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let mesh = meshes.add(Sphere::new(PROJECTILE_RADIUS));
    let materials = (0..MAX_PLAYERS)
        .map(|index| {
            materials.add(StandardMaterial {
                base_color: player_color(index),
                // Unlit keeps tracers readable against dark geometry without
                // depending on the scene's lighting.
                unlit: true,
                ..default()
            })
        })
        .collect();
    commands.insert_resource(CombatAssets { mesh, materials });
}

fn fire_weapons(
    mut commands: Commands,
    time: Res<Time>,
    assets: Res<CombatAssets>,
    gamepads: Query<&Gamepad>,
    keys: Res<ButtonInput<KeyCode>>,
    mut shooters: Query<
        (Entity, &Player, &InputSource, &Transform, &mut FireCooldown),
        Without<Dead>,
    >,
) {
    for (entity, player, source, transform, mut cooldown) in &mut shooters {
        cooldown.0.tick(time.delta());

        let input = read_input(*source, &gamepads, &keys);
        if !input.firing || !cooldown.0.is_finished() {
            continue;
        }
        cooldown.0.reset();

        let forward = transform.rotation * Vec3::NEG_Z;
        let mut origin = transform.translation + forward * MUZZLE_FORWARD;
        origin.y = MUZZLE_HEIGHT;

        let Some(material) = assets.materials.get(player.index % MAX_PLAYERS) else {
            continue;
        };

        commands.spawn((
            Projectile {
                owner: entity,
                damage: PROJECTILE_DAMAGE,
            },
            Velocity(forward * PROJECTILE_SPEED),
            Lifetime(Timer::from_seconds(PROJECTILE_LIFETIME, TimerMode::Once)),
            Mesh3d(assets.mesh.clone()),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(origin),
        ));
    }
}

fn update_projectiles(
    mut commands: Commands,
    time: Res<Time>,
    obstacles: Query<(&Transform, &Obstacle), (Without<Projectile>, Without<Player>)>,
    mut projectiles: Query<
        (Entity, &mut Transform, &Velocity, &mut Lifetime, &Projectile),
        Without<Player>,
    >,
    mut targets: Query<
        (Entity, &Transform, &mut Health, &mut Visibility),
        (With<Player>, Without<Dead>, Without<Projectile>),
    >,
    // Separate from `targets` because it touches a disjoint component, which
    // is what lets a killer be scored while a victim is being mutated.
    mut scores: Query<&mut Score>,
) {
    let dt = time.delta_secs();
    let mut kills: Vec<Entity> = Vec::new();

    for (projectile_entity, mut transform, velocity, mut lifetime, projectile) in &mut projectiles {
        transform.translation += velocity.0 * dt;
        let position = transform.translation;

        let mut consumed = lifetime.0.tick(time.delta()).is_finished();

        if !consumed {
            let bound = ARENA_HALF_EXTENT + 2.0;
            consumed = position.x.abs() > bound || position.z.abs() > bound;
        }

        if !consumed {
            consumed = obstacles.iter().any(|(obstacle_transform, obstacle)| {
                sphere_hits_box(
                    position,
                    PROJECTILE_RADIUS,
                    obstacle_transform.translation,
                    obstacle.half_extents,
                )
            });
        }

        if !consumed {
            for (target_entity, target_transform, mut health, mut visibility) in &mut targets {
                if target_entity == projectile.owner || health.current <= 0 {
                    continue;
                }
                if !hits_player(position, target_transform.translation) {
                    continue;
                }

                health.current -= projectile.damage;
                consumed = true;

                if health.current <= 0 {
                    health.current = 0;
                    *visibility = Visibility::Hidden;
                    commands.entity(target_entity).insert(Dead(Timer::from_seconds(
                        RESPAWN_SECONDS,
                        TimerMode::Once,
                    )));
                    kills.push(projectile.owner);
                }
                break;
            }
        }

        if consumed {
            commands.entity(projectile_entity).despawn();
        }
    }

    for owner in kills {
        if let Ok(mut score) = scores.get_mut(owner) {
            score.0 += 1;
        }
    }
}

/// Treats the player as an upright capsule: a radius test in XZ plus a
/// vertical band, which is both cheaper and more forgiving than a sphere.
fn hits_player(projectile: Vec3, player: Vec3) -> bool {
    let reach = PLAYER_RADIUS + PROJECTILE_RADIUS;
    let horizontal = Vec2::new(projectile.x - player.x, projectile.z - player.z);
    if horizontal.length_squared() > reach * reach {
        return false;
    }
    let half_height = PLAYER_BODY_LENGTH * 0.5 + PLAYER_RADIUS + PROJECTILE_RADIUS;
    (projectile.y - player.y).abs() <= half_height
}

/// Standard sphere-versus-axis-aligned-box overlap via the closest point.
fn sphere_hits_box(centre: Vec3, radius: f32, box_centre: Vec3, half: Vec3) -> bool {
    let closest = Vec3::new(
        centre.x.clamp(box_centre.x - half.x, box_centre.x + half.x),
        centre.y.clamp(box_centre.y - half.y, box_centre.y + half.y),
        centre.z.clamp(box_centre.z - half.z, box_centre.z + half.z),
    );
    centre.distance_squared(closest) <= radius * radius
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::player::PLAYER_CENTER_Y;

    fn player_at(x: f32, z: f32) -> Vec3 {
        Vec3::new(x, PLAYER_CENTER_Y, z)
    }

    #[test]
    fn a_shot_at_the_chest_connects() {
        assert!(hits_player(
            Vec3::new(0.0, MUZZLE_HEIGHT, 0.0),
            player_at(0.0, 0.0)
        ));
    }

    #[test]
    fn a_shot_wide_of_the_body_misses() {
        let clear = PLAYER_RADIUS + PROJECTILE_RADIUS + 0.05;
        assert!(!hits_player(
            Vec3::new(clear, MUZZLE_HEIGHT, 0.0),
            player_at(0.0, 0.0)
        ));
    }

    #[test]
    fn a_shot_grazing_the_edge_still_connects() {
        let graze = PLAYER_RADIUS + PROJECTILE_RADIUS - 0.01;
        assert!(hits_player(
            Vec3::new(graze, MUZZLE_HEIGHT, 0.0),
            player_at(0.0, 0.0)
        ));
    }

    /// Projectiles fly at a fixed height, so that height must fall inside the
    /// capsule's vertical band or nothing would ever be hit.
    #[test]
    fn the_muzzle_height_is_within_the_body() {
        assert!(hits_player(
            Vec3::new(0.0, MUZZLE_HEIGHT, 0.0),
            player_at(0.0, 0.0)
        ));
    }

    #[test]
    fn a_shot_well_above_the_head_misses() {
        assert!(!hits_player(
            Vec3::new(0.0, PLAYER_CENTER_Y + 5.0, 0.0),
            player_at(0.0, 0.0)
        ));
    }

    #[test]
    fn a_projectile_inside_cover_is_absorbed() {
        assert!(sphere_hits_box(
            Vec3::new(0.0, 1.0, 0.0),
            PROJECTILE_RADIUS,
            Vec3::new(0.0, 1.0, 0.0),
            Vec3::splat(1.0)
        ));
    }

    #[test]
    fn a_projectile_clear_of_cover_passes() {
        assert!(!sphere_hits_box(
            Vec3::new(3.0, 1.0, 0.0),
            PROJECTILE_RADIUS,
            Vec3::new(0.0, 1.0, 0.0),
            Vec3::splat(1.0)
        ));
    }

    #[test]
    fn a_projectile_just_touching_cover_is_absorbed() {
        // Sitting exactly one radius off the +X face counts as contact.
        let touching = 1.0 + PROJECTILE_RADIUS - 1e-4;
        assert!(sphere_hits_box(
            Vec3::new(touching, 1.0, 0.0),
            PROJECTILE_RADIUS,
            Vec3::new(0.0, 1.0, 0.0),
            Vec3::splat(1.0)
        ));
    }

    /// A player must survive at least two hits, or fights end instantly.
    #[test]
    fn a_kill_takes_more_than_one_shot() {
        assert!(PROJECTILE_DAMAGE < PLAYER_MAX_HEALTH);
        assert!(PLAYER_MAX_HEALTH / PROJECTILE_DAMAGE >= 2);
    }
}
