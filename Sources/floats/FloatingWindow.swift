#if os(macOS)
  import SwiftUI
  import AppKit

  /// Holds a weak reference to the window `WindowAccessor` resolves, so
  /// `EditorView` can retarget the floating state whenever it changes without
  /// needing the window itself to be observable.
  @MainActor
  final class WindowBox {
    weak var window: NSWindow?

    // Notification tokens for the traffic-light fade, torn down on deinit.
    // Mutated only on the main actor, but read once from the nonisolated
    // deinit, same pattern as `TextViewEditor.Coordinator.observerTokens`.
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
    private var didConfigureTrafficLightFading = false
    private var didInstallPinAccessory = false

    /// Adds the float toggle as a trailing title-bar accessory, so it sits in
    /// the title-bar row aligned with the traffic lights at the top-right —
    /// where a SwiftUI overlay can't reach, since content starts below the
    /// title bar. Idempotent. The button toggles the same `isFloating`
    /// default `EditorView` observes, so the two stay in sync automatically.
    func installPinAccessory() {
      guard !didInstallPinAccessory, let window else { return }
      didInstallPinAccessory = true
      window.addTitlebarAccessoryViewController(PinTitlebarAccessory())
    }

    /// Fades the close/miniaturize/zoom buttons out when the window resigns
    /// key and back in when it becomes key, so the hidden-title-bar chrome
    /// stays out of the way while the app isn't focused. Idempotent — safe to
    /// call every time `WindowAccessor` resolves the window.
    func configureTrafficLightFading() {
      guard !didConfigureTrafficLightFading, let window else { return }
      didConfigureTrafficLightFading = true

      let buttons: [NSButton] = [.closeButton, .miniaturizeButton, .zoomButton]
        .compactMap { window.standardWindowButton($0) }
      buttons.forEach { $0.alphaValue = window.isKeyWindow ? 1 : 0 }

      let center = NotificationCenter.default
      // `queue: .main` guarantees these fire on the main thread; `addObserver`'s
      // closure type itself isn't main-actor-isolated, so tell the compiler
      // what's already true rather than hopping through a `Task`.
      tokens.append(
        center.addObserver(
          forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { _ in
          MainActor.assumeIsolated {
            NSAnimationContext.runAnimationGroup { context in
              context.duration = 0.15
              buttons.forEach { $0.animator().alphaValue = 1 }
            }
          }
        })
      tokens.append(
        center.addObserver(
          forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { _ in
          MainActor.assumeIsolated {
            NSAnimationContext.runAnimationGroup { context in
              // Slower than the fade-in: becoming key should feel immediate,
              // but losing it reads better as a gentle settle.
              context.duration = 0.6
              buttons.forEach { $0.animator().alphaValue = 0 }
            }
          }
        })
    }

    deinit {
      tokens.forEach(NotificationCenter.default.removeObserver)
    }
  }

  /// The pin button, hosted in the window's title bar as a trailing accessory.
  final class PinTitlebarAccessory: NSTitlebarAccessoryViewController {
    init() {
      super.init(nibName: nil, bundle: nil)
      layoutAttribute = .trailing
      let hosting = NSHostingView(rootView: FloatToggleButton())
      hosting.frame = NSRect(x: 0, y: 0, width: 44, height: 28)
      view = hosting
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }

  /// The pin control itself. Reads and writes the shared `isFloating` default,
  /// so tapping it and the app-level ⇧⌘F command drive the same state.
  private struct FloatToggleButton: View {
    @AppStorage("isFloating") private var isFloating = false

    var body: some View {
      Button {
        isFloating.toggle()
      } label: {
        Image(systemName: isFloating ? "pin.fill" : "pin")
          .font(.system(size: 15, weight: .medium))
          // Muted either way: a touch stronger when pinned, faint when not,
          // rather than a saturated accent color.
          .foregroundStyle(.secondary)
          .opacity(isFloating ? 0.9 : 0.5)
          // Equal gap from the glyph to the top and trailing edges of the
          // accessory, so it sits the same distance from both window edges.
          .padding([.top, .trailing], 6)
          // Fill the accessory so the whole area is clickable, not just the
          // glyph; pin the glyph to the top-trailing corner within it.
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(isFloating ? "Stop floating above other windows" : "Float above other windows")
    }
  }

  /// Invisible view that hands its hosting `NSWindow` back once SwiftUI has
  /// inserted it into the view hierarchy — the only way to reach the window
  /// from a pure SwiftUI scene.
  struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      DispatchQueue.main.async { [weak view] in
        if let window = view?.window { onResolve(window) }
      }
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      DispatchQueue.main.async { [weak nsView] in
        if let window = nsView?.window { onResolve(window) }
      }
    }
  }
#endif
