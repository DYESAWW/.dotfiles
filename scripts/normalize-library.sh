#!/usr/bin/env bash
#
# normalize-library.sh — batch loudness-normalize an MP3 library
#
# Two-pass EBU R128 loudness normalization (ffmpeg loudnorm filter).
# Re-encodes each file at its ORIGINAL bitrate to keep audio quality
# equivalent, preserves ID3 tags, and mirrors the source folder
# structure into the output directory. Safe to re-run: already
# normalized files are skipped.
#
# Usage:
#   ./normalize-library.sh <input_dir> <output_dir> [target_LUFS]
#
# Example:
#   ./normalize-library.sh ~/Music ~/Music-normalized -16
#
# target_LUFS defaults to -16 (good for portable players / earbuds).
# Use -14 for a louder streaming-style target, -18/-19 for more
# conservative/dynamic.

set -uo pipefail

IN_DIR="${1:?Usage: $0 <input_dir> <output_dir> [target_LUFS]}"
OUT_DIR="${2:?Usage: $0 <input_dir> <output_dir> [target_LUFS]}"
TARGET_I="${3:--16}"
TARGET_TP="-1.5"
TARGET_LRA="11"

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
    echo "Error: ffmpeg/ffprobe not found. Install with: sudo pacman -S ffmpeg" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

total=0
done_count=0
skipped=0
failed=0

# Collect files first so we can show progress
mapfile -d '' files < <(find "$IN_DIR" -type f -iname '*.mp3' -print0)
total=${#files[@]}

if [ "$total" -eq 0 ]; then
    echo "No MP3 files found under: $IN_DIR"
    exit 0
fi

echo "Found $total MP3 file(s). Target loudness: ${TARGET_I} LUFS"
echo

i=0
for src in "${files[@]}"; do
    i=$((i + 1))
    rel="${src#"$IN_DIR"/}"
    dst="$OUT_DIR/$rel"
    dst_dir=$(dirname "$dst")
    mkdir -p "$dst_dir"

    printf '[%d/%d] %s\n' "$i" "$total" "$rel"

    if [ -f "$dst" ]; then
        echo "  -> already exists, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    # Preserve original bitrate so output quality matches the source.
    # ffprobe can occasionally emit multiple lines/values (e.g. some VBR
    # files) so take only the first line and strip anything non-numeric.
    bitrate=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=bit_rate -of csv=p=0 "$src" 2>/dev/null \
        | head -n1 | tr -cd '0-9')

    # Fall back to container-level bitrate if the stream one is missing (common for VBR)
    if [ -z "$bitrate" ]; then
        bitrate=$(ffprobe -v error -show_entries format=bit_rate \
            -of csv=p=0 "$src" 2>/dev/null | head -n1 | tr -cd '0-9')
    fi

    # Final fallback if still not a valid number
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]] || [ "$bitrate" -eq 0 ]; then
        bitrate=192000
    fi
    bitrate_k="$((bitrate / 1000))k"

    # --- Pass 1: measure loudness ---
    measured=$(ffmpeg -hide_banner -nostats -i "$src" -af \
        "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:print_format=json" \
        -f null - 2>&1)

    json=$(echo "$measured" | awk '/^\{/{f=1} f{print} /^\}/{if(f)exit}')

    m_i=$(echo "$json" | grep -oP '"input_i"\s*:\s*"\K[^"]+')
    m_tp=$(echo "$json" | grep -oP '"input_tp"\s*:\s*"\K[^"]+')
    m_lra=$(echo "$json" | grep -oP '"input_lra"\s*:\s*"\K[^"]+')
    m_thresh=$(echo "$json" | grep -oP '"input_thresh"\s*:\s*"\K[^"]+')
    m_offset=$(echo "$json" | grep -oP '"target_offset"\s*:\s*"\K[^"]+')

    if [ -z "$m_i" ] || [ -z "$m_tp" ] || [ -z "$m_lra" ] || [ -z "$m_thresh" ]; then
        echo "  -> FAILED (could not measure loudness), skipping"
        failed=$((failed + 1))
        continue
    fi

    # --- Pass 2: apply normalization, re-encode at original bitrate ---
    if ffmpeg -hide_banner -loglevel error -y -i "$src" -af \
        "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:measured_I=${m_i}:measured_TP=${m_tp}:measured_LRA=${m_lra}:measured_thresh=${m_thresh}:offset=${m_offset}:linear=true" \
        -codec:a libmp3lame -b:a "$bitrate_k" \
        -map_metadata 0 -id3v2_version 3 \
        "$dst" </dev/null; then
        done_count=$((done_count + 1))
    else
        echo "  -> FAILED (encode error), skipping"
        rm -f "$dst"
        failed=$((failed + 1))
    fi
done

echo
echo "Done. Normalized: $done_count | Skipped (existing): $skipped | Failed: $failed"
echo "Output written to: $OUT_DIR"
