import AppKit
import ImageIO

/// An NSImageView that plays an animated GIF exactly once and then holds on its
/// final frame — it does not loop. `playOnce()` (re)starts from the first frame.
///
/// Frames are decoded on demand (one at a time) rather than cached, so memory
/// stays at roughly a single frame regardless of GIF length.
final class GIFPlayerView: NSImageView {
    private var source: CGImageSource?
    private var durations: [TimeInterval] = []
    private var frameCount = 0
    private var index = 0
    private var timer: Timer?

    /// Total play time of one pass through the GIF (sum of frame delays).
    private(set) var totalDuration: TimeInterval = 0

    /// Load a GIF and precompute its per-frame delays. Does not start playback.
    func loadGIF(url: URL) {
        stop()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            source = nil
            frameCount = 0
            durations = []
            totalDuration = 0
            return
        }
        source = src
        frameCount = CGImageSourceGetCount(src)
        durations = (0..<frameCount).map { i in
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.05
            return delay > 0 ? delay : 0.05
        }
        totalDuration = durations.reduce(0, +)
    }

    /// Restart from frame 0 and play through once, holding the final frame.
    func playOnce() {
        stop()
        guard source != nil, frameCount > 0 else { return }
        animates = false
        index = 0
        showFrame(0)
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func showFrame(_ i: Int) {
        // shouldCache=false: each frame is shown once per play; the default (true)
        // would retain every decoded 1280x720 frame in the image source
        // (~190 MB after a full 54-frame play).
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source, let cg = CGImageSourceCreateImageAtIndex(source, i, options) else { return }
        image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func scheduleNext() {
        guard index < frameCount else { return }
        let delay = durations[index]
        // Use a .common-mode timer so playback continues even while menus track.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            let next = self.index + 1
            if next >= self.frameCount {
                self.timer = nil   // reached the end: hold the last frame, no loop
                return
            }
            self.index = next
            self.showFrame(next)
            self.scheduleNext()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
