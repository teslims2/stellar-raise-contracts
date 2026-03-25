#!/usr/bin/env bash
# @title   deployment_shell_script.test.sh
# @notice  Unit tests for deployment_shell_script.sh using a lightweight
#          bash test harness (no external dependencies required).
# @dev     Run: bash scripts/deployment_shell_script.test.sh
#          Exit 0 = all tests passed.

set -euo pipefail

SCRIPT="$(dirname "$0")/deployment_shell_script.sh"
PASS=0
FAIL=0

# ── Harness ──────────────────────────────────────────────────────────────────

assert_exit() {
  local desc="$1" expected="$2"; shift 2
  local actual=0
  "$@" &>/dev/null || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS  $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL  $desc  (expected exit $expected, got $actual)"
    (( FAIL++ )) || true
  fi
}

assert_output_contains() {
  local desc="$1" pattern="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if echo "$out" | grep -q "$pattern"; then
    echo "  PASS  $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL  $desc  (pattern '$pattern' not found in output)"
    (( FAIL++ )) || true
  fi
}

# ── Source helpers only (skip main) ──────────────────────────────────────────
# We source the script with main() stubbed out so we can test individual functions.

# shellcheck source=/dev/null
SOURCING=1
eval "$(sed 's/^main "\$@"$/: # main stubbed/' "$SCRIPT")"

# ── Tests: constants ──────────────────────────────────────────────────────────

echo ""
echo "=== constants ==="

assert_exit "EXIT_OK is 0" 0 \
  bash -c "$(declare -p EXIT_OK); [[ \$EXIT_OK -eq 0 ]]"

assert_exit "EXIT_MISSING_DEP is 1" 0 \
  bash -c "$(declare -p EXIT_MISSING_DEP); [[ \$EXIT_MISSING_DEP -eq 1 ]]"

assert_exit "EXIT_BAD_ARG is 2" 0 \
  bash -c "$(declare -p EXIT_BAD_ARG); [[ \$EXIT_BAD_ARG -eq 2 ]]"

assert_exit "EXIT_BUILD_FAIL is 3" 0 \
  bash -c "$(declare -p EXIT_BUILD_FAIL); [[ \$EXIT_BUILD_FAIL -eq 3 ]]"

assert_exit "EXIT_DEPLOY_FAIL is 4" 0 \
  bash -c "$(declare -p EXIT_DEPLOY_FAIL); [[ \$EXIT_DEPLOY_FAIL -eq 4 ]]"

assert_exit "EXIT_INIT_FAIL is 5" 0 \
  bash -c "$(declare -p EXIT_INIT_FAIL); [[ \$EXIT_INIT_FAIL -eq 5 ]]"

assert_exit "EXIT_NETWORK_FAIL is 6" 0 \
  bash -c "$(declare -p EXIT_NETWORK_FAIL); [[ \$EXIT_NETWORK_FAIL -eq 6 ]]"

assert_exit "DEFAULT_NETWORK is testnet" 0 \
  bash -c "$(declare -p DEFAULT_NETWORK); [[ \$DEFAULT_NETWORK == 'testnet' ]]"

assert_exit "DEFAULT_DEPLOY_LOG is deploy_errors.log" 0 \
  bash -c "$(declare -p DEFAULT_DEPLOY_LOG); [[ \$DEFAULT_DEPLOY_LOG == 'deploy_errors.log' ]]"

assert_exit "DEFAULT_MIN_CONTRIBUTION is 1" 0 \
  bash -c "$(declare -p DEFAULT_MIN_CONTRIBUTION); [[ \$DEFAULT_MIN_CONTRIBUTION -eq 1 ]]"

assert_exit "WASM_TARGET is wasm32-unknown-unknown" 0 \
  bash -c "$(declare -p WASM_TARGET); [[ \$WASM_TARGET == 'wasm32-unknown-unknown' ]]"

assert_exit "WASM_PATH contains WASM_TARGET" 0 \
  bash -c "$(declare -p WASM_TARGET WASM_PATH); [[ \$WASM_PATH == *\$WASM_TARGET* ]]"

assert_exit "RPC_TESTNET is non-empty" 0 \
  bash -c "$(declare -p RPC_TESTNET); [[ -n \$RPC_TESTNET ]]"

assert_exit "RPC_MAINNET is non-empty" 0 \
  bash -c "$(declare -p RPC_MAINNET); [[ -n \$RPC_MAINNET ]]"

assert_exit "RPC_FUTURENET is non-empty" 0 \
  bash -c "$(declare -p RPC_FUTURENET); [[ -n \$RPC_FUTURENET ]]"

assert_exit "NETWORK_TIMEOUT is positive integer" 0 \
  bash -c "$(declare -p NETWORK_TIMEOUT); [[ \$NETWORK_TIMEOUT =~ ^[0-9]+$ && \$NETWORK_TIMEOUT -gt 0 ]]"

# ── Tests: require_tool ───────────────────────────────────────────────────────

echo ""
echo "=== require_tool ==="

assert_exit "passes for 'bash' (always present)" 0 \
  bash -c "$(declare -f require_tool die log); $(declare -p EXIT_MISSING_DEP); DEPLOY_LOG=/dev/null; require_tool bash"

assert_exit "exits EXIT_MISSING_DEP for missing tool" 1 \
  bash -c "$(declare -f require_tool die log); $(declare -p EXIT_MISSING_DEP); DEPLOY_LOG=/dev/null; require_tool __no_such_tool_xyz__"

# ── Tests: validate_args ──────────────────────────────────────────────────────

echo ""
echo "=== validate_args ==="

FUTURE=$(( $(date +%s) + 86400 ))

assert_exit "passes with valid args" 0 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN 1000 $FUTURE 10"

assert_exit "exits EXIT_BAD_ARG when creator is empty" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args '' GTOKEN 1000 $FUTURE 10"

assert_exit "exits EXIT_BAD_ARG when token is empty" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR '' 1000 $FUTURE 10"

assert_exit "exits EXIT_BAD_ARG when goal is non-numeric" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN abc $FUTURE 10"

assert_exit "exits EXIT_BAD_ARG when goal is negative string" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN -5 $FUTURE 10"

assert_exit "exits EXIT_BAD_ARG when deadline is non-numeric" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN 1000 'not-a-ts' 10"

assert_exit "exits EXIT_BAD_ARG when deadline is in the past" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN 1000 1 10"

assert_exit "exits EXIT_BAD_ARG when min_contribution is non-numeric" 2 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN 1000 $FUTURE abc"

assert_exit "accepts DEFAULT_MIN_CONTRIBUTION value" 0 \
  bash -c "$(declare -f validate_args die log); $(declare -p EXIT_BAD_ARG DEFAULT_MIN_CONTRIBUTION); DEPLOY_LOG=/dev/null
           validate_args GCREATOR GTOKEN 1000 $FUTURE \$DEFAULT_MIN_CONTRIBUTION"

# ── Tests: build_contract (cargo stubbed) ────────────────────────────────────

echo ""
echo "=== build_contract ==="

assert_exit "exits EXIT_BUILD_FAIL when cargo build fails" 3 \
  bash -c "$(declare -f build_contract die log run_captured); $(declare -p EXIT_BUILD_FAIL WASM_TARGET)
           DEPLOY_LOG=/dev/null; WASM_PATH=/nonexistent.wasm
           cargo() { return 1; }
           build_contract"

assert_exit "exits EXIT_BUILD_FAIL when WASM missing after successful build" 3 \
  bash -c "$(declare -f build_contract die log run_captured); $(declare -p EXIT_BUILD_FAIL WASM_TARGET)
           DEPLOY_LOG=/dev/null; WASM_PATH=/nonexistent.wasm
           cargo() { return 0; }
           build_contract"

assert_exit "passes when cargo succeeds and WASM exists" 0 \
  bash -c "$(declare -f build_contract die log run_captured); $(declare -p EXIT_BUILD_FAIL WASM_TARGET)
           TMP=\$(mktemp); DEPLOY_LOG=/dev/null; WASM_PATH=\"\$TMP\"
           cargo() { return 0; }
           build_contract
           rm -f \"\$TMP\""

# ── Tests: deploy_contract (stellar stubbed) ─────────────────────────────────

echo ""
echo "=== deploy_contract ==="

assert_exit "exits EXIT_DEPLOY_FAIL when stellar deploy fails" 4 \
  bash -c "$(declare -f deploy_contract die log); $(declare -p EXIT_DEPLOY_FAIL)
           DEPLOY_LOG=/dev/null; WASM_PATH=/dev/null; NETWORK=testnet
           stellar() { return 1; }
           deploy_contract GCREATOR"

assert_exit "exits EXIT_DEPLOY_FAIL when stellar returns empty contract ID" 4 \
  bash -c "$(declare -f deploy_contract die log); $(declare -p EXIT_DEPLOY_FAIL)
           DEPLOY_LOG=/dev/null; WASM_PATH=/dev/null; NETWORK=testnet
           stellar() { echo ''; }
           deploy_contract GCREATOR"

assert_output_contains "returns contract ID on success" "CTEST123" \
  bash -c "$(declare -f deploy_contract die log); $(declare -p EXIT_DEPLOY_FAIL)
           DEPLOY_LOG=/dev/null; WASM_PATH=/dev/null; NETWORK=testnet
           stellar() { echo 'CTEST123'; }
           deploy_contract GCREATOR"

# ── Tests: init_contract (stellar stubbed) ───────────────────────────────────

echo ""
echo "=== init_contract ==="

assert_exit "exits EXIT_INIT_FAIL when stellar invoke fails" 5 \
  bash -c "$(declare -f init_contract die log); $(declare -p EXIT_INIT_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=testnet
           stellar() { return 1; }
           init_contract CTEST GCREATOR GTOKEN 1000 $FUTURE 10"

assert_exit "passes when stellar invoke succeeds" 0 \
  bash -c "$(declare -f init_contract die log); $(declare -p EXIT_INIT_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=testnet
           stellar() { return 0; }
           init_contract CTEST GCREATOR GTOKEN 1000 $FUTURE 10"

# ── Tests: check_network (curl stubbed) ──────────────────────────────────────

echo ""
echo "=== check_network ==="

assert_exit "passes when curl succeeds for testnet" 0 \
  bash -c "$(declare -f check_network warn die log); $(declare -p RPC_TESTNET RPC_MAINNET RPC_FUTURENET NETWORK_TIMEOUT EXIT_NETWORK_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=testnet
           curl() { return 0; }
           check_network"

assert_exit "passes when curl succeeds for mainnet" 0 \
  bash -c "$(declare -f check_network warn die log); $(declare -p RPC_TESTNET RPC_MAINNET RPC_FUTURENET NETWORK_TIMEOUT EXIT_NETWORK_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=mainnet
           curl() { return 0; }
           check_network"

assert_exit "passes when curl succeeds for futurenet" 0 \
  bash -c "$(declare -f check_network warn die log); $(declare -p RPC_TESTNET RPC_MAINNET RPC_FUTURENET NETWORK_TIMEOUT EXIT_NETWORK_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=futurenet
           curl() { return 0; }
           check_network"

assert_exit "exits EXIT_NETWORK_FAIL when curl fails" 6 \
  bash -c "$(declare -f check_network warn die log); $(declare -p RPC_TESTNET RPC_MAINNET RPC_FUTURENET NETWORK_TIMEOUT EXIT_NETWORK_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=testnet
           curl() { return 1; }
           check_network"

assert_exit "warns and passes for unknown network" 0 \
  bash -c "$(declare -f check_network warn die log); $(declare -p RPC_TESTNET RPC_MAINNET RPC_FUTURENET NETWORK_TIMEOUT EXIT_NETWORK_FAIL)
           DEPLOY_LOG=/dev/null; NETWORK=localnet; ERROR_COUNT=0
           check_network"

# ── Tests: log output ────────────────────────────────────────────────────────

echo ""
echo "=== log / die ==="

assert_output_contains "log writes level tag" "\[INFO\]" \
  bash -c "$(declare -f log); DEPLOY_LOG=/dev/null; log INFO 'hello'"

assert_output_contains "log writes message" "hello world" \
  bash -c "$(declare -f log); DEPLOY_LOG=/dev/null; log INFO 'hello world'"

assert_exit "die exits with supplied code" 3 \
  bash -c "$(declare -f log die); DEPLOY_LOG=/dev/null; die 3 'boom'"

assert_output_contains "die logs ERROR level" "\[ERROR\]" \
  bash -c "$(declare -f log die); DEPLOY_LOG=/dev/null; die 3 'boom'" || true

# ── Tests: DEPLOY_LOG file capture ───────────────────────────────────────────

echo ""
echo "=== DEPLOY_LOG file capture ==="

assert_exit "log appends to DEPLOY_LOG file" 0 \
  bash -c "$(declare -f log)
           TMP=\$(mktemp); DEPLOY_LOG=\"\$TMP\"
           log INFO 'test entry'
           grep -q 'test entry' \"\$TMP\"
           rm -f \"\$TMP\""

_test_main_truncates_log() {
  local TMP_LOG TMP_SCRIPT FUTURE
  TMP_LOG=$(mktemp)
  TMP_SCRIPT=$(mktemp --suffix=.sh)
  FUTURE=$(( $(date +%s) + 86400 ))
  echo 'stale content' > "$TMP_LOG"

  local TMP_WASM
  TMP_WASM=$(mktemp --suffix=.wasm)
  {
    echo "cargo()   { touch \"$TMP_WASM\"; return 0; }"
    echo 'stellar() { case "$2" in deploy) echo CXXX;; *) ;; esac; return 0; }'
    echo 'curl()    { return 0; }'
    # Patch readonly WASM_PATH to point at our temp file before the script declares it
    sed "s|^readonly WASM_PATH=.*|readonly WASM_PATH=\"$TMP_WASM\"|" "$SCRIPT" \
      | sed 's/^main "\$@"$/: # stubbed/'
    echo "main GCREATOR GTOKEN 1000 $FUTURE 1"
  } > "$TMP_SCRIPT"

  DEPLOY_LOG="$TMP_LOG" NETWORK=testnet bash "$TMP_SCRIPT" &>/dev/null
  local rc=$?
  rm -f "$TMP_SCRIPT" "$TMP_WASM"

  if [[ $rc -eq 0 ]] && ! grep -q 'stale content' "$TMP_LOG"; then
    rm -f "$TMP_LOG"
    return 0
  fi
  rm -f "$TMP_LOG"
  return 1
}
assert_exit "main truncates DEPLOY_LOG at start" 0 _test_main_truncates_log

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
