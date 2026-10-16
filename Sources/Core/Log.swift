import Foundation

// ~/Library/Logs/MchoseBar.log
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MchoseBar.log")
    private(set) static var lines = [String]()
    private static let formatter = ISO8601DateFormatter()

    static func write(_ s: String) {
        let line = "\(formatter.string(from: Date())) \(s)"
        print(line)
        lines.append(line)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
