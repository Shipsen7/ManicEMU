# Integrated JIT packet correction

Based on `StikJIT/Sources/ScriptRunner.swift` at revision
`3623e725876f76aecb0520582ad6194bacb15d39` (MPL-2.0; license alongside).
The JITEnabler target uses this source override; the submodule revision and
emulator binaries are unchanged.

The encoder preserves all 64 address bits, validates every memory-write reply,
and raises a JavaScript exception when preparation fails. The former nine-digit
format truncates addresses above `0xfffffffff`. Temporary file diagnostics and
host tracing are excluded. Existing progress callbacks remain available.

Run `python3 Scripts/Tests/test_jit_memory_packets.py` for packet and simulated
transport checks. These checks do not establish hardware JIT compatibility.
