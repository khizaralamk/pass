import Testing
@testable import PASS

struct SmokeTests {
    @Test func configurationIsValid() {
        #expect(AppConfiguration.current.validate().isEmpty)
    }
}
