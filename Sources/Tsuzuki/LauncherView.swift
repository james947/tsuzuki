import AppKit
import TsuzukiCore
import SwiftUI

struct LauncherView: View {
    @EnvironmentObject private var model: LauncherModel
    @FocusState private var searchFocused: Bool
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            banners
            sessionList
            Divider()
            footer
        }
        .frame(width: 480, height: 580)
        .background(WindowReader(window: $hostWindow))
        .onAppear(perform: windowOpened)
        // The menu-bar window is reused, so refresh each time it is shown. Popovers and
        // alerts have their own windows and must not trigger this.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === hostWindow else { return }
            windowOpened()
        }
        .alert(
            "Already open?",
            isPresented: Binding(
                get: { model.activeWarning != nil },
                set: { if !$0 { model.activeWarning = nil } }
            ),
            presenting: model.activeWarning
        ) { warning in
            Button("Open Anyway") { model.open(warning.session, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: { warning in
            Text(warning.message)
        }
    }

    private func windowOpened() {
        model.refresh()
        searchFocused = true
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by title, project, note or prompt", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { model.openSelected() }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onKeyPress(.escape) {
                    if model.query.isEmpty { return .ignored }
                    model.query = ""
                    return .handled
                }
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var banners: some View {
        if let error = model.errorMessage {
            Banner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .red) {
                model.errorMessage = nil
            }
        }
        ForEach(Provider.allCases, id: \.self) { provider in
            if let message = model.providerMessages[provider] {
                Banner(text: "\(provider.displayName): \(message)", systemImage: "info.circle", tint: .orange, onDismiss: nil)
            }
        }
    }

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if model.ordered.isEmpty && !model.isLoading {
                        emptyState
                    }
                    section("Pinned", model.pinned)
                    section(model.pinned.isEmpty ? nil : "Recent", model.recent)
                }
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String?, _ sessions: [Session]) -> some View {
        if !sessions.isEmpty {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }
            ForEach(sessions) { session in
                SessionRow(
                    model: model,
                    session: session,
                    isSelected: model.selectedID == session.id,
                    isPinned: model.isPinned(session),
                    note: model.note(for: session)
                )
                .equatable()
                .id(session.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(model.query.isEmpty ? "No conversations found" : "Nothing matches “\(model.query)”")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.ordered.count) conversations")
                .foregroundStyle(.secondary)
            if model.archivedCount > 0 {
                Toggle("Show archived (\(model.archivedCount))", isOn: $model.showArchived)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window !== window {
            DispatchQueue.main.async { window = view.window }
        }
    }
}

private struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(tint.opacity(0.1))
    }
}
