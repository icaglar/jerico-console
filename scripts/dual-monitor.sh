#!/usr/bin/env bash
# dual-monitor.sh — robust dual-pane marker watcher for orchestra dev tool
#
# Usage:
#   bash ~/.config/orchestra/scripts/dual-monitor.sh <project_alias>
#
# Designed for use with `Monitor` tool in Claude Code, but works standalone too.
# Each detected event is printed as a single line to stdout.
#
# Detected events (one per line):
#   marker: TASK_NNN_DONE | REVIEW_APPROVED_NNN | REVIEW_FEEDBACK_NNN | REVIEW_DEFEND_NNN | QA_PASSED_NNN | QA_FAILED_NNN
#   kimi approval pending
#   claude approval pending
#   ⚠ KIMI AUTH FAILURE — restart needed
#   ⚠ claude pane unreachable / kimi pane unreachable
#   ⚠ claude idle 20+ min
#   heartbeat (every 5 min, alive signal)
#
# Lessons learned (DO NOT remove):
#   1. Markers MUST be line-anchored (alone on a line) — prompts contain marker
#      strings in step-lists which cause false positives if matched anywhere.
#   2. TUI rendering drops some characters in long marker IDs (_122 → _1).
#      Keep marker numeric IDs short OR add prefix words for redundancy.
#   3. dedup via SEEN file (not in-memory) — survives partial monitor restarts
#   4. set +e — never exit on grep miss / command failure
#   5. Per-minute dedup for transient states (approval, auth, idle) using
#      ts_min suffix — same dialog won't spam every 20s.
#   6. Pane reachability check before processing — if dev peek returns empty,
#      skip iteration with warning instead of false-firing.
#   7. Heartbeat every 15 iterations (5 min @ 20s sleep) — orchestrator can
#      verify monitor is actually alive vs silent-dead.

set +e
DEV=~/.local/bin/dev
PROJECT="${1:-}"

if [ -z "$PROJECT" ]; then
  echo "Usage: $0 <project_alias>" >&2
  exit 2
fi

SEEN="/tmp/${PROJECT}_seen_markers.txt"
HB_FILE="/tmp/${PROJECT}_monitor_heartbeat.txt"
: > "$SEEN"
echo "[$(date +%H:%M:%S)] $PROJECT monitor armed (line-anchored + heartbeat + auth-fail + idle-stall)"

iter=0
LAST_DEAD_C=""
LAST_DEAD_K=""

while true; do
  iter=$((iter + 1))
  ts=$(date +%H:%M:%S)
  ts_min=$(date +%H%M)
  echo "$ts iter=$iter" > "$HB_FILE"

  # Heartbeat every 5 minutes (15 iterations × 20s)
  if [ $((iter % 15)) -eq 0 ]; then
    echo "[$ts] heartbeat (iter=$iter, alive)"
  fi

  # Pane reachability — left side (claude)
  cout=$($DEV peek "$PROJECT" 60 2>/dev/null | tail -50)
  if [ -z "$cout" ]; then
    if [ "$LAST_DEAD_C" != "$ts_min" ]; then
      LAST_DEAD_C=$ts_min
      echo "[$ts] ⚠ claude pane unreachable"
    fi
    sleep 20; continue
  fi

  # Pane reachability — right side (kimi)
  kout=$($DEV peek "$PROJECT" --right 60 2>/dev/null | tail -50)
  if [ -z "$kout" ]; then
    if [ "$LAST_DEAD_K" != "$ts_min" ]; then
      LAST_DEAD_K=$ts_min
      echo "[$ts] ⚠ kimi pane unreachable"
    fi
    sleep 20; continue
  fi

  combined="${cout}
${kout}"

  # Line-anchored marker match — alone on a line, optional cursor symbol prefix
  matches=$(printf '%s' "$combined" \
    | grep -oE '^[[:space:]]*[•⏺❯>]?[[:space:]]*(TASK|REVIEW_APPROVED|REVIEW_FEEDBACK|REVIEW_DEFEND|QA_PASSED|QA_FAILED)_[0-9]+(_[A-Z_]+)?[[:space:]]*$' 2>/dev/null \
    | sed -E 's/^[[:space:]]*[•⏺❯>]?[[:space:]]*//; s/[[:space:]]*$//' \
    | sort -u)
  for m in $matches; do
    [ -z "$m" ] && continue
    if ! grep -qxF "$m" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$m" >> "$SEEN"
      echo "[$ts] marker: $m"
    fi
  done

  # Approval dialogs — Kimi
  if printf '%s' "$kout" | grep -qE "requesting pprovl|\[1\] Approve" 2>/dev/null; then
    key="kapp_$ts_min"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      echo "[$ts] kimi approval pending"
    fi
  fi

  # Approval dialogs — Claude
  if printf '%s' "$cout" | grep -qE "requesting pprovl|\[1\] Approve" 2>/dev/null; then
    key="capp_$ts_min"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      echo "[$ts] claude approval pending"
    fi
  fi

  # Auth failure — Kimi (session expired)
  if printf '%s' "$kout" | grep -qE "Authoriztion filed|API Key ppers to be invlid|invalid_authentication|Type /login to re-uthentite"; then
    key="kauth_$ts_min"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      echo "[$ts] ⚠ KIMI AUTH FAILURE — restart needed"
    fi
  fi

  # Auth failure — Claude
  if printf '%s' "$cout" | grep -qE "Authoriztion filed|API Key ppers to be invlid|invalid_authentication"; then
    key="cauth_$ts_min"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      echo "[$ts] ⚠ CLAUDE AUTH FAILURE — restart needed"
    fi
  fi

  # Idle stall — Claude (Sautéed for 20+ min)
  if printf '%s' "$cout" | grep -qE "Sutéed for [2-9][0-9]m|Sutéed for [1-9][0-9]{2,}m"; then
    key="cidle_$ts_min"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      echo "[$ts] ⚠ claude idle 20+ min"
    fi
  fi

  sleep 20
done
