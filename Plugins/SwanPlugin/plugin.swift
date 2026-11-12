import PackagePlugin

/// Lets a target subclass Java classes in Swift: runs `swift-android generate` over its sources
/// and compiles the JNI entry points it writes into the target.
@main
struct SwanPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SwiftSourceModuleTarget else { return [] }
        let sources = module.sourceFiles(withSuffix: "swift").map(\.url)
        // The @JavaClass wrappers the target can see live in its dependencies.
        let wrappers = target.recursiveTargetDependencies.map(\.directoryURL.path)
        // Java loads the library, so it needs the product's name, not the target's.
        let library = context.package.products(ofType: LibraryProduct.self)
            .first { $0.targets.contains { $0.id == target.id } }?.name ?? target.name
        let output = context.pluginWorkDirectoryURL
        return [
            .buildCommand(
                displayName: "Swan: Java subclasses in \(target.name)",
                executable: try context.tool(named: "swift-android").url,
                arguments: ["generate", "--module", module.moduleName, "--library", library, "--output", output.path,
                            "--wrappers"] + wrappers + ["--sources"] + sources.map(\.path),
                inputFiles: sources,
                outputFiles: [output.appending(path: "SwanSubclasses.swift")]
            )
        ]
    }
}
