import Foundation
import Testing

/// Apple's required-reason APIs: App Store Connect rejects an upload that calls one without a reason in the privacy
/// manifest (ITMS-91053; issue #41). The app's own code (the app target and every package) is scanned for the APIs
/// Apple lists, and each category in use must be declared in `ios/App/PrivacyInfo.xcprivacy`. GRDB and SQLiteData
/// ship their own manifests.
@Suite("Privacy manifest")
struct PrivacyManifestTests {
    /// developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
    static let categories: [String: String] = [
        "NSPrivacyAccessedAPICategoryFileTimestamp":
            #"\b(creationDate|modificationDate|fileModificationDate|contentModificationDate|contentModificationDateKey|creationDateKey|getattrlist|getattrlistbulk|fgetattrlist|getattrlistat|fstatat|lstat|fstat|stat)\b\s*[(:,\]]|\.(creationDate|modificationDate|contentModificationDate)\b"#,
        "NSPrivacyAccessedAPICategorySystemBootTime": #"\b(systemUptime|mach_absolute_time)\b"#,
        "NSPrivacyAccessedAPICategoryDiskSpace":
            #"\b(volumeAvailableCapacity\w*|volumeTotalCapacity\w*|systemFreeSize|systemSize|statfs|statvfs|fstatfs|fstatvfs)\b"#,
        "NSPrivacyAccessedAPICategoryActiveKeyboards": #"\bactiveInputModes\b"#,
        "NSPrivacyAccessedAPICategoryUserDefaults": #"\b(UserDefaults|NSUserDefaults)\b|@AppStorage\b"#,
    ]

    static var ios: URL { Spec.root.deletingLastPathComponent().appending(path: "ios") }

    /// Every Swift source of the app target and the packages, comments removed.
    static func sources() throws -> [(name: String, code: String)] {
        var roots = [ios.appending(path: "App")]
        let packages = try FileManager.default.contentsOfDirectory(at: ios.appending(path: "Packages"),
                                                                   includingPropertiesForKeys: nil)
        roots += packages.map { $0.appending(path: "Sources") }
        return roots.flatMap { root -> [(name: String, code: String)] in
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
            return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.compactMap { file in
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line) }
                    .joined(separator: "\n")
                return (file.lastPathComponent, code)
            }
        }
    }

    static func declared() throws -> Set<String> {
        let data = try Data(contentsOf: ios.appending(path: "App/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return Set(types.compactMap { entry in
            guard let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String], !reasons.isEmpty else { return nil }
            return entry["NSPrivacyAccessedAPIType"] as? String
        })
    }

    @Test func everyRequiredReasonAPIWeCallIsDeclared() throws {
        let sources = try Self.sources()
        #expect(sources.count > 100, "found only \(sources.count) Swift files: the scan is broken")
        let declared = try Self.declared()
        for (category, pattern) in Self.categories {
            let regex = try Regex(pattern)
            let users = sources.filter { $0.code.contains(regex) }.map(\.name)
            #expect(users.isEmpty || declared.contains(category),
                    "\(users.sorted().joined(separator: ", ")) call \(category) APIs; declare a reason in PrivacyInfo.xcprivacy")
        }
    }

    @Test func theScanSeesTheCacheTrimming() throws {
        // PDFLibrary reads contentModificationDateKey (issue #41): the check must keep finding it.
        let regex = try Regex(try #require(Self.categories["NSPrivacyAccessedAPICategoryFileTimestamp"]))
        #expect(try Self.sources().contains { $0.name == "PDFLibrary.swift" && $0.code.contains(regex) })
    }
}
