extends SceneTree
## Run with -- --output <path> before shipping; use the engine's actual notices.
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output":
		printerr("Expected -- --output <path>")
		quit(1)
		return
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		printerr("Cannot write engine notices")
		quit(1)
		return
	file.store_string(Engine.get_license_text() + "\n\n")
	for entry in Engine.get_copyright_info():
		file.store_string(str(entry) + "\n")
	for license_name in Engine.get_license_info():
		file.store_string("\n" + license_name + "\n" + Engine.get_license_info()[license_name] + "\n")
	file.close()
	quit()
