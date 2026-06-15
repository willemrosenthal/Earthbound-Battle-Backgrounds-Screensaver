import Foundation

// Ported from src/rom/block.js
//
// A cursor into the ROM data blob. NOTE: `readInt16` reads a SINGLE byte despite
// its name — the blob is a byte array and the JS does `data[pointer++]`. Do not
// "fix" this into a real 16-bit read.
final class Block {
    private var pointer: Int

    init(_ location: Int) {
        self.pointer = location
    }

    /// Reads one byte and advances the cursor. (Misnamed in the original JS.)
    func readInt16() -> Int {
        let value = Int(gRomData[pointer])
        pointer += 1
        return value
    }

    /// Reads four bytes little-endian.
    func readInt32() -> Int {
        let b0 = readInt16()
        let b1 = readInt16()
        let b2 = readInt16()
        let b3 = readInt16()
        return b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)
    }

    /// Reads two bytes little-endian and interprets the result as a signed 16-bit int.
    func readDoubleShort() -> Int {
        let raw = readInt16() + (readInt16() << 8)
        return Int(Int16(truncatingIfNeeded: raw))
    }

    /// Measures, allocates, and decompresses the block at the current position.
    func decompress() -> [Int] {
        let size = getCompressedSize(pointer, gRomData)
        if size < 1 {
            fatalError("Invalid compressed data: \(size)")
        }
        var output = [Int](repeating: 0, count: size)
        if !romDecompress(pointer, gRomData, &output) {
            fatalError("Computed and actual decompressed sizes do not match.")
        }
        return output
    }
}
