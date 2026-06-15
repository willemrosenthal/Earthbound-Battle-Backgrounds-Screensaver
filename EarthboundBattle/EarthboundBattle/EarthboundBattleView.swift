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
    static let disabledKey = "DisabledBackgrounds" // [Int] of indices excluded from rotation
    static let saturationKey = "Saturation" // Double; 1.0 = unchanged, >1 = boosted
    static let singleChanceKey = "SingleBackgroundChance" // Int 0…100 (% chance of one layer)

    // Engine state
    private var layer1: BackgroundLayer?
    private var layer2: BackgroundLayer?
    private var alphas: [Double] = [0.5, 0.5]
    private var tick: Double = 0
    private var frameSkip: Double = 1
    private var randomizeInterval: TimeInterval = 10
    private var disabled: Set<Int> = []
    private var saturation: Double = 1
    private var singleChance: Int = 15

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
            EarthboundBattleView.frameSkipKey: 1,
            EarthboundBattleView.disabledKey: [Int](),
            EarthboundBattleView.saturationKey: 1.0,
            EarthboundBattleView.singleChanceKey: 15
        ])
    }

    private func loadSettings() {
        let d = defaults()
        let interval = d?.integer(forKey: EarthboundBattleView.intervalKey) ?? 10
        randomizeInterval = TimeInterval(interval < 3 ? 10 : interval)
        let fs = d?.integer(forKey: EarthboundBattleView.frameSkipKey) ?? 1
        frameSkip = Double(max(1, fs))
        let disabledList = d?.array(forKey: EarthboundBattleView.disabledKey) as? [Int] ?? []
        disabled = Set(disabledList)
        let sat = d?.double(forKey: EarthboundBattleView.saturationKey) ?? 1
        saturation = sat < 1 ? 1 : sat
        let chance = d?.integer(forKey: EarthboundBattleView.singleChanceKey) ?? 15
        singleChance = min(max(chance, 0), 100)
    }

    // MARK: - Background selection

    private func randomizeBackground() {
        // Usable = real (non-black) backgrounds the user hasn't disabled. Black
        // entries are always excluded; entry 0 (blank) is only ever the silent
        // partner for a single-background frame, never a "real" pick.
        let black = Rom.shared.blackEntries
        var usable = (1..<Rom.entryCount).filter { !disabled.contains($0) && !black.contains($0) }
        if usable.isEmpty { usable = (1..<Rom.entryCount).filter { !black.contains($0) } }
        if usable.isEmpty { usable = Array(1..<Rom.entryCount) }

        let l1 = usable.randomElement()!
        // `singleChance`% of the time (or when there's only one option) show a
        // single background over black; otherwise blend two distinct backgrounds.
        if usable.count < 2 || Int.random(in: 0..<100) < singleChance {
            layer1 = BackgroundLayer(entry: l1, rom: Rom.shared)
            layer2 = BackgroundLayer(entry: 0, rom: Rom.shared) // blank, alpha 0
            alphas = [1, 0]
        } else {
            var l2 = usable.randomElement()!
            while l2 == l1 { l2 = usable.randomElement()! }
            layer1 = BackgroundLayer(entry: l1, rom: Rom.shared)
            layer2 = BackgroundLayer(entry: l2, rom: Rom.shared)
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
        boostSaturation(&dst, factor: saturation)
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
