#!/usr/bin/env bash
# tools/container/in/record.sh -- `tools/dev record`, inside the dev container.
#
# Usage (in the container): tools/container/in/record.sh <binary> <out.mp4> <scale> <limit> [sss args...]
#   <binary>   the game to run (tools/dev passes its credential-free builds/record/sss)
#   <out.mp4>  where ffmpeg writes the video
#   <scale>    whole-number upscale, nearest-neighbour
#   <limit>    wall-clock limit in seconds; a game still running then is killed
#
# Starts its own X server and a PulseAudio server whose only sink is a null sink, so the
# game's sound goes nowhere but ffmpeg, which records the display and the sink's monitor
# to H.264/AAC. The game runs from a fresh launch folder (no saved settings or callsign),
# as tests/playthrough/run.sh does. Recording stops when the game exits.
set -euo pipefail

if [ $# -lt 4 ]; then
    sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi
bin=$1 out=$2 scale=$3 limit=$4
shift 4

for tool in Xvfb xdpyinfo pulseaudio pactl ffmpeg; do
    command -v "$tool" > /dev/null || {
        echo "Error: the dev image has no $tool; rebuild it with: tools/dev image" >&2
        exit 1
    }
done

launch=$(mktemp -d)
XDG_RUNTIME_DIR=$(mktemp -d)
export XDG_RUNTIME_DIR DISPLAY=:99
pids=()
cleanup() {
    if [ ${#pids[@]} -gt 0 ]; then
        kill "${pids[@]}" 2> /dev/null || true
    fi
    wait 2> /dev/null || true
}
trap cleanup EXIT

# 320x240 is the game window, fullscreen or not
Xvfb :99 -screen 0 320x240x24 -nolisten tcp > "$launch/xvfb.log" 2>&1 &
pids+=($!)
pulseaudio -n --daemonize=no --exit-idle-time=-1 \
    --load=module-native-protocol-unix --load="module-null-sink sink_name=rec" \
    > "$launch/pulse.log" 2>&1 &
pids+=($!)
for _ in $(seq 100); do
    xdpyinfo > /dev/null 2>&1 && pactl info > /dev/null 2>&1 && break
    sleep 0.1
done
xdpyinfo > /dev/null 2>&1 || { echo "Error: Xvfb did not start:" >&2; cat "$launch/xvfb.log" >&2; exit 1; }
pactl info > /dev/null 2>&1 || { echo "Error: PulseAudio did not start:" >&2; cat "$launch/pulse.log" >&2; exit 1; }

ffmpeg -nostdin -hide_banner -loglevel warning -y \
    -thread_queue_size 1024 -f x11grab -draw_mouse 0 -framerate 60 -video_size 320x240 -i :99 \
    -thread_queue_size 1024 -f pulse -i rec.monitor \
    -vf "scale=iw*$scale:ih*$scale:flags=neighbor" \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -movflags +faststart "$out" > "$launch/ffmpeg.log" 2>&1 &
ff=$!
pids+=("$ff")

echo ">>> recording: sss $*"
start=$SECONDS
rc=0
(cd "$launch" && timeout -k 5 "$limit" "$bin" "$@" > game.out 2>&1) || rc=$?
echo ">>> game exited with $rc after $((SECONDS - start))s"
sleep 1    # let the last sound reach the recording
kill -TERM "$ff" 2> /dev/null || true
wait "$ff" 2> /dev/null || true

game_log() { grep -v "^ALSA lib" "$launch/game.out" | tail -n 20 >&2 || true; }
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "Error: still running after ${limit}s (hung, or an error dialog); stopped it" >&2
    game_log
    exit 1
elif [ "$rc" -ne 0 ]; then
    echo "Error: the game exited with status $rc" >&2
    game_log
    exit 1
fi
if [ ! -s "$out" ]; then
    echo "Error: ffmpeg wrote no video:" >&2
    cat "$launch/ffmpeg.log" >&2
    exit 1
fi
