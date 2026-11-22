import SwiftUI

/// スペクトログラムの色の付け方。設定で選ぶ（`@AppStorage(SpectrogramColormap.storageKey)`）。
enum SpectrogramColormap: String, CaseIterable, Identifiable {
    /// アクセントカラー 1 色の濃さ（単色の濃淡）。
    case accent
    case viridis
    case magma
    case inferno
    case plasma

    static let storageKey = "spectrogramColormap"
    static let defaultValue = SpectrogramColormap.accent

    /// 乗算済みアルファの RGBA。
    struct Pixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    var id: Self { self }

    var name: String {
        switch self {
        case .accent: "単色（アクセントカラー）"
        case .viridis: "viridis"
        case .magma: "magma"
        case .inferno: "inferno"
        case .plasma: "plasma"
        }
    }

    /// 弱い → 強いの色の流れ。
    var flow: String {
        switch self {
        case .accent: "透明 → アクセントカラー"
        case .viridis: "紫 → 青緑 → 黄"
        case .magma: "黒 → 紫 → 橙 → 薄い黄"
        case .inferno: "黒 → 紫 → 赤橙 → 黄"
        case .plasma: "青紫 → 桃 → 黄"
        }
    }

    var summary: String {
        switch self {
        case .accent:
            "レベルをアクセントカラーの濃さだけで表す。ライト・ダークのどちらの表示にもなじむが、細かいレベル差は見分けにくい"
        case .viridis:
            "最も無難な知覚的に均一なカラーマップ（matplotlib の既定）。暗い部分も真っ黒にならない"
        case .magma:
            "黒から始まるので無音が背景に溶け込む。スペクトログラムでよく使われる"
        case .inferno:
            "magma より彩度が高く、ピークが強く目立つ"
        case .plasma:
            "黒から始まらないので、最小値もやや見える"
        }
    }

    /// 256 色の表（0xRRGGBB、弱い順）。単色は表示の環境（アクセントカラー）で決まるので nil。
    private var table: [UInt32]? {
        switch self {
        case .accent: nil
        case .viridis: Self.viridisTable
        case .magma: Self.magmaTable
        case .inferno: Self.infernoTable
        case .plasma: Self.plasmaTable
        }
    }

    /// レベル 0...255 から画素の色への対応表。単色は透明からアクセントカラーまでアルファで、
    /// それ以外は不透明の色で表す。
    func lookupTable(accent: Color.Resolved) -> [Pixel] {
        if let table {
            return table.map {
                Pixel(red: UInt8(($0 >> 16) & 0xFF), green: UInt8(($0 >> 8) & 0xFF), blue: UInt8($0 & 0xFF),
                      alpha: 255)
            }
        }
        return (0..<256).map { level in
            let alpha = Float(level) / 255
            func channel(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * alpha * 255).rounded()) }
            return Pixel(red: channel(accent.red), green: channel(accent.green), blue: channel(accent.blue),
                         alpha: UInt8(level))
        }
    }

    /// 設定画面の見本用のグラデーション。
    var gradient: Gradient {
        guard let table else {
            return Gradient(colors: [.accentColor.opacity(0), .accentColor])
        }
        let stops = 16
        return Gradient(colors: (0...stops).map { i in
            let rgb = table[i * (table.count - 1) / stops]
            return Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                         blue: Double(rgb & 0xFF) / 255)
        })
    }
}
