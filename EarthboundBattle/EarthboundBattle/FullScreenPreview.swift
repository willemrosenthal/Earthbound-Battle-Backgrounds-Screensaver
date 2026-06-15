import Cocoa

/// Builds a CGImage from an opaque 256×224 RGBA buffer (premultiplied-last, no
/// interpolation). Shared by the preview grid and the full-screen preview.
func makeSNESImage(from dst: [UInt8]) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let provider = CGDataProvider(data: Data(dst) as CFData) else { return nil }
    return CGImage(width: SNES_WIDTH, height: SNES_HEIGHT, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: SNES_WIDTH * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Borderless windows can't become key by default, which would swallow Escape /
/// click-to-dismiss. Allow it so the preview can be dismissed from the keyboard.
final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen, animated preview of a SINGLE background layer — what that entry
/// would look like alone as the screensaver. Click anywhere or press Escape to
/// dismiss. Mirrors EarthboundBattleView's render path (one layer, alpha 1).
final class LayerPreviewView: NSView {
    private let layer1: BackgroundLayer
    private let saturation: Double
    private var dst = [UInt8](repeating: 0, count: SNES_WIDTH * SNES_HEIGHT * 4)
    private var tick: Double = 0
    private var currentImage: CGImage?
    private var timer: Timer?
    var onClose: (() -> Void)?

    init(index: Int, saturation: Double) {
        self.layer1 = BackgroundLayer(entry: index, rom: Rom.shared)
        self.saturation = saturation
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        layer1.overlayFrame(&dst, letterbox: 0, ticks: tick, alpha: 1, erase: true)
        boostSaturation(&dst, factor: saturation)
        tick += 1
        currentImage = makeSNESImage(from: dst)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image = currentImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none // crisp retro pixels
        ctx.draw(image, in: bounds)      // stretch to fill the screen
    }

    override func mouseDown(with event: NSEvent) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } // 53 = Escape
        else { super.keyDown(with: event) }
    }
}
