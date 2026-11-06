// Stub frameworks for SPM compilation
import Foundation

class EKCalendar: NSObject {
    var calendarIdentifier: String = ""
    var calendarName: String = ""
}
enum EKSpan: Int {
    case spanAll = 0
    case spanDay = 1
    case spanWeek = 2
    case spanMonth = 3
    case spanFuture = 4
    case spanDefined = 5, thisEvent = 6
}
class EKPredicate: NSObject {}
class EKEventStore: NSObject {
    override init() { super.init() }
    func requestAccess(for: EKEntityType, completion: (Bool, Error?) -> Void) {}
    func predicateForEvents(withStart: Date, end: Date, calendars: [EKCalendar]?) -> EKPredicate { EKPredicate() }
    var defaultCalendarForNewEvents: EKCalendar? { nil }
    func events(matching: EKPredicate) -> [EKEvent] { [] }
    func save(_: EKEvent, span: EKSpan) throws {}
    func deleteEvent(_: EKEvent, span: EKSpan) throws {}
}
class EKEvent: NSObject {
    override init() { super.init() }
    init(eventStore: EKEventStore) { super.init() }
    var title: String = ""
    var notes: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var calendar: EKCalendar? = nil
}
enum EKEntityType: CaseIterable { case event }

class UNTimeIntervalTrigger: NSObject {
    override init() { super.init() }
    init(timeInterval: TimeInterval, repeats: Bool) { super.init() }
    static func triggering(timeInterval: TimeInterval, repeats: Bool) -> UNTimeIntervalTrigger { UNTimeIntervalTrigger() }
}
class UNNotificationRequest: NSObject {
    override init() { super.init() }
    init(identifier: String, content: Any, trigger: Any?) { super.init() }
}
class UNMutableNotificationContent: NSObject {
    override init() { super.init() }
    var title: String = ""
    var body: String = ""
    var sound: UNNotificationSound? = nil
    var categoryIdentifier: String = ""
}
struct UNNotificationSound { static let `default` = UNNotificationSound() }
class UNNotificationSettings: NSObject { var authorizationStatus: UNAuthorizationStatus = .notDetermined }
enum UNAuthorizationStatus: Int { case notDetermined, restricted, denied, authorized, provisional }

class UNUserNotificationCenter: NSObject {
    override init() { super.init() }
    static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    func add(_: UNNotificationRequest, _: (Error?) -> Void) {}
    func getNotificationSettings(_: (UNNotificationSettings) -> Void) {}
    func requestAuthorization(options: UNAuthorizationOptions, completion: (Bool, Error?) -> Void = { _, _ in }) {}
}
struct UNAuthorizationOptions: OptionSet, Hashable {
    var rawValue: Int { 0 }
    init(rawValue: Int) {}
    static let alert = UNAuthorizationOptions(rawValue: 1)
    static let sound = UNAuthorizationOptions(rawValue: 2)
    static let badge = UNAuthorizationOptions(rawValue: 4)
}
