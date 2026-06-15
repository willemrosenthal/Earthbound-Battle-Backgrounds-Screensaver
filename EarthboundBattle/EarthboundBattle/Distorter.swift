import Foundation

// Ported from src/rom/distorter.js
//
// The animated wobble. For each destination scanline it computes a sine offset
// and shifts pixels horizontally (or interlaced) or remaps them vertically.

let SNES_WIDTH = 256
let SNES_HEIGHT = 224

final class Distorter {
    var effect: DistortionEffect?

    // Precision constants from the JS (these affect HORIZONTAL backgrounds).
    private let C1 = 1.0 / 512.0
    private let C2 = 8.0 * Double.pi / (1024.0 * 256.0)
    private let C3 = Double.pi / 60.0

    private var amplitude = 0.0
    private var frequency = 0.0
    private var compression = 0.0
    private var speed = 0.0

    private func setOffsetConstants(ticks: Double, effect: DistortionEffect) {
        let t2 = ticks * 2
        amplitude = C1 * (Double(effect.amplitude) + Double(effect.amplitudeAcceleration) * t2)
        frequency = C2 * (Double(effect.frequency) + Double(effect.frequencyAcceleration) * t2)
        compression = 1 + (Double(effect.compression) + Double(effect.compressionAcceleration) * t2) / 256
        speed = C3 * Double(effect.speed) * ticks
    }

    @inline(__always) private func S(_ y: Int) -> Int {
        Int((amplitude * sin(frequency * Double(y) + speed)).rounded())
    }

    private func getAppliedOffset(_ y: Int, _ distortionEffect: Int) -> Int {
        let s = S(y)
        switch distortionEffect {
        case HORIZONTAL_INTERLACED:
            return y % 2 == 0 ? -s : s
        case VERTICAL:
            return mod(Int((Double(s) + Double(y) * compression).rounded(.down)), 256)
        default: // HORIZONTAL
            return s
        }
    }

    /// Renders one frame of one layer into `dst`. When `erase` is true the
    /// destination is overwritten; otherwise the layer is additively blended.
    func computeFrame(dst: inout [UInt8], src: [UInt8], letterbox: Int, ticks: Double,
                      alpha: Double, erase: Bool) {
        guard let effect = effect else { return }
        let distortionEffect = effect.type
        let dstStride = 1024
        let srcStride = 1024
        setOffsetConstants(ticks: ticks, effect: effect)

        for y in 0..<SNES_HEIGHT {
            let offset = getAppliedOffset(y, distortionEffect)
            let L = distortionEffect == VERTICAL ? offset : y
            let rowBase = y * dstStride
            let isLetterbox = y < letterbox || y > SNES_HEIGHT - letterbox
            for x in 0..<SNES_WIDTH {
                let bPos = x * 4 + rowBase
                if isLetterbox {
                    dst[bPos] = 0; dst[bPos + 1] = 0; dst[bPos + 2] = 0; dst[bPos + 3] = 255
                    continue
                }
                var dx = x
                if distortionEffect == HORIZONTAL || distortionEffect == HORIZONTAL_INTERLACED {
                    dx = mod(x + offset, SNES_WIDTH)
                }
                let sPos = dx * 4 + L * srcStride
                if erase {
                    dst[bPos] = clamp(alpha * Double(src[sPos]))
                    dst[bPos + 1] = clamp(alpha * Double(src[sPos + 1]))
                    dst[bPos + 2] = clamp(alpha * Double(src[sPos + 2]))
                    dst[bPos + 3] = 255
                } else {
                    dst[bPos] = clamp(Double(dst[bPos]) + alpha * Double(src[sPos]))
                    dst[bPos + 1] = clamp(Double(dst[bPos + 1]) + alpha * Double(src[sPos + 1]))
                    dst[bPos + 2] = clamp(Double(dst[bPos + 2]) + alpha * Double(src[sPos + 2]))
                    dst[bPos + 3] = 255
                }
            }
        }
    }

    @inline(__always) private func clamp(_ value: Double) -> UInt8 {
        let v = value.rounded()
        if v <= 0 { return 0 }
        if v >= 255 { return 255 }
        return UInt8(v)
    }
}
