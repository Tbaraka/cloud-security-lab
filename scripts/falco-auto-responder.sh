#!/usr/bin/env bash
# Watches Falco logs and auto-triggers disaster-recovery.sh on CRITICAL alerts
# (currently: "Lab Container Breakout Attempt").
# bash 3.2 compatible (no associative arrays) — macOS default bash.
# Usage:
#   ./scripts/falco-auto-responder.sh            # dry-run (default) — logs only
#   ./scripts/falco-auto-responder.sh --live      # actually runs disaster-recovery.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="dry-run"
if [[ "${1:-}" == "--live" ]]; then
  MODE="live"
fi

COOLDOWN_SECONDS=120
COOLDOWN_STATE=""   # space-separated "studentid:epoch" pairs

get_last_trigger() {
  local sid="$1"
  echo "$COOLDOWN_STATE" | tr ' ' '\n' | grep "^${sid}:" | cut -d: -f2 | tail -1
}

set_last_trigger() {
  local sid="$1" ts="$2"
  COOLDOWN_STATE="$(echo "$COOLDOWN_STATE" | tr ' ' '\n' | grep -v "^${sid}:" | tr '\n' ' ') ${sid}:${ts}"
}

echo "==> Falco auto-responder starting in ${MODE} mode"
echo "==> Watching for priority=Critical alerts (cooldown: ${COOLDOWN_SECONDS}s per student)"
[[ "$MODE" == "dry-run" ]] && echo "==> DRY-RUN: no destructive action will be taken. Re-run with --live to enable."

kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco -f --since=1s 2>/dev/null | \
while IFS= read -r line; do
  PRIORITY=$(echo "$line" | jq -r '.priority // empty' 2>/dev/null)
  [[ "$PRIORITY" != "Critical" ]] && continue

  RULE=$(echo "$line" | jq -r '.rule // "unknown"' 2>/dev/null)
  NS=$(echo "$line" | jq -r '.output_fields."k8s.ns.name" // empty' 2>/dev/null)

  if [[ -z "$NS" || "$NS" == "null" ]]; then
    echo "$(date '+%H:%M:%S') CRITICAL alert (rule=$RULE) but no k8s.ns.name — cannot auto-target, skipping"
    continue
  fi

  STUDENT_NS="${NS%-target}"
  STUDENT_ID="${STUDENT_NS#student-}"

  if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
    echo "$(date '+%H:%M:%S') CRITICAL alert in ns=$NS but could not derive student id, skipping"
    continue
  fi

  NOW=$(date +%s)
  LAST=$(get_last_trigger "$STUDENT_ID")
  LAST=${LAST:-0}
  if (( NOW - LAST < COOLDOWN_SECONDS )); then
    echo "$(date '+%H:%M:%S') CRITICAL alert for student-${STUDENT_ID} (rule=$RULE) — within cooldown, skipping"
    continue
  fi
  set_last_trigger "$STUDENT_ID" "$NOW"

  echo "$(date '+%H:%M:%S') CRITICAL alert: rule=$RULE ns=$NS -> student-${STUDENT_ID}"

  if [[ "$MODE" == "dry-run" ]]; then
    echo "$(date '+%H:%M:%S') [DRY-RUN] Would run: bash $ROOT/scripts/disaster-recovery.sh student-${STUDENT_ID}"
  else
    echo "$(date '+%H:%M:%S') [LIVE] Running: bash $ROOT/scripts/disaster-recovery.sh student-${STUDENT_ID}"
    bash "$ROOT/scripts/disaster-recovery.sh" "student-${STUDENT_ID}" \
      >> "$ROOT/logs/auto-dr-student-${STUDENT_ID}-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
    echo "$(date '+%H:%M:%S') DR triggered in background for student-${STUDENT_ID}, PID $!"
  fi
done
