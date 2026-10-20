import AVFoundation
import Foundation

final class SoundManager {
    static let shared = SoundManager()
    private var player: AVAudioPlayer?

    private init() {}

    func play(_ name: String) {
        let url: URL? = findSound(name)

        guard let url = url else {
            print("[SoundManager] Not found: \(name).wav")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("[SoundManager] Error playing \(name): \(error)")
        }
    }

    private func findSound(_ name: String) -> URL? {
        // 1. Bundle.main subdirectory
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sounds") {
            return url
        }
        // 2. Bundle.main flat
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return url
        }
        // 3. Relative to executable (manual bundle)
        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let resourcesDir = execURL
            .deletingLastPathComponent()  // MacOS/
            .deletingLastPathComponent()  // Contents/
            .appendingPathComponent("Resources/sounds/\(name).wav")
        if FileManager.default.fileExists(atPath: resourcesDir.path) {
            return resourcesDir
        }
        return nil
    }
}
