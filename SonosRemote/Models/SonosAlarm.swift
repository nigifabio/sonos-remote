import Foundation

/// One entry from `AlarmClock.ListAlarms`.
struct SonosAlarm: Identifiable, Hashable {
    var id: String            // "ID" attribute
    var startTime: String     // "HH:MM:SS"
    var duration: String      // "HH:MM:SS"
    var recurrence: String    // "DAILY", "WEEKDAYS", "WEEKENDS", "ONCE", "ON_0123456" (day bitmap)...
    var enabled: Bool
    var roomUUID: String      // RoomUUID — which device this alarm rings on
    var programURI: String
    var programMetaData: String
    var playMode: String      // "NORMAL", "SHUFFLE_NOREPEAT", "SHUFFLE", "REPEAT_ALL", "REPEAT_ONE"
    var volume: Int
    var includeLinkedZones: Bool
}
