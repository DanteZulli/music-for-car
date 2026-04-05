# music-for-car.sh

Bash script to convert audio files from any format to MP3 optimized for car USB drives.

## Context

Created for my **Sony CDX-GT500US** with a 64GB USB drive. The original music was in FLAC (and other formats) with cover art, lyrics files, and special characters in filenames that the stereo couldn't read correctly.

## What it does

- **Converts** all audio (FLAC, OGG, OPUS, M4A, WAV, AAC, WMA) to **MP3 256kbps CBR**
- **Normalizes** volume with `loudnorm` two-pass (I=-16 LUFS, TP=-1.5 dBTP, LRA=11 LU)
- **Highpass** at 100 Hz to eliminate rumble that car speakers can't reproduce
- **Sanitizes** folder and file names to pure ASCII (no accents, no weird symbols)
- **Cleans** ID3 metadata: keeps only title, artist, album, track, genre
- **Audio only**: discards cover images, .lrc files, and anything non-audio

## Requirements

- `ffmpeg` (with libmp3lame)
- `ffprobe` (ships with ffmpeg)
- `iconv`
- `fatsort` (to physically sort the USB drive after copying)

## Usage

```bash
./music-for-car.sh <source_dir> <dest_dir>
```

### Single album

```bash
./music-for-car.sh ~/Music/"2 Minutos - Vida Monotona (2015)" ~/mp3_para_auto
```

Processes a single album and saves it as `Band - Album` in the destination.

### All music

```bash
./music-for-car.sh ~/Music ~/mp3_para_auto
```

Processes all albums in the source directory and saves them as `NN - Band - Album` (sequentially numbered).

## Full USB drive workflow

### 1. Process the music

```bash
./music-for-car.sh ~/Music ~/mp3_para_auto
```

### 2. Format the USB drive as FAT32

```bash
# Verify the correct device with lsblk
lsblk

# Unmount
sudo umount /dev/sdX1

# Format
sudo mkfs.vfat -F 32 -n "CAR_MUSIC" /dev/sdX1
```

### 3. Copy the files

```bash
# Mount
sudo mount /dev/sdX1 /run/media/dante/CAR_MUSIC

# Copy
cp -r ~/mp3_para_auto/* /run/media/dante/CAR_MUSIC/
```

### 4. Sort with fatsort (CRUCIAL)

The Sony CDX-GT500US reads files in the physical order they appear in the FAT directory table, **not** alphabetically. `fatsort` physically reorders the entries so the stereo reads them correctly.

```bash
# Unmount first (fatsort requires the device to be unmounted)
sudo umount /run/media/dante/CAR_MUSIC

# Sort
sudo fatsort /dev/sdX1

# Remount
sudo mount /dev/sdX1 /run/media/dante/CAR_MUSIC
```

### 5. Unmount and use

```bash
sudo umount /run/media/dante/CAR_MUSIC
```

## Expected folder format

The script expects the source directory to contain albums formatted as:

```
Band - Album Name (Year)/
  01 - Song.flac
  02 - Song.flac
  cover.jpg
```

The `(Year)` at the end is optional. Everything else is parsed as `Band` and `Album`.

## Output format

### Folders

- **Multi-album mode**: `01 - Band - Album Name`
- **Single album mode**: `Band - Album Name`

### Files

- `01 - Song Name.mp3`
- `02 - Another Song.mp3`

All names are pure ASCII: no accents, no ñ, no quotes, no parentheses.

### Audio

| Property | Value |
|---|---|
| Codec | MP3 (libmp3lame) |
| Bitrate | 256 kbps CBR |
| Sample rate | 44100 Hz |
| Channels | 2 (stereo) |
| Highpass | 100 Hz |
| Loudness | -16 LUFS (two-pass loudnorm) |
| True Peak | -1.5 dBTP |
| LRA | 11 LU |

### ID3v2.3 Metadata

Only includes: `title`, `artist`, `album`, `track`, `genre`. Everything else is stripped (embedded images, comments, encoder info, etc.).

## Why these decisions

### MP3 256kbps CBR

- Maximum compatibility with car stereos
- CBR is more stable for older decoders than VBR
- 256kbps is transparent for most listeners
- Saves space vs FLAC (~4-5x less)

### Highpass at 100 Hz

Car speakers can't reproduce frequencies below ~80-100 Hz. Removing them saves bitrate that would otherwise be wasted on inaudible information.

### Loudnorm two-pass

Each album/song has a different mastering level. Without normalization, you'd have to manually adjust volume between tracks. The two-pass loudnorm first measures the actual loudness of each file, then applies the exact correction so everything plays at the same perceived volume.

### fatsort

Without fatsort, the stereo reads files in the order they were written to the FAT filesystem, which depends on the filesystem and not the name. This causes songs to play in random order. `fatsort` physically reorders the directory entries on the device to match alphabetical order.

### Audio stream only (-map 0:a)

FLAC files often have cover art embedded as video streams. Without `-map 0:a`, ffmpeg would include them in the MP3 as embedded PNG/JPEG images, unnecessarily inflating file size.

## Considerations

- FAT32 has a 4GB per-file limit (not relevant for MP3)
- Don't exceed ~500-600 files per folder to avoid issues with older stereos
- Keep a single directory level (album folders, no subfolders)
- File/folder names max 64 characters for compatibility
- If files are added or removed in the future, re-run `fatsort`

## Log

Each run generates a `processing.log` in the destination directory with details of every processed file.

## License

Personal. Free to use.
