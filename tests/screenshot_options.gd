## Renders the options menu over a paused horde round to docs/options.png.
##
##     VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \\
##         xvfb-run godot --path . --script res://tests/screenshot_options.gd
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.play()
	for device in [Config.KEYBOARD_DEVICE, 0, 1, 2]:
		main._try_join(device)
	main.start_round("horde", true)
	for i in 120:
		await physics_frame
	main.open_pause_menu()
	main.open_options_menu()
	main._menus.back().select("fov")
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png("res://docs/options.png")
	print("wrote res://docs/options.png" if error == OK else "failed: %d" % error)
	quit(0 if error == OK else 1)
