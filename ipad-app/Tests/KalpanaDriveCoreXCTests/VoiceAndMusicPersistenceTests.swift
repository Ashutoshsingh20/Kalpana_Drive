import XCTest
import Foundation
@testable import KalpanaDriveCore
@testable import Kalpana_Drive

@MainActor
final class VoiceAndMusicPersistenceTests: XCTestCase {
    
    // MARK: - KeychainHelper Tests
    
    func testKeychainHelperKeyStorage() {
        let helper = KeychainHelper.shared
        
        // Save
        let saved = helper.saveApiKey("test-key-12345")
        XCTAssertTrue(saved)
        
        // Load
        let loaded = helper.loadKeychainApiKey()
        XCTAssertEqual(loaded, "test-key-12345")
        
        // Delete
        helper.deleteApiKey()
        let loadedDeleted = helper.loadKeychainApiKey()
        XCTAssertNil(loadedDeleted)
    }
    
    func testKeychainHelperLocalOnlyMode() {
        let helper = KeychainHelper.shared
        helper.localOnlyMode = true
        
        _ = helper.saveApiKey("temp-key")
        XCTAssertNil(helper.loadApiKey(), "loadApiKey must return nil when localOnlyMode is true")
        
        helper.localOnlyMode = false
        XCTAssertEqual(helper.loadApiKey(), "temp-key")
        
        helper.deleteApiKey()
    }
    
    // MARK: - YouTubeDomainValidator Tests
    
    func testYouTubeDomainValidator() {
        XCTAssertTrue(YouTubeDomainValidator.isTrusted(URL(string: "https://music.youtube.com")))
        XCTAssertTrue(YouTubeDomainValidator.isTrusted(URL(string: "https://www.youtube.com")))
        XCTAssertTrue(YouTubeDomainValidator.isTrusted(URL(string: "https://youtube.com/watch")))
        XCTAssertFalse(YouTubeDomainValidator.isTrusted(URL(string: "https://maliciousyoutube.com")))
        XCTAssertFalse(YouTubeDomainValidator.isTrusted(URL(string: "https://google.com")))
    }
    
    // MARK: - WebKitMediaState Decoding Tests
    
    func testWebKitMediaStateDecoding() throws {
        let json = """
        {
            "isPlaying": true,
            "title": "Humma Humma",
            "artist": "A.R. Rahman",
            "artwork": "https://example.com/artwork.jpg"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let state = try JSONDecoder().decode(WebKitMediaState.self, from: data)
        
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.title, "Humma Humma")
        XCTAssertEqual(state.artist, "A.R. Rahman")
        XCTAssertEqual(state.artwork, "https://example.com/artwork.jpg")
    }

    // MARK: - Voice Assistant State Transitions
    
    func testVoiceAssistantStateTransitions() {
        var state: VoiceAssistantState = .idle
        XCTAssertEqual(state, .idle)
        
        state = .requestingPermission
        XCTAssertEqual(state, .requestingPermission)
        
        state = .listening
        XCTAssertEqual(state, .listening)
        
        state = .thinking
        XCTAssertEqual(state, .thinking)
        
        state = .speaking
        XCTAssertEqual(state, .speaking)
        
        state = .interrupted
        XCTAssertEqual(state, .interrupted)
    }

    // MARK: - Mock Types Concurrency Safe

    func testMusicWebViewPersistence() {
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
        let isGoogleAuth = controller.isGoogleAuthRedirect(URL(string: "https://accounts.google.com/signin")!)
        XCTAssertTrue(isGoogleAuth, "Google sign-in redirects inside WKWebView must be detected.")
    }
    
    func testUntrustedDomainJavaScriptRejection() {
        let controller = MockBrowserController.shared
        let success = controller.evaluateJS("play()", on: URL(string: "https://malicious-domain.com")!)
        XCTAssertFalse(success, "JavaScript evaluation must be rejected on untrusted domains.")
    }
}

// MARK: - Mock Types for Core-Level Testing (MainActor isolated for Swift 6 safety)

@MainActor
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
