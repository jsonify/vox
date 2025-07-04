// AudioProcessor.swift - Line Length Fixes
// Apply these changes to fix line length violations

// BEFORE (132 chars):
// private func performAudioExtractionWithFallback(inputURL: URL, inputPath: String, tempOutputURL: URL, progressCallback: ProgressCallback?, completion: @escaping CompletionCallback) {

// AFTER:
private func performAudioExtractionWithFallback(
    inputURL: URL,
    inputPath: String,
    tempOutputURL: URL,
    progressCallback: ProgressCallback?,
    completion: @escaping CompletionCallback
) {

// BEFORE (141 chars):
// private func handleFailedExtraction(inputPath: String, tempOutputURL: URL, error: VoxError, progressCallback: ProgressCallback?, completion: @escaping CompletionCallback) {

// AFTER:
private func handleFailedExtraction(
    inputPath: String,
    tempOutputURL: URL,
    error: VoxError,
    progressCallback: ProgressCallback?,
    completion: @escaping CompletionCallback
) {

// BEFORE (160 chars):
// private func extractAudioUsingAVFoundation(from inputURL: URL, to outputURL: URL, progressCallback: ProgressCallback?, completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {

// AFTER:
private func extractAudioUsingAVFoundation(
    from inputURL: URL,
    to outputURL: URL,
    progressCallback: ProgressCallback?,
    completion: @escaping (Result<AudioFormat, VoxError>) -> Void
) {

// BEFORE (158 chars):
// private func handleExportCompletion(exportSession: AVAssetExportSession, asset: AVAsset, outputURL: URL, progressTimer: Timer, completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {

// AFTER:
private func handleExportCompletion(
    exportSession: AVAssetExportSession,
    asset: AVAsset,
    outputURL: URL,
    progressTimer: Timer,
    completion: @escaping (Result<AudioFormat, VoxError>) -> Void
) {

// BEFORE (121 chars):
// logger.warn("AVFoundation extraction failed, attempting ffmpeg fallback: \(error.localizedDescription)", component: "AudioProcessor")

// AFTER:
logger.warn(
    "AVFoundation extraction failed, attempting ffmpeg fallback: \(error.localizedDescription)",
    component: "AudioProcessor"
)

// For long variable assignments, break at logical points:
// BEFORE:
// let error = VoxError.incompatibleAudioProperties("Audio format not compatible with transcription engines: \(audioFormat.description)")

// AFTER:
let error = VoxError.incompatibleAudioProperties(
    "Audio format not compatible with transcription engines: \(audioFormat.description)"
)