# music-for-car — Agent Notes

## What this repo is

A single bash script (`music-for-car.sh`) that converts audio files to MP3 optimized for car stereos. Uses profile-based configuration (`profiles/*.conf`). No build system, no dependencies beyond system tools.

## Commands

```bash
./music-for-car.sh [-p profile] <source_dir> <dest_dir>
```

- With profile: `./music-for-car.sh -p classic_cargo ~/Music ~/mp3_para_auto`
- Default profile: `./music-for-car.sh ~/Music ~/mp3_para_auto`
- List profiles: `./music-for-car.sh` (no args shows available profiles)

## Dependencies (system, not packaged)

- `ffmpeg` (with libmp3lame)
- `ffprobe` (ships with ffmpeg)
- `iconv`
- `fatsort`

## Architecture

- **Script**: `music-for-car.sh` — all logic
- **Profiles**: `profiles/*.conf` — shell-compatible config files with `#` comments and `KEY="value"` pairs
- **Log**: `processing.log` in the script's directory (overwritten each run)

## Key behavior

- **Auto-detects mode**: if source dir contains audio files directly → single album mode; if it contains subdirectories → multi-album mode.
- **Album naming**: expects `Band - Album (Year)` folder names. `(Year)` is optional.
- **Output naming**: multi-album → `NN - Band - Album`; single album → `Band - Album`.
- **ID3 tags**: only title, artist, album, track. Everything else stripped.
- **Sanitization**: all folder/file names converted to ASCII via `iconv` + `sed`.
- **Parallel mode**: when `PARALLEL="true"` in profile, processes all files in an album concurrently via background jobs.
- **Fast loudnorm**: when `FAST_LOUDNORM="true"`, uses single-pass instead of two-pass.

## Conventions

- `set -euo pipefail` — script fails fast on any error.
- Profile config files are sourced directly (shell-compatible).
