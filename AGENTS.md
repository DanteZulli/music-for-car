# music-for-car — Agent Notes

## What this repo is

A single bash script (`music-for-car.sh`) that converts audio files to MP3 optimized for car stereos (Sony CDX-GT500US). No build system, no dependencies beyond system tools.

## Commands

```bash
./music-for-car.sh <source_dir> <dest_dir>
```

- Single album: `./music-for-car.sh ~/Music/"Band - Album" ~/mp3_para_auto`
- Multi-album: `./music-for-car.sh ~/Music ~/mp3_para_auto`

## Dependencies (system, not packaged)

- `ffmpeg` (with libmp3lame)
- `ffprobe` (ships with ffmpeg)
- `iconv`
- `fatsort`

## Key behavior

- **Auto-detects mode**: if source dir contains audio files directly → single album mode; if it contains subdirectories → multi-album mode.
- **Album naming**: expects `Band - Album (Year)` folder names. `(Year)` is optional.
- **Output naming**: multi-album → `NN - Band - Album`; single album → `Band - Album`.
- **Audio output**: MP3 256kbps CBR, 44100 Hz, stereo, highpass 100 Hz, loudnorm two-pass (I=-16, TP=-1.5, LRA=11).
- **ID3 tags**: only title, artist, album, track, genre (hardcoded to "Rock"). Everything else stripped.
- **Sanitization**: all folder/file names converted to ASCII via `iconv` + `sed`.
- **Generates** `processing.log` in the script's directory (overwritten each run).

## Conventions

- `set -euo pipefail` — script fails fast on any error.
