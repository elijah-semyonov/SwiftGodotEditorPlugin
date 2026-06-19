@tool
class_name Scaffolder
extends RefCounted

## Idempotent, non-clobbering file/directory creation for the SwiftGodot setup.
## Every method appends human-readable lines to a `log` array so the panel can
## stream progress, and never overwrites a file the user already has.

const T = preload("res://addons/swift_godot_setup/templates.gd")

## Create a directory (recursively). Treats "already exists" as success.
static func ensure_dir(res_path: String, log: Array) -> bool:
	var abs := ProjectSettings.globalize_path(res_path)
	if DirAccess.dir_exists_absolute(abs):
		return true
	var err := DirAccess.make_dir_recursive_absolute(abs)
	if err != OK:
		log.append("  ✗ failed to create dir %s (error %d)" % [res_path, err])
		return false
	log.append("  + %s/" % res_path)
	return true

## Write `contents` to `res_path` only if no file is already there.
static func write_if_absent(res_path: String, contents: String, log: Array) -> bool:
	if FileAccess.file_exists(res_path):
		log.append("  · %s (skipped, exists)" % res_path)
		return true
	var file := FileAccess.open(res_path, FileAccess.WRITE)
	if file == null:
		log.append("  ✗ could not write %s (error %d)" % [res_path, FileAccess.get_open_error()])
		return false
	file.store_string(contents)
	file.close()
	log.append("  + %s" % res_path)
	return true

## Drop an empty .gdignore so Godot ignores Swift sources / build artifacts.
static func write_gdignore(res_dir: String, log: Array) -> bool:
	return write_if_absent(res_dir + "/.gdignore", "", log)

## Persist the chosen module name (read back by state detection after restart).
static func write_module_config(module: String, log: Array) -> bool:
	var cfg := ConfigFile.new()
	# Preserve any existing keys if the file is already there.
	if FileAccess.file_exists(T.CONFIG_FILE):
		cfg.load(T.CONFIG_FILE)
	cfg.set_value("swift_godot", "module_name", module)
	var err := cfg.save(T.CONFIG_FILE)
	if err != OK:
		log.append("  ✗ could not write %s (error %d)" % [T.CONFIG_FILE, err])
		return false
	log.append("  + %s (module_name=%s)" % [T.CONFIG_FILE, module])
	return true

## Read the persisted module name, or "" if not set up yet.
static func read_module_config() -> String:
	if not FileAccess.file_exists(T.CONFIG_FILE):
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(T.CONFIG_FILE) != OK:
		return ""
	return cfg.get_value("swift_godot", "module_name", "")

## Scaffold the full SwiftGodot integration for `module`. Returns
## { ok: bool, log: Array[String] }.
static func scaffold(module: String) -> Dictionary:
	var log: Array = []
	var ok := true

	log.append("Scaffolding SwiftGodot integration (module: %s)" % module)

	# 1. SPM project
	ok = ensure_dir(T.SPM_DIR, log) and ok
	ok = ensure_dir(T.sources_dir(module), log) and ok
	ok = write_if_absent(T.SPM_DIR + "/Package.swift", T.render(T.PACKAGE_SWIFT, module), log) and ok
	ok = write_if_absent(T.sample_swift_file(module), T.render(T.SAMPLE_SWIFT, module), log) and ok
	ok = write_gdignore(T.SPM_DIR, log) and ok
	ok = write_if_absent(T.SPM_DIR + "/.gitignore", T.SWIFT_GITIGNORE, log) and ok

	# 2. GDExtension + build output dir
	ok = ensure_dir(T.EXT_DIR, log) and ok
	ok = ensure_dir(T.BIN_DIR, log) and ok
	ok = write_if_absent(T.GDEXT_FILE, T.render(T.GDEXTENSION, module), log) and ok
	ok = write_gdignore(T.BIN_DIR, log) and ok
	ok = write_if_absent(T.EXT_DIR + "/.gitignore", T.EXTENSION_GITIGNORE, log) and ok

	# 3. Remember the module name for later runs.
	ok = write_module_config(module, log) and ok

	log.append("Done." if ok else "Completed with errors — see above.")
	return { "ok": ok, "log": log }
