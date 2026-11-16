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

    @Test("old snapshots without the learner decode to the cold start")
    func oldSnapshotDecodesToColdStartLearner() throws {
        let encoded = try JSONEncoder().encode(
            WorkspacePreferences(editorFontSize: 14, adaptiveEditorFontSizeLearner: AdaptiveFontSizeLearner(estimate: 22, evidence: 9))
        )
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "adaptiveEditorFontSizeLearner")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: data)

        #expect(decoded.adaptiveEditorFontSizeLearner.estimate == 13)
        #expect(decoded.adaptiveEditorFontSizeLearner.evidence == 4)
        #expect(decoded.editorFontSize == 14)
    }

    @Test("invalid learner values are repaired without discarding other preferences")
    func invalidLearnerPreservesOtherPreferences() throws {
        let encoded = try JSONEncoder().encode(
            WorkspacePreferences(
                editorFontSize: 18,
                adaptiveEditorFontSizeLearner: AdaptiveFontSizeLearner(estimate: 22, evidence: 9),
                isSidebarVisible: false
            )
        )
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["adaptiveEditorFontSizeLearner"] = ["estimate": 999, "evidence": 0]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: data)

        #expect(decoded.adaptiveEditorFontSizeLearner.estimate == 36)
        #expect(decoded.adaptiveEditorFontSizeLearner.evidence == 4)
        #expect(decoded.editorFontSize == 18)
        #expect(decoded.isSidebarVisible == false)
    }

    @Test("remembered size > adaptive default > unknown-existing baseline")
    func fontSizePriority() {
        var preferences = WorkspacePreferences(
            adaptiveEditorFontSizeLearner: AdaptiveFontSizeLearner(estimate: 20, evidence: 8)
        )

        preferences.applyRememberedEditorFontSize(for: nil)
        #expect(preferences.editorFontSize == 20)

        let unknown = URL(fileURLWithPath: "/tmp/unknown-\(UUID().uuidString).txt")
        preferences.applyRememberedEditorFontSize(for: unknown)
        #expect(preferences.editorFontSize == WorkspacePreferences.defaultEditorFontSize)

        let remembered = URL(fileURLWithPath: "/tmp/remembered-\(UUID().uuidString).txt")
        preferences.editorFontSize = 13
        _ = preferences.stepEditorFontSize(by: 12, rememberingFor: remembered)
        preferences.applyRememberedEditorFontSize(for: nil)
        #expect(preferences.editorFontSize == 20)
        preferences.applyRememberedEditorFontSize(for: remembered)
        #expect(preferences.editorFontSize == 25)
    }

    @Test("learning never rewrites the current size or the per-file memory")
    func learningIsIsolated() {
        var preferences = WorkspacePreferences(editorFontSize: 17)

        preferences.learnAdaptiveEditorFontSize(30)

        #expect(preferences.editorFontSize == 17)
        #expect(preferences.rememberedEditorFontSizes.isEmpty)
        #expect(abs(preferences.adaptiveEditorFontSizeLearner.estimate - (13 + (30 - 13) / 5.0)) < 0.000_001)
    }
}
