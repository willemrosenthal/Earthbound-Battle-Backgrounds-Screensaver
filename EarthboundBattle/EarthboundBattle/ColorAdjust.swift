import Foundation

/// Boosts color saturation in place on an opaque RGBA buffer. `factor` 1.0 leaves
/// colors unchanged; >1 pushes each channel away from the pixel's luminance, which
/// makes colors more vivid without shifting hue or overall brightness. Applied to
/// the final composited frame so every color on screen is affected equally.
func boostSaturation(_ buffer: inout [UInt8], factor: Double) {
    if factor <= 1.0 { return }
    var i = 0
    let count = buffer.count
    while i + 2 < count {
        let r = Double(buffer[i]), g = Double(buffer[i + 1]), b = Double(buffer[i + 2])
        // Rec. 601 luma — the gray the colors rotate around.
        let gray = 0.299 * r + 0.587 * g + 0.114 * b
        buffer[i]     = clampByte(gray + (r - gray) * factor)
        buffer[i + 1] = clampByte(gray + (g - gray) * factor)
        buffer[i + 2] = clampByte(gray + (b - gray) * factor)
        i += 4 // skip alpha
    }
}

@inline(__always) func clampByte(_ value: Double) -> UInt8 {
    if value <= 0 { return 0 }
    if value >= 255 { return 255 }
    return UInt8(value.rounded())
}
