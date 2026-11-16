import AppKit
import ApplicationServices
import SwiftUI

/// Petite fenêtre d'historique du presse-papiers, ouverte par un double ⌘C, près du pointeur.
///
/// C'est un panneau « non activant » : l'app où tu travailles reste au premier plan,
/// mais le panneau reçoit le clavier (flèches, 1 à 9, Entrée, Échap).
final class ClipboardPopupController {
    private let model: NotchModel
    private var panel: KeyPanel?
    private let state = PopupState()

    init(model: NotchModel) { self.model = model }

    var isOpen: Bool { panel?.isVisible ?? false }

    func show() {
        if isOpen { close(); return } // le raccourci ouvre et ferme
        state.selection = 0
        let panel = self.panel ?? makePanel()
        self.panel = panel

        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }

        // Près du pointeur, là où tu vas coller, sans déborder de l'écran.
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        if let v = screen?.visibleFrame {
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        Haptics.tap()
    }

    func close() { panel?.orderOut(nil) }

    private func choose(_ index: Int) {
        guard model.clipboard.indices.contains(index) else { return }
        model.copyClip?(model.clipboard[index])
        close()
        // Collage direct si l'autorisation Accessibilité est donnée ; sinon l'élément est prêt pour ⌘V.
        guard AppSettings.shared.pasteDirectly, AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Self.pressCommandV() }
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down) // 9 = V
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private func makePanel() -> KeyPanel {
        let view = ClipboardPopupView(model: model, state: state,
                                      choose: { [weak self] in self?.choose($0) },
                                      close: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 400)),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .aboveOverlays
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        p.onResignKey = { [weak self] in self?.close() } // clic ailleurs : on ferme
        return p
    }
}

final class KeyPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) } // Échap
}

final class PopupState: ObservableObject {
    @Published var selection = 0
}

struct ClipboardPopupView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var state: PopupState
    let choose: (Int) -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    private var items: [ClipItem] { Array(model.clipboard.prefix(9)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Presse-papiers", systemImage: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1–9 ou ↑↓ puis ↩")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            if items.isEmpty {
                Text("Rien copié pour l'instant.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PopupRow(index: index, item: item, selected: index == state.selection)
                    .onTapGesture { choose(index) }
                    .onHover { if $0 { state.selection = index } }
            }
        }
        .padding(8)
        .frame(width: 360)
        .modifier(GlassCard(cornerRadius: 18))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { state.selection = min(state.selection + 1, items.count - 1); return .handled }
        .onKeyPress(.upArrow) { state.selection = max(state.selection - 1, 0); return .handled }
        .onKeyPress(.return) { choose(state.selection); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), n >= 1, n <= items.count else { return .ignored }
            choose(n - 1)
            return .handled
        }
    }
}

private struct PopupRow: View {
    let index: Int
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
            if let image = item.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("Image").font(.system(size: 12))
            } else {
                Image(systemName: item.isLink ? "link" : "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let app = item.app {
                Text(app).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
    }
}
