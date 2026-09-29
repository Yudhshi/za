import Foundation

public struct MeetingEvent: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [String]
    public let isAllDay: Bool
    /// 会議リンク(Meet/Zoom/Teams 等)。見つからなければ nil
    public let joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date,
                attendees: [String], isAllDay: Bool, joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.isAllDay = isAllDay
        self.joinURL = joinURL
    }
}
