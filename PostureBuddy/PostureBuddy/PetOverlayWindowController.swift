import AppKit
import SwiftUI

/// Manages a borderless, transparent, non-activating, click-through NSPanel
/// anchored to the bottom-right corner of the active screen. It hosts:
///   - an animated GIF of the pet (walks in from the right, then stands), and
///   - a "Sit straight!" speech bubble overlaid above the pet's head.
///
/// The panel never steals focus and passes clicks through. Each `show()` reloads
/// the GIF so the walk-in replays from frame 0, and the bubble fades in shortly
/// after (once the character has walked in).
///
/// Layout is driven by the tunables below — adjust these to reposition the pet
/// and bubble.
@MainActor
final class PetOverlayWindowController {
    private var panel: NSPanel?
    private var imageView: GIFPlayerView?
    private var bubbleHost: NSHostingView<SpeechBubbleView>?
    private var isPresented = false
    private var bubbleWorkItem: DispatchWorkItem?

    // MARK: Tunables
    private let gifAspect: CGFloat = 1280.0 / 720.0   // GIF native canvas is 1280x720
    private let maxGifHeight: CGFloat = 360           // on-screen height of the GIF
    private let bubbleHeadroom: CGFloat = 80          // vertical space above the GIF for the bubble
    private let bubbleDelay: TimeInterval = 0.8       // wait for the walk-in before showing the bubble
    private let bubbleHeadFractionX: CGFloat = 0.5    // horizontal anchor over the standing head (0=left,1=right of GIF)
    private let rightBleedFraction: CGFloat = 0.20    // push panel off the right screen edge toward the corner
    private let bottomMargin: CGFloat = 0             // gap between the pet's feet and the screen bottom

    func show() {
        let panel = ensurePanel()
        layout(panel)

        // Play the GIF once from frame 0 (the walk-in), then hold the last frame.
        imageView?.playOnce()

        // Bubble starts hidden and fades in after the character walks in.
        bubbleHost?.alphaValue = 0
        bubbleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPresented else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.bubbleHost?.animator().alphaValue = 1
            }
        }
        bubbleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + bubbleDelay, execute: work)

        isPresented = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isPresented else { return }
        isPresented = false
        bubbleWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPresented else { return }
                self.panel?.orderOut(nil)
                self.imageView?.stop()            // stop playback while hidden
                self.imageView?.image = nil
                self.bubbleHost?.alphaValue = 0
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: maxGifHeight * gifAspect, height: maxGifHeight + bubbleHeadroom),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))

        let iv = GIFPlayerView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        if let url = Bundle.main.url(forResource: "posturebuddy", withExtension: "gif") {
            iv.loadGIF(url: url)
        }
        container.addSubview(iv)
        self.imageView = iv

        let bubble = NSHostingView(rootView: SpeechBubbleView(text: "Sit straight!"))
        bubble.alphaValue = 0
        container.addSubview(bubble)
        self.bubbleHost = bubble

        panel.contentView = container
        self.panel = panel
        return panel
    }

    private func layout(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let gifHeight = min(maxGifHeight, vf.height * 0.5)
        let gifWidth = gifHeight * gifAspect
        let panelHeight = gifHeight + bubbleHeadroom

        // Bottom-right, pushed right so the character enters from the corner
        // (the empty right part of the GIF canvas bleeds off-screen).
        let originX = vf.maxX - gifWidth + rightBleedFraction * gifWidth
        let originY = vf.minY + bottomMargin
        panel.setFrame(NSRect(x: originX, y: originY, width: gifWidth, height: panelHeight), display: true)

        // GIF sits in the bottom region; headroom on top holds the bubble.
        imageView?.frame = NSRect(x: 0, y: 0, width: gifWidth, height: gifHeight)

        if let bubble = bubbleHost {
            let fitting = bubble.fittingSize
            let bw = fitting.width > 0 ? fitting.width : 170
            let bh = fitting.height > 0 ? fitting.height : 64
            let bx = bubbleHeadFractionX * gifWidth - bw / 2
            let by = gifHeight - 6   // tail just overlaps the top of the GIF (near the head)
            bubble.frame = NSRect(x: bx, y: by, width: bw, height: bh)
        }
    }
}
