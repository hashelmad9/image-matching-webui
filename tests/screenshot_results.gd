## Renders the results screen after a deathmatch to docs/results.png: the
## headline, session standings, and the mutator ballot.
##
##     VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##         xvfb-run godot --path . --script res://tests/screenshot_results.gd
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
	await process_frame
	main.start_round("deathmatch", true)
	await process_frame
	var players: Array = main.players()
	# A believable scoreline, then the target is reached and the round ends.
	players[1].score = 6
	players[2].score = 4
	players[3].score = 2
	players[0].score = Config.DEATHMATCH_KILL_TARGET
	await process_frame
	await process_frame
	main.vote(0, 1)
	main.vote(1, 1)
	main.vote(2, 0)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png("res://docs/results.png")
	print("wrote res://docs/results.png" if error == OK else "failed: %d" % error)
	quit(0 if error == OK else 1)
