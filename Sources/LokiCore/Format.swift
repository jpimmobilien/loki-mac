import Foundation

/// Deutsche Anzeigeformate für Größen, Zeiten und Tempo.
public enum Format {
    private static func number(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    /// 2_300_000_000 → „2,3 GB“ (dezimale Einheiten wie im Finder)
    public static func bytes(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b >= 1e12 { return number(b / 1e12, digits: 2) + " TB" }
        if b >= 1e9 { return number(b / 1e9, digits: b >= 1e11 ? 0 : 1) + " GB" }
        if b >= 1e6 { return number(b / 1e6, digits: 0) + " MB" }
        if b >= 1e3 { return number(b / 1e3, digits: 0) + " KB" }
        return "\(Int(b)) Byte"
    }

    public static func bytes(_ bytes: UInt64) -> String { self.bytes(Int64(clamping: bytes)) }
    public static func bytes(_ bytes: Int) -> String { self.bytes(Int64(bytes)) }

    /// 3.8 → „3,8B“, 27 → „27B“
    public static func params(_ billions: Double) -> String {
        if billions < 1 { return number(billions * 1000, digits: 0) + "M" }
        return number(billions, digits: billions < 10 ? 1 : 0) + "B"
    }

    public static func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1e9 { return number(bytesPerSecond / 1e9, digits: 1) + " GB/s" }
        return number(bytesPerSecond / 1e6, digits: 0) + " MB/s"
    }

    public static func tokensPerSecond(_ tps: Double) -> String {
        number(tps, digits: tps < 10 ? 1 : 0) + " Token/s"
    }

    public static func seconds(_ s: Double) -> String {
        if s < 1 { return number(s * 1000, digits: 0) + " ms" }
        if s < 90 { return number(s, digits: s < 10 ? 1 : 0) + " s" }
        let minutes = Int((s / 60).rounded())
        return "\(minutes) min"
    }

    public static func contextTokens(_ tokens: Int) -> String {
        if tokens >= 1000 { return "\(tokens / 1024)K" }
        return "\(tokens)"
    }

    public static func percent(_ fraction: Double) -> String {
        number(fraction * 100, digits: 0) + " %"
    }
}
