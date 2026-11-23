import Foundation

/// Bounded zstd decompression of one frame, via the vendored decoder
/// (`Vendor/zstd`, imported through the bridging header).
enum Zstd {
    /// The decompressed bytes, or nil when `data` is not a zstd frame, is
    /// corrupt or truncated, or would decompress to more than `maxOutput` bytes.
    static func decompress(_ data: Data, maxOutput: Int = 262_144) -> Data? {
        guard data.count >= 4, data.prefix(4).elementsEqual([0x28, 0xB5, 0x2F, 0xFD]),
              let dctx = ZSTD_createDCtx() else { return nil }
        defer { ZSTD_freeDCtx(dctx) }

        let chunk = ZSTD_DStreamOutSize()
        var out = Data()
        var scratch = [UInt8](repeating: 0, count: chunk)
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            var input = ZSTD_inBuffer(src: src.baseAddress, size: src.count, pos: 0)
            while true {
                let (ret, produced) = scratch.withUnsafeMutableBytes { dst -> (Int, Int) in
                    var output = ZSTD_outBuffer(dst: dst.baseAddress, size: dst.count, pos: 0)
                    let r = ZSTD_decompressStream(dctx, &output, &input)
                    return (r, output.pos)
                }
                if ZSTD_isError(ret) != 0 { return nil }
                out.append(contentsOf: scratch[0..<produced])
                if out.count > maxOutput { return nil }
                if ret == 0 { return out }                       // frame complete
                if input.pos == input.size && produced == 0 { return nil }  // truncated
            }
        }
    }
}
