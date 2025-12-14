import Testing
@testable import AsciiDocCore
import Foundation

@Suite("Standard attribute collection")
struct StandardAttributesTests {

    @Test
    func includes_path_based_attributes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fileDate = DateComponents(calendar: calendar, year: 2024, month: 5, day: 10, hour: 8, minute: 9, second: 7).date!
        let now = DateComponents(calendar: calendar, year: 2024, month: 5, day: 11, hour: 12, minute: 30, second: 45).date!

        let attrs = collectStandardDocumentAttributes(
            sourcePath: "/tmp/docs/demo-guide.adoc",
            fileModificationDate: fileDate,
            now: now,
            calendar: calendar
        )

        #expect(attrs["docfile"] == "/tmp/docs/demo-guide.adoc")
        #expect(attrs["docdir"] == "/tmp/docs")
        #expect(attrs["docname"] == "demo-guide")
        #expect(attrs["docstem"] == "demo-guide")
        #expect(attrs["docfilesuffix"] == ".adoc")
        #expect(attrs["docdate"] == "2024-05-10")
        #expect(attrs["docdatetime"] == "2024-05-10 08:09:07 GMT")
        #expect(attrs["localdate"] == "2024-05-11")
        #expect(attrs["localdatetime"] == "2024-05-11 12:30:45 GMT")
    }

    @Test
    func falls_back_to_runtime_now_when_file_date_missing() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2023, month: 12, day: 1, hour: 6, minute: 0, second: 0).date!

        let attrs = collectStandardDocumentAttributes(
            sourcePath: nil,
            fileModificationDate: nil,
            now: now,
            calendar: calendar
        )

        #expect(attrs["docdate"] == "2023-12-01")
        #expect(attrs["docdatetime"] == "2023-12-01 06:00:00 GMT")
        #expect(attrs["docfilesuffix"] == nil)
        #expect(attrs["docname"] == nil)
    }
}
