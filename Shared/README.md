# Adaptive gameplay layouts

`AdaptiveGameLayout.swift` is the single geometry implementation used by
production and previews. `AdaptiveSkinDefinition.swift` translates the frames
into ordinary DeltaCore skin metadata and stationary button artwork.
`AdaptiveSkinStore.swift` caches generated archives inside the app sandbox.
Original bundled skins and user-imported/customized skins are not overwritten.
