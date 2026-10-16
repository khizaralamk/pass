import XCTest

/// Critical journeys on the simulator against the in-app mock backend. Screenshots go to `PASS_UI_SHOTS` if set.
final class CoreJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ args: [String]) {
        app.launchArguments = args
        app.launch()
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png", name: "\(name).png", payload: data, userInfo: nil)
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["PASS_UI_SHOTS"] {
            try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Taps the top-most element with the identifier (earlier screens in a NavigationStack stay in the hierarchy).
    private func tap(_ id: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let query = app.descendants(matching: .any)[id]
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: timeout), "missing \(id)", file: file, line: line)
        let matches = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
        let target = matches.last(where: { $0.isHittable }) ?? query.firstMatch
        // Let push/present transitions finish; taps during a SwiftUI navigation transition are dropped.
        _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: target)], timeout: 5)
        usleep(450_000)
        target.tap()
    }

    private func waitUntilGone(_ el: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: el)], timeout: timeout) == .completed
    }

    private func exists(_ id: String, timeout: TimeInterval = 8) -> Bool {
        app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: Launch → sign in → onboarding → Home

    func testOnboardingValidationAndCompletion() {
        launch(["-resetState"])
        XCTAssertTrue(exists("splash.demo"))
        shot("01-splash")
        tap("splash.demo")

        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("M")
        tap("onboarding.continue")
        XCTAssertTrue(app.staticTexts["Error: Name needs at least 2 characters."].waitForExistence(timeout: 3), "short name must be rejected")
        shot("02-onboarding-name-error")
        name.tap()
        name.typeText("aya")
        tap("onboarding.continue")

        XCTAssertTrue(exists("onboarding.birthday"))
        shot("03-onboarding-birthday")
        tap("onboarding.continue")
        tap("onboarding.continue") // photo: skip
        XCTAssertTrue(exists("onboarding.agree"))
        let getStarted = app.descendants(matching: .any)["onboarding.continue"].firstMatch
        XCTAssertFalse(getStarted.isEnabled, "Get started is disabled until terms are accepted")
        tap("onboarding.agree")
        shot("04-onboarding-terms")
        tap("onboarding.continue")
        tap("onboarding.notifications.skip")
        XCTAssertTrue(exists("home.list"))
        shot("05-home-after-onboarding")
    }

    // MARK: Core loop: Baton → camera → preview → pass → progress → complete → reveal → post-reveal

    func testFullRelayLoop() {
        launch(["-demoSession", "-resetState"])
        XCTAssertTrue(exists("home.takeTurn"))
        shot("10-home")
        tap("home.takeTurn")
        XCTAssertTrue(exists("baton.openCamera"))
        shot("11-baton")
        tap("baton.openCamera")
        XCTAssertTrue(exists("capture.shutter"))
        shot("12-camera")
        tap("capture.shutter")
        XCTAssertTrue(exists("preview.use"))
        shot("13-preview")
        tap("preview.retake")
        XCTAssertTrue(exists("capture.shutter"))
        tap("capture.shutter")
        tap("preview.use")

        XCTAssertTrue(exists("pass.confirm"))
        XCTAssertFalse(app.descendants(matching: .any)["pass.confirm"].firstMatch.isEnabled, "needs a selection first")
        shot("14-pass-baton")
        tap("pass.member.maya")
        tap("pass.confirm")

        XCTAssertTrue(app.staticTexts["Relay Progress"].waitForExistence(timeout: 8))
        shot("15-progress")
        // Simulate the remaining members (Maya, Zoe, Cam) until the relay completes.
        for _ in 0..<4 {
            if exists("complete.watch", timeout: 2) { break }
            tap("demo.nextMember")
        }
        XCTAssertTrue(exists("complete.watch"))
        shot("16-complete")
        tap("complete.watch")
        sleep(6)
        shot("17-reveal")
        XCTAssertTrue(exists("post.share", timeout: 30), "reveal should end on the post-reveal screen")
        shot("18-post-reveal")
        tap("post.watchAgain")
        XCTAssertTrue(exists("reveal.close", timeout: 5))
        let close = app.descendants(matching: .any)["reveal.close"].firstMatch
        XCTAssertTrue(waitUntilGone(close, timeout: 40), "reveal should finish and dismiss itself")
        XCTAssertTrue(exists("post.share", timeout: 10))
        tap("nav.back")
        sleep(2)
        shot("19-home-after-loop")
        XCTAssertTrue(exists("home.empty"), "no active relays after completion")
    }

    // MARK: Groups

    func testCreateGroupAndThreeMemberRule() {
        launch(["-demoSession", "-resetState"])
        tap("home.newGroup")
        let field = app.textFields["createGroup.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["createGroup.continue"].firstMatch.isEnabled)
        field.tap()
        field.typeText("Brunch Squad")
        shot("20-create-group")
        tap("createGroup.continue")
        XCTAssertTrue(exists("invite.codeLabel"))
        shot("21-invite")
        tap("invite.copy")
        tap("invite.done")
        XCTAssertTrue(exists("created.startRelay"))
        XCTAssertFalse(app.descendants(matching: .any)["created.startRelay"].firstMatch.isEnabled, "1 member cannot start a relay")
        shot("22-group-created")
        tap("created.goToGroup")
        XCTAssertTrue(exists("group.startRelay"))
        XCTAssertFalse(app.descendants(matching: .any)["group.startRelay"].firstMatch.isEnabled)
        shot("23-group-detail")
        tap("nav.back")
        XCTAssertTrue(app.staticTexts["Brunch Squad"].waitForExistence(timeout: 5))
    }

    func testGroupDetailAndSettings() {
        launch(["-demoSession", "-resetState"])
        tap("home.group.friday")
        XCTAssertTrue(app.staticTexts["Friday Night Crew"].waitForExistence(timeout: 8))
        shot("30-group-friday")
        tap("group.history")
        XCTAssertTrue(app.staticTexts["Past Relays"].waitForExistence(timeout: 8))
        shot("31-history")
        tap("nav.back")
        tap("nav.back")
        tap("home.profile")
        XCTAssertTrue(exists("settings.notifications"))
        shot("40-profile")
        tap("settings.notifications")
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 8))
        shot("41-notifications")
        tap("nav.back")
        tap("settings.inviteCode")
        let code = app.textFields["invite.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        code.tap()
        code.typeText("PASS-BR22")
        tap("invite.open")
        XCTAssertTrue(exists("invite.openIt"))
        shot("50-invite")
        tap("invite.openIt")
        XCTAssertTrue(exists("invite.join"))
        shot("51-join")
        tap("invite.join")
        XCTAssertTrue(app.staticTexts["Brunch Club"].waitForExistence(timeout: 8))
        shot("52-joined-group")
    }

    func testDeepLinkOpensInvite() {
        launch(["-demoSession", "-resetState"])
        XCTAssertTrue(exists("home.list"))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        _ = safari
        // Open the custom scheme through the system (simulates tapping a link).
        app.terminate()
        app.launchArguments = ["-demoSession"]
        app.launch()
        XCUIDevice.shared.system.open(URL(string: "pass://i/PASS-BR22")!)
        XCTAssertTrue(exists("invite.openIt", timeout: 15))
        shot("60-deeplink-invite")
    }
}
