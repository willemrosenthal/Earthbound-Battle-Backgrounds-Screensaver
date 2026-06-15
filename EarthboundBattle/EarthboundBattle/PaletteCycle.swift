import Foundation

// Ported from src/rom/palette_cycle.js
//
// Animates palette entries over time. The JS extended each subpalette row from 16
// to 32 entries by duplication; in practice only indices within [start, end]
// (always ≤ 15) are read, so we keep rows at length 16 and operate over the same
// used range. Behavior over the used indices is identical.
final class PaletteCycle {
    private let type: Int
    private let start1: Int
    private let end1: Int
    private let start2: Int
    private let end2: Int
    private let speed: Double

    private var cycleCountdown: Double
    private var cycleCount: Int = 0

    private let rowCount: Int
    private var originalColors: [[Int]]
    private var nowColors: [[Int]]

    init(background: BattleBackground, palette: BackgroundPalette) {
        type = background.paletteCycleType
        start1 = background.paletteCycle1Start
        end1 = background.paletteCycle1End
        start2 = background.paletteCycle2Start
        end2 = background.paletteCycle2End
        speed = Double(background.paletteCycleSpeed) / 2.0
        cycleCountdown = speed

        // Normalize every subpalette row to length 16 (padding with black).
        let source = palette.getColorMatrix()
        rowCount = source.count
        var normalized = [[Int]]()
        for row in source {
            var r = row
            if r.count < 16 { r.append(contentsOf: Array(repeating: 0, count: 16 - r.count)) }
            normalized.append(r)
        }
        originalColors = normalized
        nowColors = normalized
    }

    /// Returns the (possibly animated) colors for a subpalette. Battle backgrounds
    /// only ever use subpalette 0, so any higher index falls back to 0.
    func getColors(_ subPalette: Int) -> [Int] {
        subPalette < nowColors.count ? nowColors[subPalette] : nowColors[0]
    }

    /// Advances the palette animation one frame. Returns true if colors changed.
    @discardableResult
    func cycle() -> Bool {
        if speed == 0 { return false }
        cycleCountdown -= 1
        if cycleCountdown <= 0 {
            cycleColors()
            cycleCount += 1
            cycleCountdown = speed
            return true
        }
        return false
    }

    private func cycleColors() {
        if type == 1 || type == 2 {
            let cycleLength = end1 - start1 + 1
            guard cycleLength > 0 else { return }
            let cycle1Position = cycleCount % cycleLength
            for sub in 0..<rowCount where start1 >= 0 && end1 < 16 {
                for i in start1...end1 {
                    var newColor = i - cycle1Position
                    if newColor < start1 { newColor += cycleLength }
                    nowColors[sub][i] = originalColors[sub][newColor]
                }
            }
        }
        if type == 2 {
            let cycleLength = end2 - start2 + 1
            guard cycleLength > 0 else { return }
            let cycle2Position = cycleCount % cycleLength
            for sub in 0..<rowCount where start2 >= 0 && end2 < 16 {
                for i in start2...end2 {
                    var newColor = i - cycle2Position
                    if newColor < start2 { newColor += cycleLength }
                    nowColors[sub][i] = originalColors[sub][newColor]
                }
            }
        }
        if type == 3 {
            let cycleLength = end1 - start1 + 1
            guard cycleLength > 0 else { return }
            let cycle1Position = cycleCount % (cycleLength * 2)
            for sub in 0..<rowCount where start1 >= 0 && end1 < 16 {
                for i in start1...end1 {
                    var newColor = i + cycle1Position
                    var difference = 0
                    if newColor > end1 {
                        difference = newColor - end1 - 1
                        newColor = end1 - difference
                        if newColor < start1 {
                            difference = start1 - newColor - 1
                            newColor = start1 + difference
                        }
                    }
                    if newColor >= 0 && newColor < 16 {
                        nowColors[sub][i] = originalColors[sub][newColor]
                    }
                }
            }
        }
    }
}
