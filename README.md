# ripbar

A small status bar for [river](https://codeberg.org/river/river-classic) 0.3.x, written in Zig.

```
1 2 3 4 5 6 7 8 9 [focused window title]        [Mem: 36.0%] [Vol: 50%] [song - artist] [13/Jan/2026 5:20:57 PM]
```

- Tags 1-9 from `river-status`: focused, occupied, urgent and empty tags are drawn differently
- Title of the focused window, on the focused output
- Memory usage from `/proc/meminfo`
- Volume from `wpctl`
- Now playing on Spotify from `playerctl` (hidden when nothing is playing)
- Date and time, updated every second

Needs river 0.3.x (`river-classic`), since river 0.4+ dropped the `river-status` protocol.

## Building

Dependencies: zig 0.17, wayland, wayland-protocols, fcft, pixman.

```sh
zig build -Doptimize=ReleaseSafe
```

The binary ends up in `zig-out/bin/ripbar`. Start it from your river init:

```sh
riverctl spawn /path/to/ripbar
```

## Configuration

Fonts, colours and sizes are constants at the top of `src/main.zig`. Edit and rebuild.
