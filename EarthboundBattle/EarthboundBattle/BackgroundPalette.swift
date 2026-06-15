import Foundation

// Ported from src/rom/background_palette.js
//
// Reads a subpalette of 15-bit SNES BGR colors and converts them to 32-bit ARGB.
final class BackgroundPalette {
    private let bitsPerPixel: Int
    // colors[subPalette][index] = packed 0xAARRGGBB
    private(set) var colors: [[Int]] = []

    init(index: Int, bitsPerPixel: Int) {
        self.bitsPerPixel = bitsPerPixel
        read(index)
    }

    func getColors(_ palette: Int) -> [Int] { colors[palette] }
    func getColorMatrix() -> [[Int]] { colors }

    private func read(_ index: Int) {
        // Some palette slots are never referenced by a background, so bpp can be 0.
        // The JS would throw; we just leave an empty (unused) palette to avoid
        // crashing the screensaver.
        guard bitsPerPixel == 2 || bitsPerPixel == 4 else {
            colors = [[Int]()]
            return
        }
        let pointer = Block(0xDAD9 + index * 4)
        let address = snesToHex(pointer.readInt32())
        let data = Block(address)
        readPalette(data, count: 1)
    }

    private func readPalette(_ block: Block, count: Int) {
        let power = 1 << bitsPerPixel // 2**bpp
        colors = Array(repeating: [Int](), count: count)
        for palette in 0..<count {
            var row = [Int]()
            row.reserveCapacity(power)
            for _ in 0..<power {
                let clr16 = block.readDoubleShort()
                let b = ((clr16 >> 10) & 31) * 8
                let g = ((clr16 >> 5) & 31) * 8
                let r = (clr16 & 31) * 8
                // 0xFF alpha, then RGB. Channel order matters — easy to swap R/B.
                row.append((0xFF << 24) | (r << 16) | (g << 8) | b)
            }
            colors[palette] = row
        }
    }
}
