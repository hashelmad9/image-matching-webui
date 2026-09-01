## Renders a frame of a four-player match to a PNG, so the split-screen layout
## can be inspected without a physical machine.
##
##     xvfb-run godot --path . --rendering-driver opengl3 \
##         --rendering-method gl_compatibility --script res://tests/screenshot.gd
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	for device in [Config.KEYBOARD_DEVICE, 0, 1, 2]:
		main._try_join(device)

	# Let the bodies settle onto the floor and the cameras reach their players.
	for i in 90:
		await physics_frame
	for i in 10:
		await process_frame

	# Put a few tracers in flight so projectiles appear in the shot.
	for child in main.get_node("World/Players").get_children():
		var player := child as Player
		if player != null:
			player.fired.emit(player, player.global_position, player.forward())
	for i in 8:
		await physics_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://docs/split-screen.png"
	var error := image.save_png(path)
	if error == OK:
		print("wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	else:
		printerr("failed to save screenshot: %d" % error)
	quit(0 if error == OK else 1)
