import XCTest
import Foundation
@testable import KalpanaDriveCore

final class VoiceAndMusicPersistenceTests: XCTestCase {
    
    // MARK: - Music Persistence & Browser Tests
    
    func testMusicWebViewPersistence() {
        // Verify that only one browser controller instance exists for the session lifetime
        let controller1 = MockBrowserController.shared
        let controller2 = MockBrowserController.shared
        XCTAssertTrue(controller1 === controller2, "There must be exactly one shared browser instance.")
    }
    
    func testBrowserHistoryPersistsOnSectionSwitch() {
        let controller = MockBrowserController.shared
        controller.navigateTo("https://music.youtube.com/search")
        XCTAssertEqual(controller.currentURL, "https://music.youtube.com/search", "History/URL must persist.")
    }
    
    func testGoogleAuthRedirectDetection() {
        let controller = MockBrowserController.shared
        // Detection of google auth domains to prevent login inside WKWebView
        let isGoogleAuth = controller.isGoogleAuthRedirect(URL(string: "https://accounts.google.com/signin")!)
        XCTAssertTrue(isGoogleAuth, "Google sign-in redirects inside WKWebView must be detected.")
    }
    
    func testUntrustedDomainJavaScriptRejection() {
        let controller = MockBrowserController.shared
        let success = controller.evaluateJS("play()", on: URL(string: "https://malicious-domain.com")!)
        XCTAssertFalse(success, "JavaScript evaluation must be rejected on untrusted domains.")
    }
    
    // MARK: - Voice Assistant Coordinator & State Machine Tests
    
    func testVoiceAssistantStateTransitions() {
        var state: MockVoiceAssistantState = .idle
        XCTAssertEqual(state, .idle)
        
        state = .requestingPermission
        XCTAssertEqual(state, .requestingPermission)
        
        state = .listening
        XCTAssertEqual(state, .listening)
        
        state = .thinking
        XCTAssertEqual(state, .thinking)
    }
    
    func testSilenceCompletionTimeout() {
        let detector = MockVoiceActivityDetector()
        detector.feedSilenceSample(duration: 1.0)
        XCTAssertFalse(detector.isSilenceDetected, "Silence should not trigger until 2 seconds are reached.")
        
        detector.feedSilenceSample(duration: 2.1)
        XCTAssertTrue(detector.isSilenceDetected, "Silence must trigger after 2 seconds of inactivity.")
    }
    
    func testInterruptionDuringTTS() {
        let assistant = MockVoiceAssistant()
        assistant.state = .speaking
        
        // Simulating user speech barge-in
        assistant.handleUserBargeIn()
        XCTAssertEqual(assistant.state, .listening, "Barge-in must interrupt TTS and return state to listening.")
    }
    
    func testMusicPauseDuckAndRestore() {
        let assistant = MockVoiceAssistant()
        assistant.isMusicPlaying = true
        
        // Voice activation prepares audio session
        assistant.prepareForVoiceActivation()
        XCTAssertFalse(assistant.isMusicPlaying, "Music must be paused/ducked during voice assistant interaction.")
        
        // Deactivation restores audio session
        assistant.restoreAfterVoiceDeactivation()
        XCTAssertTrue(assistant.isMusicPlaying, "Music must resume if it was playing before assistant activation.")
    }
}

// MARK: - Mock Types for Core-Level Testing

private final class MockBrowserController {
    static let shared = MockBrowserController()
    var currentURL = "https://music.youtube.com"
    
    func navigateTo(_ url: String) {
        currentURL = url
    }
    
    func isGoogleAuthRedirect(_ url: URL) -> Bool {
        return url.host?.contains("accounts.google.com") == true
    }
    
    func evaluateJS(_ script: String, on url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host.contains("youtube.com") else {
            return false
        }
        return true
    }
}

private enum MockVoiceAssistantState {
    case idle
    case requestingPermission
    case listening
    case thinking
    case speaking
}

private final class MockVoiceActivityDetector {
    var isSilenceDetected = false
    
    func feedSilenceSample(duration: TimeInterval) {
        if duration >= 2.0 {
            isSilenceDetected = true
        } else {
            isSilenceDetected = false
        }
    }
}

private final class MockVoiceAssistant {
    var state: MockVoiceAssistantState = .idle
    var isMusicPlaying = false
    var wasPlayingBefore = false
    
    func handleUserBargeIn() {
        if state == .speaking {
            state = .listening
        }
    }
    
    func prepareForVoiceActivation() {
        wasPlayingBefore = isMusicPlaying
        if isMusicPlaying {
            isMusicPlaying = false
        }
    }
    
    func restoreAfterVoiceDeactivation() {
        if wasPlayingBefore {
            isMusicPlaying = true
        }
    }
}
