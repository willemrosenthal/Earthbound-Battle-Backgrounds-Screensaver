import Foundation

// Ported from src/rom/rom_graphics.js
//
// Decodes planar 2bpp/4bpp tiles and paints a 32×32 grid of 8×8 tiles into the
// 256×256 RGBA layer buffer (stride 1024 bytes).
final class RomGraphics {
    private let bitsPerPixel: Int
    private var gfx: [Int] = []
    private var tiles: [[[Int]]] = [] // tiles[tileIndex][x][y] = color index

    private static let stride = 1024

    init(bitsPerPixel: Int) {
        self.bitsPerPixel = bitsPerPixel
    }

    func loadGraphics(_ block: Block) {
        gfx = block.decompress()
        buildTiles()
    }

    private func buildTiles() {
        guard bitsPerPixel > 0 else { return }
        let n = gfx.count / (8 * bitsPerPixel)
        tiles = Array(repeating: Array(repeating: [Int](repeating: 0, count: 8), count: 8), count: n)
        for i in 0..<n {
            let o = i * 8 * bitsPerPixel
            for x in 0..<8 {
                for y in 0..<8 {
                    var c = 0
                    for bp in 0..<bitsPerPixel {
                        let halfBp = bp / 2 // integer floor
                        let g = gfx[o + y * 2 + (halfBp * 16 + (bp & 1))]
                        c += ((g & (1 << (7 - x))) >> (7 - x)) << bp
                    }
                    tiles[i][x][y] = c
                }
            }
        }
    }

    func draw(_ pixels: inout [UInt8], _ palette: PaletteCycle, _ arrangement: [Int]) {
        for i in 0..<32 {
            for j in 0..<32 {
                let n = j * 32 + i
                let b1 = arrangement[n * 2]
                let b2 = arrangement[n * 2 + 1] << 8
                let block = b1 + b2
                let tile = block & 0x3FF
                let verticalFlip = (block & 0x8000) != 0
                let horizontalFlip = (block & 0x4000) != 0
                let subPalette = (block >> 10) & 7
                drawTile(&pixels, x: i * 8, y: j * 8, palette: palette, tile: tile,
                         subPalette: subPalette, verticalFlip: verticalFlip, horizontalFlip: horizontalFlip)
            }
        }
    }

    private func drawTile(_ pixels: inout [UInt8], x: Int, y: Int, palette: PaletteCycle,
                          tile: Int, subPalette: Int, verticalFlip: Bool, horizontalFlip: Bool) {
        guard tile < tiles.count else { return }
        let subPaletteArray = palette.getColors(subPalette)
        for i in 0..<8 {
            let px = horizontalFlip ? x + 7 - i : x + i
            for j in 0..<8 {
                let rgb = subPaletteArray[tiles[tile][i][j]]
                let py = verticalFlip ? y + 7 - j : y + j
                let pos = 4 * px + RomGraphics.stride * py
                pixels[pos + 0] = UInt8((rgb >> 16) & 0xFF)
                pixels[pos + 1] = UInt8((rgb >> 8) & 0xFF)
                pixels[pos + 2] = UInt8(rgb & 0xFF)
                pixels[pos + 3] = 255
            }
        }
    }
}
