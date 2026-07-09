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
    private let sound = SoundPlayer(resource: "faaah", withExtension: "mp3")

    // MARK: Tunables
    private let gifAspect: CGFloat = 1280.0 / 720.0   // GIF native canvas is 1280x720
    private let maxGifHeight: CGFloat = 360           // on-screen height of the GIF
    private let bubbleHeadroom: CGFloat = 80          // minimum space above the GIF for the bubble
    private let bubbleTailOverlap: CGFloat = 6        // how far the tail dips into the GIF, toward the head
    private let bubbleLeadIn: TimeInterval = 1.0      // show the bubble this long before the GIF ends
    private let bubbleFallbackDelay: TimeInterval = 0.8  // used only if the GIF duration is unknown
    private let bubbleHeadFractionX: CGFloat = 0.5    // horizontal anchor over the standing head (0=left,1=right of GIF)
    private let rightBleedFraction: CGFloat = 0.20    // push panel off the right screen edge toward the corner
    private let bottomMargin: CGFloat = 0             // gap between the pet's feet and the screen bottom

    /// - Parameters:
    ///   - message: the line the character says; the bubble is sized around it.
    ///   - playSound: whether to play the sound effect when the character speaks.
    func show(message: String, playSound: Bool) {
        let panel = ensurePanel()
        // Set the text before laying out — the bubble's size depends on it.
        bubbleHost?.rootView = SpeechBubbleView(text: message)
        layout(panel)

        // Play the GIF once from frame 0 (the walk-in), then hold the last frame.
        imageView?.playOnce()

        // Bubble stays hidden until the character stops walking — that's the moment
        // it "says" the line — then fades in, with the sound landing on the same beat.
        bubbleHost?.alphaValue = 0
        bubbleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPresented else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.bubbleHost?.animator().alphaValue = 1
            }
            if playSound { self.sound.play() }
        }
        bubbleWorkItem = work
        let gifDuration = imageView?.totalDuration ?? 0
        let bubbleDelay = gifDuration > 0 ? max(0, gifDuration - bubbleLeadIn) : bubbleFallbackDelay
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
        bubbleWorkItem?.cancel()   // cancels a pending bubble+sound if we hide mid-walk
        sound.stop()
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

        // Placeholder text only; show(message:playSound:) sets the real line and
        // layout() resizes the bubble around it.
        let bubble = NSHostingView(rootView: SpeechBubbleView(text: ""))
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

        // Measure the bubble first — nag lines vary in length and may wrap to two
        // lines, so the headroom has to grow to fit rather than clip at the panel top.
        var bubbleSize = NSSize(width: 170, height: 64)
        if let fitting = bubbleHost?.fittingSize, fitting.width > 0, fitting.height > 0 {
            bubbleSize = fitting
        }
        let headroom = max(bubbleHeadroom, bubbleSize.height + bubbleTailOverlap + 12)
        let panelHeight = gifHeight + headroom

        // Bottom-right, pushed right so the character enters from the corner
        // (the empty right part of the GIF canvas bleeds off-screen).
        let originX = vf.maxX - gifWidth + rightBleedFraction * gifWidth
        let originY = vf.minY + bottomMargin
        panel.setFrame(NSRect(x: originX, y: originY, width: gifWidth, height: panelHeight), display: true)

        // GIF sits in the bottom region; headroom on top holds the bubble.
        imageView?.frame = NSRect(x: 0, y: 0, width: gifWidth, height: gifHeight)

        // Bubble centered over the standing head, tail just overlapping the GIF top.
        let bx = bubbleHeadFractionX * gifWidth - bubbleSize.width / 2
        let by = gifHeight - bubbleTailOverlap
        bubbleHost?.frame = NSRect(origin: NSPoint(x: bx, y: by), size: bubbleSize)
    }
}
