import SessionLauncherCore
import SwiftUI

struct SessionRow: View, Equatable {
    /// Used only for actions; rows take their display values as plain properties so
    /// they redraw only when their own values change.
    let model: LauncherModel
    let session: Session
    let isSelected: Bool
    let isPinned: Bool
    let note: String

    nonisolated static func == (lhs: SessionRow, rhs: SessionRow) -> Bool {
        lhs.session == rhs.session && lhs.isSelected == rhs.isSelected
            && lhs.isPinned == rhs.isPinned && lhs.note == rhs.note
    }

    @State private var editingNote = false
    @State private var draftNote = ""
    @State private var hovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            pinButton
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ProviderBadge(provider: session.provider)
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if session.activity != nil {
                        Circle().fill(.green).frame(width: 6, height: 6).help("May be open in another tab")
                    }
                    if session.isArchived {
                        Text("archived").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(Self.relativeFormatter.localizedString(for: session.lastActivity, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                detailLine
                if !note.isEmpty {
                    Label(note, systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            noteButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(session) }
        .help(session.projectPath)
        .contextMenu {
            Button("Open in iTerm") { model.open(session) }
            Button(isPinned ? "Unpin" : "Pin") { model.togglePin(session) }
            Button("Edit Note…") { beginNoteEdit() }
            Divider()
            Button("Copy Resume Command") { model.copyCommand(session) }
            Button("Show Project in Finder") { model.revealProject(session) }
        }
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            Text(session.projectName)
                .foregroundStyle(.secondary)
            if let prompt = session.lastPrompt {
                Text("·").foregroundStyle(.tertiary)
                Text("“\(prompt)”")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var pinButton: some View {
        Button {
            model.togglePin(session)
        } label: {
            Image(systemName: isPinned ? "star.fill" : "star")
                .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(hovering || isSelected ? 0.8 : 0.3))
        }
        .buttonStyle(.borderless)
        .padding(.top, 1)
        .help(isPinned ? "Unpin" : "Pin to top")
    }

    private var noteButton: some View {
        Button(action: beginNoteEdit) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(Color.secondary.opacity(hovering || isSelected ? 0.8 : 0))
        }
        .buttonStyle(.borderless)
        .help("Add a next-step note")
        .popover(isPresented: $editingNote, arrowEdge: .trailing) {
            NoteEditor(note: $draftNote) { saved in
                if saved { model.setNote(draftNote, for: session) }
                editingNote = false
            }
        }
    }

    private func beginNoteEdit() {
        draftNote = note
        editingNote = true
    }
}

private struct NoteEditor: View {
    @Binding var note: String
    let finish: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next step").font(.headline)
            TextField("e.g. run the migration on staging", text: $note)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($focused)
                .onSubmit { finish(true) }
            HStack {
                if !note.isEmpty {
                    Button("Clear") { note = ""; finish(true) }
                }
                Spacer()
                Button("Cancel") { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { finish(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }
}

private struct ProviderBadge: View {
    let provider: Provider

    var body: some View {
        Text(provider.displayName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private var tint: Color {
        switch provider {
        case .claude: return .orange
        case .codex: return .blue
        }
    }
}
