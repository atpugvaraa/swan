# Swan - Swift on Android Tooling

`swift android <verb>`: Android as a keyword in the normal Swift workflow. There is no separate CLI
to learn; the `swift` driver runs `swift-android` from the toolchain's `usr/bin`, the same way it
runs `swift-build`. The Swift SDK for Android and swift-java are used as released.

```swift
import AndroidKit

final class MainActivity: Activity {
    var taps = 0

    override func onCreate(_ state: Bundle?) {
        super.onCreate(state)
        let button = Button(self)
        button.setText("Tap")
        button.onClick { [unowned self] _ in taps += 1 }
        setContentView(button)
    }
}
```

```bash
swift android run HelloActivity    # build, package an APK, install, launch
```

No Java, Kotlin or Gradle project. See [Examples/HelloActivity](Examples/HelloActivity).

Every verb is a short list of ordinary commands: [docs/BY-HAND.md](docs/BY-HAND.md) lists them, to run or check yourself.

## Install

Needs a swift.org toolchain, the matching [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html),
the Android SDK (`ANDROID_HOME`, or Android Studio's default location) and a JDK.

```bash
swift run swift-android install
```

That symlinks the built tool into the active toolchain. Repeat after installing a new toolchain.

## Verbs

| | |
|---|---|
| `swift android build` | Cross-compile the package. Other options go to `swift build`. |
| `swift android run <product> [args]` | An executable runs from the device's shell and returns its exit status. A dynamic library is packaged as an app, installed and launched. |
| `swift android aar <product>` | Package a dynamic library as `<product>.aar` for a Gradle app: `implementation(files("libs/<product>.aar"))`. `-c release` strips it. |
| `swift android wrap <target> [java.class …]` | Generate Swift wrappers for Java classes into `Sources/<target>/Generated`. |
| `swift android install` | Link the tool into the active toolchain. |

`--arch` (default: the attached device's) and `--api` (default 28) apply to `build` and `run`.

## An app

A package whose product is a dynamic library, with an `Android/` directory beside `Package.swift`:

```
Android/AndroidManifest.xml   required
Android/java/                 optional Java sources
Android/res/                  optional resources
```

`run` compiles Java with `javac` and `d8`, links the manifest with `aapt2`, adds the Swift libraries,
signs with the debug keystore, and uses `adb` to install and launch.

## Subclassing Java classes in Swift

Add the plugin to the target:

```swift
.target(
    name: "HelloActivity",
    dependencies: [.product(name: "AndroidKit", package: "swan")],
    swiftSettings: [.swiftLanguageMode(.v5)],
    plugins: [.plugin(name: "SwiftAndroidPlugin", package: "swan")]
)
```

A JVM only runs an override that exists in a Java class. For each Swift class that inherits from a
`@JavaClass` wrapper, the plugin writes a Java subclass whose overrides call into Swift, and the JNI
entry points for them. The Java class is named `<module, lowercased>.<Swift class>`; that is the
name the manifest uses. The Java object keeps its Swift object alive, so stored properties persist.

A Swift closure becomes a Java interface with `SomeInterface.implemented { method, arguments in … }`.

## Calling Swift from Java

Add swift-java's `JExtractSwiftPlugin` and a `swift-java.config` to a target, and its public Swift
API becomes Java classes. `swift android run` compiles those bindings, and the SwiftKit classes
they need, straight into the APK: nothing is published to Maven and there is no Gradle plugin.
See [Examples/HelloExtract](Examples/HelloExtract).

## Wrapping more of Android, or any jar

```bash
swift android wrap AndroidKit android.widget.Toast android.net.Uri
swift android wrap FabricKit --cp minecraft.jar:brigadier.jar net.minecraft.client.gui.screens.Screen
```

## Not only Android

The generator and the `Swan` library have no Android in them. A Fabric mod uses the same plugin for
a Swift subclass of Minecraft's `Screen`, with Gradle compiling the generated Java from
`.build/plugins/outputs/<package>/<target>/destination/SwiftAndroidPlugin/swan-java`.

## Limits today

- Overrides are found with regular expressions: parameters that are closures, tuples or
  two-argument generics are not understood.
- A Swift subclass repeats the constructors its wrapper declares. swift-java 0.7.0 does not wrap
  protected constructors or generic methods, so those are declared by hand (see FabricKit).
- Abstract Java methods cannot be overridden yet (the generated Java calls `super`).
- A Swift object made for a Java object is never freed.
- The APK carries the whole Swift runtime uncompressed (about 125 MB) and one architecture.
- `print` goes nowhere in an app; there is no logcat bridge yet.
- Kotlin sources are not compiled (Java only): there is no `kotlinc` step.
- No AndroidManifest generation for apps, no release signing. An `.aar` holds one architecture.
