import Foundation

// Ported from src/rom/background_layer.js
//
// One of the two stacked layers. Holds a 256×256 RGBA source buffer that the
// graphics+palette redraw into each frame, which the distorter then samples.
final class BackgroundLayer {
    private static let width = 256
    private static let height = 256

    let entry: Int
    private let graphics: BackgroundGraphics
    private let paletteCycle: PaletteCycle
    private let distorter = Distorter()
    private var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)

    init(entry: Int, rom: Rom) {
        self.entry = entry
        let background = rom.backgroundAt(entry)
        self.graphics = rom.graphicsAt(background.graphicsIndex)
        self.paletteCycle = PaletteCycle(background: background,
                                         palette: rom.paletteAt(background.paletteIndex))
        // Choose the distortion effect (bytes 13–16, big-endian); prefer e2, else e1.
        let animation = background.animation
        let e1 = (animation >> 24) & 0xFF
        let e2 = (animation >> 16) & 0xFF
        distorter.effect = DistortionEffect(e2 != 0 ? e2 : e1)
    }

    /// Renders this layer's frame into `dst` at the given tick.
    func overlayFrame(_ dst: inout [UInt8], letterbox: Int, ticks: Double, alpha: Double, erase: Bool) {
        paletteCycle.cycle()
        graphics.draw(&pixels, paletteCycle)
        distorter.computeFrame(dst: &dst, src: pixels, letterbox: letterbox,
                               ticks: ticks, alpha: alpha, erase: erase)
    }
}
