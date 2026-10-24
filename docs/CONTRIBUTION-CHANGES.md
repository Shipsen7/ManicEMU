# Adaptive layout and integrated JIT contribution

This branch starts from upstream `fbaeab79` and contains newly authored commits.
Its scope is window-size-aware layouts, rotation handling, full-width JIT memory
packets, and coalescing delayed core starts.

## Window area and rotation

- Recalculate library and gameplay layouts when view size or safe-area insets change.
- Use current window/view bounds instead of fixed display dimensions.
- Generate adaptive layouts for the bundled default GBA, DS, and 3DS skins.
- Preserve custom skin selections, screen swapping, existing controller handling,
  and fullscreen/hide-controls choices. Generated skin archives use only app cache.
- Keep existing orientation-lock enforcement; update geometry after transitions.

## Startup and integrated JIT

- Reserve a delayed Libretro start before enqueuing it, avoiding duplicate loads
  during bursts of layout updates. Release the reservation after the load attempt.
- Preserve all 64 address bits in memory-write packets and verify every response.
- Propagate preparation failures to JavaScript instead of continuing silently.
- Use the MPL-2.0 source override without modifying core binaries or submodule pins.
- Exclude temporary on-device file tracing from the contribution.

## Validation

Run the focused checks from the repository root:

```sh
python3 Scripts/Tests/test_adaptive_game_layout.py
python3 Scripts/Tests/test_jit_memory_packets.py
python3 Scripts/Tests/test_libretro_start_scheduling.py
```

Initialize the pinned StikJIT submodule before running its regression test.
Geometry and mocked transport tests do not verify a signed app installation,
real touch input, device rotation, session preservation, or hardware JIT.
A complete upstream build and device regression pass remain necessary before merge.

## Signing and publication

Upstream signing settings and third-party attribution remain unchanged. Select
your own development team locally when building; personal signing profiles,
pairing credentials, device records, application data, and raw diagnostic exports
are not included. No IPA or other locally signed artifact is added.
