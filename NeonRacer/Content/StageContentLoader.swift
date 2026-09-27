import Foundation

enum ContentMigrationPolicy: Equatable, Sendable {
    case currentOnly
    case migrateOlderVersions

    static let shipped: ContentMigrationPolicy = .currentOnly
}

struct StageContentLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    let diagnostics: [ContentDiagnostic]

    var description: String {
        diagnostics.map(\.description).joined(separator: "\n")
    }
}

struct StageContentLoader {
    let migrationPolicy: ContentMigrationPolicy
    let validator: StageContentValidator
    let decoder: JSONDecoder

    init(
        migrationPolicy: ContentMigrationPolicy = .shipped,
        assetResolver: (any ContentAssetResolving)? = nil
    ) {
        self.migrationPolicy = migrationPolicy
        validator = StageContentValidator(assetResolver: assetResolver)
        decoder = JSONDecoder()
    }

    func load(from url: URL) throws -> StageContentDocument {
        do {
            return try load(data: Data(contentsOf: url), source: url.path)
        } catch let error as StageContentLoadError {
            throw error
        } catch {
            throw StageContentLoadError(diagnostics: [
                ContentDiagnostic(
                    source: url.path,
                    field: "$",
                    code: "source.unreadable",
                    severity: .error,
                    message: error.localizedDescription
                )
            ])
        }
    }

    func load(data: Data, source: String) throws -> StageContentDocument {
        let version = try schemaVersion(in: data, source: source)
        guard version == StageContentDocument.currentSchemaVersion else {
            let relationship = version < StageContentDocument.currentSchemaVersion ? "older" : "newer"
            let action = version < StageContentDocument.currentSchemaVersion && migrationPolicy == .migrateOlderVersions
                ? "No migration from version \(version) is registered."
                : "Re-export this file using schema version \(StageContentDocument.currentSchemaVersion)."
            throw StageContentLoadError(diagnostics: [
                ContentDiagnostic(
                    source: source,
                    field: "schemaVersion",
                    code: "schema.\(relationship)",
                    severity: .error,
                    message: "Schema version \(version) is \(relationship) than supported version \(StageContentDocument.currentSchemaVersion). \(action)"
                )
            ])
        }

        let document: StageContentDocument
        do {
            document = try decoder.decode(StageContentDocument.self, from: data)
        } catch let error as DecodingError {
            throw StageContentLoadError(diagnostics: [diagnostic(for: error, source: source)])
        } catch {
            throw StageContentLoadError(diagnostics: [
                ContentDiagnostic(source: source, field: "$", code: "decode.failed", severity: .error, message: error.localizedDescription)
            ])
        }

        let diagnostics = validator.validate(document, source: source)
        guard diagnostics.isEmpty else {
            throw StageContentLoadError(diagnostics: diagnostics)
        }
        return document
    }

    func loadFixture(named name: String, bundle: Bundle) throws -> StageContentDocument {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Content/Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        else {
            throw StageContentLoadError(diagnostics: [
                ContentDiagnostic(
                    source: "\(bundle.bundlePath)/\(name).json",
                    field: "$",
                    code: "source.missing",
                    severity: .error,
                    message: "Bundled content fixture '\(name).json' was not found."
                )
            ])
        }
        return try load(from: url)
    }

    func loadBundledFixture(named name: String) throws -> StageContentDocument {
        #if SWIFT_PACKAGE
        return try loadFixture(named: name, bundle: .module)
        #else
        return try loadFixture(named: name, bundle: Bundle(for: StageContentBundleMarker.self))
        #endif
    }

    private func schemaVersion(in data: Data, source: String) throws -> Int {
        do {
            let header = try decoder.decode(SchemaHeader.self, from: data)
            return header.schemaVersion
        } catch let error as DecodingError {
            throw StageContentLoadError(diagnostics: [diagnostic(for: error, source: source)])
        } catch {
            throw StageContentLoadError(diagnostics: [
                ContentDiagnostic(source: source, field: "schemaVersion", code: "schema.missing", severity: .error, message: error.localizedDescription)
            ])
        }
    }

    private func diagnostic(for error: DecodingError, source: String) -> ContentDiagnostic {
        let path: [CodingKey]
        let code: String
        let message: String
        switch error {
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
            code = "decode.missing-key"
            message = "Required field '\(key.stringValue)' is missing. \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            path = context.codingPath
            code = "decode.type-mismatch"
            message = "Expected \(type). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            path = context.codingPath
            code = "decode.missing-value"
            message = "Expected a non-null \(type). \(context.debugDescription)"
        case .dataCorrupted(let context):
            path = context.codingPath
            code = "decode.corrupt"
            message = context.debugDescription
        @unknown default:
            path = []
            code = "decode.failed"
            message = String(describing: error)
        }
        return ContentDiagnostic(
            source: source,
            field: fieldPath(path),
            code: code,
            severity: .error,
            message: message
        )
    }

    private func fieldPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "$" }
        return codingPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }
}

private final class StageContentBundleMarker: NSObject {}
