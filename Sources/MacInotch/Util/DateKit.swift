import Foundation

enum DateKit {
    static let persianCal: Calendar = {
        var c = Calendar(identifier: .persian)
        c.locale = Locale(identifier: "fa_IR")
        c.timeZone = .current
        return c
    }()

    static let hijriCal: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.locale = Locale(identifier: "ar")
        c.timeZone = .current
        return c
    }()

    private static func fmt(_ cal: Calendar, _ locale: String, _ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: locale)
        f.timeZone = .current
        f.dateFormat = template
        return f
    }

    static let shamsiLong = fmt(persianCal, "fa_IR", "d MMMM y")

    static let shamsiWeekday = fmt(persianCal, "fa_IR", "EEEE")

    static let shamsiNumeric = fmt(persianCal, "en_US_POSIX", "yyyy/MM/dd")

    static let persianMonthLatin = [
        "Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar",
        "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand",
    ]

    static func shamsiLatin(_ date: Date) -> String {
        let c = persianCal.dateComponents([.year, .month, .day], from: date)
        guard let m = c.month, let d = c.day, let y = c.year,
              m >= 1, m <= 12 else { return "" }
        return "\(d) \(persianMonthLatin[m - 1]) \(y)"
    }

    static let gregLong = fmt(.init(identifier: .gregorian), "en_US", "EEEE, d MMMM y")
    static let gregShort = fmt(.init(identifier: .gregorian), "en_US", "d MMM")
    static let clock = fmt(.init(identifier: .gregorian), "en_US_POSIX", "HH:mm")
    static let clockSeconds = fmt(.init(identifier: .gregorian), "en_US_POSIX", "HH:mm:ss")
    static let clock12 = fmt(.init(identifier: .gregorian), "en_US_POSIX", "h:mm a")
    static let clock12Seconds = fmt(.init(identifier: .gregorian), "en_US_POSIX", "h:mm:ss a")

    static let hijriLong = fmt(hijriCal, "ar", "d MMMM y")

    static func yearProgress(_ date: Date) -> (day: Int, total: Int, fraction: Double) {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let total = cal.range(of: .day, in: .year, for: date)?.count ?? 365
        return (day, total, Double(day) / Double(total))
    }

    static func weekNumber(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal.component(.weekOfYear, from: date)
    }

    static func shamsiYearProgress(_ date: Date) -> (day: Int, total: Int, fraction: Double) {
        let day = persianCal.ordinality(of: .day, in: .year, for: date) ?? 1
        let total = persianCal.range(of: .day, in: .year, for: date)?.count ?? 365
        return (day, total, Double(day) / Double(total))
    }

    static func daysUntilPersian(month: Int, day: Int, from date: Date = .now) -> Int? {
        let cal = persianCal
        let today = cal.startOfDay(for: date)
        let year = cal.component(.year, from: today)

        for candidateYear in [year, year + 1] {
            var components = DateComponents()
            components.year = candidateYear
            components.month = month
            components.day = day
            guard let target = cal.date(from: components) else { continue }
            let start = cal.startOfDay(for: target)
            guard start >= today else { continue }
            return cal.dateComponents([.day], from: today, to: start).day
        }
        return nil
    }

    static func daysUntilNowruz(from date: Date = .now) -> Int? {
        daysUntilPersian(month: 1, day: 1, from: date)
    }

    static func daysUntilYalda(from date: Date = .now) -> Int? {
        daysUntilPersian(month: 9, day: 30, from: date)
    }

    static func uptime() -> String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func enDigits(_ s: String) -> String {
        let map: [Character: Character] = ["۰":"0","۱":"1","۲":"2","۳":"3","۴":"4",
                                           "۵":"5","۶":"6","۷":"7","۸":"8","۹":"9",
                                           "٠":"0","١":"1","٢":"2","٣":"3","٤":"4",
                                           "٥":"5","٦":"6","٧":"7","٨":"8","٩":"9"]
        return String(s.map { map[$0] ?? $0 })
    }

    static func faDigits(_ s: String) -> String {
        let map: [Character: Character] = ["0":"۰","1":"۱","2":"۲","3":"۳","4":"۴",
                                           "5":"۵","6":"۶","7":"۷","8":"۸","9":"۹"]
        return String(s.map { map[$0] ?? $0 })
    }
}
