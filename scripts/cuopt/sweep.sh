#!/usr/bin/env bash
# GPU-share sweep for the cuOpt lane (scripts/cuopt/README.md): the same
# cuopt_layer3.jl run at several shares of the GPU, one level at a time, to see
# how the solve time scales with the GPU it is given.
#
#   scripts/cuopt/sweep.sh --out DIR [--shares "25 50 100"] [--mps auto|on|off] [-- <cuopt_layer3.jl options>]
#
# A share below 100% caps the run to that fraction of the GPU's threads with
# NVIDIA MPS (Volta or newer, native Linux only: MPS does not run in WSL2).
# Each level gets its own MPS control daemon with
# set_default_active_thread_percentage, so the cap is set before the run's
# CUDA context exists. With MPS (auto: whenever it is available and the sweep
# has more than one level), the 100% level runs under MPS too, so the cap is
# the only thing that changes between levels. A level that needs MPS where
# there is none is recorded as skipped, never run uncapped under its label.
#
# Each level is a separate process: cuOpt reports its own solve time, so Julia
# start-up and model generation do not enter the comparison. During each level
# nvidia-smi is sampled every second (GPU utilisation, memory, SM clock, power,
# temperature) and the compute processes every two seconds, which shows whether
# the MPS server carried the run.
#
# Writes, per level, DIR/share<p>.json and .md (cuopt_layer3.jl), .gpu.csv,
# .apps.csv, .rc, .seconds and .mps-log/ (or .skipped), then DIR/sweep.md and
# DIR/sweep.json (sweep_summary.py). Exit code: the worst level's.
set -uo pipefail   # no -e: one failed level must not stop the others

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT=""
SHARES="100"
MPS=auto
REST=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --shares) SHARES="$2"; shift 2 ;;
    --mps) MPS="$2"; shift 2 ;;
    --) shift; REST=("$@"); break ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (options for cuopt_layer3.jl go after --)" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || { echo "--out DIR is required" >&2; exit 2; }
case "$MPS" in auto|on|off) ;; *) echo "--mps must be auto, on or off" >&2; exit 2 ;; esac
read -r -a LEVELS <<< "$SHARES"
[ ${#LEVELS[@]} -gt 0 ] || { echo "--shares is empty" >&2; exit 2; }
for p in "${LEVELS[@]}"; do
  [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 100 ] || { echo "share '$p' is not 1-100" >&2; exit 2; }
done
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# --- Is MPS available? ----------------------------------------------------------
WHY_NO_MPS=""
if grep -qi microsoft /proc/version 2>/dev/null; then
  WHY_NO_MPS="WSL2 has no MPS (NVIDIA does not ship it there); run the sweep on native Linux"
elif ! command -v nvidia-cuda-mps-control >/dev/null 2>&1; then
  WHY_NO_MPS="nvidia-cuda-mps-control not found (it comes with the NVIDIA driver utilities)"
fi
USE_MPS=0
if [ "$MPS" = on ]; then
  [ -z "$WHY_NO_MPS" ] || { echo "--mps on: $WHY_NO_MPS" >&2; exit 2; }
  USE_MPS=1
elif [ "$MPS" = auto ] && [ -z "$WHY_NO_MPS" ]; then
  if [ ${#LEVELS[@]} -gt 1 ] || [ "${LEVELS[0]}" -lt 100 ]; then USE_MPS=1; fi
fi
[ "$MPS" = off ] && WHY_NO_MPS="--mps off"

# MPS's pipes (sockets) live in a short private temporary directory: socket
# paths are limited to about 100 characters, and artifact uploads skip sockets.
# The MPS logs are copied to DIR/share<p>.mps-log/ after each level.
MPS_DIR=""
mps_start() {   # $1: active thread percentage
  MPS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/timesjl-mps.XXXXXX") || return 1
  export CUDA_MPS_PIPE_DIRECTORY="$MPS_DIR/pipe" CUDA_MPS_LOG_DIRECTORY="$MPS_DIR/log"
  mkdir -p "$CUDA_MPS_PIPE_DIRECTORY" "$CUDA_MPS_LOG_DIRECTORY"
  nvidia-cuda-mps-control -d || return 1
  echo "set_default_active_thread_percentage $1" | nvidia-cuda-mps-control >/dev/null || return 1
  local got
  got=$(echo get_default_active_thread_percentage | nvidia-cuda-mps-control) || return 1
  awk -v g="$got" -v p="$1" 'BEGIN { exit !(g + 0 == p + 0) }' || { echo "MPS reports $got%, not $1%" >&2; return 1; }
}
mps_stop() {   # $1 (optional): stem to copy the MPS logs next to
  [ -n "$MPS_DIR" ] || return 0
  echo quit | nvidia-cuda-mps-control >/dev/null 2>&1 || true
  if [ -n "${1:-}" ] && [ -d "$MPS_DIR/log" ]; then
    mkdir -p "$1.mps-log" && cp -p "$MPS_DIR"/log/*.log "$1.mps-log/" 2>/dev/null
  fi
  rm -rf "$MPS_DIR"
  MPS_DIR=""
  unset CUDA_MPS_PIPE_DIRECTORY CUDA_MPS_LOG_DIRECTORY
}

TEL=()
telemetry_start() {   # $1: file stem
  nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,memory.total,clocks.sm,power.draw,temperature.gpu \
    --format=csv,noheader,nounits --loop-ms=1000 > "$1.gpu.csv" 2>/dev/null &
  TEL=($!)
  ( while :; do
      nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null
      sleep 2
    done ) > "$1.apps.csv" &
  TEL+=($!)
}
telemetry_stop() {
  [ ${#TEL[@]} -gt 0 ] || return 0
  kill "${TEL[@]}" 2>/dev/null
  wait "${TEL[@]}" 2>/dev/null
  TEL=()
}
trap 'telemetry_stop; mps_stop' EXIT

cd "$REPO"
echo "cuOpt GPU-share sweep: levels $(printf '%s%%, ' "${LEVELS[@]}" | sed 's/, $//'), one at a time; MPS $([ "$USE_MPS" = 1 ] && echo on || echo "off (${WHY_NO_MPS:-not needed})")"
WORST=0
for p in "${LEVELS[@]}"; do
  stem="$OUT/share$p"
  rm -rf "$stem".{json,md,gpu.csv,apps.csv,rc,seconds,skipped,mps-log}
  if [ "$p" -lt 100 ] && [ "$USE_MPS" = 0 ]; then
    echo "${WHY_NO_MPS:-MPS not in use}" > "$stem.skipped"
    echo "== $p%: skipped (${WHY_NO_MPS:-MPS not in use})"
    continue
  fi
  if [ "$USE_MPS" = 1 ] && ! mps_start "$p"; then
    mps_stop "$stem"
    echo "MPS control daemon did not start at $p%" > "$stem.skipped"
    echo "== $p%: skipped (MPS did not start)"
    continue
  fi
  echo "== $p% of the GPU"
  telemetry_start "$stem"
  t0=$(date +%s.%N)
  TIMESJL_GPU_SHARE="$p" TIMESJL_MPS=$([ "$USE_MPS" = 1 ] && echo on || echo off) \
    julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl "$stem.json" --summary "$stem.md" "${REST[@]}"
  rc=$?
  t1=$(date +%s.%N)
  telemetry_stop
  [ "$USE_MPS" = 1 ] && mps_stop "$stem"
  echo "$rc" > "$stem.rc"
  awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f\n", b - a }' > "$stem.seconds"
  [ "$rc" -gt "$WORST" ] && WORST=$rc
done

python3 "$REPO/scripts/cuopt/sweep_summary.py" "$OUT" || WORST=$(( WORST > 0 ? WORST : 1 ))
[ -f "$OUT/sweep.md" ] && cat "$OUT/sweep.md"
exit "$WORST"
