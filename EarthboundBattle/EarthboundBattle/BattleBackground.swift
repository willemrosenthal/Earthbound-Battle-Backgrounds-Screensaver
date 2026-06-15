import Foundation

// Ported from src/rom/battle_background.js
//
// Each entry is a 17-byte struct describing which graphics, palette, palette-cycle
// and distortion effect a background uses.
final class BattleBackground {
    private static let structSize = 17
    private var bbgData = [Int](repeating: 0, count: 17)

    init(_ i: Int = 0) {
        read(i)
    }

    var graphicsIndex: Int { bbgData[0] }
    var paletteIndex: Int { bbgData[1] }
    var bitsPerPixel: Int { bbgData[2] }
    var paletteCycleType: Int { bbgData[3] }
    var paletteCycle1Start: Int { bbgData[4] }
    var paletteCycle1End: Int { bbgData[5] }
    var paletteCycle2Start: Int { bbgData[6] }
    var paletteCycle2End: Int { bbgData[7] }
    var paletteCycleSpeed: Int { bbgData[8] }

    /// Bytes 13–16, packed big-endian; encodes the distortion effect sequence.
    var animation: Int {
        (bbgData[13] << 24) + (bbgData[14] << 16) + (bbgData[15] << 8) + bbgData[16]
    }

    private func read(_ index: Int) {
        let main = Block(0xDCA1 + index * BattleBackground.structSize)
        for i in 0..<BattleBackground.structSize {
            bbgData[i] = main.readInt16()
        }
    }
}
