import XCTest
@testable import Lemwincher

/// Le 16 novembre 2026 est un lundi ; le 21 un samedi ; le 22 un dimanche.
final class OpeningHoursTests: XCTestCase {
    private let cal = Fixtures.paris

    private func hours(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> OpeningHours {
        try XCTUnwrap(OpeningHours(text), "« \(text) » devrait être compris", file: file, line: line)
    }

    private func text(_ h: OpeningHours, _ day: Int, _ hour: Int, _ minute: Int = 0) -> String {
        h.statusText(at: Fixtures.date(2026, 11, day, hour, minute), calendar: cal)
    }

    func testTypicalSupermarket() throws {
        let h = try hours("Mo-Sa 08:30-20:00; Su 09:00-12:30")
        XCTAssertEqual(h.week[0], [OpeningHours.Span(start: 510, end: 1200)])
        XCTAssertEqual(h.week[6], [OpeningHours.Span(start: 540, end: 750)])
        XCTAssertEqual(h.description(forDay: 0), "8h30–20h")
        XCTAssertEqual(h.description(forDay: 6), "9h–12h30")
        XCTAssertFalse(h.isAlwaysOpen)

        XCTAssertEqual(text(h, 16, 10), "Ouvert · ferme à 20h")
        XCTAssertEqual(text(h, 16, 19, 30), "Ferme bientôt (20h)")
        XCTAssertEqual(text(h, 16, 7), "Fermé · ouvre à 8h30")
        XCTAssertEqual(text(h, 16, 21), "Fermé · ouvre demain à 8h30")
        XCTAssertEqual(text(h, 22, 13), "Fermé · ouvre demain à 8h30")
        XCTAssertTrue(h.status(at: Fixtures.date(2026, 11, 22, 10), calendar: cal).isOpen)
    }

    func testClosedOnWeekend() throws {
        let h = try hours("Mo-Fr 08:00-20:00")
        XCTAssertEqual(h.description(forDay: 5), "Fermé")
        XCTAssertEqual(text(h, 21, 21), "Fermé · ouvre lundi à 8h")
    }

    func testLunchBreak() throws {
        let h = try hours("Mo-Fr 08:00-12:00,14:00-18:00")
        XCTAssertEqual(h.week[0].count, 2)
        XCTAssertEqual(text(h, 16, 13), "Fermé · ouvre à 14h")
        XCTAssertEqual(h.description(forDay: 0), "8h–12h, 14h–18h")
    }

    func testAlwaysOpen() throws {
        let always = try hours("24/7")
        let allDay = try hours("Mo-Su 00:00-24:00")
        XCTAssertTrue(always.isAlwaysOpen)
        XCTAssertTrue(allDay.isAlwaysOpen)
        XCTAssertEqual(text(always, 16, 3), "Ouvert 24 h/24")
        XCTAssertEqual(always.description(forDay: 2), "24 h/24")
    }

    func testPastMidnight() throws {
        let h = try hours("Fr-Sa 18:00-02:00")
        XCTAssertEqual(text(h, 21, 1), "Ferme bientôt (2h)")   // samedi 1 h : créneau du vendredi
        XCTAssertTrue(h.status(at: Fixtures.date(2026, 11, 20, 23), calendar: cal).isOpen)
        XCTAssertFalse(h.status(at: Fixtures.date(2026, 11, 20, 3), calendar: cal).isOpen)
    }

    func testDayListsRulesAndOverrides() throws {
        let list = try hours("Mo,We,Fr 09:00-12:00")
        XCTAssertFalse(list.week[0].isEmpty)
        XCTAssertTrue(list.week[1].isEmpty)
        XCTAssertFalse(list.week[2].isEmpty)
        XCTAssertFalse(list.week[4].isEmpty)

        let additional = try hours("Mo-Sa 08:30-20:00, Su 09:00-12:00")
        XCTAssertEqual(additional.week[6], [OpeningHours.Span(start: 540, end: 720)])

        let override = try hours("Mo-Sa 08:00-20:00; We 08:00-12:00")
        XCTAssertEqual(override.week[2], [OpeningHours.Span(start: 480, end: 720)])
        XCTAssertEqual(override.week[1], [OpeningHours.Span(start: 480, end: 1200)])

        let holidays = try hours("Mo-Sa 08:00-20:00; PH off")
        XCTAssertTrue(holidays.week[6].isEmpty)
        XCTAssertFalse(holidays.week[5].isEmpty)

        let everyDay = try hours("08:00-20:00")
        XCTAssertTrue(everyDay.week.allSatisfy { !$0.isEmpty })

        let sundayOff = try hours("Mo-Su 08:00-21:00; Su off")
        XCTAssertTrue(sundayOff.week[6].isEmpty)
    }

    func testUnsupportedSyntaxReturnsNil() {
        XCTAssertNil(OpeningHours("sunrise-sunset"))
        XCTAssertNil(OpeningHours("Mo-Sa 08:00-20:00 \"sur rendez-vous\""))
        XCTAssertNil(OpeningHours(""))
        XCTAssertNil(OpeningHours("PH off"))
        XCTAssertNil(OpeningHours("Jan-Mar Mo-Fr 08:00-18:00"))
        XCTAssertNil(OpeningHours("Mo-Fr 8h-20h"))
    }

    func testClockFormatting() {
        XCTAssertEqual(OpeningHours.clock(510), "8h30")
        XCTAssertEqual(OpeningHours.clock(1200), "20h")
        XCTAssertEqual(OpeningHours.clock(1440), "minuit")
        XCTAssertEqual(OpeningHours.clock(1560), "2h")
    }

    func testStoreUsesOpeningHours() {
        var store = Fixtures.store("NODE:1")
        XCTAssertNil(store.hours)
        store.openingHours = "Mo-Sa 08:30-20:00"
        XCTAssertNotNil(store.hours)
        store.openingHours = "horaires variables"
        XCTAssertNil(store.hours)
    }
}
