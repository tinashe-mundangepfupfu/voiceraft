import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws -> Bool {
    if !condition() {
        throw CheckFailure(description: message)
    }
    return true
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

@main
struct ReleasePipelineCheck {
    static func main() {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let workflowPath = repoRoot.appendingPathComponent(".github/workflows/release.yml").path
        let buildScriptPath = repoRoot.appendingPathComponent("scripts/build-release-dmg.sh").path
        let signScriptPath = repoRoot.appendingPathComponent("scripts/sign-and-notarize.sh").path
        let licensePath = repoRoot.appendingPathComponent("LICENSE").path
        let readmePath = repoRoot.appendingPathComponent("README.md").path

        do {
            let workflow = try read(workflowPath)
            let buildScript = try read(buildScriptPath)
            let signScript = try read(signScriptPath)
            let license = try read(licensePath)
            let readme = try read(readmePath)

            try assert(workflow.contains("push:"), "release workflow should trigger on pushes")
            try assert(workflow.contains("'v*.*.*'"), "release workflow should listen for semver tags")
            try assert(workflow.contains("scripts/build-release-dmg.sh"), "workflow should call build-release-dmg.sh")
            try assert(workflow.contains("scripts/sign-and-notarize.sh"), "workflow should call sign-and-notarize.sh")
            try assert(workflow.contains("gh release"), "workflow should create or upload a GitHub Release")

            try assert(buildScript.contains("xcodebuild"), "build script should use xcodebuild")
            try assert(buildScript.contains("hdiutil"), "build script should create a dmg with hdiutil")
            try assert(buildScript.contains("VoiceRaft-v"), "build script should produce semver-named dmg output")

            try assert(signScript.contains("codesign"), "sign script should sign artifacts with codesign")
            try assert(signScript.contains("notarytool"), "sign script should use notarytool when secrets are present")
            try assert(signScript.contains("Skipping signing"), "sign script should support unsigned operation")

            try assert(license.contains("MIT License"), "repo should include an MIT License")

            try assert(readme.contains("## Releases"), "README should document release flow")
            try assert(readme.contains("v1.2.3"), "README should document semver release tags")
            try assert(readme.contains(".dmg"), "README should mention DMG packaging")
            try assert(readme.contains("Developer ID"), "README should mention optional Developer ID signing")

            print("release pipeline check passed")
        } catch {
            fputs("release pipeline check failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
