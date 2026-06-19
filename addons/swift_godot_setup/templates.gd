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

@Godot
class YourNewSwiftNode: Node {
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
