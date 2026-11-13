#!/usr/bin/env bash
# Latency bench for OVMS whisper transcription (OpenAI-compatible endpoint).
#
# Run anywhere with curl; point it at the service or a port-forward:
#   ./bench_asr.sh --url http://localhost:8000/v1 --runs 10 en.wav pt.wav
#
# In-cluster (no port-forward needed):
#   kubectl -n ai exec deploy/wyoming-asr -c ovms -- sh -c '...'  # or
#   kubectl -n ai port-forward deploy/wyoming-asr 8000:8000 &
#   ./bench_asr.sh --url http://localhost:8000/v1 en.wav pt.wav
#
# Reference baselines from k8s_homelab issue #1519 (RTX 2080 Ti,
# whisper-large-v3-turbo int8_float16, ~14 s clips): 0.7-1.2 s per clip.
# The trial passes when PT and EN p95 are within ~2x of that; much worse and
# the iGPU is not worth the trade.

set -euo pipefail

URL="http://localhost:8000/v1"
RUNS=10
MODEL="whisper-large-v3-turbo-int8-ov"
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "no wav files given; see --help" >&2
  exit 1
fi

# OVMS loads a --source_model on first request, which inflates run #1 badly.
echo "priming model '$MODEL' (cold load not measured)..." >&2
curl -fsS -o /dev/null "$URL/audio/transcriptions" -F "model=$MODEL" -F "file=@${FILES[0]}"

for f in "${FILES[@]}"; do
  durs=()
  texts=()
  for ((i=1; i<=RUNS; i++)); do
    out="$(mktemp)"
    t="$(curl -sS -o "$out" -w '%{time_total}' "$URL/audio/transcriptions" \
          -F "model=$MODEL" -F "file=@$f")"
    durs+=("$t")
    texts+=("$(jq -r '.text // "<error>"' "$out" 2>/dev/null || cat "$out")")
    rm -f "$out"
  done
  echo
  echo "== $f (${#durs[@]} runs) =="
  sorted="$(printf '%s\n' "${durs[@]}" | sort -n)"
  echo "$sorted" | awk '{a[NR]=$1} END{
    printf "  min %.2fs  p50 %.2fs  p95 %.2fs  max %.2fs\n", a[1], a[int((NR+1)/2)], a[int(NR*0.95+0.999)], a[NR]}'
  printf '  transcript: %s\n' "${texts[0]}"
done
