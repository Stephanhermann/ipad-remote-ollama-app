import Foundation

struct OllamaClient {
    func testConnection(baseURL: URL, auth: AuthenticationConfiguration) async throws {
        let request = try makeRequest(baseURL: baseURL, path: "/api/tags", auth: auth)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: Data())
    }

    func fetchModels(baseURL: URL, auth: AuthenticationConfiguration) async throws -> [OllamaModel] {
        let request = try makeRequest(baseURL: baseURL, path: "/api/tags", auth: auth)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func sendChat(
        baseURL: URL,
        auth: AuthenticationConfiguration,
        model: String,
        messages: [ChatMessage]
    ) async throws -> String {
        let requestMessages = messages.map {
            ChatRequest.RequestMessage(
                role: $0.role.rawValue,
                content: $0.content,
                images: $0.attachments.isEmpty ? nil : $0.attachments.map(\.base64Data)
            )
        }

        var request = try makeRequest(baseURL: baseURL, path: "/api/chat", auth: auth)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: requestMessages, stream: false)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw OllamaError.emptyResponse
        }
        return content
    }

    func streamChat(
        baseURL: URL,
        auth: AuthenticationConfiguration,
        model: String,
        messages: [ChatMessage],
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws {
        let requestMessages = messages.map {
            ChatRequest.RequestMessage(
                role: $0.role.rawValue,
                content: $0.content,
                images: $0.attachments.isEmpty ? nil : $0.attachments.map(\.base64Data)
            )
        }

        var request = try makeRequest(baseURL: baseURL, path: "/api/chat", auth: auth)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: requestMessages, stream: true)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response: response, data: Data())

        var didReceiveText = false

        for try await line in bytes.lines {
            if Task.isCancelled {
                return
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let data = Data(trimmed.utf8)
            let chunk = try JSONDecoder().decode(ChatResponse.self, from: data)
            let text = chunk.message.content
            if !text.isEmpty {
                didReceiveText = true
                await onChunk(text)
            }
        }

        if !didReceiveText {
            throw OllamaError.emptyResponse
        }
    }

    private func makeRequest(baseURL: URL, path: String, auth: AuthenticationConfiguration) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL(baseURL)) else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        applyAuthorization(to: &request, auth: auth)
        return request
    }

    private func applyAuthorization(to request: inout URLRequest, auth: AuthenticationConfiguration) {
        switch auth.mode {
        case .none:
            break
        case .bearer:
            if let token = auth.bearerToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            guard let username = auth.username,
                  let password = auth.password else { return }
            let credentials = "\(username):\(password)"
            guard let data = credentials.data(using: .utf8) else { return }
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }

    private func normalizedBaseURL(_ url: URL) -> URL {
        if url.absoluteString.hasSuffix("/") {
            return url
        }
        return URL(string: url.absoluteString + "/") ?? url
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = data.isEmpty
                ? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                : (String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
            throw OllamaError.serverError("Serverfehler \(httpResponse.statusCode): \(message)")
        }
    }
}
