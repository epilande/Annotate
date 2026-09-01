#!/usr/bin/env bash
set -euo pipefail

ffmpeg_bin="${FFMPEG:-ffmpeg}"
if ! command -v "$ffmpeg_bin" >/dev/null 2>&1; then
    echo "ffmpeg is required to generate Annotate sounds" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/Annotate/Sounds"
mkdir -p "$output_dir"

render_blip() {
    local first_frequency="$1"
    local second_frequency="$2"
    local output="$3"

    "$ffmpeg_bin" \
        -hide_banner \
        -loglevel error \
        -y \
        -fflags +bitexact \
        -f lavfi -i "sine=frequency=${first_frequency}:sample_rate=44100:duration=0.045" \
        -f lavfi -i "sine=frequency=${second_frequency}:sample_rate=44100:duration=0.045" \
        -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1,afade=t=in:st=0:d=0.008,afade=t=out:st=0.078:d=0.012,volume=0.65[a]" \
        -map "[a]" \
        -map_metadata -1 \
        -ac 1 \
        -ar 44100 \
        -c:a pcm_s16le \
        -bitexact \
        "$output"
}

render_blip 660 990 "$output_dir/overlay-on.caf"
render_blip 990 660 "$output_dir/overlay-off.caf"

"$ffmpeg_bin" \
    -hide_banner \
    -loglevel error \
    -y \
    -fflags +bitexact \
    -f lavfi -i "anoisesrc=color=pink:sample_rate=44100:duration=0.15:seed=69" \
    -af "highpass=f=450,lowpass=f=3200,afade=t=in:st=0:d=0.035,afade=t=out:st=0.09:d=0.06,volume=0.25" \
    -map_metadata -1 \
    -ac 1 \
    -ar 44100 \
    -c:a pcm_s16le \
    -bitexact \
    "$output_dir/clear-all.caf"
