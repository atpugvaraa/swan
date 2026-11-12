# Swan - Swift on Android Tooling

`swift android <verb>`: Android as a keyword in the normal Swift workflow. No separate CLI to learn;
the `swift` driver runs `swift-android` from the toolchain's `usr/bin`, like it does `swift-build`.

## Install

Needs a swift.org toolchain and the matching [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).

```bash
swift run swift-android install
```

That symlinks the built tool into the active toolchain. Repeat after installing a new toolchain.

## Use

```bash
swift android build                      # cross-compile the package for Android
swift android build --product MyLib -c release --static-swift-stdlib
swift android run hello arg1 arg2        # build, push to the attached device/emulator, run
```

`build` passes every other option to `swift build`. `run` picks the device's architecture, pushes the
executable, its `.so` products, `libc++_shared.so` and (unless `--static-swift-stdlib`) the Swift
runtime to `/data/local/tmp/swift-android/`, and exits with the program's status.

## Not yet

- Apps (`.apk`/`.aar`), `jextract` bindings, `adb install`: `run` handles command-line executables only.
- Subclassing Java classes from Swift.
