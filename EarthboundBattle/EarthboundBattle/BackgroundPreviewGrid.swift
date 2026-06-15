import Cocoa

// Renders a single static preview frame for a background and caches it. Used by
// the Options sheet's thumbnail grid. All graphics/palettes are decompressed
// eagerly in `Rom.init`, so this is cheap and safe to call on the main thread.
enum BackgroundThumbnail {
    private static var cache: [Int: NSImage] = [:]

    static func image(for index: Int) -> NSImage {
        if let cached = cache[index] { return cached }
        // One layer, ticks 0, full alpha, erase — mirrors EarthboundBattleView.makeImage().
        var dst = [UInt8](repeating: 0, count: SNES_WIDTH * SNES_HEIGHT * 4)
        let layer = BackgroundLayer(entry: index, rom: Rom.shared)
        layer.overlayFrame(&dst, letterbox: 0, ticks: 0, alpha: 1, erase: true)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let image: NSImage
        if let provider = CGDataProvider(data: Data(dst) as CFData),
           let cg = CGImage(width: SNES_WIDTH, height: SNES_HEIGHT, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: SNES_WIDTH * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            image = NSImage(cgImage: cg, size: NSSize(width: SNES_WIDTH, height: SNES_HEIGHT))
        } else {
            image = NSImage(size: NSSize(width: SNES_WIDTH, height: SNES_HEIGHT))
        }
        cache[index] = image
        return image
    }
}

// One cell in the preview grid: a thumbnail above an "on/off" checkbox labelled
// with the background's index. Built programmatically (no nib), so the view
// hierarchy is constructed in loadView(). Cells are recycled, so configure(...)
// must fully reset state and rebind the toggle to the index it now represents.
final class BackgroundThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BackgroundThumbnailItem")

    private let thumb = NSImageView()
    private let checkbox = NSButton()
    private var index = 0
    private var onToggle: ((Int, Bool) -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 96, height: 112))
        root.wantsLayer = true

        thumb.frame = NSRect(x: 0, y: 24, width: 96, height: 84) // 256:224 ≈ 96:84
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.black.cgColor
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor
        thumb.layer?.borderWidth = 1
        root.addSubview(thumb)

        checkbox.setButtonType(.switch)
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.font = NSFont.systemFont(ofSize: 11)
        checkbox.frame = NSRect(x: 2, y: 2, width: 92, height: 18)
        root.addSubview(checkbox)

        view = root
    }

    func configure(index: Int, enabled: Bool, onToggle: @escaping (Int, Bool) -> Void) {
        self.index = index
        self.onToggle = onToggle
        thumb.image = BackgroundThumbnail.image(for: index)
        checkbox.title = "#\(index)"
        checkbox.state = enabled ? .on : .off
    }

    @objc private func toggled() {
        onToggle?(index, checkbox.state == .on)
    }
}
