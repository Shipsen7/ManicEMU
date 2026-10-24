#!/usr/bin/env python3
"""Compile the production packet encoder and check GDB RSP address integrity."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    source = (root / "Vendor/StikJIT/ScriptRunner.swift").read_text()
    encoder = source.split("// BEGIN JIT packet encoder\n", 1)[1].split(
        "// END JIT packet encoder", 1
    )[0]
    upstream = (root / "StikJIT/Sources/ScriptRunner.swift").read_text()
    legacy = upstream[upstream.index("    private static func makeBlessCommands"):]
    legacy = legacy.replace("private static func makeBlessCommands", "static func makeBlessCommands")
    baseline = """enum OriginalPackets {
        static let jitPageSize: UInt64 = 16384
        static let jitPageCommandLength = 19
    """ + legacy
    harness = r'''
func check(_ address: UInt64, _ pages: Int) {
    let bytes = JITMemoryPackets.makeBlessCommands(startAddress: address, pageCount: pages)
    precondition(bytes.count == pages * JITMemoryPackets.commandLength)
    for page in 0..<pages {
        let start = page * JITMemoryPackets.commandLength
        let packet = Array(bytes[start..<(start + JITMemoryPackets.commandLength)])
        precondition(packet.first == 36 && packet[23] == 35)
        let body = String(bytes: packet[1..<23], encoding: .utf8)!
        let parts = body.dropFirst().split(separator: ",", maxSplits: 1)
        precondition(parts.count == 2 && parts[1] == "1:69")
        precondition(UInt64(parts[0], radix: 16) == address + UInt64(page) * 16384)
        let checksum = packet[1..<23].reduce(UInt8(0)) { $0 &+ $1 }
        precondition(String(bytes: packet[24..<26], encoding: .utf8) == String(format: "%02x", checksum))
    }
}
// Representative low and high addresses, 36-bit rollover,
// all pages in a 256 MiB arena, and a batch boundary at 128 packets.
for address: UInt64 in [0x15f800aa0, 0x7002000aa0, 0x7012000aa0, 0x7010000000] {
    check(address, 1)
}
check(0xfffffc000, 3)
check(0x7010000000, 16384)
check(0x7010000000, 257)
check(0xffffffffffff8000, 2)
check(0, 0)
precondition(JITMemoryPackets.isSuccessfulReply("OK"))
for response: String? in [nil, "", "E01", "E09", "error"] {
    precondition(!JITMemoryPackets.isSuccessfulReply(response))
}
let broken = String(bytes: OriginalPackets.makeBlessCommands(startAddress: 0x7010000000, pageCount: 1), encoding: .utf8)!
let corrected = String(bytes: JITMemoryPackets.makeBlessCommands(startAddress: 0x7010000000, pageCount: 1), encoding: .utf8)!
precondition(broken.hasPrefix("$M010000000,"))
precondition(corrected.hasPrefix("$M0000007010000000,"))
print("Original:", broken)
print("Corrected:", corrected)
print("PASS: actual Swift encoder preserves full-width addresses, arena pages, batch boundaries and checksums; rejects failed replies")
'''
    with tempfile.TemporaryDirectory(prefix="manicemu-jit-test-") as folder:
        test = Path(folder) / "main.swift"
        test.write_text("import Foundation\n" + encoder + baseline + harness)
        executable = Path(folder) / "jit-packets"
        subprocess.run([
            "xcrun", "swiftc", "-module-cache-path", "/tmp/manicemu-jit-swift-cache",
            str(test), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)

        # Exercise the real Swift/JavaScriptCore boundary with a fake transport.
        # Only the unavailable device FFI import is replaced; ScriptRunner runs
        # unchanged, so an E01 reply must abort the JS callback before resume.
        transport = r'''
import Darwin
struct IdeviceFfiError {}
enum StikJITError: Error { case scriptUnavailable, scriptExecution(String) }
enum StikJIT { enum Script { case universal; var name: String { "universal" } } }
enum IdeviceFFI {
    static func consume(_ error: UnsafeMutablePointer<IdeviceFfiError>, fallback: String) -> StikJITError {
        .scriptExecution(fallback)
    }
}
enum BundledScript {
    static func source(for script: StikJIT.Script) throws -> String {
        "prepare_memory_region(0x7010000000n, 32768n); log('RESUMED_AFTER_PREPARE');"
    }
}
var replies: [String?] = []
var sentPackets: [[UInt8]] = []
func debugserver_command_new(_ command: UnsafePointer<CChar>, _ args: UnsafeRawPointer?, _ count: Int) -> OpaquePointer? {
    OpaquePointer(bitPattern: 1)
}
func debugserver_command_free(_ command: OpaquePointer) {}
func idevice_string_free(_ string: UnsafeMutablePointer<CChar>) { free(string) }
func debug_proxy_send_command(_ proxy: OpaquePointer, _ command: OpaquePointer, _ response: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<IdeviceFfiError>? {
    response.pointee = strdup("OK"); return nil
}
func debug_proxy_send_raw(_ proxy: OpaquePointer, _ bytes: UnsafePointer<UInt8>, _ count: UInt) -> UnsafeMutablePointer<IdeviceFfiError>? {
    sentPackets.append(Array(UnsafeBufferPointer(start: bytes, count: Int(count)))); return nil
}
func debug_proxy_read_response(_ proxy: OpaquePointer, _ response: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<IdeviceFfiError>? {
    let reply = replies.removeFirst()
    response.pointee = reply.flatMap { strdup($0) }; return nil
}
func exercise(_ responses: [String?], succeeds: Bool) {
    replies = responses; sentPackets = []
    var logs: [String] = []
    let runner = ScriptRunner(targetPID: 1, debugProxy: OpaquePointer(bitPattern: 1)!, script: .universal) { logs.append($0) }
    var didSucceed = false
    do { try runner.run(); didSucceed = true } catch {}
    precondition(didSucceed == succeeds)
    precondition(logs.contains("RESUMED_AFTER_PREPARE") == succeeds)
    precondition(logs.contains(where: { $0.hasPrefix("Blessed ") }) == succeeds)
    precondition(sentPackets.count == 1 && sentPackets[0].count == 52)
    precondition(String(bytes: sentPackets[0].prefix(19), encoding: .utf8) == "$M0000007010000000,")
}
exercise(["OK", "OK"], succeeds: true)
exercise(["E01", "OK"], succeeds: false)
exercise(["OK", "E09"], succeeds: false)
exercise([nil, "OK"], succeeds: false)
print("PASS: real ScriptRunner/JavaScriptCore BigInt bridge and debugger reply handling (mock transport, no emulation)")
'''
        test.write_text(source.replace("@_implementationOnly import idevice", "") + transport)
        subprocess.run([
            "xcrun", "swiftc", "-module-cache-path", "/tmp/manicemu-jit-swift-cache",
            str(test), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
