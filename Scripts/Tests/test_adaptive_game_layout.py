#!/usr/bin/env python3
"""Exercise the production geometry across window sizes and safe-area changes.

This compiles the actual shared Swift geometry. It does not launch UIKit,
simulate touch input, or validate a physical device installation.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import Foundation
import CoreGraphics

let dimensions: [(CGFloat, CGFloat)] = [
    (320, 568), (393, 852), (852, 393), (744, 1133), (1024, 768),
    (393, 852), (669, 951), (951, 669), (466, 678)
]
var checked = 0
for console in AdaptiveGameSystem.allCases {
    for (width, height) in dimensions {
        for insets in [CGRect(x: 0, y: 0, width: width, height: height),
                       CGRect(x: 8, y: 20, width: width - 40, height: height - 44)] {
            guard let layout = AdaptiveGameLayout.layout(console: console, in: insets) else {
                fatalError("Missing layout for \(console) in \(insets)")
            }
            precondition(layout.screens.count == console.screenCount)
            let area = insets.insetBy(dx: -0.1, dy: -0.1)
            for screen in layout.screens {
                precondition(screen.width > 0 && screen.height > 0 && area.contains(screen))
            }
            if layout.screens.count == 2 {
                precondition(!layout.screens[0].intersects(layout.screens[1]))
                let top = layout.screens[0], bottom = layout.screens[1]
                precondition(top.width * top.height >= bottom.width * bottom.height * 1.4 - 0.1)
            }
            for i in layout.controls.indices {
                let button = layout.controls[i].frame
                precondition(button.width >= 44 && button.height >= 44 && area.contains(button))
                precondition(!layout.screens.contains { $0.intersects(button) })
                for j in layout.controls.indices where i != j {
                    precondition(!button.intersects(layout.controls[j].frame))
                }
            }
            precondition(layout.controls.contains { $0.input == "menu" })
            precondition(layout.controls.contains { $0.input == "start" })
            checked += 1
        }
    }
}
precondition(AdaptiveGameLayout.layout(console: .threeDS,
    in: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
print("PASS: \(checked) production geometry cases preserve screen separation, safe areas, and control hit areas")
'''

with tempfile.TemporaryDirectory(prefix='adaptive-layout-test-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(HARNESS)
    binary = Path(folder) / 'layout-test'
    subprocess.run([
        'xcrun', 'swiftc', '-module-cache-path', '/tmp/manicemu-layout-swift-cache',
        str(ROOT / 'Shared/AdaptiveGameLayout.swift'), str(main), '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
