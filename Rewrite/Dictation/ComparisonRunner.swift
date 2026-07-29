import Foundation

struct TranscriptResult: Identifiable, Sendable {
    let source: String
    let text: String?
    let failure: String?
    let seconds: Double

    var id: String { source }
}

struct CleanupResult: Identifiable, Sendable {
    let transcriber: String
    let cleaner: String
    let output: String?
    let failure: String?
    let seconds: Double

    var id: String { "\(transcriber) → \(cleaner)" }
}

// Records once, transcribes that one recording with both engines, then runs every
// transcript through every cleanup model. One recording is the whole point: two
// separate recordings of "the same" sentence differ in ways that would show up as
// a difference between the transcribers.
@MainActor
final class ComparisonRunner: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcripts: [TranscriptResult] = []
    @Published private(set) var cleanups: [CleanupResult] = []

    private let recorder = AudioSampleRecorder()

    var isRecording: Bool { phase == .recording }

    var isBusy: Bool {
        switch phase {
        case .transcribing, .cleaning: true
        default: false
        }
    }

    func startRecording() {
        transcripts = []
        cleanups = []
        do {
            try recorder.start()
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopAndCompare(openAIModel: OpenAIChatModel) async {
        guard phase == .recording else { return }

        let samples = await recorder.stop()
        guard !samples.isEmpty else {
            phase = .failed("Nothing was recorded")
            return
        }

        phase = .transcribing
        let fileURL: URL
        do {
            fileURL = try AudioSampleRecorder.writeWav(samples)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        transcripts = await transcribeBothWays(fileURL: fileURL, wav: PCM16Audio.wav(from: samples))

        let usable = transcripts.filter { $0.text?.isEmpty == false }
        guard !usable.isEmpty else {
            phase = .failed("Neither transcriber returned any text")
            return
        }

        phase = .cleaning
        cleanups = await cleanEveryWay(transcripts: usable, openAIModel: openAIModel)
        phase = .done
    }

    // Neither transcriber is given the screen-context terms here. Biasing only one
    // of them would show up as a quality difference that isn't one.
    private func transcribeBothWays(fileURL: URL, wav: Data) async -> [TranscriptResult] {
        await withTaskGroup(of: (Int, TranscriptResult).self) { group in
            group.addTask {
                let started = ContinuousClock.Instant.now
                do {
                    let text = try await AppleFileTranscriber.transcribe(fileURL: fileURL)
                    return (
                        0,
                        TranscriptResult(
                            source: DictationProviderChoice.appleOnDevice.title,
                            text: text,
                            failure: nil,
                            seconds: Self.elapsed(since: started)
                        )
                    )
                } catch {
                    return (
                        0,
                        TranscriptResult(
                            source: DictationProviderChoice.appleOnDevice.title,
                            text: nil,
                            failure: error.localizedDescription,
                            seconds: Self.elapsed(since: started)
                        )
                    )
                }
            }

            group.addTask {
                let started = ContinuousClock.Instant.now
                do {
                    let text = try await OpenAIFileTranscriber.transcribe(wav: wav, keywords: [])
                    return (
                        1,
                        TranscriptResult(
                            source: DictationProviderChoice.openAI.title,
                            text: text,
                            failure: nil,
                            seconds: Self.elapsed(since: started)
                        )
                    )
                } catch {
                    return (
                        1,
                        TranscriptResult(
                            source: DictationProviderChoice.openAI.title,
                            text: nil,
                            failure: error.localizedDescription,
                            seconds: Self.elapsed(since: started)
                        )
                    )
                }
            }

            var results: [(Int, TranscriptResult)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private struct CleanupJob: Sendable {
        let order: Int
        let transcriber: String
        let transcript: String
        let provider: CleanupProviderChoice
        let label: String
    }

    // Two on-device cleanups running at once contend for the same local model, so
    // both report a time neither would take alone — which reads as the on-device
    // model being slow rather than as measurement error. On-device work is
    // therefore serialized. Network calls spend their time waiting, so they can
    // overlap each other and the local work without distorting anything.
    private func cleanEveryWay(
        transcripts: [TranscriptResult],
        openAIModel: OpenAIChatModel
    ) async -> [CleanupResult] {
        let cleaners: [(CleanupProviderChoice, String)] = [
            (.appleOnDevice, CleanupProviderChoice.appleOnDevice.title),
            (.openAI, openAIModel.title)
        ]

        var jobs: [CleanupJob] = []
        for transcript in transcripts {
            for cleaner in cleaners {
                jobs.append(
                    CleanupJob(
                        order: jobs.count,
                        transcriber: transcript.source,
                        transcript: transcript.text ?? "",
                        provider: cleaner.0,
                        label: cleaner.1
                    )
                )
            }
        }

        async let remote = Self.runConcurrently(
            jobs.filter { $0.provider == .openAI }, openAIModel: openAIModel
        )
        let local = await Self.runOneAtATime(
            jobs.filter { $0.provider == .appleOnDevice }, openAIModel: openAIModel
        )

        let remoteResults = await remote
        return (local + remoteResults)
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    nonisolated private static func runOneAtATime(
        _ jobs: [CleanupJob],
        openAIModel: OpenAIChatModel
    ) async -> [(Int, CleanupResult)] {
        var results: [(Int, CleanupResult)] = []
        for job in jobs {
            results.append(await run(job, openAIModel: openAIModel))
        }
        return results
    }

    nonisolated private static func runConcurrently(
        _ jobs: [CleanupJob],
        openAIModel: OpenAIChatModel
    ) async -> [(Int, CleanupResult)] {
        await withTaskGroup(of: (Int, CleanupResult).self) { group in
            for job in jobs {
                group.addTask { await run(job, openAIModel: openAIModel) }
            }
            var results: [(Int, CleanupResult)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    nonisolated private static func run(
        _ job: CleanupJob,
        openAIModel: OpenAIChatModel
    ) async -> (Int, CleanupResult) {
        let started = ContinuousClock.Instant.now
        do {
            let output = try await RewriteRunner.runCleanup(
                provider: job.provider,
                openAIModel: openAIModel,
                transcript: job.transcript
            )
            return (
                job.order,
                CleanupResult(
                    transcriber: job.transcriber,
                    cleaner: job.label,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    failure: nil,
                    seconds: elapsed(since: started)
                )
            )
        } catch {
            return (
                job.order,
                CleanupResult(
                    transcriber: job.transcriber,
                    cleaner: job.label,
                    output: nil,
                    failure: error.localizedDescription,
                    seconds: elapsed(since: started)
                )
            )
        }
    }

    nonisolated private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.Instant.now - start
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}
