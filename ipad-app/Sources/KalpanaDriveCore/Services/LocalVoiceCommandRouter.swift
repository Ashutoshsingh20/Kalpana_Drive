import Foundation

public actor LocalVoiceCommandRouter: SpeechCommandRouter {
    public init() {}

    public func route(_ transcript: String, state: DrivingState) async -> VoiceResponse {
        let command = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch command {
        case "navigate home", "take me home", "ghar chalo":
            return VoiceResponse(spokenText: "Starting directions home.", visualText: "Navigate home")
        case "pause music", "music pause karo":
            return VoiceResponse(spokenText: "Pausing music.", visualText: "Music paused")
        case "play music", "music chalao":
            return VoiceResponse(spokenText: "Playing music.", visualText: "Music playing")
        case "what is my eta", "eta kya hai":
            return VoiceResponse(spokenText: "No active route.", visualText: "No active route")
        default:
            let short = state.restrictsInteraction
                ? "I can't do that locally while driving."
                : "That command is not available offline yet."
            return VoiceResponse(spokenText: short, visualText: short)
        }
    }
}

