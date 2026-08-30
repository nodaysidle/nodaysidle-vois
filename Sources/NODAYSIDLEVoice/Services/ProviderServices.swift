import Foundation

enum ProviderError: Error, Equatable {
    case missingCredential
    case unsupportedAudioFormat
    case audioTooLarge
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case unavailable
    case timeout
    case emptyTranscript
}

extension ProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingCredential: "Add the provider key in Settings."
        case .unsupportedAudioFormat: "This audio format is not supported."
        case .audioTooLarge: "The audio file is too large for one request."
        case .invalidURL, .invalidResponse: "The provider returned an invalid response."
        case .unauthorized: "The provider rejected the saved key."
        case .rateLimited: "The provider rate limit was reached."
        case .unavailable: "The provider is temporarily unavailable."
        case .timeout: "The provider did not respond in time."
        case .emptyTranscript: "The provider returned no final text."
        }
    }
}

typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

private func liveHTTPTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
    return (data, response)
}

struct CloudTranscription: Equatable, Sendable {
    let text: String
    let durationSeconds: Double?
    let cost: Double?
    let requestID: String?
}

struct OpenRouterCatalogModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

actor OpenRouterModelCatalog {
    private let transport: HTTPTransport
    private var cached: (expiresAt: Date, models: [OpenRouterCatalogModel])?

    init(transport: @escaping HTTPTransport = liveHTTPTransport) {
        self.transport = transport
    }

    nonisolated static func request(credential: String) throws -> URLRequest {
        guard !credential.isEmpty else { throw ProviderError.missingCredential }
        var components = URLComponents(string: "https://openrouter.ai/api/v1/models")
        components?.queryItems = [URLQueryItem(name: "output_modalities", value: "transcription")]
        guard let url = components?.url else { throw ProviderError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        return request
    }

    nonisolated static func parse(_ data: Data) throws -> [OpenRouterCatalogModel] {
        struct Body: Decodable {
            struct Model: Decodable { let id: String; let name: String }
            let data: [Model]
        }
        return try JSONDecoder().decode(Body.self, from: data).data
            .map { OpenRouterCatalogModel(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func models(credential: String, now: Date = .now) async throws -> [OpenRouterCatalogModel] {
        if let cached, cached.expiresAt > now { return cached.models }
        let (data, response) = try await transport(Self.request(credential: credential))
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw ProviderError.unauthorized
        case 429: throw ProviderError.rateLimited
        case 500...599: throw ProviderError.unavailable
        default: throw ProviderError.invalidResponse
        }
        let models = try Self.parse(data)
        cached = (now.addingTimeInterval(600), models)
        return models
    }
}

actor OpenRouterSTTEngine {
    static let maximumAudioBytes = 25 * 1_024 * 1_024
    static let supportedFormats: Set<String> = ["wav", "mp3", "flac", "m4a", "ogg", "webm", "aac"]

    private let transport: HTTPTransport

    init(transport: @escaping HTTPTransport = liveHTTPTransport) {
        self.transport = transport
    }

    static func request(
        audio: Data,
        format: String,
        model: String,
        credential: String
    ) throws -> URLRequest {
        let normalizedFormat = format.lowercased()
        guard supportedFormats.contains(normalizedFormat) else { throw ProviderError.unsupportedAudioFormat }
        guard audio.count <= maximumAudioBytes else { throw ProviderError.audioTooLarge }
        guard !credential.isEmpty else { throw ProviderError.missingCredential }
        guard let url = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions") else {
            throw ProviderError.invalidURL
        }

        struct InputAudio: Encodable { let data: String; let format: String }
        struct Body: Encodable {
            let model: String
            let inputAudio: InputAudio
            let temperature: Double
            enum CodingKeys: String, CodingKey {
                case model
                case inputAudio = "input_audio"
                case temperature
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            model: model,
            inputAudio: InputAudio(data: audio.base64EncodedString(), format: normalizedFormat),
            temperature: 0
        ))
        return request
    }

    func transcribe(
        audio: Data,
        format: String,
        model: String,
        credential: String
    ) async throws -> CloudTranscription {
        let request = try Self.request(audio: audio, format: format, model: model, credential: credential)
        let (data, response) = try await transport(request)
        try Self.validate(response.statusCode)

        struct Usage: Decodable {
            let seconds: Double?
            let cost: Double?
        }
        struct Body: Decodable {
            let text: String
            let usage: Usage?
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ProviderError.emptyTranscript }
        return CloudTranscription(
            text: text,
            durationSeconds: body.usage?.seconds,
            cost: body.usage?.cost,
            requestID: response.value(forHTTPHeaderField: "X-Generation-Id")
        )
    }

    private nonisolated static func validate(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300: return
        case 401, 403: throw ProviderError.unauthorized
        case 408: throw ProviderError.timeout
        case 429: throw ProviderError.rateLimited
        case 500...599: throw ProviderError.unavailable
        default: throw ProviderError.invalidResponse
        }
    }
}

actor DeepgramEngine {
    private struct Envelope: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable { let transcript: String }
            let alternatives: [Alternative]
        }
        let type: String
        let channel: Channel?
        let isFinal: Bool?
        let fromFinalize: Bool?

        enum CodingKeys: String, CodingKey {
            case type, channel
            case isFinal = "is_final"
            case fromFinalize = "from_finalize"
        }
    }

    private enum WorkResult: Sendable {
        case senderFinished
        case transcript(String)
        case timedOut
    }

    private let session: URLSession
    private var activeTask: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated static func endpoint(sampleRate: Int, channels: Int) throws -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        components?.queryItems = [
            .init(name: "model", value: "nova-3"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: String(sampleRate)),
            .init(name: "channels", value: String(channels)),
            .init(name: "interim_results", value: "true"),
            .init(name: "smart_format", value: "true"),
            .init(name: "punctuate", value: "true"),
            .init(name: "endpointing", value: "300"),
        ]
        guard let url = components?.url else { throw ProviderError.invalidURL }
        return url
    }

    nonisolated static func parseResult(_ data: Data) throws -> String? {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.type == "Results", envelope.isFinal == true else { return nil }
        let text = envelope.channel?.alternatives.first?.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    func transcribe(
        frames: AsyncStream<Data>,
        credential: String,
        timeout: Duration = .seconds(45)
    ) async throws -> String {
        guard !credential.isEmpty else { throw ProviderError.missingCredential }
        var request = URLRequest(url: try Self.endpoint(sampleRate: 16_000, channels: 1))
        request.setValue("Token \(credential)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        activeTask = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            activeTask = nil
        }

        return try await withThrowingTaskGroup(of: WorkResult.self) { group in
            group.addTask {
                for await frame in frames {
                    try Task.checkCancellation()
                    try await task.send(.data(frame))
                }
                try await task.send(.string(#"{"type":"Finalize"}"#))
                return .senderFinished
            }
            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(8))
                    try await task.send(.string(#"{"type":"KeepAlive"}"#))
                }
                return .senderFinished
            }
            group.addTask {
                var parts: [String] = []
                while true {
                    let message = try await task.receive()
                    let data = switch message {
                    case .data(let data): data
                    case .string(let text): Data(text.utf8)
                    @unknown default: throw ProviderError.invalidResponse
                    }
                    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                    if envelope.type == "Error" { throw ProviderError.unavailable }
                    if envelope.isFinal == true,
                       let text = envelope.channel?.alternatives.first?.transcript
                        .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        parts.append(text)
                    }
                    if envelope.fromFinalize == true {
                        return .transcript(parts.joined(separator: " "))
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }

            for try await result in group {
                switch result {
                case .senderFinished:
                    continue
                case .timedOut:
                    group.cancelAll()
                    throw ProviderError.timeout
                case .transcript(let text):
                    group.cancelAll()
                    try? await task.send(.string(#"{"type":"CloseStream"}"#))
                    guard !text.isEmpty else { throw ProviderError.emptyTranscript }
                    return text
                }
            }
            throw ProviderError.invalidResponse
        }
    }

    func cancel() {
        activeTask?.cancel(with: .goingAway, reason: nil)
        activeTask = nil
    }
}

actor RefinementService {
    private let transport: HTTPTransport

    init(transport: @escaping HTTPTransport = liveHTTPTransport) {
        self.transport = transport
    }

    func refine(
        _ transcript: String,
        instruction: String,
        model: String,
        credential: String
    ) async -> String {
        do {
            guard !credential.isEmpty else { throw ProviderError.missingCredential }
            guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
                throw ProviderError.invalidURL
            }
            struct Message: Encodable { let role: String; let content: String }
            struct Reasoning: Encodable { let enabled = false }
            struct Body: Encodable {
                let model: String
                let messages: [Message]
                let temperature = 0.0
                let reasoning = Reasoning()
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(Body(
                model: model,
                messages: [
                    Message(role: "system", content: instruction),
                    Message(role: "user", content: transcript),
                ]
            ))
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else { throw ProviderError.unavailable }
            struct Response: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message
                }
                let choices: [Choice]
            }
            let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? transcript : content
        } catch {
            return transcript
        }
    }
}
