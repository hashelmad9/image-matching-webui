//! Static level geometry: floor, boundary walls and cover.
//!
//! Interior cover carries [`Obstacle`], which both `player` (push-out) and
//! `combat` (projectile absorption) treat as a solid axis-aligned box. The
//! boundary walls are decorative only — players are clamped to the arena in
//! `player::move_players`, so walls never need collision of their own.

use crate::config::*;
use bevy::{light::CascadeShadowConfigBuilder, prelude::*};
use std::f32::consts::PI;

/// A solid axis-aligned box centred on the entity's translation.
#[derive(Component)]
pub struct Obstacle {
    pub half_extents: Vec3,
}

pub struct ArenaPlugin;

impl Plugin for ArenaPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_arena);
    }
}

fn setup_arena(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let span = ARENA_HALF_EXTENT * 2.0;

    // Floor
    commands.spawn((
        Mesh3d(meshes.add(Plane3d::default().mesh().size(span, span))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgb(0.16, 0.17, 0.21),
            perceptual_roughness: 0.9,
            ..default()
        })),
        Transform::from_xyz(0.0, 0.0, 0.0),
    ));

    let wall_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.28, 0.30, 0.38),
        perceptual_roughness: 0.85,
        ..default()
    });

    // Boundary walls, one per side, sitting just outside the playable area.
    let edge = ARENA_HALF_EXTENT + WALL_THICKNESS * 0.5;
    let long = span + WALL_THICKNESS * 2.0;
    let walls: [(Vec3, Vec3); 4] = [
        // (centre, full size)
        (
            Vec3::new(0.0, WALL_HEIGHT * 0.5, -edge),
            Vec3::new(long, WALL_HEIGHT, WALL_THICKNESS),
        ),
        (
            Vec3::new(0.0, WALL_HEIGHT * 0.5, edge),
            Vec3::new(long, WALL_HEIGHT, WALL_THICKNESS),
        ),
        (
            Vec3::new(-edge, WALL_HEIGHT * 0.5, 0.0),
            Vec3::new(WALL_THICKNESS, WALL_HEIGHT, long),
        ),
        (
            Vec3::new(edge, WALL_HEIGHT * 0.5, 0.0),
            Vec3::new(WALL_THICKNESS, WALL_HEIGHT, long),
        ),
    ];
    for (centre, size) in walls {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
            MeshMaterial3d(wall_material.clone()),
            Transform::from_translation(centre),
        ));
    }

    // Interior cover. Symmetric so no spawn point is advantaged.
    let cover_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.38, 0.34, 0.30),
        perceptual_roughness: 0.8,
        ..default()
    });
    let cover: [(Vec3, Vec3); 5] = [
        // (centre on the floor, half extents)
        (Vec3::new(0.0, 0.0, 0.0), Vec3::new(2.5, 1.5, 2.5)),
        (Vec3::new(-10.0, 0.0, -4.0), Vec3::new(1.2, 1.2, 3.5)),
        (Vec3::new(10.0, 0.0, 4.0), Vec3::new(1.2, 1.2, 3.5)),
        (Vec3::new(4.0, 0.0, -11.0), Vec3::new(3.5, 1.2, 1.2)),
        (Vec3::new(-4.0, 0.0, 11.0), Vec3::new(3.5, 1.2, 1.2)),
    ];
    for (centre, half) in cover {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(
                half.x * 2.0,
                half.y * 2.0,
                half.z * 2.0,
            ))),
            MeshMaterial3d(cover_material.clone()),
            // Cuboid meshes are centred on the origin, so lift by half the
            // height to sit the box on the floor.
            Transform::from_translation(centre + Vec3::Y * half.y),
            Obstacle { half_extents: half },
        ));
    }

    // Key light. The cascade bounds are sized to the arena so shadows stay
    // crisp across the whole playable area.
    commands.spawn((
        DirectionalLight {
            illuminance: 10_000.0,
            shadow_maps_enabled: true,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(EulerRot::ZYX, 0.0, 0.8, -PI / 3.5)),
        CascadeShadowConfigBuilder {
            num_cascades: 2,
            first_cascade_far_bound: 24.0,
            maximum_distance: 90.0,
            ..default()
        }
        .build(),
    ));

    commands.insert_resource(GlobalAmbientLight {
        color: Color::srgb(0.7, 0.78, 1.0),
        brightness: 220.0,
        ..default()
    });
}
