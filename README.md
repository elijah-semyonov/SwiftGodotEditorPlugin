# SwiftGodot Setup

A Godot 4 editor plugin that turns any existing project into a [SwiftGodot](https://github.com/migueldeicaza/SwiftGodot) project. Install it from the **Asset Library**, enable it, and one click scaffolds a Swift Package Manager project and a `.gdextension`; another click builds it and reloads the editor so your Swift `@Godot` nodes show up.

It is the install-into-your-project counterpart of the clone-and-go [SwiftGodotTemplate](https://github.com/elijah-semyonov/SwiftGodotTemplate).

## Requirements

- Godot 4.4+ (developed against 4.7)
- A Swift 6.1+ toolchain on your `PATH`
  - **macOS (Apple silicon):** Swift from Xcode 16.3+
  - **Windows (x86_64):** [Swift 6.1](https://www.swift.org/install/windows/)
- The editor must **not** be sandboxed (the plugin launches `swift` as an external process)

## Install

1. From the in-editor **AssetLib** tab, find "SwiftGodot Setup" and install it (or copy `addons/swift_godot_setup/` into your project).
2. **Project → Project Settings → Plugins** and enable **SwiftGodot Setup**.
3. A **SwiftGodot** tab appears in the top main-screen bar.

## Use

1. Open the **SwiftGodot** tab.
2. Enter a **module name** (default `SwiftGodotGame`) and click **Set up SwiftGodot**. This creates, without touching any existing files:
   - `swift_godot_game/` — the SPM project (`Package.swift`, `Sources/<Module>/<Module>.swift`), hidden from Godot via `.gdignore`
   - `addons/swift_godot_extension/swift_godot.gdextension` — the GDExtension descriptor
   - `addons/swift_godot_extension/bin/` — build-output directory (git-ignored)
3. Click **Rebuild**. The first build resolves and compiles SwiftGodot (several minutes); later builds are fast. The editor restarts automatically so the freshly built library loads.
4. Add the sample `YourNewSwiftNode` to a scene to confirm it works, then edit the Swift sources and Rebuild as you go. Tick **Clean build** to run `swift package clean` first.

## How it works

The plugin runs `swift build --package-path swift_godot_game --build-path addons/swift_godot_extension/bin` via `OS.create_process`. The generated `.gdextension` points at the exact artifacts SwiftPM emits:

```
addons/swift_godot_extension/bin/arm64-apple-macosx/debug/lib<Module>.dylib   (your code)
addons/swift_godot_extension/bin/arm64-apple-macosx/debug/libSwiftGodot.dylib (dependency)
```

The chosen module name is recorded in `addons/swift_godot_extension/swift_godot_setup.cfg` so the plugin can report build state across editor restarts.

## Windows note

After the first Windows build you must copy the Swift runtime DLLs into
`addons/swift_godot_extension/bin/x86_64-unknown-windows-msvc/debug/`. They live next to your Swift toolchain (`Get-Command swift` →
`...\Swift\Runtimes\<version>\usr\bin`). See the
[SwiftGodot Windows docs](https://migueldeicaza.github.io/SwiftGodotDocs/documentation/swiftgodot/windows).

## License

MIT — see [LICENSE](LICENSE).
