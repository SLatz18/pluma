import XCTest
@testable import Pluma

final class DebugLogLevelTests: XCTestCase {
    private var originalLevel = DebugLog.Level.normal

    override func setUp() {
        super.setUp()
        originalLevel = DebugLog.level
    }

    override func tearDown() {
        DebugLog.level = originalLevel
        super.tearDown()
    }

    /// The property the whole design rests on: verbose tracing sits inside
    /// CaretResolver, which runs on every keystroke, so a filtered-out call has
    /// to cost an integer compare and nothing else — no interpolation, no rect
    /// formatting, no allocation. If this test ever fails, verbose logging has
    /// started costing something on the typing path.
    func testFilteredOutMessageIsNeverEvaluated() {
        DebugLog.level = .normal

        var evaluations = 0
        func expensiveMessage() -> String {
            evaluations += 1
            return "should never be built"
        }

        DebugLog.log(expensiveMessage(), at: .verbose)
        XCTAssertEqual(evaluations, 0)
    }

    func testMessageAtOrBelowTheCurrentLevelIsEvaluated() {
        DebugLog.level = .verbose

        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return "verbose test line"
        }

        DebugLog.log(message(), at: .verbose)
        XCTAssertEqual(evaluations, 1)
    }

    func testQuietStillLetsFailuresThrough() {
        DebugLog.level = .quiet

        var quietEvaluations = 0
        var normalEvaluations = 0
        DebugLog.log({ quietEvaluations += 1; return "failure" }(), at: .quiet)
        DebugLog.log({ normalEvaluations += 1; return "chatter" }(), at: .normal)

        XCTAssertEqual(quietEvaluations, 1)
        XCTAssertEqual(normalEvaluations, 0)
    }

    func testDefaultLevelForUntaggedCallsIsNormal() {
        DebugLog.level = .quiet

        var evaluations = 0
        DebugLog.log({ evaluations += 1; return "untagged" }())
        XCTAssertEqual(evaluations, 0, "an untagged call should behave as .normal")

        DebugLog.level = .normal
        DebugLog.log({ evaluations += 1; return "untagged" }())
        XCTAssertEqual(evaluations, 1)
    }

    func testLevelsAreOrderedQuietToVerbose() {
        XCTAssertLessThan(DebugLog.Level.quiet.rawValue, DebugLog.Level.normal.rawValue)
        XCTAssertLessThan(DebugLog.Level.normal.rawValue, DebugLog.Level.verbose.rawValue)
    }

    func testPreferencesRoundTripAndDefaultToNormal() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DebugLogLevelTests"))
        defaults.removePersistentDomain(forName: "DebugLogLevelTests")

        XCTAssertEqual(Preferences.logLevel(from: defaults), .normal)

        Preferences.setLogLevel(.verbose, to: defaults)
        XCTAssertEqual(Preferences.logLevel(from: defaults), .verbose)

        defaults.set(99, forKey: Preferences.logLevelKey)
        XCTAssertEqual(Preferences.logLevel(from: defaults), .normal, "garbage falls back")

        defaults.removePersistentDomain(forName: "DebugLogLevelTests")
    }
}
