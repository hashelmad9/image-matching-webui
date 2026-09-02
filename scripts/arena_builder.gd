## Assembles an arena from a layout in `Arenas` using the Modular Space Kit.
##
## Everything is built at runtime: a floor of 4m tiles, a ring of wall
## segments with corner pillars, then the layout's cover. Each solid piece
## gets a StaticBody3D with box collision sized from the piece's own mesh
## bounds — accurate for the kit's blocky pieces, and it means a new piece
## needs no collision authoring. Pieces with an opening declare their boxes.
class_name ArenaBuilder
extends RefCounted

const TILE := 4.0
const FLOOR_THICKNESS := 0.5


## Builds `name` under `parent`, replacing whatever was built there before.
## Returns the node holding the pieces.
static func build(parent: Node3D, name: String) -> Node3D:
	clear(parent)
	var root := Node3D.new()
	root.name = "Pieces"
	root.set_meta("arena", name)
	parent.add_child(root)

	_build_floor(root)
	_build_walls(root)
	for entry: Dictionary in Arenas.layout(name)["cover"]:
		place(root, str(entry["piece"]), Vector3(float(entry["x"]), 0.0, float(entry["z"])),
			float(entry.get("rot", 0.0)), entry.get("collide", "auto"))
	return root


static func clear(parent: Node3D) -> void:
	var old := parent.get_node_or_null("Pieces")
	if old != null:
		parent.remove_child(old)
		old.free()


static func built_name(parent: Node3D) -> String:
	var pieces := parent.get_node_or_null("Pieces")
	return str(pieces.get_meta("arena", "")) if pieces != null else ""


static func _build_floor(root: Node3D) -> void:
	var half := Config.ARENA_HALF_EXTENT
	var count := int(round(half * 2.0 / TILE))
	var start := -half + TILE * 0.5
	# One collider for the whole floor beats sixty-four small ones.
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = Config.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half * 2.0, FLOOR_THICKNESS, half * 2.0)
	shape.shape = box
	shape.position.y = -FLOOR_THICKNESS * 0.5
	body.add_child(shape)
	root.add_child(body)
	for ix in count:
		for iz in count:
			var tile := _instance("template-floor")
			if tile == null:
				return
			tile.position = Vector3(start + ix * TILE, 0.0, start + iz * TILE)
			body.add_child(tile)


static func _build_walls(root: Node3D) -> void:
	var half := Config.ARENA_HALF_EXTENT
	var count := int(round(half * 2.0 / TILE))
	var start := -half + TILE * 0.5
	# A wall segment's solid part lies on its -Z side, so facing each edge
	# outward puts the thickness outside the playable square.
	for i in count:
		var along := start + i * TILE
		place(root, "template-wall", Vector3(along, 0.0, -half), 0.0)
		place(root, "template-wall", Vector3(along, 0.0, half), 180.0)
		place(root, "template-wall", Vector3(-half, 0.0, along), -90.0)
		place(root, "template-wall", Vector3(half, 0.0, along), 90.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			place(root, "template-wall-corner", Vector3(sx * (half + 0.5), 0.0, sz * (half + 0.5)), 0.0)


## Places one kit piece. `collide` is "auto", "none", or a list of boxes.
static func place(root: Node3D, piece: String, at: Vector3, rot_degrees: float, collide: Variant = "auto") -> Node3D:
	var model := _instance(piece)
	if model == null:
		return null
	var holder: Node3D
	if collide is String and collide == "none":
		holder = Node3D.new()
	else:
		var body := StaticBody3D.new()
		body.collision_layer = Config.LAYER_WORLD
		body.collision_mask = 0
		holder = body
	holder.name = piece
	holder.position = at
	holder.rotation.y = deg_to_rad(rot_degrees)
	holder.add_child(model)
	root.add_child(holder)

	if holder is StaticBody3D:
		var boxes: Array = []
		if collide is Array:
			for b in collide:
				boxes.append(AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3] - b[0], b[4] - b[1], b[5] - b[2])))
		else:
			boxes.append(local_bounds(model))
		for aabb: AABB in boxes:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = aabb.size
			shape.shape = box
			shape.position = aabb.get_center()
			holder.add_child(shape)
	return holder


static func _instance(piece: String) -> Node3D:
	var packed := load(Arenas.PIECE_DIR + piece + ".glb") as PackedScene
	if packed == null:
		push_warning("ArenaBuilder: missing piece %s" % piece)
		return null
	return packed.instantiate() as Node3D


## Bounds of every mesh under `node`, in `node`'s own space.
static func local_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in _meshes(node):
		var box: AABB = (node.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
