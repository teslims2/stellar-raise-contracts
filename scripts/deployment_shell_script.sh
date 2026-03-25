#!/usr/bin/env bash
# @title   deployment_shell_script.sh
# @notice  Builds, deploys, and initialises the Stellar Raise crowdfund contract
#          on a target network with structured error capturing and logging.
# @dev     Requires: stellar CLI (>=0.0.18), Rust + wasm32-unknown-unknown target.
#          All errors are captured to DEPLOY_LOG (default: deploy_errors.log).
#          Exit codes:
#            0  – success
#            1  – missing dependency
#            2  – invalid / missing argument
#            3  – build failure
#            4  – deploy failure
#            5  – initialise failure
#            6  – network connectivity failure

set -euo pipefail

# ── Exit code constants ───────────────────────────────────────────────────────

# @notice Named exit codes for each failure category.
#         Using constants prevents silent mismatches between the script body,
#         tests, and CI step-failure checks.
readonly EXIT_OK=0
readonly EXIT_MISSING_DEP=1
readonly EXIT_BAD_ARG=2
readonly EXIT_BUILD_FAIL=3
readonly EXIT_DEPLOY_FAIL=4
readonly EXIT_INIT_FAIL=5
readonly EXIT_NETWORK_FAIL=6

# ── Build constants ───────────────────────────────────────────────────────────

# @notice Rust compilation target and output artifact path.
readonly WASM_TARGET="wasm32-unknown-unknown"
readonly WASM_PATH="target/${WASM_TARGET}/release/crowdfund.wasm"

# ── Network RPC endpoints ─────────────────────────────────────────────────────

# @notice Health-check URLs for each supported Stellar network.
#         Used by check_network() to verify connectivity before deploying.
readonly RPC_TESTNET="https://soroban-testnet.stellar.org/health"
readonly RPC_MAINNET="https://soroban.stellar.org/health"
readonly RPC_FUTURENET="https://rpc-futurenet.stellar.org/health"

# @notice Maximum seconds to wait for the RPC health-check response.
readonly NETWORK_TIMEOUT=10

# ── Defaults ──────────────────────────────────────────────────────────────────

# @notice Default values for environment-overridable settings.
readonly DEFAULT_NETWORK="testnet"
readonly DEFAULT_DEPLOY_LOG="deploy_errors.log"
readonly DEFAULT_MIN_CONTRIBUTION=1

# ── Runtime configuration (env-overridable) ───────────────────────────────────

NETWORK="${NETWORK:-$DEFAULT_NETWORK}"
DEPLOY_LOG="${DEPLOY_LOG:-$DEFAULT_DEPLOY_LOG}"
DRY_RUN="${DRY_RUN:-false}"
ERROR_COUNT=0

# ── Helpers ──────────────────────────────────────────────────────────────────

# @notice Writes a timestamped message to stdout and the error log.
# @param  $1  severity  (INFO | WARN | ERROR)
# @param  $2  message
log() {
  local level="$1" msg="$2"
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "[$ts] [$level] $msg" | tee -a "$DEPLOY_LOG"
}

# @notice Logs an error with optional context (failed command / captured stderr)
#         and exits with the supplied code. Increments ERROR_COUNT before exit.
# @param  $1  exit_code
# @param  $2  message
# @param  $3  context  (optional – extra detail such as the failed command)
die() {
  local code="$1" msg="$2" context="${3:-}"
  (( ERROR_COUNT++ )) || true
  log "ERROR" "$msg"
  if [[ -n "$context" ]]; then
    log "ERROR" "  context: $context"
  fi
  log "ERROR" "  exit_code=$code  errors_total=$ERROR_COUNT"
  exit "$code"
}

# @notice Records a non-fatal warning and increments the error counter.
# @param  $1  message
warn() {
  (( ERROR_COUNT++ )) || true
  log "WARN" "$1"
}

# @notice Verifies that a required CLI tool is present on PATH.
# @param  $1  tool name
require_tool() {
  command -v "$1" &>/dev/null || die $EXIT_MISSING_DEP "Required tool not found: $1" "Ensure '$1' is installed and on your PATH"
}

# @notice Runs a command, capturing its stderr to the deploy log and measuring
#         elapsed time. Returns the command's exit code.
# @param  $@  command and arguments
run_captured() {
  local start_time end_time elapsed rc=0
  start_time=$(date +%s)
  "$@" 2>>"$DEPLOY_LOG" || rc=$?
  end_time=$(date +%s)
  elapsed=$(( end_time - start_time ))
  log "INFO" "  step_duration=${elapsed}s  command='$1'"
  return $rc
}

# @notice Prints a usage summary and exits 0.
print_help() {
  cat <<HELPEOF
Usage: deployment_shell_script.sh [OPTIONS] <creator> <token> <goal> <deadline> [min_contribution]

Builds, deploys, and initialises the Stellar Raise crowdfund contract.

Positional arguments:
  creator            Stellar address of the campaign creator
  token              Stellar address of the token contract
  goal               Funding goal in stroops (positive integer)
  deadline           Unix timestamp for campaign end (must be in the future)
  min_contribution   Minimum pledge amount (default: $DEFAULT_MIN_CONTRIBUTION)

Options:
  --help             Show this help message and exit
  --dry-run          Validate arguments and dependencies without deploying

Environment variables:
  NETWORK            Stellar network to target (default: $DEFAULT_NETWORK)
  DEPLOY_LOG         Path for the error/info log (default: $DEFAULT_DEPLOY_LOG)
  DRY_RUN            Set to 'true' to enable dry-run mode

Exit codes:
  $EXIT_OK  success             $EXIT_BUILD_FAIL  build failure        $EXIT_NETWORK_FAIL  network failure
  $EXIT_MISSING_DEP  missing dependency  $EXIT_DEPLOY_FAIL  deploy failure
  $EXIT_BAD_ARG  invalid argument    $EXIT_INIT_FAIL  init failure
HELPEOF
  exit $EXIT_OK
}

# ── Argument validation ───────────────────────────────────────────────────────

# @notice Validates all required positional arguments.
# @param  $1  creator   – Stellar address of the campaign creator
# @param  $2  token     – Stellar address of the token contract
# @param  $3  goal      – Funding goal (integer, stroops)
# @param  $4  deadline  – Unix timestamp for campaign end
# @param  $5  min_contribution – Minimum pledge amount
validate_args() {
  local creator="$1" token="$2" goal="$3" deadline="$4" min_contribution="$5"

  [[ -n "$creator" ]]                       || die $EXIT_BAD_ARG "creator is required"
  [[ -n "$token" ]]                         || die $EXIT_BAD_ARG "token is required"
  [[ "$goal" =~ ^[0-9]+$ ]]                 || die $EXIT_BAD_ARG "goal must be a positive integer, got: '$goal'"
  [[ "$deadline" =~ ^[0-9]+$ ]]             || die $EXIT_BAD_ARG "deadline must be a Unix timestamp, got: '$deadline'"
  [[ "$min_contribution" =~ ^[0-9]+$ ]]     || die $EXIT_BAD_ARG "min_contribution must be a positive integer"

  local now; now="$(date +%s)"
  (( deadline > now )) || die $EXIT_BAD_ARG "deadline must be in the future (got $deadline, now $now)"
}

# ── Network pre-check ────────────────────────────────────────────────────────

# @notice Performs a lightweight connectivity check against the target Stellar
#         network RPC endpoint. Skipped in dry-run mode and for unknown networks.
# @dev    Uses NETWORK_TIMEOUT constant to cap the curl wait time.
check_network() {
  local rpc_url
  case "$NETWORK" in
    testnet)   rpc_url="$RPC_TESTNET"   ;;
    mainnet)   rpc_url="$RPC_MAINNET"   ;;
    futurenet) rpc_url="$RPC_FUTURENET" ;;
    *)
      warn "Unknown network '$NETWORK' — skipping connectivity pre-check"
      return 0
      ;;
  esac
  log "INFO" "Checking network connectivity ($NETWORK)..."
  if ! curl --silent --fail --max-time "$NETWORK_TIMEOUT" "$rpc_url" &>/dev/null 2>>"$DEPLOY_LOG"; then
    die $EXIT_NETWORK_FAIL "Network connectivity check failed for $NETWORK" "GET $rpc_url timed out or returned non-200"
  fi
  log "INFO" "Network reachable."
}

# ── Core steps ───────────────────────────────────────────────────────────────

# @notice Compiles the contract to WASM using the WASM_TARGET constant.
build_contract() {
  log "INFO" "Building WASM..."
  if ! run_captured cargo build --target "$WASM_TARGET" --release; then
    die $EXIT_BUILD_FAIL "cargo build failed – see $DEPLOY_LOG for details" "cargo build --target $WASM_TARGET --release"
  fi
  [[ -f "$WASM_PATH" ]] || die $EXIT_BUILD_FAIL "WASM artifact not found at $WASM_PATH after build"
  log "INFO" "Build succeeded: $WASM_PATH"
}

# @notice Deploys the WASM to the network and returns the contract ID via stdout.
# @param  $1  source – signing identity / secret key
deploy_contract() {
  local source="$1"
  log "INFO" "Deploying to $NETWORK..."
  local contract_id
  if ! contract_id=$(stellar contract deploy \
      --wasm "$WASM_PATH" \
      --network "$NETWORK" \
      --source "$source" 2>>"$DEPLOY_LOG"); then
    die $EXIT_DEPLOY_FAIL "stellar contract deploy failed – see $DEPLOY_LOG for details" "stellar contract deploy --network $NETWORK"
  fi
  [[ -n "$contract_id" ]] || die $EXIT_DEPLOY_FAIL "Deploy returned an empty contract ID"
  log "INFO" "Contract deployed: $contract_id"
  echo "$contract_id"
}

# @notice Calls initialize on the deployed contract.
# @param  $1  contract_id
# @param  $2  creator
# @param  $3  token
# @param  $4  goal
# @param  $5  deadline
# @param  $6  min_contribution
init_contract() {
  local contract_id="$1" creator="$2" token="$3" goal="$4" deadline="$5" min_contribution="$6"
  log "INFO" "Initialising campaign on contract $contract_id..."
  if ! stellar contract invoke \
      --id "$contract_id" \
      --network "$NETWORK" \
      --source "$creator" \
      -- initialize \
      --creator "$creator" \
      --token "$token" \
      --goal "$goal" \
      --deadline "$deadline" \
      --min_contribution "$min_contribution" 2>>"$DEPLOY_LOG"; then
    die $EXIT_INIT_FAIL "Contract initialisation failed – see $DEPLOY_LOG for details" "stellar contract invoke --id $contract_id -- initialize"
  fi
  log "INFO" "Campaign initialised successfully."
}

# @notice Prints a final summary of errors/warnings captured during the run.
print_summary() {
  echo ""
  if [[ "$ERROR_COUNT" -gt 0 ]]; then
    log "WARN" "Completed with $ERROR_COUNT warning(s). Review $DEPLOY_LOG for details."
  else
    log "INFO" "Deployment completed successfully with 0 errors."
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────

main() {
  # Handle --help and --dry-run flags before positional args
  local positional=()
  for arg in "$@"; do
    case "$arg" in
      --help)    print_help ;;
      --dry-run) DRY_RUN="true" ;;
      *)         positional+=("$arg") ;;
    esac
  done

  local creator="${positional[0]:-}"
  local token="${positional[1]:-}"
  local goal="${positional[2]:-}"
  local deadline="${positional[3]:-}"
  local min_contribution="${positional[4]:-$DEFAULT_MIN_CONTRIBUTION}"

  # Truncate log for this run
  : > "$DEPLOY_LOG"

  require_tool cargo
  require_tool stellar

  validate_args "$creator" "$token" "$goal" "$deadline" "$min_contribution"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "Dry-run mode: arguments and dependencies validated. Skipping build/deploy/init."
    print_summary
    return 0
  fi

  check_network

  build_contract
  local contract_id
  contract_id="$(deploy_contract "$creator")"
  init_contract "$contract_id" "$creator" "$token" "$goal" "$deadline" "$min_contribution"

  print_summary

  echo ""
  echo "Contract ID: $contract_id"
  echo "Save this Contract ID for interacting with the campaign."
}

main "$@"
