#!/usr/bin/env python3
"""Exercise the production delayed-start guards with a deterministic UI queue.

The load body is mocked; the actual PlayViewController scheduling fragment is
compiled as Swift. This reproduces bursts of layout updates during the 350 ms
start delay, reentrant updates during loading, failure/retry and later restart.
It does not run UIKit, emulator cores or JIT on hardware.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'ManicEmu/ManicEmu/Sources/Business/Play/VIewControllers/PlayViewController.swift').read_text()
method = source.split('private func updateLibretroViews()', 1)[1]
fragment = method.split('// Skin/layout updates can arrive', 1)[1]
fragment = fragment[fragment.index('guard !libretroStartScheduled'):].split('//为了适配PSKM', 1)[0]
old_fragment = '''DispatchQueue.main.asyncAfter(delay: 0.35) { [weak self] in
                guard let self = self else { return }
'''
harness = r'''
import Foundation
final class UIQueue {
    var pending: [() -> Void] = []
    func asyncAfter(delay: Double, execute: @escaping () -> Void) {
        precondition(delay == 0.35)
        pending.append(execute)
    }
    func drain() {
        while !pending.isEmpty { pending.removeFirst()() }
    }
}
enum DispatchQueue { static let main = UIQueue() }
final class Player {
    var gameMetalView: NSObject?
    var libretroStartScheduled = false
    var failNext = false
    var loads = 0
    func update() {
        if gameMetalView != nil { return } // existing view takes layout-only branch
        FRAGMENT
            self.loads += 1
            if self.failNext { self.failNext = false; return }
            self.gameMetalView = NSObject()
            self.update() // reentrant skin/layout update during synchronous load
        }
    }
}
let player = Player()
for _ in 0..<12 { player.update() }
INITIAL_ASSERTION
DispatchQueue.main.drain()
FINAL_ASSERTION
AFTER_TEST
'''
fixed = harness.replace('FRAGMENT', fragment)
fixed = fixed.replace('INITIAL_ASSERTION', 'precondition(DispatchQueue.main.pending.count == 1)')
fixed = fixed.replace('FINAL_ASSERTION', 'precondition(player.loads == 1 && !player.libretroStartScheduled)')
fixed = fixed.replace('AFTER_TEST', r'''
for _ in 0..<12 { player.update() }
precondition(DispatchQueue.main.pending.isEmpty && player.loads == 1)
player.gameMetalView = nil
player.update()
DispatchQueue.main.drain()
precondition(player.loads == 2)
let retry = Player()
retry.failNext = true
retry.update()
DispatchQueue.main.drain()
precondition(retry.loads == 1 && retry.gameMetalView == nil && !retry.libretroStartScheduled)
retry.update()
DispatchQueue.main.drain()
precondition(retry.loads == 2 && retry.gameMetalView != nil)
print("PASS: production delayed-start guards coalesce layout bursts, prevent repeated core loads, and allow failure retry/restart (mock UI queue)")
''')
old = harness.replace('FRAGMENT', old_fragment)
old = old.replace('INITIAL_ASSERTION', 'precondition(DispatchQueue.main.pending.count == 12)')
old = old.replace('FINAL_ASSERTION', 'precondition(player.loads == 12)')
old = old.replace('AFTER_TEST', 'print("CONTROL: original scheduling reproduces 12 core loads from 12 early layout updates")')
with tempfile.TemporaryDirectory(prefix='manicemu-start-test-') as folder:
    for name, swift in [('old', old), ('fixed', fixed)]:
        path = Path(folder) / f'{name}.swift'
        path.write_text(swift)
        subprocess.run(['xcrun', 'swift', '-module-cache-path', '/tmp/manicemu-jit-swift-cache', str(path)], check=True)
