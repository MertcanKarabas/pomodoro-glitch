import AppKit
import SpiderCore

enum PhaseSound {
    /// Work done → break time. Break done → back to work.
    @MainActor static func play(_ finished: Phase) {
        let name = finished == .work ? "Glass" : "Hero"
        NSSound(named: NSSound.Name(name))?.play()
    }
}
