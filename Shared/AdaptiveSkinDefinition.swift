// SPDX-License-Identifier: AGPL-3.0-or-later
import UIKit

/// Converts a shipped FLEX skin definition into an ordinary ControllerSkin
/// archive payload. DeltaCore continues handling touch, controller inputs,
/// screen swapping, haptics and thumbsticks through its existing interfaces.
enum AdaptiveSkinDefinition {
    struct Payload {
        let info: Data
        let files: [String: Data]
        let identifier: String
    }
    static func make(source: Data, console: AdaptiveGameSystem, size: CGSize,
                     safeArea: UIEdgeInsets, key: String,
                     asset: (String) -> Data?) throws -> Payload {
        guard var info = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              let representations = info["representations"] as? [String: Any],
              let phone = representations["iphone"] as? [String: Any],
              let display = phone["edgeToEdge"] as? [String: Any],
              var representation = display[size.width > size.height ? "landscape" : "portrait"] as? [String: Any],
              let layout = AdaptiveGameLayout.layout(console: console,
                  in: CGRect(origin: .zero, size: size).inset(by: safeArea)),
              let originalItems = representation["items"] as? [[String: Any]],
              var screens = representation["screens"] as? [[String: Any]],
              screens.count == layout.screens.count,
              let sourceID = info["identifier"] as? String else { throw Failure.invalidSource }
        func dictionary(_ rect: CGRect) -> [String: CGFloat] {
            ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        func inputNames(_ item: [String: Any]) -> [String] {
            (item["inputs"] as? [String]) ?? Array((item["inputs"] as? [String: String] ?? [:]).values)
        }
        let shoulders = ["l": "L", "r": "R", "l1": "L", "r1": "R", "l2": "ZL", "r2": "ZR"]
        var files: [String: Data] = [:]
        var items: [[String: Any]] = []
        for control in layout.controls {
            guard var item = originalItems.first(where: { inputNames($0).contains(control.input) }) else {
                throw Failure.missingInput(control.input)
            }
            item["frame"] = dictionary(control.frame)
            item["extendedEdges"] = ["top": 0, "bottom": 0, "left": 0, "right": 0]
            if var thumbstick = item["thumbstick"] as? [String: Any] {
                thumbstick["width"] = control.frame.width
                thumbstick["height"] = control.frame.height
                item["thumbstick"] = thumbstick
            }
            if let title = shoulders[control.input] {
                let filename = "adaptive-\(control.input).pdf"
                files[filename] = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: control.frame.size)).pdfData { context in
                    context.beginPage()
                    drawShoulder(title, frame: CGRect(origin: .zero, size: control.frame.size))
                }
                item["asset"] = ["normal": filename]
            }
            items.append(item)
        }
        for index in screens.indices { screens[index]["outputFrame"] = dictionary(layout.screens[index]) }
        if console != .gba {
            guard var touch = originalItems.first(where: { inputNames($0).contains("touchScreenX") }) else {
                throw Failure.missingInput("touchScreenX")
            }
            touch["frame"] = dictionary(layout.screens[1])
            touch["extendedEdges"] = ["top": 0, "bottom": 0, "left": 0, "right": 0]
            items.append(touch)
        }
        // Background contains only the stationary button artwork. Thumbstick
        // knobs stay separate so DeltaCore can move them during real input.
        files["adaptive-background.pdf"] = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            context.beginPage()
            for (control, item) in zip(layout.controls, items) {
                guard item["thumbstick"] == nil else { continue }
                if let label = shoulders[control.input] { drawShoulder(label, frame: control.frame); continue }
                guard let filename = (item["asset"] as? [String: String])?["normal"],
                      let data = asset(filename), let provider = CGDataProvider(data: data as CFData),
                      let document = CGPDFDocument(provider), let page = document.page(at: 1) else { continue }
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: control.frame.minX, y: control.frame.maxY)
                cg.scaleBy(x: 1, y: -1)
                let source = page.getBoxRect(.mediaBox)
                cg.concatenate(page.getDrawingTransform(.mediaBox,
                    rect: CGRect(origin: .zero, size: control.frame.size), rotate: 0, preserveAspectRatio: true))
                if source.width > 0 && source.height > 0 { cg.drawPDFPage(page) }
                cg.restoreGState()
            }
        }
        representation["mappingSize"] = ["width": size.width, "height": size.height]
        representation["assets"] = ["resizable": "adaptive-background.pdf"]
        representation["items"] = items
        representation["screens"] = screens
        // Match exact current window geometry for every trait fallback. Runtime
        // resizing generates a different cache key before controller layout.
        let orientations = ["portrait": representation, "landscape": representation]
        info["representations"] = ["iphone": ["standard": orientations, "edgeToEdge": orientations],
                                   "ipad": ["standard": orientations]]
        let identifier = sourceID + ".adaptive.v1." + key
        info["identifier"] = identifier
        info["name"] = "\(console.rawValue) Adaptive"
        return Payload(info: try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]), files: files, identifier: identifier)
    }
    private static func drawShoulder(_ title: String, frame: CGRect) {
        let plate = UIBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
        UIColor(white: 0.12, alpha: 1).setFill(); plate.fill()
        UIColor(white: 0.4, alpha: 1).setStroke(); plate.lineWidth = 1; plate.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold)]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attributes)
    }
    enum Failure: Error { case invalidSource, missingInput(String) }
}
