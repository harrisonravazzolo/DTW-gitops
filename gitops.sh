#!/usr/bin/env bash
# -x: Print all executed commands to the terminal.
# -u: Exit if an undefined variable is used.
# -o pipefail: Exit if any command in a pipeline fails.
set -xuo pipefail

# Error tracking
ERRORS=()

FLEET_GITOPS_DIR="${FLEET_GITOPS_DIR:-.}"
FLEET_GLOBAL_FILE="${FLEET_GLOBAL_FILE:-$FLEET_GITOPS_DIR/default.yml}"
FLEETCTL="${FLEETCTL:-fleetctl}"
FLEET_DRY_RUN_ONLY="${FLEET_DRY_RUN_ONLY:-false}"
FLEET_DELETE_OTHER_TEAMS="${FLEET_DELETE_OTHER_TEAMS:-true}"

# Helper function to run commands and collect errors
run_command() {
  local cmd_desc="$1"
  shift
  if ! "$@"; then
    ERRORS+=("ERROR: $cmd_desc (exit code: $?)")
  fi
}

if [ -f "$FLEET_GLOBAL_FILE" ]; then
	run_command "Validating org_settings in global file" grep -Exq "^org_settings:.*" "$FLEET_GLOBAL_FILE"
else
	FLEET_DELETE_OTHER_TEAMS=false
fi

if compgen -G "$FLEET_GITOPS_DIR"/teams/*.yml > /dev/null; then
  run_command "Validating unique team names" bash -c '! perl -nle "print \$1 if /^name:\s*(.+)\$/" "$FLEET_GITOPS_DIR"/teams/*.yml | sort | uniq -d | grep . -cq'
fi

args=()
if [ -f "$FLEET_GLOBAL_FILE" ]; then
	args=(-f "$FLEET_GLOBAL_FILE")
fi

for team_file in "$FLEET_GITOPS_DIR"/teams/*.yml; do
  if [ -f "$team_file" ]; then
    args+=(-f "$team_file")
  fi
done

if [ "$FLEET_DELETE_OTHER_TEAMS" = true ]; then
  args+=(--delete-other-teams)
fi

# Dry run
run_command "FleetCtl GitOps dry-run" $FLEETCTL gitops "${args[@]}" --dry-run

if [ "$FLEET_DRY_RUN_ONLY" = true ]; then
  # Still print errors before exiting
  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "=== ERRORS ENCOUNTERED ===" >&2
    printf '%s\n' "${ERRORS[@]}" >&2
    exit 1
  fi
  exit 0
fi

# Real run
run_command "FleetCtl GitOps apply" $FLEETCTL gitops "${args[@]}"

# Print all errors at the end
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "=== ERRORS ENCOUNTERED ===" >&2
  printf '%s\n' "${ERRORS[@]}" >&2
  exit 1
else
  echo ""
  echo "=== SUCCESS: No errors encountered ===" 
  exit 0
fi
