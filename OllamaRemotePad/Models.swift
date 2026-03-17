import Foundation

struct ImageAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var filename: String
    var mimeType: String
    var base64Data: String

    init(id: UUID = UUID(), filename: String, mimeType: String, base64Data: String) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.base64Data = base64Data
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var attachments: [ImageAttachment]

    init(id: UUID = UUID(), role: Role, content: String, attachments: [ImageAttachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([ImageAttachment].self, forKey: .attachments) ?? []
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessage]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

enum AuthenticationMode: String, CaseIterable, Codable, Identifiable {
    case none
    case bearer
    case basic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Keine"
        case .bearer:
            return "Bearer Token"
        case .basic:
            return "Benutzername/Passwort"
        }
    }
}

struct ServerProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var serverURL: String
    var authenticationMode: AuthenticationMode
    var authToken: String
    var authUsername: String
    var authPassword: String

    init(
        id: UUID = UUID(),
        name: String = "Standardserver",
        serverURL: String = "http://192.168.1.10:11434",
        authenticationMode: AuthenticationMode = .none,
        authToken: String = "",
        authUsername: String = "",
        authPassword: String = ""
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.authenticationMode = authenticationMode
        self.authToken = authToken
        self.authUsername = authUsername
        self.authPassword = authPassword
    }
}

struct AuthenticationConfiguration {
    let mode: AuthenticationMode
    let bearerToken: String?
    let username: String?
    let password: String?
}

struct OllamaModel: Identifiable, Decodable, Hashable {
    let name: String
    let modifiedAt: String?
    let size: Int64?

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
    }
}

struct TagsResponse: Decodable {
    let models: [OllamaModel]
}

struct ChatRequest: Encodable {
    struct RequestMessage: Encodable {
        let role: String
        let content: String
        let images: [String]?
    }

    let model: String
    let messages: [RequestMessage]
    let stream: Bool
}

struct ChatResponse: Decodable {
    struct ResponseMessage: Decodable {
        let role: String?
        let content: String
    }

    let message: ResponseMessage
    let done: Bool?
}

enum OllamaError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case emptyResponse
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die Server-URL ist ungueltig."
        case .invalidResponse:
            return "Die Antwort vom Server war nicht gueltig."
        case .serverError(let message):
            return message
        case .emptyResponse:
            return "Ollama hat keine Antwort zurueckgegeben."
        case .imageEncodingFailed:
            return "Das ausgewaehlte Bild konnte nicht verarbeitet werden."
        }
    }
}
