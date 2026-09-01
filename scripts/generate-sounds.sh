#!/usr/bin/env bash
# Synthesizes the app's feedback sounds with ffmpeg. Two themes ship, each with three cues:
#
#   chalk-*  chalk tap on a board, dropped in the tray, felt eraser swipe
#   paper-*  page flip, sheet set down, page tear
#
# Everything is deterministic (seeded noise, bitexact encoding), so re-running this script
# reproduces the committed .caf files byte for byte.
set -euo pipefail

ffmpeg_bin="${FFMPEG:-ffmpeg}"
if ! command -v "$ffmpeg_bin" >/dev/null 2>&1; then
	echo "ffmpeg is required to generate Annotate sounds" >&2
	exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/Annotate/Sounds"
mkdir -p "$output_dir"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

rate=44100

# Renders a filtergraph (which must end in [out]) to a float WAV so mixing never clips.
render() {
	local name="$1" graph="$2"
	"$ffmpeg_bin" -hide_banner -loglevel error -y -fflags +bitexact \
		-filter_complex "$graph" -map "[out]" \
		-map_metadata -1 -ac 1 -ar "$rate" -c:a pcm_f32le -bitexact "$work_dir/$name.wav"
}

# Loudness-matches a clip (RMS to -20 dBFS, peaks capped at -1 dBFS) and writes the final .caf.
finish() {
	local name="$1" peak rms gain
	read -r peak rms < <("$ffmpeg_bin" -hide_banner -i "$work_dir/$name.wav" \
		-af astats=measure_overall=Peak_level+RMS_level:measure_perchannel=none -f null - 2>&1 |
		awk '/Peak level dB/ {p=$NF} /RMS level dB/ {r=$NF} END {print p, r}')
	gain=$(echo "a=-1-($peak); b=-20-($rms); if (a<b) a else b" | bc -l)
	"$ffmpeg_bin" -hide_banner -loglevel error -y -fflags +bitexact -i "$work_dir/$name.wav" \
		-af "volume=${gain}dB,areverse,afade=t=in:d=0.008,areverse,afade=t=in:d=0.002" \
		-map_metadata -1 -c:a pcm_s16le -bitexact "$output_dir/$name.caf"
}

# Filtergraph building blocks -------------------------------------------------
# noise <label> <color> <seed> <duration> <filters>: seeded noise through a filter chain
noise() { echo "anoisesrc=color=$2:seed=$3:r=$rate:d=$4,$5[$1]"; }
# grain <label> <seed> <duration> <lowpass Hz> [power]: slow positive modulator for texture
grain() { echo "anoisesrc=color=white:seed=$2:r=$rate:d=$3,lowpass=f=$4:p=2,aeval=exprs='pow(abs(val(0))\,${5:-1})'[$1]"; }
# envelope <in> <out> <expr>: multiply a stream by a time-varying expression
envelope() { echo "[$1]aeval=exprs='val(0)*($3)'[$2]"; }
# synth <label> <duration> <expr>: a stream synthesized directly from an expression of t
synth() { echo "aevalsrc=exprs='$3':s=$rate:d=$2[$1]"; }
# knock <body Hz> <ring Hz> <start> <amp>: a tap transient (noise attack plus two decaying partials)
knock() {
	echo "if(gt(t,$3),$4*((random(0)*2-1)*exp(-(t-$3)*300)*0.4+sin(2*PI*$2*(t-$3))*exp(-(t-$3)*110)*0.5+sin(2*PI*$1*(t-$3))*exp(-(t-$3)*60)),0)"
}

# Chalk -----------------------------------------------------------------------
render chalk-overlay-on "$(synth a 0.1 '(random(0)*2-1)*exp(-t*350)*0.6+sin(2*PI*1500*t)*exp(-t*160)*0.35+sin(2*PI*520*t)*exp(-t*70)*0.5');[a]lowpass=f=5000[out]"
render chalk-overlay-off "$(synth a 0.2 "$(knock 380 1000 0 1)+$(knock 300 850 0.07 0.7)");[a]lowpass=f=3500[out]"
render chalk-clear-all "$(noise n pink 61 0.26 'highpass=f=200,lowpass=f=2200');$(grain g 62 0.26 60);[n][g]amultiply[m];$(envelope m out 'pow(sin(PI*t/0.26)\,1.1)')"

# Paper -----------------------------------------------------------------------
render paper-overlay-on "$(noise n white 51 0.22 'highpass=f=1500,lowpass=f=9000');$(grain g 52 0.22 500 1.5);[n][g]amultiply[m];$(envelope m e 'if(lt(t\,0.12)\,pow(t/0.12\,2)\,exp(-(t-0.12)*50))');$(synth w 0.22 'if(gt(t,0.12),sin(2*PI*140*(t-0.12))*exp(-(t-0.12)*40)*0.05,0)');[e][w]amix=inputs=2:normalize=0[out]"
render paper-overlay-off "$(noise n pink 53 0.14 'highpass=f=300,lowpass=f=4000');$(envelope n e 'sin(PI*t/0.14)');$(synth w 0.14 'if(gt(t,0.09),sin(2*PI*120*(t-0.09))*exp(-(t-0.09)*50)*0.25,0)');[e][w]amix=inputs=2:normalize=0[out]"
render paper-clear-all "$(noise n white 54 0.3 'highpass=f=800,lowpass=f=7000');$(grain g 55 0.3 900 1.5);[n][g]amultiply[m];$(envelope m out 'min(1\,t/0.02)*(1-t/0.3)*(0.6+0.4*sin(2*PI*t*7))')"

for clip in "$work_dir"/*.wav; do
	finish "$(basename "${clip%.wav}")"
done
