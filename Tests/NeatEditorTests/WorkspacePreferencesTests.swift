import Foundation
import Testing

@testable import NeatEditor

/// Font-size preference tests: stepping clamps at both ends, per-file memory
/// only tracks real files, and unknown files fall back to the default size.
struct WorkspacePreferencesTests {
    @Test("stepping clamps at the minimum and maximum sizes")
    func steppingClamps() {
        var preferences = WorkspacePreferences(editorFontSize: 13)

        while preferences.stepEditorFontSize(by: -1, rememberingFor: nil) {}
        #expect(preferences.editorFontSize == 10)

        while preferences.stepEditorFontSize(by: 1, rememberingFor: nil) {}
        #expect(preferences.editorFontSize == 36)

        let steppedPastMax = preferences.stepEditorFontSize(by: 1, rememberingFor: nil)
        #expect(!steppedPastMax)
        let steppedFarPastMin = preferences.stepEditorFontSize(by: -100, rememberingFor: URL(fileURLWithPath: "/tmp/x"))
        #expect(steppedFarPastMin)
    }

    @Test("stepping without a file does not grow the remembered table")
    func steppingWithoutFileRemembersNothing() {
        var preferences = WorkspacePreferences(editorFontSize: 13)

        _ = preferences.stepEditorFontSize(by: 2, rememberingFor: nil)

        #expect(preferences.editorFontSize == 15)
        #expect(preferences.rememberedEditorFontSizes.isEmpty)
    }

    @Test("unknown files fall back to the default size")
    func unknownFileFallsBackToDefault() {
        var preferences = WorkspacePreferences()
        let unknown = URL(fileURLWithPath: "/tmp/never-seen-\(UUID().uuidString).txt")

        preferences.applyRememberedEditorFontSize(for: unknown)

        #expect(preferences.editorFontSize == WorkspacePreferences.defaultEditorFontSize)
    }

    @Test("remembered size follows the file across save and reselect")
    func rememberedSizeRoundTrip() {
        var preferences = WorkspacePreferences()
        let file = URL(fileURLWithPath: "/tmp/note-\(UUID().uuidString).txt")

        _ = preferences.stepEditorFontSize(by: 5, rememberingFor: file)
        preferences.applyRememberedEditorFontSize(for: nil)
        preferences.applyRememberedEditorFontSize(for: file)

        #expect(preferences.editorFontSize == WorkspacePreferences.defaultEditorFontSize + 5)
    }

    @Test("out-of-range decoded sizes are clamped")
    func decodedSizesClamped() throws {
        let data = try JSONEncoder().encode(
            WorkspacePreferences(editorFontSize: 999, tabBehavior: .spaces2)
        )
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: data)

        #expect(decoded.editorFontSize == 36)
    }
}
