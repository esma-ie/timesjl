#!/usr/bin/env bash
# Sets up NVIDIA cuOpt for TIMES.jl on Linux: WSL2 Ubuntu on James's Windows
# workstation (setup_wsl2.ps1 runs this), or a native Ubuntu.
#
#   bash scripts/cuopt/wsl2/setup_cuopt.sh [--cuda 12|13] [--ref main] [--dir ~/git/TIMESjl] [--no-demo]
#
# 1. checks the GPU (cuOpt: Volta or newer, compute capability 7.0+; CUDA 13: 7.5+)
# 2. installs Julia (juliaup) if missing
# 3. installs the cuOpt 26.10 library (pip wheel libcuopt-mathopt-cuNN) in a venv
# 4. writes ~/.config/timesjl/cuopt.env (LD_LIBRARY_PATH, CPU thread limits),
#    sources it from ~/.bashrc, and writes ~/.config/timesjl/cuopt-nightly.conf
#    (what the local nightly solves) unless it exists
# 5. clones esma-ie/TIMESjl on the Linux file system (fast; /mnt/c is slow)
# 6. instantiates scripts/cuopt and solves a small LP on the GPU
# 7. unless --no-demo: the cuOpt layer-3 check on the demo12 CI fixture
#
# Idempotent: run it again to update. It never touches a checkout with local
# changes, and never installs an NVIDIA driver inside WSL (the Windows driver
# provides the GPU there; a Linux driver in WSL breaks it).
set -euo pipefail

CUDA=12
REF=main
DIR="$HOME/git/TIMESjl"
DEMO=1
CUOPT_VERSION="26.10.*"   # cuOpt.jl 0.5.0 (scripts/cuopt/Project.toml) loads only cuOpt 26.10
VENV="$HOME/.venvs/cuopt"
ENVFILE="$HOME/.config/timesjl/cuopt.env"
OUTDIR="$HOME/timesjl-cuopt"

while [ $# -gt 0 ]; do
  case "$1" in
    --cuda) CUDA="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --no-demo) DEMO=0; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$CUDA" in 12|13) ;; *) echo "--cuda must be 12 or 13" >&2; exit 2 ;; esac

say() { printf '\n== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. GPU ------------------------------------------------------------------
say "GPU"
WSL=0
grep -qi microsoft /proc/version 2>/dev/null && WSL=1
if [ "$WSL" = 1 ] && dpkg -l 2>/dev/null | grep -qE '^ii\s+nvidia-driver-'; then
  echo "WARNING: a Linux NVIDIA driver package is installed inside WSL. CUDA on WSL uses"
  echo "         the Windows driver; remove the Linux one (sudo apt purge 'nvidia-driver-*')."
fi
command -v nvidia-smi >/dev/null 2>&1 || {
  [ "$WSL" = 1 ] && die "nvidia-smi not found. Update the NVIDIA driver on Windows, then 'wsl --update' and 'wsl --shutdown'."
  die "nvidia-smi not found: install the NVIDIA driver (sudo ubuntu-drivers install) and reboot."
}
GPU=$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader | head -1) ||
  die "nvidia-smi cannot query the GPU"
echo "$GPU"
CC=$(echo "$GPU" | awk -F', ' '{print $4}')
MIN_CC=7.0; [ "$CUDA" = 13 ] && MIN_CC=7.5
awk -v c="$CC" -v m="$MIN_CC" 'BEGIN { exit !(c + 0 >= m + 0) }' ||
  die "compute capability $CC is below $MIN_CC, which cuOpt (CUDA $CUDA) needs"

# --- 2. Packages and Julia ----------------------------------------------------
say "System packages"
NEED=()
for p in python3-venv python3-pip git curl ca-certificates rsync; do
  dpkg -s "$p" >/dev/null 2>&1 || NEED+=("$p")
done
if [ ${#NEED[@]} -gt 0 ]; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${NEED[@]}"
fi
echo "ok"

say "Julia"
export PATH="$HOME/.juliaup/bin:$PATH"
if ! command -v juliaup >/dev/null 2>&1; then
  curl -fsSL https://install.julialang.org | sh -s -- --yes
fi
juliaup add release >/dev/null 2>&1 || true
juliaup default release >/dev/null
julia --version
julia -e 'VERSION >= v"1.11" || error("scripts/cuopt needs Julia 1.11 or later")'

# --- 3. cuOpt library -----------------------------------------------------------
say "cuOpt $CUOPT_VERSION (CUDA $CUDA wheel)"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "libcuopt-mathopt-cu${CUDA}==${CUOPT_VERSION}"
LIBDIR=$("$VENV/bin/python" -I -c "import libcuopt_mathopt, os; print(os.path.join(os.path.dirname(libcuopt_mathopt.__file__), 'lib64'))")
[ -f "$LIBDIR/libcuopt_mathopt.so" ] || die "libcuopt_mathopt.so not found in $LIBDIR"
echo "$LIBDIR"

# --- 4. Environment file ----------------------------------------------------------
say "Environment ($ENVFILE)"
mkdir -p "$(dirname "$ENVFILE")"
cat > "$ENVFILE" <<EOF
# Written by scripts/cuopt/wsl2/setup_cuopt.sh; run it again to update.
# cuOpt 26.10 for cuOpt.jl (the wheel's RPATH finds the CUDA libraries it needs)
export TIMESJL_CUOPT_LIB="$LIBDIR"
case ":\${LD_LIBRARY_PATH:-}:" in
  *":$LIBDIR:"*) ;;
  *) export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" ;;
esac
export PATH="\$HOME/.juliaup/bin:\$PATH"
# Local run limits on James's workstation (CLAUDE.md): at most 12 threads per run
export TIMESJL_THREADS="\${TIMESJL_THREADS:-12}"
export OMP_NUM_THREADS="\${OMP_NUM_THREADS:-12}"
EOF
LINE="[ -f \"$ENVFILE\" ] && . \"$ENVFILE\"   # TIMES.jl cuOpt lane"
grep -qF "$ENVFILE" "$HOME/.bashrc" 2>/dev/null || echo "$LINE" >> "$HOME/.bashrc"
# shellcheck disable=SC1090
. "$ENVFILE"
echo "ok (new shells load it from ~/.bashrc)"

NIGHTLY_CONF="$HOME/.config/timesjl/cuopt-nightly.conf"
if [ ! -f "$NIGHTLY_CONF" ]; then
  cat > "$NIGHTLY_CONF" <<'CONF'
# What the local cuOpt nightly solves (scripts/cuopt/wsl2/nightly_local.sh).
# Edit freely; the next night picks it up. Results stay on this machine.
REF=main                      # branch the WSL checkout is moved to before each night
FIXTURES=demo12_off           # public CI fixtures: comma-separated, all, or empty for none
REF_MODELS=""                 # reference runs, e.g. "OTNYC-reference OTCGEN-reference" (TIM allowed: local only)
REF_WIN=/mnt/c/git/esma/timesjl-reference
REF_LINUX="$HOME/timesjl-reference"
ROOTS=""                      # "name=path ..." for reference runs whose run file was not kept
METHODS="barrier pdlp"
SHARES=100                    # WSL2 has no MPS, so only the full GPU here
KEEP_NIGHTS=30
CONF
  echo "wrote $NIGHTLY_CONF"
fi

# --- 5. TIMESjl checkout ------------------------------------------------------------
say "TIMESjl at $DIR ($REF)"
if [ -d "$DIR/.git" ]; then
  if [ -n "$(git -C "$DIR" status --porcelain)" ]; then
    echo "local changes in $DIR: left as it is (not fetched, not switched)"
  else
    git -C "$DIR" fetch -q origin "$REF"
    git -C "$DIR" checkout -q -B "$REF" FETCH_HEAD
  fi
else
  mkdir -p "$(dirname "$DIR")"
  git clone -q https://github.com/esma-ie/TIMESjl "$DIR"
  git -C "$DIR" fetch -q origin "$REF"
  git -C "$DIR" checkout -q -B "$REF" FETCH_HEAD
fi
git -C "$DIR" log -1 --format='%h %s'
[ -f "$DIR/scripts/cuopt/Project.toml" ] || die "$REF has no scripts/cuopt yet: pass --ref <the cuOpt branch>"

# --- 6. Julia environment and a GPU smoke test ------------------------------------------
say "scripts/cuopt environment"
cd "$DIR"
julia --project=scripts/cuopt -e 'using Pkg; Pkg.resolve(); Pkg.instantiate(); Pkg.precompile()'

say "Smoke test: a small LP on the GPU (barrier + crossover)"
julia --project=scripts/cuopt -e '
    import JuMP, cuOpt
    m = JuMP.Model(cuOpt.Optimizer)
    JuMP.set_attribute(m, cuOpt.CUOPT_METHOD, cuOpt.CUOPT_METHOD_BARRIER)
    JuMP.set_attribute(m, cuOpt.CUOPT_CROSSOVER, true)
    JuMP.set_silent(m)
    JuMP.@variable(m, x >= 0); JuMP.@variable(m, 0 <= y <= 3)
    JuMP.@objective(m, Min, 12x + 20y)
    JuMP.@constraint(m, 6x + 8y >= 100); JuMP.@constraint(m, 7x + 12y >= 120)
    JuMP.optimize!(m)
    obj = JuMP.objective_value(m)
    println("cuOpt ", JuMP.get_attribute(m, JuMP.MOI.SolverVersion()), ": ",
            JuMP.termination_status(m), ", objective ", obj, " (expected 205)")
    JuMP.termination_status(m) == JuMP.OPTIMAL && isapprox(obj, 205; rtol=1e-9) || exit(1)'

# --- 7. demo12 ----------------------------------------------------------------------------
mkdir -p "$OUTDIR"
if [ "$DEMO" = 1 ]; then
  say "cuOpt layer 3 on the demo12 CI fixture"
  scripts/cuopt/sweep.sh --out "$OUTDIR/setup-demo12" --shares 100 -- --only demo12_off --quiet || true
fi

cat <<EOF

Done. Results go to $OUTDIR. Next, from $DIR in a new shell:

  # every public CI fixture
  scripts/cuopt/sweep.sh --out $OUTDIR/fixtures -- --only all --quiet

  # the nightly, by hand (what the scheduled task runs; settings in $NIGHTLY_CONF)
  scripts/cuopt/wsl2/nightly_local.sh

  # a reference run from the workstation (copy it to the Linux side first: /mnt/c is slow)
  rsync -a /mnt/c/git/esma/timesjl-reference/<model>/ ~/timesjl-reference/<model>/
  julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl $OUTDIR/<model>.json --ref ~/timesjl-reference <model>

A cuOpt run uses at most $TIMESJL_THREADS CPU threads (cuOpt's CPU side; the GPU
is not limited) and counts as one of the four CPU-heavy runs allowed at once on
the workstation. The scheduled nightly takes a Windows run slot for it; runs
started by hand here do not, so keep count. TIM's results stay on this machine
(CLAUDE.md).
EOF
