/// ユーザーが選んだ入力デバイス。
enum DeviceSelection: Hashable, Sendable {
    /// システム既定の入力デバイスに追従する。
    case systemDefault
    /// UID で特定のデバイスを指定する。
    case device(uid: String)

    init(storageValue: String?) {
        if let storageValue, !storageValue.isEmpty {
            self = .device(uid: storageValue)
        } else {
            self = .systemDefault
        }
    }

    var storageValue: String {
        switch self {
        case .systemDefault: ""
        case .device(let uid): uid
        }
    }
}
