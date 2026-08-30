import Foundation
import Testing
@testable import NODAYSIDLEVoice

private actor RequestCapture {
    private var body: Data?
    func set(_ body: Data?) { self.body = body }
    func value() -> Data? { body }
}

@Test func deepgramUsesNovaThreeLinearPCMAndIgnoresInterimTextForInsertion() throws {
    let url = try DeepgramEngine.endpoint(sampleRate: 16_000, channels: 1, language: "it", keyterms: ["Codex", "SwiftData"])
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = try #require(components.queryItems)
    let query = Dictionary(items.compactMap { item -> (String, String)? in
        guard item.name != "keyterm", let value = item.value else { return nil }
        return (item.name, value)
    }, uniquingKeysWith: { first, _ in first })

    #expect(components.scheme == "wss")
    #expect(components.host == "api.deepgram.com")
    #expect(query["model"] == "nova-3")
    #expect(query["encoding"] == "linear16")
    #expect(query["sample_rate"] == "16000")
    #expect(query["channels"] == "1")
    #expect(query["interim_results"] == "true")
    #expect(query["language"] == "it")
    #expect(items.filter { $0.name == "keyterm" }.compactMap(\.value) == ["Codex", "SwiftData"])

    let interim = Data(#"{"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"partial"}]}}"#.utf8)
    let final = Data(#"{"type":"Results","is_final":true,"speech_final":true,"channel":{"alternatives":[{"transcript":"Final text."}]}}"#.utf8)
    #expect(try DeepgramEngine.parseResult(interim) == nil)
    #expect(try DeepgramEngine.parseUpdate(interim) == .interim("partial"))
    #expect(try DeepgramEngine.parseResult(final) == "Final text.")
    #expect(try DeepgramEngine.parseUpdate(final) == .final("Final text."))
}

@Test func deepgramInterimNeverCountsAsInsertableFinal() throws {
    let interim = Data(#"{"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"do not paste this"}]}}"#.utf8)
    let final = Data(#"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"paste only this"}]}}"#.utf8)
    #expect(try DeepgramEngine.parseResult(interim) == nil)
    #expect(try DeepgramEngine.parseUpdate(interim) == .interim("do not paste this"))
    #expect(try DeepgramEngine.parseResult(final) == "paste only this")
}
    let request = try OpenRouterSTTEngine.request(
        audio: Data([0, 1, 2, 3]),
        format: "wav",
        model: "openai/whisper-large-v3",
        credential: "test-token",
        language: "sl"
    )
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let inputAudio = try #require(json["input_audio"] as? [String: Any])

    #expect(request.url?.path == "/api/v1/audio/transcriptions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    #expect(inputAudio["data"] as? String == "AAECAw==")
    #expect(json["language"] as? String == "sl")
    #expect(!(String(decoding: body, as: UTF8.self).contains("test-token")))
    #expect(throws: ProviderError.unsupportedAudioFormat) {
        _ = try OpenRouterSTTEngine.request(audio: Data(), format: "caf", model: "model", credential: "token")
    }
    #expect(throws: ProviderError.audioTooLarge) {
        _ = try OpenRouterSTTEngine.request(
            audio: Data(count: OpenRouterSTTEngine.maximumAudioBytes + 1),
            format: "wav",
            model: "model",
            credential: "token"
        )
    }
}

@Test func openRouterCatalogRequestsOnlyTranscriptionModelsWithoutPuttingTheKeyInTheURL() throws {
    let request = try OpenRouterModelCatalog.request(credential: "catalog-token")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.path == "/api/v1/models")
    #expect(components.queryItems == [URLQueryItem(name: "output_modalities", value: "transcription")])
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer catalog-token")
    #expect(!(request.url?.absoluteString.contains("catalog-token") ?? true))

    let models = try OpenRouterModelCatalog.parse(Data(#"{"data":[{"id":"provider/stt","name":"STT Model"}]}"#.utf8))
    #expect(models == [OpenRouterCatalogModel(id: "provider/stt", name: "STT Model")])
}

@Test func openRouterRateLimitIsClassifiedWithoutParsingAFalseTranscript() async {
    let engine = OpenRouterSTTEngine(transport: { request in
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        ) else { throw ProviderError.invalidResponse }
        return (Data(#"{"error":{"message":"slow down"}}"#.utf8), response)
    })

    await #expect(throws: ProviderError.rateLimited) {
        _ = try await engine.transcribe(
            audio: Data([0]),
            format: "wav",
            model: "openai/whisper-large-v3",
            credential: "token"
        )
    }
}

@Test func refinementFailureReturnsTheCompletedRawTranscript() async {
    let service = RefinementService(transport: { request in
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        ) else { throw ProviderError.invalidResponse }
        return (Data(), response)
    })

    let text = await service.refine(
        "raw completed transcript",
        instruction: "Make it concise.",
        model: "text-model",
        credential: "token"
    )
    #expect(text == "raw completed transcript")
}

@Test func refinementSendsOnlyTheActiveModeInstructionAndCompletedTranscript() async throws {
    let capture = RequestCapture()
    let service = RefinementService(transport: { request in
        await capture.set(request.httpBody)
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) else { throw ProviderError.invalidResponse }
        return (Data(#"{"choices":[{"message":{"content":"Clean result"}}]}"#.utf8), response)
    })

    let result = await service.refine(
        "active completed transcript",
        instruction: "Active mode only.",
        model: "provider/text-model",
        credential: "test-token"
    )
    let body = try #require(await capture.value())
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(json["messages"] as? [[String: String]])

    #expect(result == "Clean result")
    #expect(messages == [
        ["role": "system", "content": "Active mode only."],
        ["role": "user", "content": "active completed transcript"],
    ])
    #expect(json["temperature"] as? Double == 0)
    #expect(!String(decoding: body, as: UTF8.self).contains("test-token"))
    #expect(!String(decoding: body, as: UTF8.self).contains("inactive mode"))
}
