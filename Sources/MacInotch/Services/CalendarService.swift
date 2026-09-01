import Foundation
import EventKit
import AppKit

struct AgendaEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var joinURL: URL?
    var isAllDay: Bool
    var calendarColor: NSColor?

    var startsIn: TimeInterval { start.timeIntervalSinceNow }
    var isRunning: Bool { start <= Date() && end > Date() }

    var countdown: String {
        if isRunning {
            let left = Int(end.timeIntervalSinceNow / 60)
            return left > 0 ? "\(left)m left" : "ending"
        }
        let minutes = Int(startsIn / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "in \(hours)h \(minutes % 60)m" : "in \(hours / 24)d"
    }

    static func == (a: AgendaEvent, b: AgendaEvent) -> Bool {
        a.title == b.title && a.start == b.start && a.end == b.end
    }
}

struct ReminderItem: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var overdue: Bool
    var list: String

    var detail: String {
        guard let due else { return list }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(due) ? "HH:mm" : "d MMM"
        return "\(formatter.string(from: due)) · \(list)"
    }
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var next: AgendaEvent?
    @Published private(set) var agenda: [AgendaEvent] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var remindersAuthorized = false

    private let store = EKEventStore()
    private var timer: Timer?

    private init() {}

    func start() {
        refreshAuthorization()
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authorized = granted
                self.denied = !granted
                self.tick()
            }
        }
        requestReminderAccess()
    }

    func requestReminderAccess() {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            Task { @MainActor in
                self?.remindersAuthorized = granted
                self?.tick()
            }
        }
    }

    private func refreshAuthorization() {
        remindersAuthorized =
            EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
            denied = false
        case .denied, .restricted:
            authorized = false
            denied = true
        default:
            authorized = false
            denied = false
        }
    }

    private func tick() {
        refreshAuthorization()
        guard authorized, Prefs.shared.d.showCalendar else {
            if next != nil { next = nil }
            return
        }

        let now = Date()
        let horizon = now.addingTimeInterval(Prefs.shared.d.calendarHorizonHours * 3600)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                 end: horizon, calendars: nil)

        let upcoming = store.events(matching: predicate)
            .filter { event in
                if event.isAllDay && !Prefs.shared.d.calendarAllDay { return false }
                if event.status == .canceled { return false }
                return (event.endDate ?? now) > now
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }

        guard let event = upcoming.first, let start = event.startDate,
              let end = event.endDate else {
            if next != nil { next = nil }
            return
        }

        let candidate = AgendaEvent(
            title: event.title ?? "Untitled",
            start: start,
            end: end,
            location: event.location,
            joinURL: Self.conferenceURL(for: event),
            isAllDay: event.isAllDay,
            calendarColor: event.calendar?.color)

        if candidate != next { next = candidate }

        let today = Calendar.current.startOfDay(for: now)
        let tomorrow = today.addingTimeInterval(86_400)
        let list = upcoming.prefix(12).compactMap { event -> AgendaEvent? in
            guard let start = event.startDate, let end = event.endDate,
                  start < tomorrow else { return nil }
            return AgendaEvent(title: event.title ?? "Untitled",
                               start: start, end: end,
                               location: event.location,
                               joinURL: Self.conferenceURL(for: event),
                               isAllDay: event.isAllDay,
                               calendarColor: event.calendar?.color)
        }
        if list != agenda { agenda = list }

        refreshReminders()
    }

    private func refreshReminders() {
        guard Prefs.shared.d.showReminders, remindersAuthorized else {
            if !reminders.isEmpty { reminders = [] }
            return
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Calendar.current.startOfDay(for: Date()).addingTimeInterval(172_800),
            calendars: nil)

        store.fetchReminders(matching: predicate) { found in
            let items = (found ?? []).prefix(12).map { reminder in
                let due = reminder.dueDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                }
                return ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "Untitled",
                    due: due,
                    overdue: due.map { $0 < Date() } ?? false,
                    list: reminder.calendar?.title ?? "Reminders")
            }
            let sorted = items.sorted {
                ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
            }
            Task { @MainActor in
                if sorted != CalendarService.shared.reminders {
                    CalendarService.shared.reminders = sorted
                }
            }
        }
    }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "around.co", "meet.jit.si",
    ]

    static func conferenceURL(for event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }

        let haystack = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard !haystack.isEmpty else { return nil }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(haystack.startIndex..., in: haystack)
        let matches = detector?.matches(in: haystack, range: range) ?? []
        for match in matches {
            if let url = match.url, isMeeting(url) { return url }
        }
        return nil
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host.hasSuffix($0) }
    }
}
