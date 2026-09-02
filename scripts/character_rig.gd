## Shared helpers for the Kenney rigged character, used by players and enemies.
##
## Kenney ships each animation as its own FBX with a duplicate skeleton, so the
## clips are lifted out and re-hosted on one AnimationPlayer parented to the
## character root, where the "Root/Skeleton3D:bone" track paths resolve
## against our skeleton without rewriting.
class_name CharacterRig
extends RefCounted

const ANIMATION_SOURCES := {
	"idle": ["res://assets/characters/animations/idle.fbx", "Root|Idle"],
	"run": ["res://assets/characters/animations/run.fbx", "Root|Run"],
}


static func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := find_mesh(child)
		if found != null:
			return found
	return null


## Applies a texture atlas and tint to the rig's mesh. Returns the material so
## callers can tweak it later (the tag mode highlights whoever is "it").
static func apply_skin(root: Node, texture_path: String, tint: Color) -> StandardMaterial3D:
	var mesh := find_mesh(root)
	if mesh == null:
		push_warning("CharacterRig: no mesh under %s" % root.name)
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(texture_path) as Texture2D
	material.albedo_color = tint
	material.roughness = 0.8
	mesh.material_override = material
	return material


## Builds an AnimationPlayer with the idle and run clips under `root`.
static func build_animation_player(root: Node3D) -> AnimationPlayer:
	var library := AnimationLibrary.new()
	for clip_name: String in ANIMATION_SOURCES:
		var source: Array = ANIMATION_SOURCES[clip_name]
		var clip := _load_animation(source[0], source[1])
		if clip != null:
			library.add_animation(clip_name, clip)
	if library.get_animation_list().is_empty():
		push_warning("CharacterRig: no animations loaded")
		return null
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.add_animation_library("", library)
	return player


static func _load_animation(path: String, clip_name: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	var source := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var clip: Animation = null
	if source != null and source.has_animation(clip_name):
		clip = source.get_animation(clip_name).duplicate()
		clip.loop_mode = Animation.LOOP_LINEAR
	scene.free()
	return clip
