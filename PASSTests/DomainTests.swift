import Foundation
import Testing
@testable import PASS

struct ValidatorTests {
    @Test func displayNameTrimsAndCollapsesWhitespace() {
        #expect((try? Validators.displayName("  Maya   Chen ").get()) == "Maya Chen")
    }

    @Test func displayNameRejectsEmptyShortAndLong() {
        #expect(Validators.displayName("   ") == .failure(.required("Name")))
        #expect(Validators.displayName("M") == .failure(.tooShort("Name", 2)))
        #expect(Validators.displayName(String(repeating: "a", count: 31)) == .failure(.tooLong("Name", 30)))
    }

    @Test func groupAndChallengeRanges() {
        #expect((try? Validators.groupName("Friday Night Crew").get()) == "Friday Night Crew")
        #expect(Validators.challengeTitle("Hi") == .failure(.tooShort("Challenge", 3)))
        #expect((try? Validators.challengeTitle("Show us your dinner 🍽️").get()) == "Show us your dinner 🍽️")
    }

    @Test func dateOfBirthEnforcesSixteen() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cal = Calendar(identifier: .gregorian)
        let sixteenToday = cal.date(byAdding: .year, value: -16, to: now)!
        let almostSixteen = cal.date(byAdding: .day, value: 1, to: sixteenToday)!
        #expect((try? Validators.dateOfBirth(sixteenToday, now: now, calendar: cal).get()) != nil)
        if case .failure(let e) = Validators.dateOfBirth(almostSixteen, now: now, calendar: cal) {
            #expect(e.message.contains("16 or older"))
        } else { Issue.record("under 16 accepted") }
        #expect(Validators.dateOfBirth(now.addingTimeInterval(86_400), now: now, calendar: cal) == .failure(.invalid("Date of birth can't be in the future.")))
    }

    @Test func reportDetailsCapped() {
        #expect(Validators.reportDetails(String(repeating: "x", count: 501)) == .failure(.tooLong("Details", 500)))
        #expect((try? Validators.reportDetails("").get()) == "")
    }
}

struct InviteCodeTests {
    @Test func normalizesManyInputForms() {
        #expect(InviteCode.normalize("pass-fn74") == "PASS-FN74")
        #expect(InviteCode.normalize(" PASS FN74 ") == "PASS-FN74")
        #expect(InviteCode.normalize("fn74") == "PASS-FN74")
        #expect(InviteCode.normalize("https://pass-app.example/i/PASS-FN74") == "PASS-FN74")
        #expect(InviteCode.normalize("pass://i/pass-fn74") == "PASS-FN74")
    }

    @Test func rejectsConfusablesAndWrongLength() {
        #expect(InviteCode.normalize("PASS-FN7") == nil)
        #expect(InviteCode.normalize("PASS-FN70") == nil, "0 is not in the alphabet")
        #expect(InviteCode.normalize("PASS-FNO4") == nil, "O is not in the alphabet")
        #expect(InviteCode.normalize("") == nil)
    }

    @Test func generatedCodesAreValidAndDeterministicForSeed() {
        struct Seeded: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }
        var g1 = Seeded(s: 42), g2 = Seeded(s: 42)
        let a = InviteCode.generate(using: &g1), b = InviteCode.generate(using: &g2)
        #expect(a == b)
        #expect(InviteCode.normalize(a) == a)
    }
}

struct FormatterTests {
    @Test func countdownFormats() {
        #expect(PassFormatters.countdown(7087) == "1:58:07")
        #expect(PassFormatters.countdown(-5) == "0:00:00")
        #expect(PassFormatters.shortCountdown(899) == "14:59")
    }

    @Test func initialsAndFirstName() {
        #expect(PassFormatters.initials("Maya Chen") == "MC")
        #expect(PassFormatters.initials("Maya") == "MA")
        #expect(PassFormatters.initials("") == "?")
        #expect(PassFormatters.firstName("Jordan Lee") == "Jordan")
    }
}

struct RevealTimelineTests {
    func manifest(_ types: [MediaType], videoMs: Int? = 3000) -> RevealManifest {
        RevealManifest(relayID: "r", challengeTitle: "Worst selfie wins", groupName: "Crew", outcome: .complete, participantCount: types.count,
                       items: types.enumerated().map { RevealManifest.Item(position: $0.offset + 1, firstName: "P\($0.offset)", colorHex: "#FF6B35",
                                                                            mediaType: $0.element, fileName: "f", durationMs: $0.element == .video ? videoMs : nil) })
    }

    @Test func fivePhotosMatchTheFigmaMathWithTwoSecondIntro() {
        let segs = RevealTimeline.build(manifest(Array(repeating: .photo, count: 5)))
        #expect(segs.map(\.kind) == [.intro, .participant(index: 0), .participant(index: 1), .participant(index: 2), .participant(index: 3), .participant(index: 4), .recap, .passed, .end])
        #expect(abs(RevealTimeline.totalDuration(segs) - (2.0 + 5 * 1.6 + 1.8 + 2.2 + 2.4)) < 0.001)
        #expect(segs[1].start == 2.0)
    }

    @Test func videosUseTheirLengthCappedAtFourSeconds() {
        let segs = RevealTimeline.build(manifest([.photo, .video, .video], videoMs: 9000))
        #expect(segs[2].duration == 4.0)
        let short = RevealTimeline.build(manifest([.video], videoMs: 2500))
        #expect(short[1].duration == 2.5)
    }

    @Test func segmentLookupIsStable() {
        let segs = RevealTimeline.build(manifest([.photo, .photo]))
        #expect(RevealTimeline.segment(at: 0, in: segs)?.kind == .intro)
        #expect(RevealTimeline.segment(at: 2.0, in: segs)?.kind == .participant(index: 0))
        #expect(RevealTimeline.segment(at: 999, in: segs)?.kind == .end)
    }
}

struct DeepLinkTests {
    let config = AppConfiguration.current

    @Test func parsesSchemeAndUniversalLinks() {
        #expect(DeepLink.parse(URL(string: "pass://i/PASS-FN74")!, configuration: config) == .invite(code: "PASS-FN74"))
        #expect(DeepLink.parse(URL(string: "pass://invite?code=fn74")!, configuration: config) == .invite(code: "PASS-FN74"))
        #expect(DeepLink.parse(URL(string: "https://pass-app.example/i/PASS-FN74")!, configuration: config) == .invite(code: "PASS-FN74"))
    }

    @Test func ignoresUnknownOrMalformedLinks() {
        #expect(DeepLink.parse(URL(string: "https://evil.example/i/PASS-FN74")!, configuration: config) == nil)
        #expect(DeepLink.parse(URL(string: "pass://i/not-a-code")!, configuration: config) == nil)
        #expect(DeepLink.parse(URL(string: "pass://settings")!, configuration: config) == nil)
    }
}
