@tool
extends MarginContainer

## Main-screen panel. Three states:
##   NOT_SET_UP        -> show module-name field + "Set up SwiftGodot"
##   SET_UP_NOT_BUILT  -> show "Rebuild" (first build resolves & compiles SwiftGodot)
##   BUILT             -> show "Rebuild" + "set up and built" status
## The build flow (swift build + editor restart) is adapted from the reference
## SwiftGodotTemplate editor plugin.

const T = preload("res://addons/swift_godot_setup/templates.gd")

enum State { NOT_SET_UP, SET_UP_NOT_BUILT, BUILT }

const PROGRESS_MARKERS := ["˥", "˦", "˧", "˨", "˩", "˨", "˧", "˦"]

@onready var status_label: RichTextLabel = $VBoxContainer/StatusLabel
@onready var setup_row: HBoxContainer = $VBoxContainer/SetupRow
@onready var module_edit: LineEdit = $VBoxContainer/SetupRow/ModuleEdit
@onready var primary_button: Button = $VBoxContainer/ButtonsContainer/PrimaryButton
@onready var clean_build_check_button: CheckButton = $VBoxContainer/ButtonsContainer/CleanBuildCheckButton
@onready var log: RichTextLabel = $VBoxContainer/Log

var _working := false
var _swift_available := false

signal state_changed(working: bool)

func _ready() -> void:
	if module_edit.text.strip_edges() == "":
		module_edit.text = T.DEFAULT_MODULE

	state_changed.connect(func(is_working: bool):
		_working = is_working
		primary_button.disabled = is_working
		clean_build_check_button.disabled = is_working
		module_edit.editable = not is_working
	)
	refresh_state()

# --- state detection ------------------------------------------------------

func current_module() -> String:
	var persisted := Scaffolder.read_module_config()
	if persisted != "":
		return persisted
	var typed := module_edit.text.strip_edges() if is_instance_valid(module_edit) else ""
	return typed if typed != "" else T.DEFAULT_MODULE

func _built_artifact_exists(module: String) -> bool:
	# Check the host platform's expected product.
	var macos := T.BIN_DIR + "/" + T.macos_product(module)
	var windows := T.BIN_DIR + "/" + T.windows_product(module)
	if OS.get_name() == "Windows":
		return FileAccess.file_exists(windows)
	return FileAccess.file_exists(macos)

func detect_state() -> State:
	var has_package := FileAccess.file_exists(T.SPM_DIR + "/Package.swift")
	var has_gdext := FileAccess.file_exists(T.GDEXT_FILE)
	if not (has_package and has_gdext):
		return State.NOT_SET_UP
	if _built_artifact_exists(current_module()):
		return State.BUILT
	return State.SET_UP_NOT_BUILT

# --- toolchain ------------------------------------------------------------

func check_toolchain() -> bool:
	if OS.is_sandboxed():
		return false
	var out: Array = []
	var code := OS.execute("swift", ["--version"], out, true)
	return code == 0

# --- UI refresh -----------------------------------------------------------

func refresh_state() -> void:
	if not is_node_ready() or _working:
		return

	_swift_available = check_toolchain()
	var state := detect_state()

	# Disconnect any previous primary action.
	for c in primary_button.pressed.get_connections():
		primary_button.pressed.disconnect(c.callable)

	match state:
		State.NOT_SET_UP:
			setup_row.visible = true
			clean_build_check_button.visible = false
			primary_button.text = "Set up SwiftGodot"
			primary_button.pressed.connect(do_setup)
			_set_status("[b]Not set up.[/b] Choose a Swift module name and click [i]Set up SwiftGodot[/i] to scaffold the SPM project and GDExtension into this project.")
		State.SET_UP_NOT_BUILT:
			setup_row.visible = false
			clean_build_check_button.visible = true
			primary_button.text = "Rebuild"
			primary_button.pressed.connect(recompile_swift)
			_set_status("[b]Scaffolded[/b] (module: %s), not built yet. Click [i]Rebuild[/i] to compile. The first build downloads SwiftGodot and may take several minutes." % current_module())
		State.BUILT:
			setup_row.visible = false
			clean_build_check_button.visible = true
			primary_button.text = "Rebuild"
			primary_button.pressed.connect(recompile_swift)
			_set_status("[color=#5fd35f][b]SwiftGodot is set up and built[/b][/color] (module: %s). Edit Swift sources in %s and click Rebuild." % [current_module(), T.SPM_DIR])

	# Toolchain / sandbox guard affects everything that runs `swift`.
	if OS.is_sandboxed():
		primary_button.disabled = true
		_append_status("\n[color=#e06c6c]Editor is sandboxed — cannot launch external processes. Run Godot un-sandboxed to use this plugin.[/color]")
	elif not _swift_available and state != State.NOT_SET_UP:
		primary_button.disabled = true
		_append_status("\n[color=#e06c6c]Swift toolchain not found. Install Swift (e.g. via Xcode) and ensure `swift` is on your PATH, then reopen this tab.[/color]")
	else:
		primary_button.disabled = false

	if OS.get_name() == "Windows" and state == State.SET_UP_NOT_BUILT:
		_append_status("\n[color=#d3b25f]Windows: after the first build, copy the Swift runtime DLLs into %s/%s. See the SwiftGodot Windows docs.[/color]" % [T.BIN_DIR, T.WINDOWS_TRIPLE + "/debug"])

func _set_status(bbcode: String) -> void:
	status_label.clear()
	status_label.append_text(bbcode)

func _append_status(bbcode: String) -> void:
	status_label.append_text(bbcode)

func append_log(line: String) -> void:
	log.append_text(line + "\n")

# --- setup action ---------------------------------------------------------

func do_setup() -> void:
	var module := module_edit.text.strip_edges()
	if module == "":
		module = T.DEFAULT_MODULE
	if not T.is_valid_module(module):
		log.clear()
		append_log("Invalid module name '%s'. Use a letter or underscore followed by letters, digits or underscores." % module)
		return

	state_changed.emit(true)
	log.clear()
	var result := Scaffolder.scaffold(module)
	for line in result["log"]:
		append_log(line)
	state_changed.emit(false)

	if result["ok"]:
		append_log("\nSetup complete. Click \"Rebuild\" to compile (first build may take a few minutes).")
	refresh_state()

# --- build action (adapted from SwiftGodotTemplate) -----------------------

func wait_process_finished(pid: int, progress_text: String) -> void:
	var start_time := Time.get_ticks_msec()
	var i := 0
	var initial_log_text := log.get_parsed_text()
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.1).timeout
		var time_passed := (Time.get_ticks_msec() - start_time) / 1000
		log.text = "%s%s %s %s s " % [initial_log_text, progress_text, PROGRESS_MARKERS[i], time_passed]
		i = (i + 1) % PROGRESS_MARKERS.size()
	log.text = initial_log_text

func recompile_swift() -> void:
	state_changed.emit(true)
	log.clear()

	if OS.is_sandboxed():
		append_log("Impossible to launch OS processes. Editor is sandboxed.")
		state_changed.emit(false)
		return

	var swift_path := ProjectSettings.globalize_path(T.SPM_DIR)
	var target_dir := ProjectSettings.globalize_path(T.BIN_DIR)

	if not DirAccess.dir_exists_absolute(target_dir):
		var err := DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			append_log("Error creating directory '" + target_dir + "'")
			state_changed.emit(false)
			return
		append_log("Building from scratch. This can take a while; subsequent builds are much faster.")

	if clean_build_check_button.button_pressed:
		append_log("Running `swift package clean`")
		var clean_pid := OS.create_process(
			"swift", ["package", "clean", "--package-path", swift_path, "--build-path", target_dir], false
		)
		if clean_pid == -1:
			append_log("Couldn't execute `swift package clean`")
			state_changed.emit(false)
			return
		await wait_process_finished(clean_pid, "Cleaning")
		append_log("Cleaned")

	# Keep Godot from importing build artifacts.
	var gdignore_path := target_dir.path_join(".gdignore")
	var f := FileAccess.open(gdignore_path, FileAccess.WRITE)
	if f == null:
		append_log("Error creating '" + gdignore_path + "'")
		state_changed.emit(false)
		return
	f.close()

	append_log("Building into %s" % target_dir)
	var pid := OS.create_process(
		"swift", ["build", "--package-path", swift_path, "--build-path", target_dir], false
	)
	if pid == -1:
		append_log("Couldn't execute `swift build`")
		state_changed.emit(false)
		return

	append_log("Running `swift build`")
	await wait_process_finished(pid, "Building")
	append_log("Done! Restarting editor.")
	await get_tree().create_timer(1.0).timeout
	EditorInterface.restart_editor(false)
