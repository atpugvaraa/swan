import Testing
@testable import swift_android

@Test func runSplitsBuildOptionsProductAndProgramArguments() throws {
    let invocation = try Invocation(
        ["--arch", "x86_64", "-c", "release", "--static-swift-stdlib", "probe", "search", "--api", "-c"],
        takesProduct: true
    )
    #expect(invocation.arch == "x86_64")
    #expect(invocation.api == "28")
    #expect(invocation.buildArguments == ["-c", "release", "--static-swift-stdlib"])
    #expect(invocation.product == "probe")
    // After the product, even words that look like our options belong to the program.
    #expect(invocation.programArguments == ["search", "--api", "-c"])
}

@Test func buildPassesBareWordsThrough() throws {
    let invocation = try Invocation(["--api", "31", "--product", "CisumBridge"], takesProduct: false)
    #expect(invocation.api == "31")
    #expect(invocation.product == nil)
    #expect(invocation.buildArguments == ["--product", "CisumBridge"])
}

@Test func missingValueFails() {
    #expect(throws: Failure.self) { try Invocation(["--arch"], takesProduct: false) }
}

@Test func findsSwiftSubclassesOfJavaClasses() throws {
    let wrappers = javaWrappers(in: """
        @JavaClass("android.app.Activity")
        open class Activity: Context {}
        @JavaClass("android.os.Bundle") open class Bundle: JavaObject {}
        """)
    #expect(wrappers == ["Activity": "android.app.Activity", "Bundle": "android.os.Bundle"])

    let found = javaSubclasses(in: """
        final class MainActivity: Activity {
            var taps = 0
            override func onCreate(_ state: Bundle?) {
                super.onCreate(state)
                if taps > 0 { taps = 0 }
            }
            override func onKeyDown(_ code: Int32, _ event: Bundle?) -> Bool { true }
            func helper() {}
        }
        class Plain: Other { override func f() {} }
        """, wrappers: wrappers)
    #expect(found == [
        JavaSubclass(name: "MainActivity", superclass: "Activity", methods: [
            .init(name: "onCreate", parameters: ["Bundle?"], result: nil),
            .init(name: "onKeyDown", parameters: ["Int32", "Bundle?"], result: "Bool"),
        ])
    ])

    let java = try javaStub(found[0], package: "app", library: "App", wrappers: wrappers)
    #expect(java.contains("public class MainActivity extends android.app.Activity"))
    #expect(java.contains("public boolean onKeyDown(int a0, android.os.Bundle a1)"))
    #expect(java.contains("if (swanIn1) { return super.onKeyDown(a0, a1); }"))
    #expect(swiftThunks(found, package: "my_app").contains(#"@_cdecl("Java_my_1app_MainActivity_swan0")"#))
}
