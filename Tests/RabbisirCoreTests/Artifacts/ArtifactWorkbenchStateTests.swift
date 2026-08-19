import Testing

@testable import RabbisirCore

@Suite("Artifact workbench state")
@MainActor
struct ArtifactWorkbenchStateTests {
  @Test("Unsaved edits survive a document switch until the user decides")
  func unsavedDraftRequiresAChoiceBeforeSwitching() {
    let state = WorkspaceState()
    let first = UpstreamMarkdownDocument(
      path: "docs/first.md",
      content: "first",
      bytes: 5,
      modifiedAt: 1
    )
    let second = UpstreamMarkdownDocument(
      path: "docs/second.md",
      content: "second",
      bytes: 6,
      modifiedAt: 2
    )

    state.showArtifact(first)
    state.updateArtifactDraft("edited first")
    state.showArtifact(second)

    #expect(state.artifactDocument == first)
    #expect(state.artifactDraft == "edited first")
    #expect(state.pendingArtifactDocument == second)
    #expect(state.isArtifactDirty)

    state.cancelPendingArtifactSwitch()
    #expect(state.artifactDocument == first)
    #expect(state.artifactDraft == "edited first")
    #expect(state.pendingArtifactDocument == nil)

    state.showArtifact(second)
    state.discardDraftAndShowPendingArtifact()
    #expect(state.artifactDocument == second)
    #expect(state.artifactDraft == "second")
    #expect(!state.isArtifactDirty)
  }

  @Test("Saving before a document switch writes the current draft then opens the target")
  func saveThenSwitchPreservesBothDocuments() async {
    let state = WorkspaceState()
    let first = UpstreamMarkdownDocument(
      path: "docs/first.md",
      content: "first",
      bytes: 5,
      modifiedAt: 1
    )
    let second = UpstreamMarkdownDocument(
      path: "docs/second.md",
      content: "second",
      bytes: 6,
      modifiedAt: 2
    )
    var savedDocument: UpstreamMarkdownDocument?
    var savedContent: String?
    state.configureArtifactActions(
      save: { document, content in
        savedDocument = document
        savedContent = content
        return UpstreamMarkdownDocument(
          path: document.path,
          content: content,
          bytes: content.utf8.count,
          modifiedAt: 3
        )
      },
      openExternal: { _ in },
      reload: { $0 }
    )

    state.showArtifact(first)
    state.updateArtifactDraft("edited first")
    state.showArtifact(second)

    #expect(await state.saveDraftAndShowPendingArtifact())
    #expect(savedDocument == first)
    #expect(savedContent == "edited first")
    #expect(state.artifactDocument == second)
    #expect(state.artifactDraft == "second")
    #expect(state.pendingArtifactDocument == nil)
  }

  @Test("Reload refuses to discard an unsaved draft without explicit confirmation")
  func reloadProtectsUnsavedDraft() async {
    let state = WorkspaceState()
    let original = UpstreamMarkdownDocument(
      path: "docs/report.md",
      content: "saved",
      bytes: 5,
      modifiedAt: 1
    )
    var reloadCount = 0
    state.showArtifact(original)
    state.configureArtifactActions(
      save: { document, _ in document },
      openExternal: { _ in },
      reload: { document in
        reloadCount += 1
        return UpstreamMarkdownDocument(
          path: document.path,
          content: "reloaded",
          bytes: 8,
          modifiedAt: 2
        )
      }
    )
    state.updateArtifactDraft("unsaved")

    #expect(!(await state.reloadArtifact()))
    #expect(reloadCount == 0)
    #expect(state.artifactDraft == "unsaved")

    #expect(await state.reloadArtifact(discardingUnsavedChanges: true))
    #expect(reloadCount == 1)
    #expect(state.artifactDraft == "reloaded")
    #expect(!state.isArtifactDirty)
  }

  @Test("Upstream save result replaces the displayed Markdown revision")
  func saveWritesBackUpstreamDocument() async {
    let state = WorkspaceState()
    let original = UpstreamMarkdownDocument(
      path: "report.md",
      content: "# Original",
      bytes: 10,
      modifiedAt: 12
    )
    state.showArtifact(original)
    state.configureArtifactActions(
      save: { document, content in
        #expect(document == original)
        #expect(content == "# Updated")
        return UpstreamMarkdownDocument(
          path: document.path,
          content: content,
          bytes: 9,
          modifiedAt: 13
        )
      },
      openExternal: { _ in },
      reload: { $0 }
    )

    #expect(await state.saveArtifact(content: "# Updated"))
    #expect(state.artifactDocument?.content == "# Updated")
    #expect(state.artifactDocument?.modifiedAt == 13)
    #expect(state.artifactFailureMessage == nil)
  }

  @Test("Reload and external open use the currently displayed document")
  func reloadAndOpenUseCurrentDocument() async {
    let state = WorkspaceState()
    let original = UpstreamMarkdownDocument(
      path: "docs/report.md",
      content: "old",
      bytes: 3,
      modifiedAt: 5
    )
    var openedPath: String?
    state.showArtifact(original)
    state.configureArtifactActions(
      save: { document, _ in document },
      openExternal: { document in openedPath = document.path },
      reload: { document in
        UpstreamMarkdownDocument(
          path: document.path,
          content: "fresh",
          bytes: 5,
          modifiedAt: 6
        )
      }
    )

    #expect(await state.reloadArtifact())
    await state.openArtifactExternally()

    #expect(state.artifactDocument?.content == "fresh")
    #expect(openedPath == "docs/report.md")
    #expect(state.artifactFailureMessage == nil)
  }
}
