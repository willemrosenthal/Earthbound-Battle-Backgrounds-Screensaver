import ScreenSaver
import Cocoa

// The screensaver principal class. The Info.plist's NSPrincipalClass is
// "EarthboundBattleView" (no module prefix), so we pin the Objective-C runtime
// name with @objc(...) to match.
@objc(EarthboundBattleView)
final class EarthboundBattleView: ScreenSaverView {

    // Defaults
    static let defaultsName = "com.willem.EarthboundBattle"
    static let intervalKey = "RandomizeInterval"
    static let frameSkipKey = "FrameSkip"

    // Engine state
    private var layer1: BackgroundLayer?
    private var layer2: BackgroundLayer?
    private var alphas: [Double] = [0.5, 0.5]
    private var tick: Double = 0
    private var frameSkip: Double = 1
    private var randomizeInterval: TimeInterval = 10

    // Output: 256×224 RGBA
    private var dst = [UInt8](repeating: 0, count: SNES_WIDTH * SNES_HEIGHT * 4)
    private var currentImage: CGImage?
    private var randomizeTimer: Timer?

    private lazy var sheetController = ConfigureSheetController(defaultsName: EarthboundBattleView.defaultsName)

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = 1.0 / 30.0
        registerDefaults()
        loadSettings()
        randomizeBackground()
    }

    // MARK: - Settings

    private func defaults() -> ScreenSaverDefaults? {
        ScreenSaverDefaults(forModuleWithName: EarthboundBattleView.defaultsName)
    }

    private func registerDefaults() {
        defaults()?.register(defaults: [
            EarthboundBattleView.intervalKey: 10,
            EarthboundBattleView.frameSkipKey: 1
        ])
    }

    private func loadSettings() {
        let d = defaults()
        let interval = d?.integer(forKey: EarthboundBattleView.intervalKey) ?? 10
        randomizeInterval = TimeInterval(interval < 3 ? 10 : interval)
        let fs = d?.integer(forKey: EarthboundBattleView.frameSkipKey) ?? 1
        frameSkip = Double(max(1, fs))
    }

    // MARK: - Background selection

    private func randomizeBackground() {
        let l1 = Int.random(in: 0..<Rom.entryCount)
        let l2 = Int.random(in: 0..<Rom.entryCount)
        layer1 = BackgroundLayer(entry: l1, rom: Rom.shared)
        layer2 = BackgroundLayer(entry: l2, rom: Rom.shared)
        // Alpha rules mirror engine.js: a blank (0) layer drops out entirely.
        if l1 != 0 && l2 == 0 {
            alphas = [1, 0]
        } else if l1 == 0 && l2 != 0 {
            alphas = [0, 1]
        } else {
            alphas = [0.5, 0.5]
        }
    }

    // MARK: - Animation lifecycle

    override func startAnimation() {
        super.startAnimation()
        loadSettings() // pick up any changed Options without reinstalling
        randomizeTimer = Timer.scheduledTimer(withTimeInterval: randomizeInterval, repeats: true) { [weak self] _ in
            self?.randomizeBackground()
        }
    }

    override func stopAnimation() {
        randomizeTimer?.invalidate()
        randomizeTimer = nil
        super.stopAnimation()
    }

    override func animateOneFrame() {
        guard let layer1 = layer1, let layer2 = layer2 else { return }
        // Layer 0 erases (overwrites); layer 1 blends additively.
        layer1.overlayFrame(&dst, letterbox: 0, ticks: tick, alpha: alphas[0], erase: true)
        layer2.overlayFrame(&dst, letterbox: 0, ticks: tick, alpha: alphas[1], erase: false)
        tick += frameSkip
        currentImage = makeImage()
        setNeedsDisplay(bounds)
    }

    private func makeImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(dst) as CFData) else { return nil }
        return CGImage(width: SNES_WIDTH, height: SNES_HEIGHT, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: SNES_WIDTH * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image = currentImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none // crisp retro pixels
        ctx.draw(image, in: bounds)      // stretch to fill the whole monitor
    }

    // MARK: - Configuration sheet

    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? { sheetController.window }
}
