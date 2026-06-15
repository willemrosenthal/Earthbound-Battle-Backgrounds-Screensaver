import Foundation

// Ported from src/rom/rom.js
//
// The whole engine reads bytes out of one binary blob (`truncated_backgrounds.dat`).
// In the JS this blob is a module-global `data` Uint8Array; we mirror that with a
// file-global byte array that `Block` and the decompressor read through.
var gRomData: [UInt8] = []

// Helper: emulate JS modular arithmetic that always returns a non-negative result.
@inline(__always) func mod(_ n: Int, _ m: Int) -> Int {
    return ((n % m) + m) % m
}

// Build a table mapping each byte to its bit-reversed value (used by the decompressor).
let REVERSED_BYTES: [Int] = {
    var r = [Int](repeating: 0, count: 256)
    for i in 0..<256 {
        var value = 0
        for b in 0..<8 where (i & (1 << b)) != 0 {
            value |= 1 << (7 - b)
        }
        r[i] = value
    }
    return r
}()

/// Converts a SNES address into a file offset within the (truncated) data blob.
/// Ported verbatim from `snesToHex` in rom.js — the magic constants matter.
func snesToHex(_ address: Int, header: Bool = true) -> Int {
    var newAddress = address
    if newAddress >= 0x400000 && newAddress < 0x600000 {
        newAddress -= 0x0
    } else if newAddress >= 0xC00000 && newAddress < 0x1000000 {
        newAddress -= 0xC00000
    } else {
        fatalError("SNES address out of range: \(newAddress)")
    }
    if header {
        newAddress += 0x200
    }
    return newAddress - 0xA0200
}

// Decompression command types.
private let UNCOMPRESSED_BLOCK = 0
private let RUN_LENGTH_ENCODED_BYTE = 1
private let RUN_LENGTH_ENCODED_SHORT = 2
private let INCREMENTAL_SEQUENCE = 3
private let REPEAT_PREVIOUS_DATA = 4
private let REVERSE_BITS = 5
private let UNKNOWN_1 = 6
private let UNKNOWN_2 = 7

/// Measures the decompressed size of the block starting at `start`. Mirrors
/// `getCompressedSize` in rom.js. Returns a negative error code on failure.
func getCompressedSize(_ start: Int, _ data: [UInt8]) -> Int {
    var bpos = 0
    var pos = start
    var bpos2 = 0
    while data[pos] != 0xFF {
        if pos >= data.count { return -8 }
        var commandType = Int(data[pos]) >> 5
        var length = (Int(data[pos]) & 0x1F) + 1
        if commandType == 7 {
            commandType = (Int(data[pos]) & 0x1C) >> 2
            length = ((Int(data[pos]) & 3) << 8) + Int(data[pos + 1]) + 1
            pos += 1
        }
        if bpos + length < 0 { return -1 }
        pos += 1
        if commandType >= 4 {
            bpos2 = (Int(data[pos]) << 8) + Int(data[pos + 1])
            if bpos2 < 0 { return -2 }
            pos += 2
        }
        switch commandType {
        case UNCOMPRESSED_BLOCK:
            bpos += length
            pos += length
        case RUN_LENGTH_ENCODED_BYTE:
            bpos += length
            pos += 1
        case RUN_LENGTH_ENCODED_SHORT:
            if bpos < 0 { return -3 }
            bpos += 2 * length
            pos += 2
        case INCREMENTAL_SEQUENCE:
            bpos += length
            pos += 1
        case REPEAT_PREVIOUS_DATA:
            if bpos2 < 0 { return -4 }
            bpos += length
        case REVERSE_BITS:
            if bpos2 < 0 { return -5 }
            bpos += length
        case UNKNOWN_1:
            if bpos2 - length + 1 < 0 { return -6 }
            bpos += length
        default:
            return -7
        }
    }
    return bpos
}

/// Decompresses into `output` (already sized). Mirrors `decompress` in rom.js.
/// Returns false on failure. Do not refactor — a single off-by-one corrupts a
/// whole background.
func romDecompress(_ start: Int, _ data: [UInt8], _ output: inout [Int]) -> Bool {
    let maxLength = output.count
    var pos = start
    var bpos = 0
    var bpos2 = 0
    var tmp = 0
    while data[pos] != 0xFF {
        if pos >= data.count { return false }
        var commandType = Int(data[pos]) >> 5
        var len = (Int(data[pos]) & 0x1F) + 1
        if commandType == 7 {
            commandType = (Int(data[pos]) & 0x1C) >> 2
            len = ((Int(data[pos]) & 3) << 8) + Int(data[pos + 1]) + 1
            pos += 1
        }
        if bpos + len > maxLength || bpos + len < 0 { return false }
        pos += 1
        if commandType >= 4 {
            bpos2 = (Int(data[pos]) << 8) + Int(data[pos + 1])
            if bpos2 >= maxLength || bpos2 < 0 { return false }
            pos += 2
        }
        switch commandType {
        case UNCOMPRESSED_BLOCK:
            var n = len
            while n != 0 { output[bpos] = Int(data[pos]); bpos += 1; pos += 1; n -= 1 }
        case RUN_LENGTH_ENCODED_BYTE:
            var n = len
            while n != 0 { output[bpos] = Int(data[pos]); bpos += 1; n -= 1 }
            pos += 1
        case RUN_LENGTH_ENCODED_SHORT:
            if bpos + 2 * len > maxLength || bpos < 0 { return false }
            var n = len
            while n != 0 {
                output[bpos] = Int(data[pos]); bpos += 1
                output[bpos] = Int(data[pos + 1]); bpos += 1
                n -= 1
            }
            pos += 2
        case INCREMENTAL_SEQUENCE:
            tmp = Int(data[pos]); pos += 1
            var n = len
            while n != 0 { output[bpos] = tmp; tmp += 1; bpos += 1; n -= 1 }
        case REPEAT_PREVIOUS_DATA:
            if bpos2 + len > maxLength || bpos2 < 0 { return false }
            for i in 0..<len { output[bpos] = output[bpos2 + i]; bpos += 1 }
        case REVERSE_BITS:
            if bpos2 + len > maxLength || bpos2 < 0 { return false }
            var n = len
            while n != 0 { output[bpos] = REVERSED_BYTES[output[bpos2] & 0xFF]; bpos += 1; bpos2 += 1; n -= 1 }
        case UNKNOWN_1:
            if bpos2 - len + 1 < 0 { return false }
            var n = len
            while n != 0 { output[bpos] = output[bpos2]; bpos += 1; bpos2 -= 1; n -= 1 }
        default:
            return false
        }
    }
    return true
}

/// Container that parses and holds every background, palette and graphics object.
/// Built once, lazily, and shared across all screen instances.
final class Rom {
    private(set) var backgrounds: [BattleBackground] = []
    private(set) var palettes: [BackgroundPalette] = []
    private(set) var graphics: [BackgroundGraphics] = []

    static let entryCount = 327 // indices 0...326

    // Entries whose graphics are entirely palette-index 0, so they render as a
    // solid black frame. In EarthBound these are the "empty" half of a two-layer
    // combo — useless shown alone — so we hide them from the picker and never put
    // them in rotation. Computed once on first use (real backgrounds bail on their
    // first non-black pixel, so the scan is cheap).
    private(set) lazy var blackEntries: Set<Int> = {
        var result = Set<Int>()
        var dst = [UInt8](repeating: 0, count: SNES_WIDTH * SNES_HEIGHT * 4)
        for i in 1..<Rom.entryCount {
            let layer = BackgroundLayer(entry: i, rom: self)
            layer.overlayFrame(&dst, letterbox: 0, ticks: 0, alpha: 1, erase: true)
            var allBlack = true
            var p = 0
            while p + 2 < dst.count {
                if dst[p] != 0 || dst[p + 1] != 0 || dst[p + 2] != 0 { allBlack = false; break }
                p += 4
            }
            if allBlack { result.insert(i) }
        }
        return result
    }()

    static let shared: Rom = {
        let url = Bundle(for: Rom.self).url(forResource: "truncated_backgrounds", withExtension: "dat")!
        let bytes = [UInt8](try! Data(contentsOf: url))
        return Rom(bytes)
    }()

    init(_ data: [UInt8]) {
        gRomData = data

        // Determine bit depth per palette/graphics by inspecting the backgrounds.
        var paletteBits = [Int](repeating: 0, count: 114)
        var graphicsBits = [Int](repeating: 0, count: 103)
        for i in 0...326 {
            let background = BattleBackground(i)
            backgrounds.append(background)
            let palette = background.paletteIndex
            let bpp = background.bitsPerPixel
            paletteBits[palette] = bpp
            graphicsBits[background.graphicsIndex] = bpp
        }
        for i in 0..<114 {
            palettes.append(BackgroundPalette(index: i, bitsPerPixel: paletteBits[i]))
        }
        for i in 0..<103 {
            graphics.append(BackgroundGraphics(index: i, bitsPerPixel: graphicsBits[i]))
        }
    }

    func backgroundAt(_ i: Int) -> BattleBackground { backgrounds[i] }
    func graphicsAt(_ i: Int) -> BackgroundGraphics { graphics[i] }
    func paletteAt(_ i: Int) -> BackgroundPalette { palettes[i] }
}
