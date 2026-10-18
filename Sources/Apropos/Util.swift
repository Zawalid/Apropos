import Foundation
import os

public enum AproposLog {
    public static let subsystem = "com.zawalid.apropos"
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let panel = Logger(subsystem: subsystem, category: "panel")
    public static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
}
