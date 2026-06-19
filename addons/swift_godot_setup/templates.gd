@tool
class_name SwiftGodotTemplates
extends RefCounted

## Single source of truth for every file this plugin scaffolds into the host
## project. The bodies live here as string constants (with a `__MODULE__`
## placeholder substituted at write time) so the addon ships nothing on disk
## that Godot might mistake for part of the user's project.

const DEFAULT_MODULE := "SwiftGodotGame"

# Where the scaffolded pieces land in the host project. These match the
# reference SwiftGodotTemplate layout so the generated .gdextension paths line up
# with `swift build`'s output.
const SPM_DIR := "res://swift_godot_game"
const EXT_DIR := "res://addons/swift_godot_extension"
const GDEXT_FILE := EXT_DIR + "/swift_godot.gdextension"
const BIN_DIR := EXT_DIR + "/bin"
# Records the chosen module name so state detection survives an editor restart.
const CONFIG_FILE := EXT_DIR + "/swift_godot_setup.cfg"

# SwiftPM emits artifacts under <build-path>/<unversioned-triple>/<config>/.
const MACOS_TRIPLE := "arm64-apple-macosx"
const WINDOWS_TRIPLE := "x86_64-unknown-windows-msvc"

static func sources_dir(module: String) -> String:
	return SPM_DIR + "/Sources/" + module

static func sample_swift_file(module: String) -> String:
	return sources_dir(module) + "/" + module + ".swift"

## Replace the module placeholder throughout a template body.
static func render(template: String, module: String) -> String:
	return template.replace("__MODULE__", module)

## A valid Swift module / SwiftPM target identifier.
static func is_valid_module(module: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	return re.search(module) != null

## Relative path (under BIN_DIR) of the built product for a platform.
static func macos_product(module: String) -> String:
	return MACOS_TRIPLE + "/debug/lib" + module + ".dylib"

static func windows_product(module: String) -> String:
	return WINDOWS_TRIPLE + "/debug/" + module + ".dll"

const PACKAGE_SWIFT := """// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "__MODULE__",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "__MODULE__",
            type: .dynamic,
            targets: ["__MODULE__"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftGodot", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "__MODULE__",
            dependencies: [
                .product(name: "SwiftGodot", package: "swiftgodot")
            ],
            plugins: [
                .plugin(name: "EntryPointGeneratorPlugin", package: "swiftgodot")
            ]
        ),
    ]
)
"""

const SAMPLE_SWIFT := """// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftGodot
import Foundation

/// A demo node that wiggles around in a Lissajous pattern, spins, and emits
/// signals as it goes. It shows off the SwiftGodot features you'll use most —
/// exported properties (@Export), signals (@Signal), callable methods
/// (@Callable) and lifecycle overrides (_ready/_process) — and gives the
/// \"Registered Classes\" tab something interesting to display.
///
/// Add it to a 2D scene to watch it move, then replace it with your own
/// @Godot classes.
@Godot
class WigglyNode: Node2D {
	/// How fast the wiggle animates.
	@Export var speed: Double = 2.0
	/// How far (in pixels) the node travels from its starting point.
	@Export var amplitude: Double = 48.0
	/// Degrees per second the node spins.
	@Export var spinSpeed: Double = 90.0
	/// Whether to emit `looped` after every full cycle.
	@Export var announceLoops: Bool = true

	/// Emitted once, when the node enters the tree and starts wiggling.
	@Signal var started: SimpleSignal
	/// Emitted each time a full wiggle cycle completes; carries the loop count.
	@Signal var looped: SignalWithArguments<Int>

	private var origin = Vector2(x: 0, y: 0)
	private var elapsed: Double = 0
	private var loops: Int = 0

	override func _ready() {
		origin = position
		started.emit()
		GD.print(\"WigglyNode is ready — wiggling away!\")
	}

	override func _process(delta: Double) {
		elapsed += delta * speed

		// Lissajous path: different frequencies on X and Y.
		position = Vector2(
			x: origin.x + Float(amplitude * sin(elapsed * 2.0)),
			y: origin.y + Float(amplitude * sin(elapsed * 3.0))
		)

		// Spin (degrees/sec -> radians).
		rotation += delta * (spinSpeed * Double.pi / 180.0)

		// Count completed cycles and announce them.
		let completed = Int(elapsed / (2.0 * Double.pi))
		if completed > loops {
			loops = completed
			if announceLoops {
				looped.emit(loops)
			}
		}
	}

	/// Reset the wiggle back to its starting point. Callable from GDScript.
	@Callable
	func resetWiggle() {
		elapsed = 0
		loops = 0
		rotation = 0
		position = origin
	}

	/// Number of full cycles completed so far. Callable from GDScript.
	@Callable
	func loopCount() -> Int {
		loops
	}
}
"""

# Every library/dependency filename carries the module placeholder for the
# product, and the literal "SwiftGodot" for the framework dependency.
const GDEXTENSION := """[configuration]
entry_symbol = "swift_entry_point"
compatibility_minimum = 4.4


[libraries]
macos.debug = "res://addons/swift_godot_extension/bin/arm64-apple-macosx/debug/lib__MODULE__.dylib"
windows.x86_64.debug = "res://addons/swift_godot_extension/bin/x86_64-unknown-windows-msvc/debug/__MODULE__.dll"
windows.x86_64.release = "res://addons/swift_godot_extension/bin/x86_64-unknown-windows-msvc/debug/__MODULE__.dll"

[dependencies]
macos.debug = "res://addons/swift_godot_extension/bin/arm64-apple-macosx/debug/libSwiftGodot.dylib"
windows.x86_64.debug = "res://addons/swift_godot_extension/bin/x86_64-unknown-windows-msvc/debug/SwiftGodot.dll"
windows.x86_64.release = "res://addons/swift_godot_extension/bin/x86_64-unknown-windows-msvc/debug/SwiftGodot.dll"
"""

const SWIFT_GITIGNORE := """.build
.index-build
DerivedData
/.previous-build
xcuserdata
.DS_Store
*~
.swiftpm
Package.resolved
/build
.docc-build
.vscode
"""

const EXTENSION_GITIGNORE := "bin\n"
