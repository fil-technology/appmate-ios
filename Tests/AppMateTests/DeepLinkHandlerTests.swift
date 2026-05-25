import XCTest
@testable import AppMate

final class DeepLinkHandlerTests: XCTestCase {

    func testParsesReturnToApp() throws {
        let url = URL(string: "myapp://retention-flow/action?type=return_to_app&session_id=sid_123")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(link.action, .returnToApp)
        XCTAssertEqual(link.sessionId, "sid_123")
    }

    func testParsesOpenPremium() throws {
        let url = URL(string: "myapp://retention-flow/action?type=open_premium&session_id=sid_x")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(link.action, .openPremium)
    }

    func testParsesOpenSupport() throws {
        let url = URL(string: "myapp://retention-flow/action?type=open_support&session_id=sid")!
        let link = try XCTUnwrap(RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp"))
        XCTAssertEqual(link.action, .openSupport)
    }

    func testParsesOpenFeature() throws {
        let url = URL(string: "myapp://retention-flow/action?type=open_feature&feature_id=onboarding&session_id=sid")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(link.action, .openFeature(id: "onboarding"))
    }

    func testRejectsOpenFeatureWithoutId() {
        let url = URL(string: "myapp://retention-flow/action?type=open_feature&session_id=sid")!
        XCTAssertNil(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
    }

    func testParsesManageSubscription() throws {
        let url = URL(string: "myapp://retention-flow/action?type=manage_subscription&session_id=sid")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(link.action, .manageSubscription)
    }

    func testParsesExternalURL() throws {
        let url = URL(string: "myapp://retention-flow/action?type=external_url&url=https://example.com/help&session_id=sid")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(
            link.action,
            .externalURL(URL(string: "https://example.com/help")!)
        )
    }

    func testParsesNoneForUnknownTypeWithoutFailing() throws {
        let url = URL(string: "myapp://retention-flow/action?type=future_action&session_id=sid")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
        XCTAssertEqual(link.action, .none)
    }

    func testRejectsWrongScheme() {
        let url = URL(string: "otherapp://retention-flow/action?type=return_to_app&session_id=sid")!
        XCTAssertNil(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
    }

    func testRejectsWrongHost() {
        let url = URL(string: "myapp://other-host/action?type=return_to_app")!
        XCTAssertNil(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
    }

    func testRejectsWrongPath() {
        let url = URL(string: "myapp://retention-flow/elsewhere?type=return_to_app")!
        XCTAssertNil(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
    }

    func testRejectsMissingType() {
        let url = URL(string: "myapp://retention-flow/action?session_id=sid")!
        XCTAssertNil(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: "myapp")
        )
    }

    func testAcceptsAnySchemeWhenExpectedIsNil() throws {
        let url = URL(string: "whatever://retention-flow/action?type=return_to_app")!
        let link = try XCTUnwrap(
            RetentionFlowDeepLinkHandler.parse(url, expectedScheme: nil)
        )
        XCTAssertEqual(link.action, .returnToApp)
    }
}
