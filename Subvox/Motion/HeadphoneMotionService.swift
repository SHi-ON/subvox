import Combine
import CoreMotion
import ObjectiveC

/// Streams headphone-motion updates from connected AirPods.
///
/// `CMHeadphoneMotionManager` only exists in newer macOS SDKs, so this service talks to it
/// dynamically (runtime class lookup + IMP calls): the app compiles against older SDKs,
/// lights up where the class exists, and reports `.unsupported` elsewhere.
@MainActor
final class HeadphoneMotionService: ObservableObject {
    enum Status: Equatable {
        case unsupported
        case denied
        case waiting
        case streaming
        case error(String)

        var label: String {
            switch self {
            case .unsupported: return "Headphone motion unsupported"
            case .denied: return "Motion access denied"
            case .waiting: return "Waiting for AirPods"
            case .streaming: return "Streaming"
            case .error(let message): return message
            }
        }
    }

    static let historySeconds: TimeInterval = 10

    @Published private(set) var status: Status = .waiting
    @Published private(set) var isConnected = false
    @Published private(set) var latest: MotionSample?
    @Published private(set) var history: [MotionSample] = []
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var sampleCount = 0

    var onSample: ((MotionSample) -> Void)?

    private var manager: NSObject?
    private let proxy = DelegateProxy()
    private var rateWindow: [TimeInterval] = []

    func start() {
        guard let cls: AnyObject = NSClassFromString("CMHeadphoneMotionManager") else {
            status = .unsupported
            return
        }
        guard let manager = cls.perform(NSSelectorFromString("new"))?.takeRetainedValue() as? NSObject else {
            status = .unsupported
            return
        }
        guard (manager.value(forKey: "isDeviceMotionAvailable") as? Bool) == true else {
            status = .unsupported
            return
        }
        switch Self.authorizationStatus(of: cls as! AnyClass) {
        case 1, 2: // restricted, denied
            status = .denied
            return
        default:
            break
        }

        proxy.onChange = { [weak self] connected in
            Task { @MainActor in self?.connectionChanged(connected) }
        }
        if let proto = NSProtocolFromString("CMHeadphoneMotionManagerDelegate") {
            _ = class_addProtocol(DelegateProxy.self, proto)
        }
        manager.setValue(proxy, forKey: "delegate")
        Self.callVoid(manager, NSSelectorFromString("startConnectionStatusUpdates"))
        self.manager = manager

        typealias StartFn = @convention(c) (
            NSObject, Selector, OperationQueue,
            @convention(block) (CMDeviceMotion?, Error?) -> Void
        ) -> Void
        let sel = NSSelectorFromString("startDeviceMotionUpdatesToQueue:withHandler:")
        let handler: @convention(block) (CMDeviceMotion?, Error?) -> Void = { [weak self] motion, error in
            Task { @MainActor [weak self] in
                self?.handle(motion, error)
            }
        }
        if let imp = manager.method(for: sel) {
            unsafeBitCast(imp, to: StartFn.self)(manager, sel, .main, handler)
        }
    }

    func stop() {
        if let manager {
            Self.callVoid(manager, NSSelectorFromString("stopDeviceMotionUpdates"))
            Self.callVoid(manager, NSSelectorFromString("stopConnectionStatusUpdates"))
        }
    }

    /// `+[CMHeadphoneMotionManager authorizationStatus]`, returning the raw
    /// `CMAuthorizationStatus` value (0 not determined, 1 restricted, 2 denied, 3 authorized).
    private static func authorizationStatus(of cls: AnyClass) -> Int {
        let sel = NSSelectorFromString("authorizationStatus")
        guard let method = class_getClassMethod(cls, sel) else { return 0 }
        typealias Fn = @convention(c) (AnyClass?, Selector) -> Int
        return unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, sel)
    }

    private static func callVoid(_ manager: NSObject, _ sel: Selector) {
        typealias Fn = @convention(c) (NSObject, Selector) -> Void
        if let imp = manager.method(for: sel) {
            unsafeBitCast(imp, to: Fn.self)(manager, sel)
        }
    }

    private func connectionChanged(_ connected: Bool) {
        isConnected = connected
        if !connected {
            status = .waiting
            sampleRate = 0
            rateWindow.removeAll()
        }
    }

    private func handle(_ motion: CMDeviceMotion?, _ error: Error?) {
        if let error {
            let ns = error as NSError
            if ns.domain == CMErrorDomain, ns.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                status = .denied
            } else {
                status = .error(error.localizedDescription)
            }
            return
        }
        guard let motion else { return }

        let sample = MotionSample(motion)
        latest = sample
        status = .streaming
        isConnected = true
        sampleCount += 1

        history.append(sample)
        let cutoff = sample.t - Self.historySeconds
        if let firstKept = history.firstIndex(where: { $0.t >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }

        rateWindow.append(sample.t)
        rateWindow.removeAll { $0 < sample.t - 1 }
        if let first = rateWindow.first, sample.t > first {
            sampleRate = Double(rateWindow.count - 1) / (sample.t - first)
        }

        onSample?(sample)
    }
}

/// Implements the `CMHeadphoneMotionManagerDelegate` selectors without referencing the
/// protocol, which this SDK does not expose on macOS. The methods are adopted dynamically
/// in `start()` so the manager recognizes this object as a delegate.
private final class DelegateProxy: NSObject {
    var onChange: ((Bool) -> Void)?

    @objc func headphoneMotionManagerDidConnect(_ manager: NSObject) {
        onChange?(true)
    }

    @objc func headphoneMotionManagerDidDisconnect(_ manager: NSObject) {
        onChange?(false)
    }
}
