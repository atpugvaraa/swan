# What `swift android` does, by hand

Every verb is a short list of ordinary commands. Run them yourself to check any step.
The code is in `Sources/swift-android/`; each section names the file.

Set these once (your versions may differ):

```bash
SDK=swift-6.4.2-RELEASE_android                     # swift sdk list
TRIPLE=aarch64-unknown-linux-android28              # <arch>-unknown-linux-android<api>
TOOLS=~/Library/Android/sdk/build-tools/37.0.0      # newest directory in build-tools
JAR=~/Library/Android/sdk/platforms/android-36.1/android.jar
```

## 0. Why `swift android` exists at all

`swift foo` runs a program named `swift-foo` from the toolchain's `usr/bin`. Nothing else.

```bash
swift -print-target-info | grep runtimeResourcePath   # <toolchain>/usr/lib/swift
ls <toolchain>/usr/bin | grep '^swift-'               # swift-build, swift-sdk, ..., swift-android
ls -l <toolchain>/usr/bin/swift-android               # a symlink into this repo's .build
```

`swift android install` makes that symlink (`install()` in `SwiftAndroid.swift`).

## 1. `swift android build`

`build()` in `SwiftAndroid.swift`. One command:

```bash
swift sdk list                                        # finds $SDK: the line containing "android"
swift build --swift-sdk $SDK --triple $TRIPLE         # plus whatever options you passed
```

## 2. `swift android run <executable>`

`runOnDevice()` in `SwiftAndroid.swift`.

```bash
adb get-state                                         # must print "device"
adb shell getprop ro.product.cpu.abi                  # arm64-v8a → aarch64
swift build --swift-sdk $SDK --triple $TRIPLE --product hello
swift build --swift-sdk $SDK --triple $TRIPLE --product hello --show-bin-path    # → $BIN
swift sdk configure --show-configuration $SDK $TRIPLE # sdkRootPath, swiftResourcesPath

adb shell mkdir -p /data/local/tmp/swift-android/hello
adb push --sync <swiftResourcesPath>/android/*.so /data/local/tmp/swift-android/runtime-$SDK-aarch64
adb push --sync $BIN/hello <sdkRootPath>/usr/lib/aarch64-linux-android/libc++_shared.so \
    /data/local/tmp/swift-android/hello
adb shell 'cd /data/local/tmp/swift-android/hello && LD_LIBRARY_PATH=.:../runtime-'$SDK'-aarch64 ./hello'
```

With `--static-swift-stdlib` the runtime push is skipped.

## 3. `swift android run <library>`: an APK with no Gradle

`runApp()` and `compileJava()` in `App.swift`. An APK is a zip: a compiled manifest, `classes.dex`,
and `lib/<abi>/*.so`.

```bash
S=$BIN/HelloActivity.apk-stage; mkdir -p $S/lib/arm64-v8a
cp $BIN/*.so <libc++_shared.so> <swift runtime .so files> $S/lib/arm64-v8a/

# Java → .class → .dex. Sources: Android/java, the generated subclasses, jextract's bindings.
find . -name '*.java' -path '*swan-java*'             # what SwiftAndroidPlugin generated
javac --release 17 -classpath $JAR -d $S/classes <all .java files>
$TOOLS/d8 --lib $JAR --min-api 28 --output $S $(find $S/classes -name '*.class')

# Manifest (and res/) → an APK with no code in it yet.
$TOOLS/aapt2 link -o $S/unaligned.apk --manifest Android/AndroidManifest.xml -I $JAR \
    --min-sdk-version 28 --target-sdk-version 28

# Add the code, align, sign with the debug key, install, launch.
(cd $S && zip -q -r -0 unaligned.apk lib classes.dex)
$TOOLS/zipalign -f -P 16 4 $S/unaligned.apk $BIN/HelloActivity.apk
$TOOLS/apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android $BIN/HelloActivity.apk
adb install -r $BIN/HelloActivity.apk
adb shell monkey -p swan.helloactivity -c android.intent.category.LAUNCHER 1
```

Check the result:

```bash
unzip -l $BIN/HelloActivity.apk | head -40
$TOOLS/aapt2 dump badging $BIN/HelloActivity.apk | head -5
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml | grep -o 'text="[^"]*"'
adb logcat --pid=$(adb shell pidof swan.helloactivity)
```

## 4. A Swift subclass of a Java class

`Subclasses.swift`, run by `Plugins/SwiftAndroidPlugin` during `swift build`. See what it wrote:

```bash
cd Examples/HelloActivity
swift android build --product HelloActivity
find .build/plugins/outputs -path '*SwiftAndroidPlugin*' -type f
```

- `swan-java/helloactivity/MainActivity.java`: the real Java subclass. Each override calls a
  `native` method; a `long swanPeer` field holds the Swift object.
- `SwanSubclasses.swift`: one `@_cdecl("Java_helloactivity_MainActivity_swan0")` function per
  override. It finds the Swift object and calls your method.

Run the generator directly:

```bash
swift-android generate --module HelloActivity --library HelloActivity --output /tmp/out \
    --wrappers ../../Sources/AndroidKit --sources Sources/HelloActivity/MainActivity.swift
```

Confirm the JNI symbols are in the library:

```bash
nm -D --defined-only $BIN/libHelloActivity.so | grep Java_
```

The runtime side is `Sources/Swan/Peer.swift` (Swift object ↔ Java object) and
`Sources/Swan/Proxy.swift` (Swift closure as a Java interface, through `java.lang.reflect.Proxy`).

## 5. `swift android wrap`

`Wrap.swift`. It runs swift-java's own generator:

```bash
swift build --package-path .build/checkouts/swift-java --product swift-java
<bin>/swift-java wrap-java --swift-module AndroidKit --config Sources/AndroidKit/swift-java.config \
    --depends-on SwiftJava=.build/checkouts/swift-java/Sources/SwiftJava/swift-java.config \
    -o Sources/AndroidKit/Generated --cp $JAR
```

One `--cp` per jar. The lines it prints with "has not been translated" are the skipped methods.

## 6. `swift android aar`

`aar()` in `App.swift`. An AAR is a zip a Gradle app depends on.

```bash
swift build --swift-sdk $SDK --triple $TRIPLE --product CisumBridge -c release --static-swift-stdlib
S=$BIN/CisumBridge.aar-stage; mkdir -p $S/jni/arm64-v8a $S/classes
<ndk>/toolchains/llvm/prebuilt/*/bin/llvm-strip -o $S/jni/arm64-v8a/libCisumBridge.so $BIN/libCisumBridge.so
cp <libc++_shared.so> $S/jni/arm64-v8a/
jar --create --file $S/classes.jar -C $S/classes .    # compiled Java, or empty
# AndroidManifest.xml: Android/AndroidManifest.xml, or a generated one naming the package
touch $S/R.txt
(cd $S && zip -q -r $BIN/CisumBridge.aar .)
```

Check it, and use it:

```bash
unzip -l $BIN/CisumBridge.aar
```

```kotlin
dependencies { implementation(files("libs/CisumBridge.aar")) }
```

## 7. The Minecraft mod

No `swift android` verb: the mod runs on a desktop JVM, so Gradle does the packaging.

```bash
cd ~/Programming/Kotlin/Mods/ASkyblockMod/swift
swift build --disable-sandbox                         # runs SwiftAndroidPlugin: asmcore/AsmScreen.java
cd .. && JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home \
    ASM_AUTO_SCREEN=1 ./gradlew runClient
```

`build.gradle` adds the plugin's `swan-java` directory to the client source set, and
`-Djava.library.path` points at `swift/.build/out/Products/Debug`.
