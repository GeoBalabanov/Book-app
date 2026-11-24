import Foundation
import SwiftData

/// Seconds spent reading on one local calendar day.
@Model
final class ReadingDay {
    @Attribute(.unique) var day: String      // "yyyy-MM-dd", local time
    var seconds: Double

    init(day: String, seconds: Double = 0) {
        self.day = day
        self.seconds = seconds
    }
}

enum ReadingStats {
    static let goalKey = "lexi.dailyGoalMinutes"
    static let goalOptions = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    /// Daily goal in minutes (Apple Books starts at 5).
    static var goalMinutes: Int {
        get { UserDefaults.standard.object(forKey: goalKey) as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: goalKey) }
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Consecutive days meeting the goal, ending today (or yesterday, if today
    /// isn't done yet, so the streak doesn't look broken in the morning).
    static func currentStreak(seconds: [String: Double], goal: Int, now: Date = .now, calendar: Calendar = .current) -> Int {
        let target = Double(goal * 60)
        var day = calendar.startOfDay(for: now)
        if (seconds[key(for: day, calendar: calendar)] ?? 0) < target {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while (seconds[key(for: day, calendar: calendar)] ?? 0) >= target {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// "4:07" under an hour, "1:05:00" above.
    static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Counts active reading time. Each page turn, tap or lookup adds the time since
/// the previous one, capped so a book left open doesn't count as reading.
@MainActor
final class ReadingTracker {
    static let maxGap: TimeInterval = 120

    private var last: Date?
    private var pending: Double = 0
    private let context: ModelContext?

    init(context: ModelContext?) { self.context = context }

    func start(now: Date = .now) { last = now }

    func activity(now: Date = .now) {
        if let last { pending += min(now.timeIntervalSince(last), Self.maxGap) }
        last = now
        if pending >= 15 { flush(now: now) }
    }

    /// Stop counting (reader closed or app in the background).
    func pause(now: Date = .now) {
        activity(now: now)
        last = nil
        flush(now: now)
    }

    private func flush(now: Date) {
        guard pending > 0, let context else { return }
        let key = ReadingStats.key(for: now)
        let day = (try? context.fetch(FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.day == key })))?.first
            ?? { let d = ReadingDay(day: key); context.insert(d); return d }()
        day.seconds += pending
        pending = 0
        try? context.save()
    }
}
