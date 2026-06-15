import Cocoa

// One cell in the preview grid: an animated thumbnail above an "on/off" checkbox
// labelled with the background's index. Built programmatically (no nib), so the
// view hierarchy is constructed in loadView(). Cells are recycled, so configure()
// fully rebuilds render state and rebinds the toggle to the index it now shows.
//
// A static single frame can't distinguish backgrounds that differ only in their
// distortion/palette-cycle motion (131 of 327 share a graphics+palette), and
// palette-cycle-driven backgrounds look flat/dark when frozen — so each visible
// cell animates, driven by the controller's timer calling renderFrame().
final class BackgroundThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BackgroundThumbnailItem")
    // Shared with the Options slider so previews reflect the chosen saturation live.
    static var previewSaturation: Double = 1

    private let thumb = NSImageView()
    private let checkbox = NSButton()
    private var index = 0
    private var onToggle: ((Int, Bool) -> Void)?
    private var onPreview: ((Int) -> Void)?

    // Live animation state. The palette cycle is stateful (it advances on every
    // overlayFrame call), so we keep one layer per cell and step it each frame.
    private var layer: BackgroundLayer?
    private var dst = [UInt8](repeating: 0, count: SNES_WIDTH * SNES_HEIGHT * 4)
    private var tick: Double = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 96, height: 112))
        root.wantsLayer = true

        thumb.frame = NSRect(x: 0, y: 24, width: 96, height: 84) // 256:224 ≈ 96:84
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.black.cgColor
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor
        thumb.layer?.borderWidth = 1
        thumb.toolTip = "Click to preview full screen"
        thumb.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(thumbClicked)))
        root.addSubview(thumb)

        checkbox.setButtonType(.switch)
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.font = NSFont.systemFont(ofSize: 11)
        checkbox.frame = NSRect(x: 2, y: 2, width: 92, height: 18)
        root.addSubview(checkbox)

        view = root
    }

    func configure(index: Int, enabled: Bool, onToggle: @escaping (Int, Bool) -> Void,
                   onPreview: @escaping (Int) -> Void) {
        self.index = index
        self.onToggle = onToggle
        self.onPreview = onPreview
        checkbox.title = "#\(index)"
        checkbox.state = enabled ? .on : .off
        layer = BackgroundLayer(entry: index, rom: Rom.shared)
        tick = 0
        renderFrame() // paint an initial frame so the cell isn't blank
    }

    /// Renders the current animation frame and advances the clock. Called once on
    /// configure, then on each tick of the controller's timer (visible cells only).
    func renderFrame() {
        guard let layer = layer else { return }
        layer.overlayFrame(&dst, letterbox: 0, ticks: tick, alpha: 1, erase: true)
        boostSaturation(&dst, factor: Self.previewSaturation)
        tick += 1
        if let cg = makeSNESImage(from: dst) {
            thumb.image = NSImage(cgImage: cg, size: NSSize(width: SNES_WIDTH, height: SNES_HEIGHT))
        }
    }

    @objc private func toggled() {
        onToggle?(index, checkbox.state == .on)
    }

    @objc private func thumbClicked() {
        onPreview?(index)
    }
}
