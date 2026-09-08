#!/usr/bin/env bash
# notebooklm-sync.sh — sync project docs to a NotebookLM notebook
# Usage:
#   notebooklm-sync.sh <alias> [--dry-run] [--force]
#   notebooklm-sync.sh --install-hook <alias>
#   notebooklm-sync.sh --list
set -euo pipefail

NLM="${NLM_BIN:-${HOME}/.local/bin/nlm}"
CONF_DIR="${HOME}/.config/orchestra/notebooklm"
LOG_DIR="${HOME}/.config/orchestra/logs"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "[$(date '+%H:%M:%S')] $*"; }

# ── subcommand: --list ────────────────────────────────────────────────────────

if [[ "${1:-}" == "--list" ]]; then
  echo "Configured notebooks:"
  for f in "${CONF_DIR}"/*.conf; do
    [[ -f "$f" ]] || { echo "  (none)"; exit 0; }
    alias_name="$(basename "$f" .conf)"
    # shellcheck disable=SC1090
    source "$f"
    echo "  ${alias_name}  →  notebook ${NOTEBOOK_ID}  (${PROJECT_DIR})"
  done
  exit 0
fi

# ── subcommand: --install-hook ────────────────────────────────────────────────

if [[ "${1:-}" == "--install-hook" ]]; then
  [[ -n "${2:-}" ]] || die "--install-hook requires an alias argument"
  ALIAS="$2"
  CONF_FILE="${CONF_DIR}/${ALIAS}.conf"
  [[ -f "$CONF_FILE" ]] || die "Config not found: ${CONF_FILE}"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  HOOK_FILE="${PROJECT_DIR}/.git/hooks/post-commit"
  SNIPPET="# notebooklm-sync for ${ALIAS}
\"${SCRIPT_PATH}\" \"${ALIAS}\" >> \"${LOG_DIR}/notebooklm-sync-${ALIAS}.log\" 2>&1 &"

  if [[ -f "$HOOK_FILE" ]]; then
    echo "WARNING: post-commit hook already exists at ${HOOK_FILE}"
    echo "Append the following snippet manually:"
    echo "---"
    echo "$SNIPPET"
    echo "---"
  else
    mkdir -p "${PROJECT_DIR}/.git/hooks"
    printf '#!/usr/bin/env bash\n%s\n' "$SNIPPET" > "$HOOK_FILE"
    chmod +x "$HOOK_FILE"
    echo "Installed post-commit hook at ${HOOK_FILE}"
  fi
  exit 0
fi

# ── normal sync mode ──────────────────────────────────────────────────────────

ALIAS="${1:-}"
[[ -n "$ALIAS" ]] || { echo "Usage: $(basename "$0") <alias> [--dry-run] [--force]"; exit 1; }

DRY_RUN=false
FORCE=false
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
    *) die "Unknown flag: $arg" ;;
  esac
done

# ── preflight checks ──────────────────────────────────────────────────────────

[[ -x "$NLM" ]] || die "nlm not found or not executable at ${NLM}"

# verify auth by running a harmless nlm command
if ! "$NLM" notebook list --json >/dev/null 2>&1; then
  die "nlm is not authenticated. Run: nlm login"
fi

CONF_FILE="${CONF_DIR}/${ALIAS}.conf"
[[ -f "$CONF_FILE" ]] || die "Config file not found: ${CONF_FILE}"

# shellcheck disable=SC1090
source "$CONF_FILE"

[[ -n "${NOTEBOOK_ID:-}" ]] || die "NOTEBOOK_ID not set in ${CONF_FILE}"
[[ -n "${PROJECT_DIR:-}" ]] || die "PROJECT_DIR not set in ${CONF_FILE}"
[[ -n "${DOCS:-}" ]]        || die "DOCS not set in ${CONF_FILE}"

# verify notebook is reachable
if ! "$NLM" source list "$NOTEBOOK_ID" --json >/dev/null 2>&1; then
  die "Notebook ${NOTEBOOK_ID} is unreachable. Check NOTEBOOK_ID in ${CONF_FILE} or nlm auth."
fi

# ── setup log + state ─────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/notebooklm-sync-${ALIAS}.log"

# Tee to log file unless running interactively already redirected
exec > >(tee -a "$LOG_FILE") 2>&1

STATE_FILE="${CONF_DIR}/${ALIAS}.state"
touch "$STATE_FILE"

log "=== notebooklm-sync: ${ALIAS} | dry=${DRY_RUN} force=${FORCE} ==="

# ── expand DOCS globs ─────────────────────────────────────────────────────────

declare -a EXPANDED_DOCS=()
for pattern in $DOCS; do
  # expand relative to PROJECT_DIR
  for match in "${PROJECT_DIR}"/${pattern}; do
    if [[ -e "$match" ]]; then
      EXPANDED_DOCS+=("$match")
    else
      die "Doc path does not exist on disk: ${match}  (pattern: ${pattern})"
    fi
  done
done

# ── fetch current notebook sources once ──────────────────────────────────────

SOURCES_JSON="$("$NLM" source list "$NOTEBOOK_ID" --json)"

get_source_id_by_title() {
  local title="$1"
  echo "$SOURCES_JSON" | python3 -c "
import json, sys
sources = json.load(sys.stdin)
for s in sources:
    if s.get('title') == '$title':
        print(s['id'])
        sys.exit(0)
sys.exit(1)
" 2>/dev/null || true
}

# ── sync loop ─────────────────────────────────────────────────────────────────

TOTAL=0; SKIPPED=0; UPDATED=0; ADDED=0; FAILED=0

for abs_path in "${EXPANDED_DOCS[@]}"; do
  TOTAL=$((TOTAL + 1))
  basename_file="$(basename "$abs_path")"
  rel_path="${abs_path#${PROJECT_DIR}/}"

  # compute current sha256
  current_sha="$(shasum -a 256 "$abs_path" | awk '{print $1}')"

  # read stored sha
  stored_sha="$(grep -E "^${rel_path}  " "$STATE_FILE" 2>/dev/null | awk '{print $2}' || true)"

  if [[ "$current_sha" == "$stored_sha" ]] && [[ "$FORCE" == "false" ]]; then
    log "SKIP  ${rel_path}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # find existing source id
  existing_id="$(get_source_id_by_title "$basename_file")"

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$existing_id" ]]; then
      log "DRY-RUN  WOULD DELETE source id=${existing_id} title=${basename_file}"
    fi
    log "DRY-RUN  WOULD ADD file=${abs_path} title=${basename_file}"
    if [[ -n "$stored_sha" ]]; then
      log "DRY-RUN  UPDATED  ${rel_path}"
    else
      log "DRY-RUN  ADDED    ${rel_path}"
    fi
    continue
  fi

  # actual sync
  set +e

  # delete existing source if found
  if [[ -n "$existing_id" ]]; then
    if "$NLM" source delete "$existing_id" --confirm >/dev/null 2>&1; then
      log "  Deleted old source ${existing_id} (${basename_file})"
    else
      log "FAILED  ${rel_path}  (could not delete old source ${existing_id})"
      FAILED=$((FAILED + 1))
      set -e
      continue
    fi
  fi

  # add new source
  add_json="$("$NLM" source add "$NOTEBOOK_ID" --file "$abs_path" --title "$basename_file" --wait --json 2>/dev/null)"
  add_exit=$?
  # JSON shape: {"source_type": "file", "source_id": "...", "title": "..."}
  new_id="$(echo "$add_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('source_id',''))" 2>/dev/null)"
  set -e

  # Fallback: if source_id came back empty, look up by title in source list
  if [[ -z "$new_id" ]]; then
    new_id="$("$NLM" source list "$NOTEBOOK_ID" --json 2>/dev/null | python3 -c "
import json, sys
sources = json.load(sys.stdin)
title = '$basename_file'
matched = [s for s in sources if s.get('title') == title]
if matched:
    print(matched[-1].get('id', ''))
" 2>/dev/null || true)"
  fi

  if [[ $add_exit -ne 0 ]] || [[ -z "$new_id" ]]; then
    [[ -n "$existing_id" ]] && log "WARNING  old source deleted, upload unconfirmed — verify with: nlm source list $NOTEBOOK_ID"
    log "FAILED  ${rel_path}  (upload failed — verify with: nlm source list $NOTEBOOK_ID)"
    FAILED=$((FAILED + 1))
    continue
  fi

  # update state only after successful upload
  if grep -qE "^${rel_path}  " "$STATE_FILE" 2>/dev/null; then
    sed -i '' "s|^${rel_path}  .*|${rel_path}  ${current_sha}|" "$STATE_FILE"
  else
    echo "${rel_path}  ${current_sha}" >> "$STATE_FILE"
  fi

  if [[ -n "$stored_sha" ]]; then
    log "UPDATED  ${rel_path}  (source id=${new_id})"
    UPDATED=$((UPDATED + 1))
  else
    log "ADDED    ${rel_path}  (source id=${new_id})"
    ADDED=$((ADDED + 1))
  fi
done

log "=== Done: ${TOTAL} total | ${SKIPPED} skip | ${UPDATED} updated | ${ADDED} added | ${FAILED} failed ==="
[[ $FAILED -eq 0 ]] || exit 1
