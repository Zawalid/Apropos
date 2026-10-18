import Foundation
import os

enum CueLog {
    static let subsystem = "com.zawalid.cue"
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
}
