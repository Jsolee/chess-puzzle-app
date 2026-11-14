#if DEBUG
import Foundation

/// Store screenshots: `-scene openings` (or today, review, lesson, path, exercises, atlas, chart, profile) opens that screen
/// straight away, so tools/store_screenshots.py can capture each language without tapping. Debug builds only.
enum ScreenshotScene {
    static let value = UserDefaults.standard.string(forKey: "scene")
    static func `is`(_ name: String) -> Bool { value == name }
}
#endif
