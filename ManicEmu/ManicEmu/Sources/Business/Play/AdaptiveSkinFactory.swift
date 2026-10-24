// SPDX-License-Identifier: AGPL-3.0-or-later
import UIKit

/// Applied only when using the bundled default GBA/DS/3DS skin. Explicit skin
/// choices and the existing hide-controls/fullscreen mode remain authoritative.
enum AdaptiveSkinFactory {
    static func make(gameType: GameType, size: CGSize, safeArea: UIEdgeInsets,
                     swapScreens: Bool) -> ControllerSkin? {
        let console: AdaptiveGameSystem
        switch gameType {
        case .gba: console = .gba
        case .ds: console = .ds
        case ._3ds: console = .threeDS
        default: return nil
        }
        let sourceURL = URL(fileURLWithPath: R.Path.Resource)
            .appendingPathComponent(console.rawValue + "_FLEX.manicskin")
        guard FileManager.default.fileExists(atPath: sourceURL.path), size.width > 0, size.height > 0 else { return nil }
        do {
            let url = try AdaptiveSkinStore.shared.skin(console: console, sourceURL: sourceURL,
                size: size, safeArea: safeArea)
            guard var skin = ControllerSkin(fileURL: url) else { return nil }
            skin.isSwapScreen = swapScreens
            return skin
        } catch {
            Log.debug("Adaptive skin generation failed; retaining bundled skin: \(error.localizedDescription)")
            return nil
        }
    }
}
