import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatArchive: Codable {
    var exportedAt: Date
    var selectedSessionID: UUID?
    var sessions: [ChatSession]
}

struct ChatArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var archive: ChatArchive

    init(archive: ChatArchive) {
        self.archive = archive
    }

    init(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        archive = try decoder.decode(ChatArchive.self, from: data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        return .init(regularFileWithContents: data)
    }
}
