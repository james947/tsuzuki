import Foundation

/// Reads newline-delimited records from a file starting at an offset, without loading
/// the whole file. Lines longer than `maxLineBytes` are skipped: the records this app
/// needs are small, while tool output lines can be tens of megabytes.
struct LineScanner {
    static let newline = UInt8(ascii: "\n")

    let maxLineBytes: Int
    let chunkSize: Int

    init(maxLineBytes: Int = 1 << 20, chunkSize: Int = 4 << 20) {
        self.maxLineBytes = maxLineBytes
        self.chunkSize = chunkSize
    }

    /// Calls `body` for each complete line after `offset` and returns the offset just
    /// past the last complete line, so a partially written final line is read next time.
    func scan(url: URL, from offset: UInt64, _ body: (Data) -> Void) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var chunkBase = offset
        var lastLineEnd = offset
        var pending = Data()
        var skipping = false

        // Each chunk is released before the next is read; without the pool, Foundation's
        // read buffers accumulate until the whole scan ends (hundreds of megabytes).
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
            var start = chunk.startIndex
            while let newlineIndex = Self.indexOfNewline(in: chunk, from: start) {
                if !skipping {
                    let line: Data
                    if pending.isEmpty {
                        line = chunk[start..<newlineIndex]
                    } else {
                        pending.append(chunk[start..<newlineIndex])
                        line = pending
                    }
                    if !line.isEmpty, line.count <= maxLineBytes {
                        body(line)
                    }
                }
                pending.removeAll(keepingCapacity: true)
                skipping = false
                lastLineEnd = chunkBase + UInt64(chunk.distance(from: chunk.startIndex, to: newlineIndex) + 1)
                start = chunk.index(after: newlineIndex)
            }
            if !skipping, start < chunk.endIndex {
                pending.append(chunk[start...])
                if pending.count > maxLineBytes {
                    pending.removeAll(keepingCapacity: false)
                    skipping = true
                }
            }
            chunkBase += UInt64(chunk.count)
            return true
        }) {}
        return lastLineEnd
    }

    /// `memchr` is far faster than a generic `firstIndex(of:)` over hundreds of megabytes.
    private static func indexOfNewline(in data: Data, from start: Data.Index) -> Data.Index? {
        guard start < data.endIndex else { return nil }
        return data.withUnsafeBytes { buffer -> Data.Index? in
            let offset = data.distance(from: data.startIndex, to: start)
            guard let base = buffer.baseAddress,
                  let found = memchr(base + offset, Int32(newline), buffer.count - offset)
            else { return nil }
            return data.index(data.startIndex, offsetBy: base.distance(to: found))
        }
    }
}
