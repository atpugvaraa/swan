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
