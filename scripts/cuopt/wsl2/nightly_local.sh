#!/usr/bin/env bash
# Nightly cuOpt run on James's workstation, inside WSL2 Ubuntu. Local only:
# its results stay on this machine (they may include TIM, CLAUDE.md).
#
# Started each night by the Windows scheduled task "TIMESjl cuOpt nightly
# (WSL2)" (register_nightly.ps1 -> nightly_task.py, which holds one of the
# workstation's four run slots while this runs). By hand:
#
#   bash ~/git/TIMESjl/scripts/cuopt/wsl2/nightly_local.sh [--conf FILE]
#
# Settings, in ~/.config/timesjl/cuopt-nightly.conf (setup_cuopt.sh writes the
# defaults; edit it to change what runs, no commit needed):
#   REF=main               branch to move the checkout to first (only if it has no local changes)
#   FIXTURES=demo12_off    public CI fixtures: comma-separated, "all", or empty for none
#   REF_MODELS=""          reference runs (model ids of reference/suite.toml, e.g. "OTNYC-reference"),
#                          copied from REF_WIN to REF_LINUX (reduce_off) before solving
#   REF_WIN=/mnt/c/git/esma/timesjl-reference
#   REF_LINUX=$HOME/timesjl-reference
#   ROOTS=""               "name=path ..." for reference runs whose run file was not kept
#   METHODS="barrier pdlp"
#   SHARES=100             WSL2 has no MPS: levels below 100% are recorded as skipped
#   KEEP_NIGHTS=30         nights kept in ~/timesjl-cuopt/nightly
#
# Writes ~/timesjl-cuopt/nightly/<date>/ (fixtures/, reference/: sweep.md and
# the JSON of each level; nightly.log; status.txt) and points
# ~/timesjl-cuopt/nightly/latest at it. From Windows:
#   \\wsl.localhost\<distro>\home\<user>\timesjl-cuopt\nightly\latest\
#
# Everything runs inside main(): bash has read the whole script before the
# checkout (and so this file) is updated.

main() {
  set -uo pipefail
  local conf="$HOME/.config/timesjl/cuopt-nightly.conf" envfile="$HOME/.config/timesjl/cuopt.env"
  while [ $# -gt 0 ]; do
    case "$1" in
      --conf) conf="$2"; shift 2 ;;
      -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; return 0 ;;
      *) echo "unknown option: $1" >&2; return 2 ;;
    esac
  done
  [ -f "$envfile" ] || { echo "$envfile not found: run scripts/cuopt/wsl2/setup_cuopt.sh first" >&2; return 2; }
  # shellcheck disable=SC1090
  . "$envfile"
  local REF=main FIXTURES=demo12_off REF_MODELS="" REF_WIN=/mnt/c/git/esma/timesjl-reference
  local REF_LINUX="$HOME/timesjl-reference" ROOTS="" METHODS="barrier pdlp" SHARES=100 KEEP_NIGHTS=30
  # shellcheck disable=SC1090
  [ -f "$conf" ] && . "$conf"

  local repo base out
  repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
  base="$HOME/timesjl-cuopt/nightly"
  out="$base/$(date +%F)"
  [ -e "$out" ] && out="$out-$(date +%H%M)"
  mkdir -p "$out"
  exec > >(tee -a "$out/nightly.log") 2>&1
  echo "== cuOpt nightly (WSL2), $(date -Is), $(hostname)"
  echo "   fixtures: ${FIXTURES:-none}; reference runs: ${REF_MODELS:-none}; methods: $METHODS; GPU shares: $SHARES"

  cd "$repo" || return 2
  if [ -z "$(git status --porcelain)" ]; then
    git fetch -q origin "$REF" && git checkout -q -B "$REF" FETCH_HEAD
  else
    echo "   the checkout has local changes: running it as it is"
  fi
  echo "   TIMESjl $(git log -1 --format='%h %s')"
  local pkglog
  pkglog=$(julia --project=scripts/cuopt -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()' 2>&1) ||
    { echo "$pkglog" | tail -30; echo "Julia environment failed"; echo "environment: failed" > "$out/status.txt"; return 1; }

  local margs=(--quiet) m worst=0 rc
  for m in $METHODS; do margs+=(--method "$m"); done
  : > "$out/status.txt"

  if [ -n "$FIXTURES" ]; then
    echo "== fixtures ($FIXTURES)"
    scripts/cuopt/sweep.sh --out "$out/fixtures" --shares "$SHARES" -- --only "$FIXTURES" "${margs[@]}"
    rc=$?; echo "fixtures: exit $rc" >> "$out/status.txt"; [ "$rc" -gt "$worst" ] && worst=$rc
  fi

  if [ -n "$REF_MODELS" ]; then
    echo "== reference runs ($REF_MODELS)"
    local model rargs=() r copied=()
    for model in $REF_MODELS; do
      if [ -d "$REF_WIN/$model/reduce_off" ]; then
        mkdir -p "$REF_LINUX/$model"
        rsync -a --delete "$REF_WIN/$model/reduce_off/" "$REF_LINUX/$model/reduce_off/" && copied+=("$model")
      else
        echo "   $model: no $REF_WIN/$model/reduce_off; skipped"
      fi
    done
    for r in $ROOTS; do rargs+=(--root "$r"); done
    if [ ${#copied[@]} -gt 0 ]; then
      scripts/cuopt/sweep.sh --out "$out/reference" --shares "$SHARES" -- --ref "$REF_LINUX" "${rargs[@]}" "${copied[@]}" "${margs[@]}"
      rc=$?; echo "reference: exit $rc" >> "$out/status.txt"; [ "$rc" -gt "$worst" ] && worst=$rc
    fi
  fi

  ln -sfn "$out" "$base/latest"
  find "$base" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n "-$KEEP_NIGHTS" | xargs -r rm -rf
  echo "== done, exit $worst: $out"
  return "$worst"
}

main "$@"
exit $?
