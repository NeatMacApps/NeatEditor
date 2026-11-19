import Foundation
import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

private actor MockFileAssociationService: FileAssociationManaging {
    private var statuses: [DefaultFileType: DefaultFileTypeStatus]
    private var errorsByType: [DefaultFileType: any Error] = [:]
    private var postApplyStatuses: [DefaultFileType: DefaultFileTypeStatus] = [:]
    private(set) var appliedTypes: [DefaultFileType] = []

    init(statuses: [DefaultFileType: DefaultFileTypeStatus]) {
        self.statuses = statuses
    }

    func setError(_ error: (any Error)?, for fileType: DefaultFileType) {
        errorsByType[fileType] = error
    }

    func setPostApplyStatus(_ status: DefaultFileTypeStatus?, for fileType: DefaultFileType) {
        postApplyStatuses[fileType] = status
    }

    func fetchStatuses(for types: [DefaultFileType]) async -> [DefaultFileType: DefaultFileTypeStatus] {
        var result: [DefaultFileType: DefaultFileTypeStatus] = [:]
        for type in types {
            if let status = statuses[type] {
                result[type] = status
            }
        }
        return result
    }

    func setDefaultApplication(for fileType: DefaultFileType) async throws {
        appliedTypes.append(fileType)
        if let error = errorsByType[fileType] {
            throw error
        }
        if let overrideStatus = postApplyStatuses[fileType] {
            statuses[fileType] = overrideStatus
        } else {
            statuses[fileType] = DefaultFileTypeStatus(
                fileType: fileType,
                currentApplicationURL: URL(fileURLWithPath: "/Applications/NeatEditor.app"),
                currentApplicationName: "NeatEditor",
                isCurrentAppDefault: true
            )
        }
    }
}

@MainActor
struct DefaultFileAssociationTests {
    private static func status(
        _ fileType: DefaultFileType,
        appName: String?,
        isDefault: Bool
    ) -> DefaultFileTypeStatus {
        DefaultFileTypeStatus(
            fileType: fileType,
            currentApplicationURL: appName.map { URL(fileURLWithPath: "/Applications/\($0).app") },
            currentApplicationName: appName,
            isCurrentAppDefault: isDefault
        )
    }

    private static func makeWorkspace(
        service: MockFileAssociationService,
        defaults: UserDefaults? = nil,
        enablesAutomaticDefaultAppPrompts: Bool = true,
        launchDefaultAppPromptDelay: Duration = .zero
    ) throws -> (WorkspaceStore, URL, UserDefaults, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorDefaultAppTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "NeatEditorDefaultAppTests-\(UUID())"
        let resolvedDefaults = try defaults ?? #require(UserDefaults(suiteName: suite))
        if defaults == nil {
            let state = WorkspaceStore.WorkspaceState(
                tabs: [],
                selectedFileURL: nil,
                isSettingsSelected: false,
                preferences: WorkspacePreferences()
            )
            resolvedDefaults.set(
                try JSONEncoder().encode(state),
                forKey: WorkspaceStore.UserDefaultsKey.workspaceState
            )
        }
        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: resolvedDefaults,
            fileAssociationService: service,
            enablesAutomaticDefaultAppPrompts: enablesAutomaticDefaultAppPrompts,
            launchDefaultAppPromptDelay: launchDefaultAppPromptDelay
        )
        return (store, directory, resolvedDefaults, suite)
    }

    private static func cleanUp(
        _ store: WorkspaceStore,
        directory: URL,
        defaults: UserDefaults,
        suite: String,
        clearDefaults: Bool = true
    ) {
        store.pendingSaveStateTask?.cancel()
        store.pendingAdaptiveFontTask?.cancel()
        store.pendingDefaultAppTask?.cancel()
        store.pendingAdaptiveFontSample = nil
        if clearDefaults {
            defaults.removePersistentDomain(forName: suite)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("file type matching covers txt, text, extensionless files, and markdown only")
    func fileTypeMatching() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorMatchTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let extensionlessFile = tempDir.appendingPathComponent("README")
        try "hello".write(to: extensionlessFile, atomically: true, encoding: .utf8)

        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/note.txt")) == .plainText)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/NOTE.TXT")) == .plainText)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/note.text")) == .plainText)
        #expect(DefaultFileType.match(for: extensionlessFile) == .plainText)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/LICENSE")) == .plainText)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/readme.md")) == .markdown)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/guide.MARKDOWN")) == .markdown)

        #expect(DefaultFileType.match(for: tempDir) == nil)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/folder/", isDirectory: true)) == nil)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/data.json")) == nil)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/image.png")) == nil)
        #expect(DefaultFileType.match(for: URL(fileURLWithPath: "/tmp/notes.rtf")) == nil)
        #expect(DefaultFileType.match(for: URL(string: "https://example.com/a.txt")!) == nil)
    }

    @Test("bundle display name and current-application matching handle app extensions and bundle IDs")
    func systemServiceHelpers() {
        #expect(
            SystemFileAssociationService.displayName(
                for: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            ) == "TextEdit"
        )
        #expect(
            SystemFileAssociationService.displayName(
                for: URL(fileURLWithPath: "/Applications/Typora")
            ) == "Typora"
        )

        let derivedApp = URL(fileURLWithPath: "/tmp/DerivedData/NeatEditor.app")
        let installedApp = URL(fileURLWithPath: "/Applications/NeatEditor.app")
        #expect(
            SystemFileAssociationService.isCurrentApplication(
                handlerURL: installedApp,
                applicationURL: derivedApp,
                bundleIdentifier: "com.x0c.NeatEditor",
                handlerBundleIdentifier: { _ in "com.x0c.NeatEditor" }
            )
        )
        #expect(
            !SystemFileAssociationService.isCurrentApplication(
                handlerURL: URL(fileURLWithPath: "/Applications/Typora.app"),
                applicationURL: installedApp,
                bundleIdentifier: "com.x0c.NeatEditor",
                handlerBundleIdentifier: { _ in "abnerworks.Typora" }
            )
        )
    }

    @Test("startup prompt appears once when plain text is unassigned and respects Not Now / Don't Ask Again")
    func startupPromptLifecycle() async throws {
        let initialStatuses: [DefaultFileType: DefaultFileTypeStatus] = [
            .plainText: Self.status(.plainText, appName: "TextEdit", isDefault: false),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ]
        let service = MockFileAssociationService(statuses: initialStatuses)
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        await store.evaluateDefaultAppPromptOnLaunch()

        let prompt = try #require(store.defaultAppPrompt)
        #expect(prompt.trigger == .startup)
        #expect(prompt.selectedTypes == [.plainText])
        #expect(prompt.showsDontAskAgain)

        // "Not Now" suppresses repeat startup prompts across relaunches.
        store.dismissDefaultAppPrompt(suppressFuturePrompts: false)
        #expect(store.defaultAppPrompt == nil)

        let (relaunchStore, relaunchDir, _, _) = try Self.makeWorkspace(
            service: service,
            defaults: defaults
        )
        defer { Self.cleanUp(relaunchStore, directory: relaunchDir, defaults: defaults, suite: suite, clearDefaults: false) }
        await relaunchStore.evaluateDefaultAppPromptOnLaunch()
        #expect(relaunchStore.defaultAppPrompt == nil)

        // But an external .md open still prompts once until dismissed or suppressed globally.
        let mdURL = relaunchDir.appendingPathComponent("note.md")
        try "# Hi".write(to: mdURL, atomically: true, encoding: .utf8)
        relaunchStore.openFiles(at: [mdURL], source: .external)
        await relaunchStore.pendingDefaultAppTask?.value

        let externalPrompt = try #require(relaunchStore.defaultAppPrompt)
        #expect(externalPrompt.trigger == .externalOpen([.markdown]))
        #expect(externalPrompt.selectedTypes == [.markdown])

        // "Don't Ask Again" suppresses all future automatic prompts.
        relaunchStore.dismissDefaultAppPrompt(suppressFuturePrompts: true)
        let txtURL = relaunchDir.appendingPathComponent("note.txt")
        try "hello".write(to: txtURL, atomically: true, encoding: .utf8)
        relaunchStore.openFiles(at: [txtURL], source: .external)
        await relaunchStore.pendingDefaultAppTask?.value
        #expect(relaunchStore.defaultAppPrompt == nil)
    }

    @Test("startup does not prompt when plain text is already handled by NeatEditor")
    func startupSkipsPromptWhenPlainTextIsDefault() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        await store.evaluateDefaultAppPromptOnLaunch()

        #expect(store.defaultAppPrompt == nil)
        #expect(defaults.bool(forKey: WorkspaceStore.UserDefaultsKey.hasHandledStartupDefaultAppPrompt))
    }

    @Test("internal file opens never trigger automatic prompts; external opens prompt once per type")
    func externalVsInternalOpenPrompting() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        await store.evaluateDefaultAppPromptOnLaunch()
        #expect(store.defaultAppPrompt == nil)

        let mdURL = directory.appendingPathComponent("readme.md")
        try "# Doc".write(to: mdURL, atomically: true, encoding: .utf8)

        store.openFiles(at: [mdURL], source: .internal)
        await store.pendingDefaultAppTask?.value
        #expect(store.defaultAppPrompt == nil)

        store.openFiles(at: [mdURL], source: .external)
        await store.pendingDefaultAppTask?.value
        let prompt = try #require(store.defaultAppPrompt)
        #expect(prompt.trigger == .externalOpen([.markdown]))
        #expect(prompt.selectedTypes == [.markdown])

        // Dismissing with "Not Now" remembers .markdown so reopening externally does not nag again.
        store.dismissDefaultAppPrompt(suppressFuturePrompts: false)
        let secondMD = directory.appendingPathComponent("other.markdown")
        try "# Other".write(to: secondMD, atomically: true, encoding: .utf8)
        store.openFiles(at: [secondMD], source: .external)
        await store.pendingDefaultAppTask?.value
        #expect(store.defaultAppPrompt == nil)
    }

    @Test("cold launch queued external file avoids double prompt and failure alerts suppress interruption")
    func coldLaunchQueuedExternalAndFailureAlertGuard() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "TextEdit", isDefault: false),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        let mdURL = directory.appendingPathComponent("launch.md")
        try "# Launch".write(to: mdURL, atomically: true, encoding: .utf8)

        store.openFiles(at: [mdURL], source: .external)
        await store.evaluateDefaultAppPromptOnLaunch()

        let prompt = try #require(store.defaultAppPrompt)
        #expect(prompt.trigger == .externalOpen([.markdown]))
        #expect(prompt.selectedTypes == [.markdown])

        // Active failure alert suppresses automatic prompts.
        let (alertStore, alertDir, alertDefaults, alertSuite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(alertStore, directory: alertDir, defaults: alertDefaults, suite: alertSuite) }
        alertStore.presentDocumentFailure(title: "Save Failed", message: "Disk error")
        await alertStore.evaluateDefaultAppPromptOnLaunch()
        #expect(alertStore.defaultAppPrompt == nil)
    }

    @Test("apply flow skips already-default types and handles success, user Keep, and errors")
    func applyFlowStates() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        // User declines system confirmation ("Keep Typora"): unchanged handler stays open with guidance.
        await service.setError(CocoaError(.userCancelled), for: .markdown)
        store.presentDefaultAppSettingsSheet()
        await store.pendingDefaultAppTask?.value

        var sheet = try #require(store.defaultAppPrompt)
        #expect(sheet.trigger == .settings)
        #expect(sheet.selectedTypes == [.markdown])

        await store.applySelectedDefaultAppTypes()
        #expect(await service.appliedTypes == [.markdown])
        sheet = try #require(store.defaultAppPrompt)
        #expect(!sheet.isApplying)
        #expect(!sheet.isErrorFeedback)
        #expect(sheet.feedbackMessage == String(localized: "defaultApp.feedback.confirmationRequired"))
        #expect(sheet.selectedTypes == [.markdown])

        // System error surfaces inline error feedback.
        await service.setError(
            NSError(domain: NSOSStatusErrorDomain, code: -54, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]),
            for: .markdown
        )
        await store.applySelectedDefaultAppTypes()
        sheet = try #require(store.defaultAppPrompt)
        #expect(sheet.isErrorFeedback)
        #expect(sheet.feedbackMessage == "Permission denied")

        // User confirms in system dialog: sheet auto-dismisses and summary updates.
        await service.setError(nil, for: .markdown)
        await store.applySelectedDefaultAppTypes()
        #expect(store.defaultAppPrompt == nil)
        #expect(store.defaultFileTypesSummary == String(localized: "settings.defaultApp.summary.all"))
    }

    @Test("SettingsView with restart notice fits inside minimum content height and leaves open theme area at 650 pt")
    func settingsLayoutFitsMinimumHeight() throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        store.defaultFileTypeStatuses = [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ]
        store.isLanguageChangePendingRestart = true

        let host = NSHostingView(rootView: SettingsView().environment(store))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: SettingsView.minimumContentHeight)
        host.layoutSubtreeIfNeeded()

        let fitting = host.fittingSize
        #expect(fitting.height <= SettingsView.minimumContentHeight)
        #expect(fitting.height < 610)
    }

    @Test("DefaultAppRegistrationSheet lays out cleanly across prompt modes and appearances",
          arguments: [NSAppearance.Name.aqua, .darkAqua])
    func registrationSheetLayout(appearanceName: NSAppearance.Name) throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "TextEdit", isDefault: false),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        let statuses: [DefaultFileType: DefaultFileTypeStatus] = [
            .plainText: Self.status(.plainText, appName: "NeatEditor", isDefault: true),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ]

        for trigger in [
            DefaultAppPromptState.Trigger.startup,
            .externalOpen([.markdown]),
            .settings,
        ] {
            store.defaultAppPrompt = DefaultAppPromptState(
                trigger: trigger,
                statuses: statuses,
                selectedTypes: [.markdown],
                feedbackMessage: String(localized: "defaultApp.feedback.confirmationRequired"),
                isErrorFeedback: false
            )
            let host = NSHostingView(rootView: DefaultAppRegistrationSheet().environment(store))
            host.appearance = NSAppearance(named: appearanceName)
            host.frame = CGRect(x: 0, y: 0, width: 440, height: 360)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            #expect(size.width == 440)
            #expect(size.height > 120 && size.height < 420)
        }
    }

    @Test("external open arriving during launch delay wins over startup prompt")
    func externalOpenArrivingDuringLaunchDelayWinsOverStartup() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "TextEdit", isDefault: false),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(
            service: service,
            launchDefaultAppPromptDelay: .milliseconds(80)
        )
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        let mdURL = directory.appendingPathComponent("launch-doc.md")
        try "# Doc".write(to: mdURL, atomically: true, encoding: .utf8)

        let launchTask = Task {
            await store.evaluateDefaultAppPromptOnLaunch()
        }
        try await Task.sleep(for: .milliseconds(15))
        store.openFiles(at: [mdURL], source: .external)
        await launchTask.value

        let prompt = try #require(store.defaultAppPrompt)
        #expect(prompt.trigger == .externalOpen([.markdown]))
        #expect(prompt.selectedTypes == [.markdown])
    }

    @Test("late external open upgrades untouched startup prompt in place and respects user edits")
    func lateExternalOpenUpgradesUntouchedStartupPromptInPlaceAndRespectsUserEdits() async throws {
        let service = MockFileAssociationService(statuses: [
            .plainText: Self.status(.plainText, appName: "TextEdit", isDefault: false),
            .markdown: Self.status(.markdown, appName: "Typora", isDefault: false),
        ])
        let (store, directory, defaults, suite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(store, directory: directory, defaults: defaults, suite: suite) }

        await store.evaluateDefaultAppPromptOnLaunch()
        let initialPrompt = try #require(store.defaultAppPrompt)
        #expect(initialPrompt.trigger == .startup)
        #expect(initialPrompt.selectedTypes == [.plainText])

        let mdURL = directory.appendingPathComponent("late.md")
        try "# Late".write(to: mdURL, atomically: true, encoding: .utf8)
        store.openFiles(at: [mdURL], source: .external)
        await store.pendingDefaultAppTask?.value

        let upgraded = try #require(store.defaultAppPrompt)
        #expect(upgraded.id == initialPrompt.id)
        #expect(upgraded.trigger == .externalOpen([.markdown]))
        #expect(upgraded.selectedTypes == [.markdown])

        // Once the user modifies selection on a startup sheet, a late external open must not overwrite it.
        let (editedStore, editedDir, editedDefaults, editedSuite) = try Self.makeWorkspace(service: service)
        defer { Self.cleanUp(editedStore, directory: editedDir, defaults: editedDefaults, suite: editedSuite) }

        await editedStore.evaluateDefaultAppPromptOnLaunch()
        editedStore.setDefaultFileTypeSelected(false, for: .plainText)
        let secondMD = editedDir.appendingPathComponent("second.md")
        try "# Second".write(to: secondMD, atomically: true, encoding: .utf8)
        editedStore.openFiles(at: [secondMD], source: .external)
        await editedStore.pendingDefaultAppTask?.value

        let retained = try #require(editedStore.defaultAppPrompt)
        #expect(retained.trigger == .startup)
        #expect(retained.selectedTypes.isEmpty)
    }
}
