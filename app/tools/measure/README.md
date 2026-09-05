# measure

A C port of the synthesised textures, used to level-match the library.

    cc -O2 -o textures textures.c -lm && ./textures 30

Prints, per sound at its catalog defaults: RMS, an A-weighted RMS, the peak,
a brightness figure, and the A-weighted level after the default slider and
the mixer's headroom. The `trim` values in `Model/SoundCatalog.swift` were
derived from that table so every sound lands near -27 dB A-weighted at its
default slider, capped so that no sound peaks above -14 dBFS there.

Keep this file in step with the Swift when a texture changes. It is a ruler,
not the engine.
