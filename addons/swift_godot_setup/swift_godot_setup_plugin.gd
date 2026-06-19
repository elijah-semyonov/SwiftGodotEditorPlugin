@tool
extends EditorPlugin

const MainPanel := preload("res://addons/swift_godot_setup/panel.tscn")

var main_panel_instance: Control

func _enter_tree() -> void:
	main_panel_instance = MainPanel.instantiate()
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)

func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible
		# Re-detect state each time the tab is shown so the UI reflects any
		# changes (setup performed, build finished) without a manual refresh.
		if visible and main_panel_instance.has_method("refresh_state"):
			main_panel_instance.refresh_state()

func _get_plugin_name() -> String:
	return "SwiftGodot"

func _get_plugin_icon() -> Texture2D:
	# On a brand-new install the SVG may not be imported yet during the first
	# filesystem scan; fall back to no icon rather than erroring.
	const ICON := "res://addons/swift_godot_setup/swift_godot_logo.svg"
	if not ResourceLoader.exists(ICON):
		return null
	# The SVG imports at full size, which renders huge on the tab. Resize it to
	# match the built-in main-screen tabs (16px, scaled for the editor/HiDPI).
	var tex: Texture2D = load(ICON)
	var img := tex.get_image()
	var px := int(round(16.0 * EditorInterface.get_editor_scale()))
	img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
