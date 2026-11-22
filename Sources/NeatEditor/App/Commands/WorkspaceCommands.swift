import AppKit
import SwiftUI

struct WorkspaceCommands: Commands {
    let workspaceStore: WorkspaceStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                workspaceStore.createNewDocument()
            } label: {
                Label("New", systemImage: "doc")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                workspaceStore.createNewDocument()
            } label: {
                Label("New Tab", systemImage: "plus.square")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button {
                openDocumentsFromUserHome()
            } label: {
                Label("Open...", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                workspaceStore.openSettings()
            } label: {
                Label("Settings...", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button {
                workspaceStore.saveCurrentDocument()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button {
                workspaceStore.saveAndCloseCurrentDocument()
            } label: {
                Label("Close Tab", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(workspaceStore.selectedTabID == nil)

            Button {
                workspaceStore.reopenLastClosedDocument()
            } label: {
                Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!workspaceStore.canReopenClosedTab)
        }

        CommandGroup(after: .textEditing) {
            Button {
                workspaceStore.presentSearchBar()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspaceStore.selectedTabID == nil || workspaceStore.isSettingsSelected)

            Button {
                workspaceStore.findNextMatch()
            } label: {
                Label("Find Next", systemImage: "chevron.down")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(
                workspaceStore.selectedTabID == nil ||
                workspaceStore.isSettingsSelected ||
                !workspaceStore.searchState.canSubmit
            )

            Button {
                workspaceStore.findPreviousMatch()
            } label: {
                Label("Find Previous", systemImage: "chevron.up")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(
                workspaceStore.selectedTabID == nil ||
                workspaceStore.isSettingsSelected ||
                !workspaceStore.searchState.canSubmit
            )
        }

        CommandGroup(after: .toolbar) {
            Button {
                workspaceStore.increaseEditorFontSize()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button {
                workspaceStore.decreaseEditorFontSize()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("-", modifiers: .command)

            if workspaceStore.isMarkdownSurfaceAvailable {
                Divider()

                Button {
                    workspaceStore.toggleMarkdownSourceMode()
                } label: {
                    Label("Toggle Source Mode", systemImage: "chevron.left.forwardslash.chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!workspaceStore.isSelectedTabMarkdown || workspaceStore.isSettingsSelected)
            }
        }

        CommandGroup(after: .sidebar) {
            Button {
                workspaceStore.toggleSidebar()
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        if workspaceStore.isMarkdownSurfaceAvailable {
            CommandMenu("Format") {
                Group {
                    Button {
                        workspaceStore.performMarkdownFormatting(.bold)
                    } label: {
                        Label("Bold", systemImage: "bold")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("b", modifiers: .command)

                    Button {
                        workspaceStore.performMarkdownFormatting(.italic)
                    } label: {
                        Label("Italic", systemImage: "italic")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("i", modifiers: .command)

                    Button {
                        workspaceStore.performMarkdownFormatting(.underline)
                    } label: {
                        Label("Underline", systemImage: "underline")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("u", modifiers: .command)

                    Button {
                        workspaceStore.performMarkdownFormatting(.strikethrough)
                    } label: {
                        Label("Strikethrough", systemImage: "strikethrough")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("x", modifiers: [.command, .shift])

                    Button {
                        workspaceStore.performMarkdownFormatting(.inlineCode)
                    } label: {
                        Label("Inline Code", systemImage: "chevron.left.slash.chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    Button {
                        workspaceStore.performMarkdownFormatting(.highlight)
                    } label: {
                        Label("Highlight", systemImage: "highlighter")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                    Button {
                        workspaceStore.performMarkdownFormatting(.link)
                    } label: {
                        Label("Link", systemImage: "link")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Button {
                        workspaceStore.performMarkdownFormatting(.insertImage)
                    } label: {
                        Label("Insert Image…", systemImage: "photo")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                    Divider()

                    ForEach(1...6, id: \.self) { level in
                        Button {
                            workspaceStore.performMarkdownFormatting(.heading(level))
                        } label: {
                            Label(
                                String(format: String(localized: "Heading %lld"), level),
                                systemImage: "number"
                            )
                            .labelStyle(.titleAndIcon)
                        }
                        .keyboardShortcut(
                            KeyEquivalent(Character(String(level))),
                            modifiers: [.command]
                        )
                    }

                    Button {
                        workspaceStore.performMarkdownFormatting(.heading(0))
                    } label: {
                        Label("Paragraph", systemImage: "text.alignleft")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("0", modifiers: .command)

                    Divider()

                    Button {
                        workspaceStore.performMarkdownFormatting(.insertOrAlignTable)
                    } label: {
                        Label("Insert / Align Table", systemImage: "tablecells")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])

                    Button {
                        workspaceStore.performMarkdownFormatting(.codeBlock)
                    } label: {
                        Label("Code Block", systemImage: "curlybraces.square")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option])

                    Button {
                        workspaceStore.performMarkdownFormatting(.mathBlock)
                    } label: {
                        Label("Math Block", systemImage: "function")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("m", modifiers: [.command, .option])

                    Button {
                        workspaceStore.performMarkdownFormatting(.blockquote)
                    } label: {
                        Label("Blockquote", systemImage: "text.quote")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("q", modifiers: [.command, .option])

                    Divider()

                    Button {
                        workspaceStore.performMarkdownFormatting(.bulletList)
                    } label: {
                        Label("Bullet List", systemImage: "list.bullet")
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        workspaceStore.performMarkdownFormatting(.orderedList)
                    } label: {
                        Label("Ordered List", systemImage: "list.number")
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        workspaceStore.performMarkdownFormatting(.taskList)
                    } label: {
                        Label("Task List", systemImage: "checklist")
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        workspaceStore.performMarkdownFormatting(.horizontalRule)
                    } label: {
                        Label("Horizontal Rule", systemImage: "minus")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .disabled(!workspaceStore.canPerformMarkdownFormatting)
            }
        }
    }

    @MainActor
    private func openDocumentsFromUserHome() {
        let panel = NSOpenPanel()
        panel.directoryURL = workspaceStore.documentsFolder
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else {
            return
        }

        workspaceStore.openFiles(at: panel.urls)
    }
}
