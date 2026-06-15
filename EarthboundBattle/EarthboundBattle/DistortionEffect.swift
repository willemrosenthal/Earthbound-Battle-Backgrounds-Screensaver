import Foundation

// Ported from src/rom/distortion_effect.js
//
// A 17-byte block of distortion parameters. Values are stored as bytes but the
// math treats them as signed 16-bit, so all the multi-byte getters cast to Int16.

let HORIZONTAL = 1
let HORIZONTAL_INTERLACED = 2
let VERTICAL = 3

@inline(__always) private func asInt16(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

final class DistortionEffect {
    private var data = [Int](repeating: 0, count: 17)

    init(_ index: Int = 0) {
        read(index)
    }

    static func sanitize(_ type: Int) -> Int {
        (type != HORIZONTAL && type != VERTICAL) ? HORIZONTAL_INTERLACED : type
    }

    var type: Int { DistortionEffect.sanitize(data[2]) }
    var frequency: Int { asInt16(data[3] + (data[4] << 8)) }
    var amplitude: Int { asInt16(data[5] + (data[6] << 8)) }
    var compression: Int { asInt16(data[8] + (data[9] << 8)) }
    var frequencyAcceleration: Int { asInt16(data[10] + (data[11] << 8)) }
    var amplitudeAcceleration: Int { asInt16(data[12] + (data[13] << 8)) }
    var speed: Int { asInt16(data[14]) }
    var compressionAcceleration: Int { asInt16(data[15] + (data[16] << 8)) }

    private func read(_ index: Int) {
        let main = Block(0xF708 + index * 17)
        for i in 0..<17 {
            data[i] = main.readInt16()
        }
    }
}
