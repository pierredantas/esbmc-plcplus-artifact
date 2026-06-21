#!/usr/bin/env bash
# =============================================================================
# run_all.sh — ESBMC-PLC+ Artifact Experiment Runner
#
# Reproduces the experimental results from:
#   "ESBMC-PLC+: A Unified Framework for Formal Verification of IEC 61131-3
#    PLC Programs via ESBMC" (ARXIV)
#
# Usage:
#   bash run_all.sh [--esbmc /path/to/esbmc] [--nuxmv /path/to/nuXmv]
#
# Prerequisites:
#   pip3 install pyyaml          (for RQ5 nuXmv comparison)
#   bash scripts/setup.sh        (downloads nuXmv automatically)
#
# All results are printed to stdout and saved to results/
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ESBMC_OVERRIDE=""
NUXMV_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --esbmc) ESBMC_OVERRIDE="$2"; shift 2 ;;
        --nuxmv) NUXMV_OVERRIDE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate ESBMC binary
# Precedence: --esbmc flag > ./esbmc (artifact bundle) >
#             build/src/esbmc/esbmc (repo build) > esbmc on PATH
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_esbmc() {
    if [[ -n "$ESBMC_OVERRIDE" ]]; then
        echo "$ESBMC_OVERRIDE"; return
    fi
    for candidate in \
        "$SCRIPT_DIR/esbmc" \
        "$SCRIPT_DIR/build/src/esbmc/esbmc" \
        "$(command -v esbmc 2>/dev/null || true)"
    do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"; return
        fi
    done
    echo ""
}

ESBMC="$(find_esbmc)"

# ---------------------------------------------------------------------------
# Locate NuXmv binary
# ---------------------------------------------------------------------------
find_nuxmv() {
    if [[ -n "$NUXMV_OVERRIDE" ]]; then
        echo "$NUXMV_OVERRIDE"; return
    fi
    for candidate in \
        "$SCRIPT_DIR/nuXmv" \
        "/tmp/nuXmv-2.2.0-macos64/usr/local/bin/nuXmv" \
        "/tmp/nuXmv-2.2.0-Linux/usr/local/bin/nuXmv" \
        "$(command -v nuXmv 2>/dev/null || true)"
    do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"; return
        fi
    done
    echo ""
}
NUXMV="$(find_nuxmv)"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BENCH="$SCRIPT_DIR/benchmarks"
ST_BENCH="$SCRIPT_DIR/st_benchmarks"
NUXMV_EXP="$SCRIPT_DIR/experiments/nuxmv_comparison"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAILURES=$((FAILURES+1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC}  $*"; }

FAILURES=0

# ---------------------------------------------------------------------------
# Helper: run ESBMC and return verdict (SAFE | VIOLATION | UNKNOWN)
# ---------------------------------------------------------------------------
esbmc_verdict() {
    local log="$1"
    if grep -q "VERIFICATION SUCCESSFUL" "$log" 2>/dev/null; then
        echo "SAFE"
    elif grep -q "VERIFICATION FAILED" "$log" 2>/dev/null; then
        echo "VIOLATION"
    else
        echo "UNKNOWN"
    fi
}

# ---------------------------------------------------------------------------
# Helper: time a command, capture output to a log file, return elapsed seconds
# Usage: elapsed=$(run_timed LOGFILE CMD [ARGS...])
# ---------------------------------------------------------------------------
run_timed() {
    local log="$1"; shift
    local start end
    start=$(python3 -c 'import time; print(time.time())')
    "$@" > "$log" 2>&1 || true
    end=$(python3 -c 'import time; print(time.time())')
    python3 -c "print(f'{$end - $start:.3f}')"
}

# ===========================================================================
echo ""
echo "============================================================"
echo "  ESBMC-PLC+ Artifact — Experiment Runner"
echo "  $(date)"
printf "  ESBMC:  %s\n" "${ESBMC:-NOT FOUND}"
echo "============================================================"
echo ""

if [[ -z "$ESBMC" ]]; then
    echo -e "${RED}ERROR: ESBMC binary not found.${NC}"
    echo "  Build ESBMC from source:  bash scripts/build.sh"
    echo "  Or specify the path:      bash run_all.sh --esbmc /path/to/esbmc"
    exit 1
fi

ESBMC_VERSION=$("$ESBMC" --version 2>&1 | head -1)
echo "  Version: $ESBMC_VERSION"
echo ""

COMMON_FLAGS="--z3 --no-div-by-zero-check --no-pointer-check --no-align-check"

# ===========================================================================
echo "── RQ1: ST Frontend — motor_sequencing (D1) ──────────────────────────"
# ---------------------------------------------------------------------------
# D1: motor_simple.c with P2 (absence violation), expected VIOLATION at k=2
# Bug fix: use --incremental-bmc (not --k-induction) when the expected
#          result is a VIOLATION; k-induction proves safety, not violations.
# ---------------------------------------------------------------------------
D1_FILE="$ST_BENCH/motor_simple.c"

if [[ ! -f "$D1_FILE" ]]; then
    fail "st_benchmarks/motor_simple.c not found"
else
    echo "  → ESBMC --incremental-bmc on motor_simple.c (P2: absence check) ..."
    D1_LOG="$RESULTS/d1_motor_simple_p2.log"
    D1_TIME=$(run_timed "$D1_LOG" \
        "$ESBMC" "$D1_FILE" --incremental-bmc $COMMON_FLAGS)
    D1_VERDICT=$(esbmc_verdict "$D1_LOG")
    printf "  Result:   %s\n" "$D1_VERDICT"
    printf "  Time:     %ss\n" "$D1_TIME"
    echo "  Expected: VIOLATION (P2 — Motor_B active while Motor_A inactive)"
    if [[ "$D1_VERDICT" == "VIOLATION" ]]; then
        pass "D1: ST frontend correctly finds P2 violation"
    else
        fail "D1: got $D1_VERDICT, expected VIOLATION"
    fi
fi
echo ""

# ===========================================================================
echo "── RQ2: Graphical LD Function Blocks — beremiz_traffic_light (C1) ───"
# ---------------------------------------------------------------------------
# C1: beremiz_traffic_light.ld with 3 safety properties, expected SAFE
# The LD file is graphical PLCopen XML; ESBMC auto-detects graphical format.
# --k-induction is correct here (proves unbounded safety).
# Bug fix: the professor's issue was that their ESBMC binary was upstream
#          ESBMC (without --ld-props support). The ESBMC-PLC+ fork is needed.
# ---------------------------------------------------------------------------
C1_LD="$BENCH/beremiz_traffic_light/beremiz_traffic_light.ld"
C1_PROPS="$BENCH/beremiz_traffic_light/props.yaml"

if [[ ! -f "$C1_LD" ]]; then
    fail "benchmarks/beremiz_traffic_light/beremiz_traffic_light.ld not found"
elif [[ ! -f "$C1_PROPS" ]]; then
    fail "benchmarks/beremiz_traffic_light/props.yaml not found"
else
    echo "  → ESBMC --k-induction on beremiz_traffic_light.ld (3 properties) ..."
    C1_LOG="$RESULTS/c1_beremiz_traffic_light.log"
    C1_TIME=$(run_timed "$C1_LOG" \
        "$ESBMC" "$C1_LD" --ld-props "$C1_PROPS" --k-induction $COMMON_FLAGS)
    C1_VERDICT=$(esbmc_verdict "$C1_LOG")
    printf "  Result:   %s\n" "$C1_VERDICT"
    printf "  Time:     %ss\n" "$C1_TIME"
    echo "  Expected: SAFE (3 properties, k-induction at k=2)"
    if [[ "$C1_VERDICT" == "SAFE" ]]; then
        pass "C1: graphical LD function block extension correctly verifies traffic light"
    else
        if grep -q "ld-props" "$C1_LOG" 2>/dev/null || \
           grep -q "unrecognised option" "$C1_LOG" 2>/dev/null; then
            fail "C1: got $C1_VERDICT — your ESBMC binary does not support --ld-props." \
                 "You need the ESBMC-PLC+ fork, not upstream ESBMC."
        else
            fail "C1: got $C1_VERDICT, expected SAFE"
        fi
    fi
fi
echo ""

# ===========================================================================
echo "── RQ4: Inherited Benchmarks (regression) ────────────────────────────"
# ---------------------------------------------------------------------------
# All ESBMC-PLC (A1-A13 textual LD) and ESBMC-GraphPLC (B1-B3 graphical LD)
# benchmarks must produce the same verdict as reported in the original papers.
# ---------------------------------------------------------------------------

declare -a LD_BENCHMARKS=(
    # Format: "label|ld_file|props_file|expected|mode"
    # mode: ki = k-induction (SAFE), bmc = incremental-bmc (VIOLATION)
    "tank_safe|$BENCH/tank_level_control/tank_level_control.ld|$BENCH/tank_level_control/props.yaml|SAFE|ki"
    "tank_unsafe|$BENCH/tank_level_control/tank_level_control_unsafe.ld|$BENCH/tank_level_control/props.yaml|VIOLATION|bmc"
    "bottle_safe|$BENCH/bottle_filling/bottle_filling_safe.ld|$BENCH/bottle_filling/props.yaml|SAFE|ki"
    "bottle_unsafe|$BENCH/bottle_filling/bottle_filling_unsafe.ld|$BENCH/bottle_filling/props.yaml|VIOLATION|bmc"
    "elevator_safe|$BENCH/elevator/elevator_safe.ld|$BENCH/elevator/props.yaml|SAFE|ki"
    "elevator_unsafe|$BENCH/elevator/elevator_unsafe.ld|$BENCH/elevator/props_unsafe.yaml|VIOLATION|bmc"
    "traffic_safe|$BENCH/traffic_light/traffic_light_safe.ld|$BENCH/traffic_light/props.yaml|SAFE|ki"
    "traffic_unsafe|$BENCH/traffic_light/traffic_light_unsafe.ld|$BENCH/traffic_light/props.yaml|VIOLATION|bmc"
    "beremiz_bacnet|$BENCH/beremiz_bacnet/beremiz_bacnet.ld|$BENCH/beremiz_bacnet/props.yaml|SAFE|ki"
    "stairs|$BENCH/stairs_light/stairs_light.ld|$BENCH/stairs_light/props.yaml|SAFE|ki"
    "dimmer|$BENCH/dimmer_light_control/dimmer_light_control.ld|$BENCH/dimmer_light_control/props.yaml|SAFE|ki"
)

RQ4_PASS=0; RQ4_FAIL=0
printf "  %-22s %-10s %-10s %s\n" "Benchmark" "Expected" "Got" "Result"
printf "  %-22s %-10s %-10s %s\n" "---------" "--------" "---" "------"

for entry in "${LD_BENCHMARKS[@]}"; do
    IFS='|' read -r label ld props expected mode <<< "$entry"

    if [[ ! -f "$ld" ]]; then
        printf "  %-22s %-10s %-10s %s\n" "$label" "$expected" "SKIP" "file not found"
        skip "$label (LD file missing)"
        continue
    fi

    log="$RESULTS/rq4_${label}.log"
    if [[ "$mode" == "ki" ]]; then
        run_timed "$log" "$ESBMC" "$ld" --ld-props "$props" \
            --k-induction $COMMON_FLAGS > /dev/null 2>&1 || true
    else
        run_timed "$log" "$ESBMC" "$ld" --ld-props "$props" \
            --incremental-bmc $COMMON_FLAGS > /dev/null 2>&1 || true
    fi
    verdict=$(esbmc_verdict "$log")

    if [[ "$verdict" == "$expected" ]]; then
        printf "  %-22s %-10s %-10s ${GREEN}PASS${NC}\n" "$label" "$expected" "$verdict"
        RQ4_PASS=$((RQ4_PASS+1))
    else
        printf "  %-22s %-10s %-10s ${RED}FAIL${NC}\n" "$label" "$expected" "$verdict"
        RQ4_FAIL=$((RQ4_FAIL+1))
        FAILURES=$((FAILURES+1))
    fi
done

echo ""
echo "  RQ4 summary: $RQ4_PASS passed, $RQ4_FAIL failed"
echo ""

# ===========================================================================
echo "── RQ5: NuXmv Comparison ─────────────────────────────────────────────"
# ---------------------------------------------------------------------------
# Bug fix: the original run_all.sh had a bash syntax error at line 205:
#     `|| true)"'
# caused by nesting a here-string (<<<) inside $(). This is resolved by
# delegating to the standalone run_experiments.sh which uses temp files.
# ---------------------------------------------------------------------------
if [[ -z "$NUXMV" ]]; then
    skip "RQ5: NuXmv not found. Run 'bash scripts/setup.sh' to download it."
    skip "RQ5: Or specify: bash run_all.sh --nuxmv /path/to/nuXmv"
elif [[ ! -f "$NUXMV_EXP/run_experiments.sh" ]]; then
    skip "RQ5: experiments/nuxmv_comparison/run_experiments.sh not found"
else
    echo "  → Running ESBMC-PLC+ vs NuXmv BDD/IC3 comparison ..."
    echo "    (8 benchmarks × 2 NuXmv modes, timeout 120s each; may take ~30 min)"
    RQ5_CSV="$NUXMV_EXP/results/results.csv"
    bash "$NUXMV_EXP/run_experiments.sh"
    rq5_rows=$(wc -l < "$RQ5_CSV" 2>/dev/null || echo 0)
    rq5_rows=$((rq5_rows - 1))   # subtract header row
    if [[ $rq5_rows -ge 8 ]]; then
        pass "RQ5: NuXmv comparison completed ($rq5_rows/8 benchmarks, LaTeX table: $NUXMV_EXP/results/results_table.tex)"
    else
        fail "RQ5: NuXmv comparison incomplete ($rq5_rows/8 benchmarks — check $NUXMV_EXP/results/)"
    fi
fi
echo ""

# ===========================================================================
echo "============================================================"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "  ${GREEN}ALL EXPERIMENTS PASSED${NC}"
    echo "  Results saved to: results/"
else
    echo -e "  ${RED}$FAILURES EXPERIMENT(S) FAILED${NC}"
    echo "  Logs: results/*.log"
    echo ""
    echo "  Common causes:"
    echo "   • RQ1/RQ2 UNKNOWN: your ESBMC binary is upstream ESBMC, not"
    echo "     ESBMC-PLC+. Build from this repo: bash scripts/build.sh"
    echo "   • RQ2 UNKNOWN: try 'bash run_all.sh --esbmc ./path/to/plcplus-esbmc'"
fi
echo "============================================================"
echo ""

exit $((FAILURES > 0 ? 1 : 0))
