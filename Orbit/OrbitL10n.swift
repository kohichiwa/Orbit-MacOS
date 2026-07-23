import Foundation

enum OrbitL10n {
    nonisolated static func text(
        _ key: String,
        fallback: String,
        comment: String = ""
    ) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .main,
            value: fallback,
            comment: comment
        )
    }

    nonisolated static func format(
        _ key: String,
        fallback: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, fallback: fallback),
            locale: .current,
            arguments: arguments
        )
    }
}
