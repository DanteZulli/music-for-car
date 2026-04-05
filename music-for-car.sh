#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# music-for-car.sh
#
# Processes music folders for a car USB drive:
#   - Renames folders: "Band - Album" (no special characters)
#   - Converts EVERYTHING to MP3 CBR
#   - Applies highpass + loudnorm
#   - Cleans ID3 metadata
#
# Usage:
#   ./music-for-car.sh [-p profile] <source_dir> <dest_dir>
#
# Profiles are stored in profiles/*.conf
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"
LOG_FILE="$SCRIPT_DIR/processing.log"

###############################################################################
# Defaults
###############################################################################
PROFILE_NAME="Default"
HIGHPASS_FREQ="100"
LOUDNORM_I="-16"
LOUDNORM_TP="-1.5"
LOUDNORM_LRA="11"
BITRATE="256k"
SAMPLE_RATE="44100"
FFMPEG_THREADS="0"
FAST_LOUDNORM="false"
PARALLEL="false"

###############################################################################
# Parse arguments
###############################################################################
PROFILE=""
while getopts "p:" opt; do
    case "$opt" in
        p) PROFILE="$OPTARG" ;;
        *) echo "Usage: $0 [-p profile] <source_dir> <dest_dir>"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -lt 2 ]; then
    echo "Usage: $0 [-p profile] <source_dir> <dest_dir>"
    echo ""
    echo "  source_dir  - Folder with albums (or a single album)"
    echo "  dest_dir    - Where processed MP3s are saved"
    echo "  -p profile  - Profile name (looks in profiles/ directory)"
    echo ""
    echo "Available profiles:"
    if [ -d "$PROFILES_DIR" ]; then
        for f in "$PROFILES_DIR"/*.conf; do
            [ -f "$f" ] && echo "  $(basename "$f" .conf)"
        done
    fi
    exit 1
fi

###############################################################################
# Load profile
###############################################################################
if [ -n "$PROFILE" ]; then
    PROFILE_FILE="$PROFILES_DIR/${PROFILE}.conf"
    if [ ! -f "$PROFILE_FILE" ]; then
        echo "Error: profile '$PROFILE' not found at $PROFILE_FILE"
        exit 1
    fi
    # Source profile (allows comments via #)
    # shellcheck source=/dev/null
    source "$PROFILE_FILE"
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
    log "Profile: $PROFILE_NAME ($PROFILE)"
fi

MUSIC_DIR="$1"
WORK_DIR="$2"

mkdir -p "$WORK_DIR"
: > "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

###############################################################################
# Sanitize names: ASCII, no weird characters
###############################################################################
sanitize() {
    echo "$1" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | sed -E \
            -e "s/['\`´]//g" \
            -e 's/[^a-zA-Z0-9 _.-]+//g' \
            -e 's/  +/ /g' \
            -e 's/^ +//;s/ +$//'
}

###############################################################################
# Extract "Band - Album" from original folder name
###############################################################################
parse_band_album() {
    local raw="$1"
    local cleaned
    cleaned=$(echo "$raw" | sed -E 's/ *\([0-9]{4}\)$//')
    local band album
    band=$(echo "$cleaned" | sed -E 's/ *- .*//')
    album=$(echo "$cleaned" | sed -E 's/^[^-]+ *- *//')
    echo "${band}|${album}"
}

###############################################################################
# Count audio files in a folder
###############################################################################
count_audio_files() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \( \
        -iname "*.flac" -o -iname "*.mp3" -o -iname "*.wav" -o \
        -iname "*.ogg" -o -iname "*.opus" -o -iname "*.m4a" -o \
        -iname "*.aac" -o -iname "*.wma" -o -iname "*.alac" \
    \) | wc -l
}

###############################################################################
# Build the audio filter string
###############################################################################
build_filter() {
    local filter=""
    if [ "$HIGHPASS_FREQ" != "0" ] && [ -n "$HIGHPASS_FREQ" ]; then
        filter="highpass=f=${HIGHPASS_FREQ},"
    fi
    filter="${filter}loudnorm=I=${LOUDNORM_I}:TP=${LOUDNORM_TP}:LRA=${LOUDNORM_LRA}"
    echo "$filter"
}

###############################################################################
# Build the loudnorm measurement filter
###############################################################################
build_loudnorm_measure() {
    echo "loudnorm=I=${LOUDNORM_I}:TP=${LOUDNORM_TP}:LRA=${LOUDNORM_LRA}:print_format=json"
}

###############################################################################
# Convert a single audio file to MP3
###############################################################################
convert_one() {
    local input="$1"
    local output="$2"
    local track_num="$3"
    local title="$4"
    local artist="$5"
    local album="$6"

    local file_base
    file_base=$(basename "$input")

    if [ "$FAST_LOUDNORM" = "true" ]; then
        # Single-pass loudnorm (less accurate, faster)
        local filter
        filter=$(build_filter)
        ffmpeg -nostdin -y -i "$input" \
            -map 0:a -af "$filter" \
            -codec:a libmp3lame -b:a "$BITRATE" -ar "$SAMPLE_RATE" -ac 2 \
            -threads "$FFMPEG_THREADS" \
            -map_metadata -1 \
            -id3v2_version 3 \
            -metadata title="$title" \
            -metadata artist="$artist" \
            -metadata album="$album" \
            -metadata track="$track_num" \
            "$output" 2>/dev/null
    else
        # Two-pass loudnorm
        # Pass 1: Measure
        local measured
        measured=$(ffmpeg -nostdin -i "$input" -af "$(build_loudnorm_measure)" -f null - 2>&1 \
            | grep -A 20 '"input_' || true)

        local input_i input_tp input_lra input_thresh target_offset
        input_i=$(echo "$measured" | grep '"input_i"' | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | tr -d ',')
        input_tp=$(echo "$measured" | grep '"input_tp"' | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | tr -d ',')
        input_lra=$(echo "$measured" | grep '"input_lra"' | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | tr -d ',')
        input_thresh=$(echo "$measured" | grep '"input_thresh"' | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | tr -d ',')
        target_offset=$(echo "$measured" | grep '"target_offset"' | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/' | tr -d ',')

        input_i=${input_i:--24.0}
        input_tp=${input_tp:--2.0}
        input_lra=${input_lra:-12.0}
        input_thresh=${input_thresh:--34.0}
        target_offset=${target_offset:-0.0}

        # Pass 2: Convert with measured values + clean metadata (audio stream only)
        local filter
        filter=$(build_filter)
        filter="${filter}:measured_I=${input_i}:measured_TP=${input_tp}:measured_LRA=${input_lra}:measured_thresh=${input_thresh}:offset=${target_offset}:linear=true"

        ffmpeg -nostdin -y -i "$input" \
            -map 0:a -af "$filter" \
            -codec:a libmp3lame -b:a "$BITRATE" -ar "$SAMPLE_RATE" -ac 2 \
            -threads "$FFMPEG_THREADS" \
            -map_metadata -1 \
            -id3v2_version 3 \
            -metadata title="$title" \
            -metadata artist="$artist" \
            -metadata album="$album" \
            -metadata track="$track_num" \
            "$output" 2>/dev/null
    fi

    return $?
}

###############################################################################
# Convert an audio file to MP3 (wrapper that handles naming and metadata)
###############################################################################
convert_to_mp3() {
    local input="$1"
    local output="$2"
    local padded_track="$3"
    local orig_title="$4"
    local orig_artist="$5"
    local orig_album="$6"

    convert_one "$input" "$output" "$padded_track" "$orig_title" "$orig_artist" "$orig_album"
    return $?
}

###############################################################################
# MAIN
###############################################################################
log "=========================================="
log "Starting processing"
log "Source directory: $MUSIC_DIR"
log "Destination directory: $WORK_DIR"
log "=========================================="

# Determine if MUSIC_DIR is a single album or a directory with multiple albums
if count_audio_files "$MUSIC_DIR" | grep -q '^[1-9]'; then
    FOLDERS=("$MUSIC_DIR")
else
    mapfile -t FOLDERS < <(find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

TOTAL=${#FOLDERS[@]}
COUNTER=0
SKIPPED=0

for folder in "${FOLDERS[@]}"; do
    COUNTER=$((COUNTER + 1))
    folder_name=$(basename "$folder")

    audio_count=$(count_audio_files "$folder")
    if [ "$audio_count" -eq 0 ]; then
        log "SKIP (no audio): $folder_name"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    IFS='|' read -r band album <<< "$(parse_band_album "$folder_name")"
    band=$(sanitize "$band")
    album=$(sanitize "$album")

    dest_folder_name="$band - $album"
    dest_path="$WORK_DIR/$dest_folder_name"

    log "[$COUNTER/$TOTAL] Processing: $folder_name -> $dest_folder_name ($audio_count files)"

    mkdir -p "$dest_path"

    if [ "$PARALLEL" = "true" ]; then
        # Parallel mode: process files concurrently
        file_counter=0
        pids=()
        while IFS= read -r audio_file; do
            file_counter=$((file_counter + 1))
            padded_track=$(printf "%02d" "$file_counter")

            file_base=$(basename "$audio_file")
            file_no_ext="${file_base%.*}"

            # Strip numeric prefixes from name (can be multiple: "01 - 01 - ...")
            file_no_ext=$(echo "$file_no_ext" | sed -E 's/^([0-9]+[. -]+)+//')
            # Strip prefixes like "Band_Name_XX_" (compound names with embedded track number)
            embedded_track=$(echo "$file_no_ext" | grep -oP '(?<=_)[0-9]{2}(?=_)' | head -1 || true)
            if [ -n "$embedded_track" ]; then
                file_no_ext=$(echo "$file_no_ext" | sed -E "s/^.*_${embedded_track}_//")
            fi

            out_name="${padded_track} - ${file_no_ext}.mp3"
            out_name=$(sanitize "$out_name")
            out_path="$dest_path/$out_name"

            # Extract original track number for metadata
            orig_track=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_track=$(echo "$orig_track" | cut -d'/' -f1 | sed 's/^0*//')
            [ -z "$orig_track" ] || [ "$orig_track" -eq 0 ] 2>/dev/null && orig_track="$padded_track"

            orig_artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_album=$(ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_title=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "$audio_file" 2>/dev/null || echo "")

            [ -z "$orig_artist" ] && orig_artist="$band"
            [ -z "$orig_album" ] && orig_album="$album"
            [ -z "$orig_title" ] && orig_title="$file_no_ext"

            convert_to_mp3 "$audio_file" "$out_path" "$padded_track" "$orig_title" "$orig_artist" "$orig_album" &
            pids+=($!)
        done < <(find "$folder" -maxdepth 1 -type f \( \
            -iname "*.flac" -o -iname "*.mp3" -o -iname "*.wav" -o \
            -iname "*.ogg" -o -iname "*.opus" -o -iname "*.m4a" -o \
            -iname "*.aac" -o -iname "*.wma" -o -iname "*.alac" \
        \) | sort)

        # Wait for all background jobs and log results
        ok_count=0
        err_count=0
        for pid in "${pids[@]}"; do
            if wait "$pid"; then
                ok_count=$((ok_count + 1))
            else
                err_count=$((err_count + 1))
            fi
        done

        # Log results in order
        file_counter=0
        while IFS= read -r audio_file; do
            file_counter=$((file_counter + 1))
            padded_track=$(printf "%02d" "$file_counter")

            file_base=$(basename "$audio_file")
            file_no_ext="${file_base%.*}"
            file_no_ext=$(echo "$file_no_ext" | sed -E 's/^([0-9]+[. -]+)+//')
            embedded_track=$(echo "$file_no_ext" | grep -oP '(?<=_)[0-9]{2}(?=_)' | head -1 || true)
            if [ -n "$embedded_track" ]; then
                file_no_ext=$(echo "$file_no_ext" | sed -E "s/^.*_${embedded_track}_//")
            fi

            out_name="${padded_track} - ${file_no_ext}.mp3"
            out_name=$(sanitize "$out_name")

            # Check if file exists (successful conversion)
            if [ -f "$dest_path/$out_name" ]; then
                log "  OK: $out_name"
            else
                log "  ERROR: $(basename "$audio_file")"
            fi
        done < <(find "$folder" -maxdepth 1 -type f \( \
            -iname "*.flac" -o -iname "*.mp3" -o -iname "*.wav" -o \
            -iname "*.ogg" -o -iname "*.opus" -o -iname "*.m4a" -o \
            -iname "*.aac" -o -iname "*.wma" -o -iname "*.alac" \
        \) | sort)

        log "  Completed: $dest_folder_name ($ok_count files converted, $err_count errors)"
    else
        # Sequential mode
        file_counter=0
        while IFS= read -r audio_file; do
            file_counter=$((file_counter + 1))
            padded_track=$(printf "%02d" "$file_counter")

            file_base=$(basename "$audio_file")
            file_no_ext="${file_base%.*}"

            # Strip numeric prefixes from name (can be multiple: "01 - 01 - ...")
            file_no_ext=$(echo "$file_no_ext" | sed -E 's/^([0-9]+[. -]+)+//')
            # Strip prefixes like "Band_Name_XX_" (compound names with embedded track number)
            embedded_track=$(echo "$file_no_ext" | grep -oP '(?<=_)[0-9]{2}(?=_)' | head -1 || true)
            if [ -n "$embedded_track" ]; then
                file_no_ext=$(echo "$file_no_ext" | sed -E "s/^.*_${embedded_track}_//")
            fi

            out_name="${padded_track} - ${file_no_ext}.mp3"
            out_name=$(sanitize "$out_name")
            out_path="$dest_path/$out_name"

            # Extract original track number for metadata
            orig_track=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_track=$(echo "$orig_track" | cut -d'/' -f1 | sed 's/^0*//')
            [ -z "$orig_track" ] || [ "$orig_track" -eq 0 ] 2>/dev/null && orig_track="$padded_track"

            orig_artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_album=$(ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
            orig_title=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "$audio_file" 2>/dev/null || echo "")

            [ -z "$orig_artist" ] && orig_artist="$band"
            [ -z "$orig_album" ] && orig_album="$album"
            [ -z "$orig_title" ] && orig_title="$file_no_ext"

            if convert_to_mp3 "$audio_file" "$out_path" "$padded_track" "$orig_title" "$orig_artist" "$orig_album"; then
                log "  OK: $out_name"
            else
                log "  ERROR: $audio_file"
            fi
        done < <(find "$folder" -maxdepth 1 -type f \( \
            -iname "*.flac" -o -iname "*.mp3" -o -iname "*.wav" -o \
            -iname "*.ogg" -o -iname "*.opus" -o -iname "*.m4a" -o \
            -iname "*.aac" -o -iname "*.wma" -o -iname "*.alac" \
        \) | sort)

        log "  Completed: $dest_folder_name ($file_counter files converted)"
    fi
done

log "=========================================="
log "Processing finished"
log "Total folders: $TOTAL"
log "Folders processed: $((TOTAL - SKIPPED))"
log "Folders without audio: $SKIPPED"
log "=========================================="
