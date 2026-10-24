// SPDX-License-Identifier: AGPL-3.0-or-later
// Shared by the production skin adapter and independent previews.
import Foundation
import CoreGraphics

enum AdaptiveGameSystem: String, CaseIterable, Identifiable {
    case gba = "GBA", ds = "DS", threeDS = "3DS"
    var id: String { rawValue }
    var screenCount: Int { self == .gba ? 1 : 2 }
}

enum AdaptiveGameLayout {
    struct Control {
        let input: String
        let frame: CGRect
    }
    struct Layout {
        let screens: [CGRect]
        let controls: [Control]
        var screenArea: CGFloat { screens.reduce(0) { $0 + $1.width * $1.height } }
    }
    // Maximize usable picture area with aspect ratios intact. Controls occupy
    // reserved rails/decks and never cover either game screen.
    static func layout(console: AdaptiveGameSystem, in availableArea: CGRect) -> Layout? {
        let area = availableArea.insetBy(dx: 6, dy: 6)
        guard area.width >= 260, area.height >= 260 else { return nil }
        let gap: CGFloat = 8
        let leftWidth: CGFloat = 112
        let rightWidth: CGFloat = 128
        let tall: CGFloat = console == .threeDS ? 288 : (console == .ds ? 236 : 216)
        var candidates: [Layout] = []
        func fit(_ ratio: CGFloat, in box: CGRect) -> CGRect {
            let width = max(0, min(box.width, box.height * ratio))
            let height = width / ratio
            return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
        }
        let topRatio: CGFloat = console == .gba ? 1.5 : (console == .ds ? 4.0 / 3 : 5.0 / 3)
        let bottomRatio: CGFloat = 4.0 / 3
        func screenCandidates(in stage: CGRect) -> [[CGRect]] {
            guard stage.width >= 128, stage.height >= 80 else { return [] }
            if console == .gba { return [[fit(topRatio, in: stage)]] }
            var choices: [[CGRect]] = []
            // Sweep the secondary width, keeping it useful and the primary
            // at least 40% larger in area. No cropping, stretching or overlays.
            let minimum = min(CGFloat(144), max(112, stage.width * 0.38))
            for width in stride(from: minimum, through: stage.width, by: CGFloat(2)) {
                let height = width / bottomRatio
                let topBox = CGRect(x: stage.minX, y: stage.minY, width: stage.width, height: stage.height - height - gap)
                if topBox.height > 0 {
                    let top = fit(topRatio, in: topBox)
                    let lower = CGRect(x: stage.midX - width / 2, y: stage.maxY - height, width: width, height: height)
                    if top.width * top.height >= width * height * 1.4 { choices.append([top, lower]) }
                }
                let topBoxBeside = CGRect(x: stage.minX, y: stage.minY, width: stage.width - width - gap, height: stage.height)
                if topBoxBeside.width > 0 && height <= stage.height {
                    let top = fit(topRatio, in: topBoxBeside)
                    let lower = CGRect(x: stage.maxX - width, y: stage.midY - height / 2, width: width, height: height)
                    if top.width * top.height >= width * height * 1.4 { choices.append([top, lower]) }
                }
            }
            return choices
        }
        func controls(left: CGRect, right: CGRect) -> [Control] {
            var result: [Control] = []
            func add(_ input: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in zone: CGRect) {
                result.append(Control(input: input, frame: CGRect(x: zone.minX + x, y: zone.minY + y, width: w, height: h)))
            }
            let third = console == .threeDS
            add(third ? "l1" : (console == .ds ? "l" : "l1"), 0, 0, 48, 44, in: left)
            add(third ? "r1" : (console == .ds ? "r" : "r1"), right.width - 48, 0, 48, 44, in: right)
            if third {
                add("l2", 56, 0, 48, 44, in: left)
                add("r2", right.width - 104, 0, 48, 44, in: right)
                add("leftThumbstickUp", 20, 52, 72, 72, in: left)
                add("up", 6, 132, 100, 100, in: left)
                add("rightThumbstickUp", 42, 188, 44, 44, in: right)
            } else {
                add("up", 0, 52, 112, 112, in: left)
            }
            if console == .gba {
                add("b", 12, 108, 52, 52, in: right)
                add("a", 72, 52, 52, 52, in: right)
            } else {
                // Separate 44pt face buttons; a diamond needs 128pt overall.
                add("x", 42, 52, 44, 44, in: right)
                add("y", 0, 96, 44, 44, in: right)
                add("a", 84, 96, 44, 44, in: right)
                add("b", 42, 140, 44, 44, in: right)
            }
            add("menu", 0, left.height - 44, 44, 44, in: left)
            add("flex", 56, left.height - 44, 44, 44, in: left)
            add("select", right.width - 100, right.height - 44, 44, 44, in: right)
            add("start", right.width - 44, right.height - 44, 44, 44, in: right)
            return result
        }
        // Portrait: compact controls below the screens, no shell artwork.
        let deckHeight = tall // 3DS stick and D-pad form one vertical column.
        if area.height - deckHeight - gap >= 80 {
            let lw: CGFloat = leftWidth
            let rw: CGFloat = rightWidth
            let left = CGRect(x: area.minX, y: area.maxY - deckHeight, width: lw, height: deckHeight)
            let right = CGRect(x: area.maxX - rw, y: left.minY, width: rw, height: deckHeight)
            let buttons = controls(left: left, right: right)
            let stage = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height - deckHeight - gap)
            for screens in screenCandidates(in: stage) { candidates.append(Layout(screens: screens, controls: buttons)) }
            // A wide Duo has room for the touchscreen between the controls.
            if console != .gba {
                let lowerBox = CGRect(x: left.maxX + gap, y: left.minY, width: right.minX - left.maxX - 2 * gap, height: deckHeight)
                if lowerBox.width >= 144 {
                    var upper = fit(topRatio, in: stage)
                    upper.origin.y = stage.minY
                    let freeColumn = CGRect(x: lowerBox.minX, y: upper.maxY + gap,
                        width: lowerBox.width, height: area.maxY - upper.maxY - gap)
                    var lower = fit(bottomRatio, in: freeColumn)
                    // Preserve the primary picture and cap the secondary only
                    // if it would violate the requested upper/lower hierarchy.
                    let maximumArea = upper.width * upper.height / 1.4
                    if lower.width * lower.height > maximumArea {
                        let factor = sqrt(maximumArea / (lower.width * lower.height))
                        lower = fit(bottomRatio, in: CGRect(x: freeColumn.midX - lower.width * factor / 2,
                            y: freeColumn.minY, width: lower.width * factor, height: freeColumn.height))
                    }
                    if upper.width * upper.height >= lower.width * lower.height * 1.4 {
                        candidates.append(Layout(screens: [upper, lower], controls: buttons))
                    }
                }
            }
        }
        // On the inner display, spread controls horizontally into a shallow
        // deck instead of reserving tall columns for them.
        if console != .threeDS && area.width >= 640 && area.height >= 280 {
            let deckHeight: CGFloat = console == .gba ? 112 : 132
            let groupWidth: CGFloat = 240
            let left = CGRect(x: area.minX, y: area.maxY - deckHeight, width: groupWidth, height: deckHeight)
            let right = CGRect(x: area.maxX - groupWidth, y: left.minY, width: groupWidth, height: deckHeight)
            var buttons: [Control] = []
            func add(_ input: String, x: CGFloat, y: CGFloat, w: CGFloat = 44, h: CGFloat = 44, rightSide: Bool = false) {
                let zone = rightSide ? right : left
                buttons.append(Control(input: input, frame: CGRect(x: zone.minX + x, y: zone.minY + y, width: w, height: h)))
            }
                add("up", x: 0, y: 0, w: 112, h: 112)
                add(console == .ds ? "l" : "l1", x: 120, y: 0, w: 48)
                add("menu", x: 120, y: deckHeight - 44); add("flex", x: 176, y: deckHeight - 44)
                add(console == .ds ? "r" : "r1", x: 136, y: 0, w: 48, rightSide: true)
                add("select", x: 136, y: deckHeight - 44, rightSide: true); add("start", x: 192, y: deckHeight - 44, rightSide: true)
            if console == .gba {
                add("a", x: 72, y: 0, w: 52, h: 52, rightSide: true)
                add("b", x: 12, y: 60, w: 52, h: 52, rightSide: true)
            } else {
                add("x", x: 42, y: 0, rightSide: true); add("y", x: 0, y: 44, rightSide: true)
                add("a", x: 84, y: 44, rightSide: true); add("b", x: 42, y: 88, rightSide: true)
            }
            let stage = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height - deckHeight - gap)
            for screens in screenCandidates(in: stage) { candidates.append(Layout(screens: screens, controls: buttons)) }
            if console != .gba {
                let lowerBox = CGRect(x: left.maxX + gap, y: left.minY, width: right.minX - left.maxX - 2 * gap, height: deckHeight)
                if lowerBox.width >= 144 {
                    var upper = fit(topRatio, in: stage)
                    upper.origin.y = stage.minY
                    let freeColumn = CGRect(x: lowerBox.minX, y: upper.maxY + gap,
                        width: lowerBox.width, height: area.maxY - upper.maxY - gap)
                    let lower = fit(bottomRatio, in: freeColumn)
                    if upper.width * upper.height >= lower.width * lower.height * 1.4 {
                        candidates.append(Layout(screens: [upper, lower], controls: buttons))
                    }
                }
            }
        }
        // Short/wide windows: controls at the edges, pictures fill the center.
        if area.height >= tall {
            let left = CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height)
            let right = CGRect(x: area.maxX - rightWidth, y: area.minY, width: rightWidth, height: area.height)
            let stage = CGRect(x: left.maxX + gap, y: area.minY, width: right.minX - left.maxX - 2 * gap, height: area.height)
            let buttons = controls(left: left, right: right)
            for screens in screenCandidates(in: stage) { candidates.append(Layout(screens: screens, controls: buttons)) }
        }
        func score(_ layout: Layout) -> CGFloat {
            guard console != .gba, layout.screens.count == 2 else { return layout.screenArea }
            let upper = layout.screens[0], lower = layout.screens[1]
            return upper.width * upper.height + 1.35 * lower.width * lower.height
        }
        return candidates.max { score($0) < score($1) }
    }
}
