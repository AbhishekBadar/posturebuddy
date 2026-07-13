import CoreMotion
import Foundation

/// Abstracts AirPods head-motion delivery so the tracker is testable without
/// CoreMotion. Handlers may be called on any queue.
protocol MotionSource: AnyObject {
    var isAvailable: Bool { get }
    func start(handler: @escaping (_ pitchRadians: Double, _ timestamp: Date) -> Void,
               errorHandler: @escaping (Error) -> Void)
    func stop()
}

/// The real source: wraps CMHeadphoneMotionManager and forwards pitch only.
final class CMHeadphoneMotionSource: MotionSource {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.posturebuddy.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(handler: @escaping (Double, Date) -> Void,
               errorHandler: @escaping (Error) -> Void) {
        guard !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: queue) { motion, error in
            if let error {
                errorHandler(error)
            } else if let motion {
                handler(motion.attitude.pitch, Date())
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
