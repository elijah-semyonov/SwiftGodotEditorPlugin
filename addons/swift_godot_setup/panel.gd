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
@onready var restart_button: Button = $VBoxContainer/ButtonsContainer/RestartButton
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
		restart_button.disabled = is_working
		module_edit.editable = not is_working
	)
	restart_button.pressed.connect(func(): EditorInterface.restart_editor(false))
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

	# The restart button only appears right after a successful build.
	restart_button.visible = false

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

# OS.create_process can't capture a child's output, so we run build steps
# through a shell with stdout+stderr redirected to this file, then tail it into
# the Log live.
const BUILD_LOG := "user://swift_godot_build.log"

func _shell_for(command: String) -> Dictionary:
	if OS.get_name() == "Windows":
		return { "exe": "cmd.exe", "args": ["/c", command] }
	return { "exe": "/bin/sh", "args": ["-c", command] }

## Run `command` via a shell, streaming its output into the Log and an elapsed
## spinner into the status bar. Returns false if the process couldn't start.
func _run_streamed(command: String, progress_text: String) -> bool:
	var log_abs := ProjectSettings.globalize_path(BUILD_LOG)
	# Truncate before each step so we only tail this run's output.
	var truncate := FileAccess.open(BUILD_LOG, FileAccess.WRITE)
	if truncate:
		truncate.close()

	var full := '%s > "%s" 2>&1' % [command, log_abs]
	var shell := _shell_for(full)
	var pid := OS.create_process(shell["exe"], shell["args"], false)
	if pid == -1:
		append_log("Couldn't execute: %s" % command)
		return false

	var start_time := Time.get_ticks_msec()
	var i := 0
	var offset := 0
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.1).timeout
		offset = _stream_chunk(log_abs, offset)
		var secs := (Time.get_ticks_msec() - start_time) / 1000
		_set_status("[b]%s[/b] %s  %d s" % [progress_text, PROGRESS_MARKERS[i], secs])
		i = (i + 1) % PROGRESS_MARKERS.size()
	# Flush anything written between the last poll and process exit.
	_stream_chunk(log_abs, offset)
	return true

## Append the portion of the log file past `offset`; returns the new offset.
## Uses add_text (not append_text) so build output like "[1/273]" isn't parsed
## as BBCode.
func _stream_chunk(log_abs: String, offset: int) -> int:
	var f := FileAccess.open(log_abs, FileAccess.READ)
	if f == null:
		return offset
	var size := f.get_length()
	if size > offset:
		f.seek(offset)
		log.add_text(f.get_buffer(size - offset).get_string_from_utf8())
		offset = size
	f.close()
	return offset

func recompile_swift() -> void:
	state_changed.emit(true)
	log.clear()

	if OS.is_sandboxed():
		append_log("Cannot launch processes — the editor is sandboxed.")
		state_changed.emit(false)
		refresh_state()
		return

	var swift_path := ProjectSettings.globalize_path(T.SPM_DIR)
	var target_dir := ProjectSettings.globalize_path(T.BIN_DIR)

	if not DirAccess.dir_exists_absolute(target_dir):
		var err := DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			append_log("Error creating directory '%s'" % target_dir)
			state_changed.emit(false)
			refresh_state()
			return
		append_log("Building from scratch — the first build can take several minutes.")

	if clean_build_check_button.button_pressed:
		append_log("$ swift package clean")
		var clean_cmd := 'swift package clean --package-path "%s" --build-path "%s"' % [swift_path, target_dir]
		if not await _run_streamed(clean_cmd, "Cleaning"):
			state_changed.emit(false)
			refresh_state()
			return

	# Keep Godot from importing build artifacts.
	var gdignore_path := target_dir.path_join(".gdignore")
	var gf := FileAccess.open(gdignore_path, FileAccess.WRITE)
	if gf:
		gf.close()

	append_log("$ swift build --package-path %s --build-path %s\n" % [T.SPM_DIR, T.BIN_DIR])
	var build_cmd := 'swift build --package-path "%s" --build-path "%s"' % [swift_path, target_dir]
	if not await _run_streamed(build_cmd, "Building"):
		state_changed.emit(false)
		refresh_state()
		return

	state_changed.emit(false)
	if _built_artifact_exists(current_module()):
		_set_status("[color=#5fd35f][b]Build succeeded.[/b][/color] Click [i]Restart editor[/i] to load the extension.")
		append_log("\nBuild complete. Click \"Restart editor\" to load the extension.")
		restart_button.visible = true
		restart_button.disabled = false
	else:
		# Leave the build output visible and don't restart — the log holds the error.
		_set_status("[color=#e06c6c][b]Build failed.[/b][/color] See the log above; the editor was not restarted.")
