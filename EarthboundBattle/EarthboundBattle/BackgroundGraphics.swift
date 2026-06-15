import Foundation

// Ported from src/rom/background_graphics.js
//
// Loads + decompresses the graphics tileset and the 32×32 tile arrangement for a
// background, via the ROM's pointer tables.
final class BackgroundGraphics {
    private let romGraphics: RomGraphics
    private var arrangement: [Int] = []
    private let bitsPerPixel: Int

    init(index: Int, bitsPerPixel: Int) {
        self.bitsPerPixel = bitsPerPixel
        self.romGraphics = RomGraphics(bitsPerPixel: bitsPerPixel)
        read(index)
    }

    private func read(_ index: Int) {
        // Unreferenced graphics slots have bpp 0; skip them (never requested).
        guard bitsPerPixel == 2 || bitsPerPixel == 4 else { return }
        // Graphics pointer table entry.
        let graphicsPointerBlock = Block(0xD7A1 + index * 4)
        romGraphics.loadGraphics(Block(snesToHex(graphicsPointerBlock.readInt32())))
        // Arrangement pointer table entry.
        let arrayPointerBlock = Block(0xD93D + index * 4)
        let arrayPointer = snesToHex(arrayPointerBlock.readInt32())
        arrangement = Block(arrayPointer).decompress()
    }

    func draw(_ pixels: inout [UInt8], _ palette: PaletteCycle) {
        romGraphics.draw(&pixels, palette, arrangement)
    }
}
