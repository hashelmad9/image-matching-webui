## Bakes a navigation mesh from the arena's static colliders at startup, so
## horde enemies can path around cover instead of walking into it.
##
## Baked at runtime rather than in the editor so a rebuilt or generated arena
## never ships with a stale mesh. On this arena it takes a few milliseconds.
class_name NavigationBuilder
extends RefCounted


static func build(world: Node3D, arena: Node) -> NavigationRegion3D:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = Config.PLAYER_RADIUS + 0.2
	navmesh.agent_height = Config.PLAYER_HEIGHT
	navmesh.agent_max_climb = 0.3
	navmesh.cell_size = 0.3
	navmesh.cell_height = 0.2
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Config.LAYER_WORLD

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, arena)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)

	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = navmesh
	world.add_child(region)
	return region
