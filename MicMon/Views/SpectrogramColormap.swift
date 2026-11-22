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

    /// 設定の一覧に出す名前。
    var name: String {
        switch self {
        case .accent: "単色（アクセントカラー・既定）"
        default: shortName
        }
    }

    /// ウィンドウ表示の見出しに出す短い名前。
    var shortName: String {
        switch self {
        case .accent: "単色"
        case .viridis: "viridis"
        case .magma: "magma"
        case .inferno: "inferno"
        case .plasma: "plasma"
        }
    }

    /// 設定に出す特徴（色の流れを含む）。
    var summary: String {
        switch self {
        case .accent:
            "アクセントカラーの濃さでレベルを表します。レベルに比例した透明度で塗るため背景になじみ、ほかの表示の邪魔をしません。弱い成分の細かな差は読み取りにくくなります。"
        case .viridis:
            "濃い紫 → 青 → 緑 → 黄。明るさが一様に増えていくので、色覚の違いがあっても、白黒にしてもレベルの大小が正しく読めます。迷ったらこれ。"
        case .magma:
            "黒 → 紫 → 赤 → 淡い黄。いちばん低いレベルがほぼ黒になり、暗い背景に自然に溶け込みます。ノイズフロア付近の弱い成分の差が見やすい配色です。"
        case .inferno:
            "黒 → 紫 → 橙 → 黄。magma に似ていますが高レベル側のコントラストが強く、ピークや強い倍音が目立ちます。"
        case .plasma:
            "濃い青 → 紫 → 橙 → 黄。最も暗い色でも黒にならないため、無音の部分も色として見え、表示領域の境目がわかりやすくなります。"
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
