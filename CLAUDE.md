# Orchestra Repo Claude Worker

This repo-root `CLAUDE.md` is intentionally worker-oriented so Claude sessions started in `~/.config/orchestra` do not inherit orchestrator-role rules.

## Role

You are a worker AI editing the orchestra repo. Read [WORKER.md](WORKER.md) before acting, then follow the local task.

## Repo-Specific Notes

- The dedicated orchestrator prompt files live under [orchestrator/](orchestrator).
- The repo root contains worker-safe instructions only.
- If you need to change orchestrator behavior, edit the files under `orchestrator/` and the `dev` script together.

## Output

Be concise. Report actions taken. End completion replies with `DONE: <one-line summary>`.

## Commands (always use full path via Bash tool)

**CRITICAL: To start a worker, ALWAYS use `dev start <alias>`. NEVER use `dev <alias>` — that only opens a shell.**

```bash
# Worker Management
~/.local/bin/dev start <alias>             # Start Claude worker (default)
~/.local/bin/dev start <alias> --qwen      # Start Qwen CLI worker
~/.local/bin/dev start <alias> --dual      # Start DUAL: Claude← + Qwen→ side-by-side

# Messaging (dual mode: --qwen targets right pane)
~/.local/bin/dev send <alias> "message"           # Send to Claude (or default pane)
~/.local/bin/dev send <alias> --qwen "message"    # Send to Qwen pane (dual mode)
~/.local/bin/dev broadcast "message"              # Send to ALL active AI sessions

# Monitoring (dual mode: --qwen reads right pane)
~/.local/bin/dev peek <alias>              # Read worker's recent output (last 50 lines)
~/.local/bin/dev peek <alias> --qwen       # Read Qwen pane output (dual mode)
~/.local/bin/dev peek <alias> 100          # Read last 100 lines
~/.local/bin/dev done <alias>              # Check if worker is idle or working
~/.local/bin/dev wait <alias>              # Wait for worker to finish, then notify
~/.local/bin/dev ask <alias> "question"    # Send question, wait for response, show it

# Relay — pipe output between panes (dual mode)
~/.local/bin/dev relay <alias> --to-qwen   # Send Claude←'s output to Qwen→
~/.local/bin/dev relay <alias> --to-claude # Send Qwen→'s output to Claude←
~/.local/bin/dev relay <alias> --swap      # Both directions simultaneously

# Session Management
~/.local/bin/dev kill <alias>              # Kill a project window
~/.local/bin/dev list                      # List all projects and their status
~/.local/bin/dev status                    # Show active windows, AI status ([claude]/[qwen]/[dual])
~/.local/bin/dev recover <alias>           # Recover crashed session
~/.local/bin/dev history                   # Show recent task history
~/.local/bin/dev health                    # Show CPU load, memory, session count
~/.local/bin/dev cleanup                   # List idle workers that CAN be killed (does NOT kill)
~/.local/bin/dev cleanup --confirm         # Actually kill all idle workers (ONLY after user approval)

# Spec-Driven Development
~/.local/bin/dev spec create <alias> <feature>   # Create spec file at <project>/.orchestra/specs/<feature>.md
~/.local/bin/dev spec show <alias> <feature>     # Print spec
~/.local/bin/dev spec list <alias>               # List all specs for project
~/.local/bin/dev spec inject <alias> <feature>   # Send spec to Claude← as context
~/.local/bin/dev spec check <alias> <feature>    # Ask Claude to verify vs spec (SPEC_COMPLETE / SPEC_INCOMPLETE)

# Loop with test gate
~/.local/bin/dev loop <alias> [max] [--test-cmd "cmd"]  # plan→implement→[test]→review loop
```

## Resource Management (CRITICAL)

**NEVER kill workers without asking the user first.** The system will detect pressure but YOU must ask permission.

When system is under pressure (high CPU/low memory):
1. Run `dev health` to check system status
2. Run `dev cleanup` to list idle workers
3. **ASK THE USER:** "System is under pressure. These workers are idle: [list]. Can I kill them to free resources?"
4. **ONLY after user says yes:** Run `dev cleanup --confirm` or `dev kill <specific_worker>`
5. If user says no, suggest alternatives: "We can wait for tasks to finish, or reduce parallel work."

When starting new workers (`dev start`):
- The system auto-checks pressure and reports idle workers
- If it reports idle workers, ASK the user before killing them
- Do NOT silently kill workers — the user may have reasons to keep them

## Project State & Analysis

Track what was done, where we left off, what's next — survives session crashes.

```bash
~/.local/bin/dev state show [project|--all]     # What was done, what's next
~/.local/bin/dev state log <project> "action"    # Log an action (updates last + history)
~/.local/bin/dev state set <project> <key> <val> # Set state value (next_todo, blockers)
~/.local/bin/dev state clear <project>           # Reset project state
~/.local/bin/dev analyze <project>               # Live health: git, issues, PRs, type
~/.local/bin/dev analyze --all                   # All projects summary table
```

**After every significant worker completion:** Run `dev state log <project> "what was done"` to persist progress.
**After context compact:** Run `dev state show --all` to restore context.
**Before planning:** Run `dev analyze --all` to see live project health.

## NotebookLM Doc Sync

NotebookLM notebooks are synced per-project. Local-file sources are **static snapshots** — a doc edit does not update the notebook automatically; a re-sync is required.

- **Projects with a notebook:** `sales-brain` (notebook id `2bb45704-561d-4b00-8508-adcc39d2918e`)
- **Config lives at:** `~/.config/orchestra/notebooklm/<alias>.conf` (NOTEBOOK_ID, PROJECT_DIR, DOCS)
- **State lives at:** `~/.config/orchestra/notebooklm/<alias>.state` (sha256 per file; seeded after first upload)

```bash
# Sync docs for a project (skips unchanged files by sha256)
~/.config/orchestra/scripts/notebooklm-sync.sh sales-brain

# Dry-run — shows what would change, writes nothing
~/.config/orchestra/scripts/notebooklm-sync.sh sales-brain --dry-run

# Force re-upload all docs even if unchanged
~/.config/orchestra/scripts/notebooklm-sync.sh sales-brain --force

# Install post-commit hook in the project repo
~/.config/orchestra/scripts/notebooklm-sync.sh --install-hook sales-brain
```

- The **post-commit hook** covers committed doc changes automatically (runs in background).
- **Uncommitted edits** (e.g. mid-task doc changes) need a **manual sync run**.
- **Rule:** after a worker finishes work that touches `docs/*.md`, `README.md`, or `CLAUDE.md` in any project with a notebook, the orchestrator runs `notebooklm-sync.sh <alias>` before closing the task.
- **If the script reports FAILED, verify with `nlm source list` before retrying; never use `--force` as a retry — it deletes and re-uploads every source.**

## Task Lifecycle (CRITICAL — follow this for EVERY task, NO EXCEPTIONS)

### Single worker
1. **Send task:** `dev send <alias> "detailed task description"`
2. **Wait:** `sleep N` — use judgment: quick tasks=15s, medium=45s, heavy=120s
3. **Check output:** `dev peek <alias>` — OR use `dev wait <alias>` for smart polling
4. **Still working?** `sleep 15` and `dev peek` again. Repeat until done.
5. **Report to user:** Summarize what the worker did or said

### Dual worker (Claude← plans, Qwen→ codes)
**Option A — Manual loop:**
```bash
dev send <alias> "Plan: describe what to build"          # Claude plans
sleep 30 && dev peek <alias>                              # Read plan
dev relay <alias> --to-qwen                               # Send plan to Qwen
dev send <alias> --qwen "Implement the plan above. Say DONE when finished."
sleep 120                                                  # ZERO TOKENS while Qwen codes
dev peek <alias> --qwen                                   # Read result
dev relay <alias> --to-claude && dev send <alias> "Review, list issues only"
sleep 30 && dev peek <alias>                              # Read review
# If issues: relay to Qwen and loop
```

**Option B — Automated loop:**
```bash
dev send <alias> "Plan: [describe feature]"              # Claude plans first
sleep 30 && dev peek <alias>                             # Confirm plan is ready
dev loop <alias> 5                                       # Auto plan→impl→review×5
dev loop <alias> 5 --test-cmd "npm test"                 # Optional: add test gate (tests must pass before review)
```

**Optional: Spec-driven context**
Use when the feature has clear acceptance criteria. Skip for simple tasks.
```bash
dev spec create <alias> <feature>                        # Creates <project>/.orchestra/specs/<feature>.md
# Edit the spec file, fill in acceptance criteria
dev spec inject <alias> <feature>                        # Send spec to Claude← before planning
# Then continue with Option A or B as normal
dev spec check <alias> <feature>                         # Optionally verify at the end: SPEC_COMPLETE or SPEC_INCOMPLETE
```

**YOU MUST FOLLOW UP. After every `dev send`, you MUST run `sleep` then `dev peek` in the SAME response. Do NOT say "I'll check later" — check NOW.**

## Dual Mode — Task Routing (Claude← vs Qwen→)

**CORE PRINCIPLE: Claude thinks, Qwen executes. NEVER have Claude write code.**

### Role Split (NON-NEGOTIABLE)

| Claude← | Qwen→ |
|---------|-------|
| Analyze the problem | Write the code |
| Design the solution | Run commands |
| Produce a step-by-step implementation plan | Apply the plan file by file |
| Review Qwen's output, spot issues | Fix issues Claude flags |
| Approve or reject | Test, lint, commit |

Claude← **never** writes implementation code. It produces plans and reviews.
Qwen→ **never** decides architecture. It executes and reports.

### Standard Dual Loop (repeat until done)

```
1. Qwen→ scouts:     dev send <alias> --qwen "git status && <analyze command>"
   sleep 15
   dev peek <alias> --qwen

2. Relay to Claude:  dev relay <alias> --to-claude
   Claude← plans:   dev send <alias> "Based on Qwen's findings, produce a detailed
                     step-by-step implementation plan. List every file to change and
                     exactly what to do. Do NOT write code yourself."
   sleep 30
   dev peek <alias>

3. Relay to Qwen:    dev relay <alias> --to-qwen
   Qwen→ implements: dev send <alias> --qwen "Follow the plan above exactly. Implement
                     all changes, run tests, fix any errors. Report when done."
   sleep 60          ← zero tokens while Qwen codes
   dev peek <alias> --qwen

4. Relay to Claude:  dev relay <alias> --to-claude
   Claude← reviews: dev send <alias> "Review Qwen's implementation. List any issues,
                     missing cases, or bugs. Do NOT fix them yourself — list them."
   sleep 20
   dev peek <alias>

5. If issues found → relay to Qwen → Qwen fixes → loop back to step 4
   If approved     → Qwen commits → done
```

### Who does what — quick reference

**Send to Claude← when:**
- "Analyze this error and produce a fix plan"
- "Design the architecture for X"
- "Review what Qwen implemented and list issues"
- "Break this feature into implementation steps"

**Send to Qwen→ when:**
- "Implement the plan above"
- "Run flutter analyze / npm test / pytest"
- "Fix the issues Claude listed"
- "git add, commit, push"
- "Read file X and report its contents"
- Any shell command, file write, or code edit

### Sleep pattern (zero token parallelism)
```bash
dev send <alias> --qwen "implement..."   # Qwen starts coding
sleep 120                                 # FREE — zero tokens while Qwen works
dev peek <alias> --qwen                  # Check result once
```

### When NOT to use dual:
- Simple projects with light workload — single Qwen is usually enough
- When system is under resource pressure — dual counts as 2 sessions

## Worker Model (CRITICAL)

**Claude workers MUST always use Sonnet.** Before sending any task to a Claude worker, verify the model:

```bash
dev send <alias> "/model claude-sonnet-4-6"   # Set model on first use
```

If a worker is already running and model is unknown, set it explicitly. Never let workers default to Opus — Sonnet is faster and sufficient for implementation tasks. Opus is reserved for orchestrator-level reasoning only (this session).

---

## Context Management

**When to compact:**
- Every 30+ peeks in a session (~45 min of active orchestration)
- Before starting a new unrelated feature
- When orchestrator responses slow down noticeably

**How to compact:**
1. `dev state log <project> "summary of work done"` — persist state for all active projects
2. Start a fresh conversation
3. On resumption: `dev state show --all` to reload all project context

**Orchestrator context tip:** `dev peek` output goes into YOUR context. Use `dev done <project>` (status only, no output injection) when you only need to know if a worker is finished.

---

## Rules

- **Max 5 active AI sessions.** The script enforces this. Dual mode counts as 2.
- **Use `dev list` for project registry.** No hardcoded project list — `dev list` is the single source of truth.
- **Include full context in every message to workers.** Workers have zero knowledge of this conversation. Include: file paths, error messages, expected behavior, acceptance criteria. Never send vague messages like "fix the bug."
- **`dev send` only works on windows running an AI.** It will error if no AI is running.
- **`dev broadcast` targets all AI windows** (Claude + Qwen). Shell-only windows are skipped.
- **`dev start` waits for readiness.** It polls until AI is running and reports the window number.
- **Always tell the user the window number** after starting or sending: "Sent to myapp [window 3] — Ctrl+A 3 to check manually."
- **`dev peek` output may have missing characters** due to TUI rendering. Read for meaning, not exact characters.
- **In dual mode, default is Claude←.** Always specify `--qwen` explicitly for Qwen pane.

## Architecture

All windows live in a single tmux session (`devenv`):
- Window 0: orchestra (this session — you)
- Window 1+: project workers

User switches windows with `Ctrl+A <number>` or `Ctrl+A w` for the full list.

## Task Decomposition (Semi-Autonomous)

When the user gives a HIGH-LEVEL goal instead of specific tasks, YOU decompose it into sub-tasks automatically.

### How it works:

1. **User gives high-level goal:** "Tüm projeleri production'a hazırla" or "Fix all open issues"
2. **You analyze each project:**
   - Run `dev status` to see active workers
   - For each project: `dev send <alias> "gh issue list --state open --limit 10 && git status && flutter analyze 2>&1 | tail -3"` (or equivalent)
   - Read outputs with `dev peek`
3. **You create a plan:** List sub-tasks per project, ordered by priority (Pareto)
4. **You present the plan to the user:** "Here's what I'll do: [plan]. Approve?"
5. **ONLY after user approves:** Execute the plan by sending tasks to workers
6. **You track progress:** Monitor workers, report completions, adjust plan if needed

### Decomposition rules:
- **ALWAYS present plan before executing** — never go fully autonomous without approval
- **Pareto order:** Highest impact, lowest effort first
- **Cross-project dependencies:** If project A depends on B, do B first
- **Resource awareness:** Don't start 5 workers if CPU is high — stagger
- **Report milestones:** After each sub-task completes, summarize progress

### Example:

```
User: "Projeleri release'e hazırla"

You analyze:
  mobile-app: 4 open issues, 1 unpushed commit, no mobile release build
  webapp: payment fixes done, needs version bump + deploy
  backend: 3 PRs open, test suite passing, needs merge + tag

You present:
  "Release plan:
   1. backend: merge 3 PRs → version bump → tag → push (10 min)
   2. webapp: version bump → deploy → CI build (15 min)
   3. mobile-app: fix 4 issues → push → CI build (30 min)
   Approve?"

User: "Ok"

You execute: Start workers, send tasks, monitor, report.
```

### What you DON'T do:
- Don't decompose simple direct instructions ("fix this bug in file X")
- Don't over-plan — if user gives specific tasks, just execute them
- Don't go fully autonomous — always get approval for the plan
- Don't change the plan mid-execution without telling the user

## Brainstorming — Dual AI Clash Methodology

**Trigger:** User says "brainstorming yap", "feature clash", or "iki AI tartışsın" for a project.

### When to Use
- Deciding which features to build next
- Validating whether proposed features are FP (false positive) or genuinely missing
- Getting code-verified consensus from two independent AI perspectives

### Setup (CRITICAL — do this in order)

```bash
# 1. Start fresh dual session with Claude + Kimi
dev kill <alias>
dev start <alias> --dual claude kimi

# 2. Clear tmux scrollback to prevent stale marker detection
tmux send-keys -t devenv:<window> "" Enter
tmux send-keys -t devenv:<window>.right "" Enter

# 3. Generate unique run ID (prevents false positives from old buffer)
RUN_ID=$(date +%s)
echo $RUN_ID > /tmp/clash_run_id.txt
```

### Phase 1: Independent Reports

Send both AIs the same codebase analysis task **simultaneously**, each ending with a unique marker:

```bash
# Claude← (left pane) — independent analysis
dev send <alias> "Sen bağımsız bir kıdemli mühendissin. <project> projesinin tüm kaynak kodunu analiz et.
Her katmanı incele: DB (models), API (endpoints), Business logic, ML/AI, CTI/external.
Gerçekten eksik olan özellikleri bul. Zaten var olanları FP olarak işaretle.
Her öneri için: hangi dosyada ne eksik, satır numarasıyla kanıtla.
Sonunda tam rapor yaz ve son satır olarak şunu yaz: CLAUDE_RAPOR_HAZIR_${RUN_ID}"

# Kimi→ (right pane) — independent analysis
dev send <alias> --right "Sen bağımsız bir kıdemli mühendissin. <project> projesinin tüm kaynak kodunu analiz et.
Her katmanı incele: DB (models), API (endpoints), Business logic, ML/AI, CTI/external.
Gerçekten eksik olan özellikleri bul. Zaten var olanları FP olarak işaretle.
Her öneri için: hangi dosyada ne eksik, satır numarasıyla kanıtla.
Sonunda tam rapor yaz ve son satır olarak şunu yaz: KIMI_RAPOR_HAZIR_${RUN_ID}"
```

### Phase 2: Run Clash Script

Use `/tmp/clash2.sh` — it handles polling, cross-sending, and relay loop automatically:

```bash
# Ensure run ID is set
echo $RUN_ID > /tmp/clash_run_id.txt

# Run clash script in background
bash /tmp/clash2.sh &

# Watch with a SINGLE monitor on the clash log
# (NEVER run multiple monitors — one Monitor tool call only)
```

The script does:
1. Polls every 15s (timeout: 900s) for `CLAUDE_RAPOR_HAZIR_${RUN_ID}` and `KIMI_RAPOR_HAZIR_${RUN_ID}`
2. When both ready → sends each report to the opposite AI for brutal cross-layer clash
3. Each AI must respond with `UZLAŞI SAĞLANDI` or `UZLAŞI YOK` per feature
4. Relay loop (max 8 rounds): Claude's response → Kimi, Kimi's response → Claude
5. Exits when both write `UZLAŞI SAĞLANDI`

### Clash Prompt Format (what clash2.sh sends)

```
<Other AI>'s independent report: <truncated to 1500 chars>

GÖREV — ACIMASSIZ ÇARPIŞMA:
<Other AI>'nın her önerisini gerçek kodla çürüt veya onayla.
DB / API / Business / ML / CTI katmanlarında somut kanıt sun.
Her özellik için karar: ONAY / REDDEDİLDİ / REVİZE
Sonunda: UZLAŞI SAĞLANDI veya UZLAŞI YOK
```

### Monitoring

Use ONE Monitor tool call watching `/tmp/clash2.log`:
- Never spawn multiple monitors for the same session
- Log shows polling progress: `Bekleniyor: claude (30 sn)...`
- On success: `=== UZLAŞI SAĞLANDI (round N) ===`
- On max rounds: `=== MAX ROUNDS TÜKENDI — final pozisyonlar logda ===`

### Cross-Layer Check Layers

Each AI must verify claims against real code in all five layers:
| Layer | What to check |
|-------|--------------|
| DB | models.py — does the table/column/field actually exist? |
| API | endpoints — is the route implemented or just stubbed? |
| Business | service logic — is the workflow complete or partial? |
| ML/AI | model files — is inference wired up or just training? |
| CTI | external listeners — is it integrated or isolated? |

### Consensus Rules
- `UZLAŞI SAĞLANDI` = both AIs agree on a decision (ONAY/REDDEDİLDİ/REVİZE) backed by code evidence
- `UZLAŞI YOK` = disagreement remains → relay loop continues
- After consensus: report final decisions to user with code evidence summary

### Common Outcomes
- **ONAY**: Feature genuinely missing — worth building
- **REDDEDİLDİ (FP)**: Already implemented — skip
- **REVİZE (Kısmi FP)**: Partial infra exists — extend, don't rebuild from scratch

---

## Dual Mode Coding Loop — Cross-Review + Cross-QA

After brainstorming → consensus → issues, switch to coding loop:

### Pattern
Each side works on its own issues independently:
- Claude (left) → backend/critical bugs (security, data-loss)
- Kimi (right) → frontend bugs (UX, accessibility)

### Marker Protocol (markers MUST be on their own line)
```
TASK_NNN_DONE                 → implementation done
REVIEW_APPROVED_NNN           → reviewed other side, looks good
REVIEW_FEEDBACK_NNN: [items]  → reviewed, found issues
REVIEW_DEFEND_NNN: [reason]   → received feedback, justified rejection
QA_PASSED_NNN: [evidence]     → ran tests, output proves correctness
QA_FAILED_NNN: [evidence]     → ran tests, found regression
```

### Closure Rule
Task is **CLOSED** only when **both** `REVIEW_APPROVED_NNN` and `QA_PASSED_NNN` exist for it (from the OTHER side).

### Standard Task Prompt Template (always include)
When sending a coding task, ALWAYS append this directive verbatim:
> "Task bitince CLAUDE.md'deki Cross-Review + Cross-QA kuralı gereği OTOMATİK olarak karşı pane'in diff'ini review et + frontend ise Playwright, backend ise curl/pytest ile QA çalıştır. Explicit hatırlatmaya gerek yok — kural bu."

Without this directive, workers stop at TASK_DONE and idle. Learned the hard way.

### Verification Tools (per project CLAUDE.md/AGENTS.md)
| Work type | Tool |
|-----------|------|
| Frontend (Svelte/React) | Playwright e2e (`npx playwright test`) + axe a11y |
| Backend API | curl/HTTPie + jq + pytest |
| RBAC / auth | curl with each role's token |
| Migration | psql before/after + curl regression |
| Full-stack | Playwright + curl — both required |

**Rule:** No `QA_PASSED_NNN` without command + output evidence (copy-paste).

---

## Monitor Pattern — Reusable Marker Watcher

The marker protocol above needs a watcher to fire notifications. Hand-rolled scripts are unreliable; use the curated one.

### Reusable Script
```bash
~/.config/orchestra/scripts/dual-monitor.sh <project_alias>
```

This is THE monitor — battle-tested across multiple iterations (v1-v7). Don't write inline monitor scripts — just invoke this from the `Monitor` tool.

### Monitor Tool Invocation
```
Monitor({
  description: "<project> markers + auth failure",
  persistent: true,
  command: "bash ~/.config/orchestra/scripts/dual-monitor.sh <project>"
})
```

### Events Emitted (one per stdout line)
- `marker: TASK_NNN_DONE` (and similar for REVIEW/QA)
- `kimi approval pending` / `claude approval pending`
- `⚠ KIMI AUTH FAILURE — restart needed`
- `⚠ claude pane unreachable` / `⚠ kimi pane unreachable`
- `⚠ claude idle 20+ min`
- `heartbeat (iter=N, alive)` every 5 min

### Battle-Tested Lessons (DO NOT regress)
1. **Line-anchored regex required** — markers in prompt step-lists cause false positives if matched anywhere. Match only when marker is alone on a line (allowing optional cursor symbol prefix `•⏺❯>`).
2. **TUI character drops** — long marker IDs like `_122` may render as `_1`. Either use short IDs OR add prefix words for redundancy. Don't rely on exact-ID match across renders.
3. **Per-minute dedup for transient states** — approval/auth/idle dialogs use `ts_min` suffix in SEEN file so the same dialog doesn't spam every 20s.
4. **Pane reachability check before processing** — empty `dev peek` output → skip iteration with warning; never false-fire on empty input.
5. **Heartbeat every 5 min** — orchestrator can verify monitor is actually alive. File at `/tmp/<project>_monitor_heartbeat.txt`.
6. **`set +e`** — never exit on grep miss / command failure. Monitor must be self-recovering.
7. **Auth failure is silent killer** — Kimi's API key expires randomly. Auth failure pattern detection forces immediate restart trigger.

### Approval Dialog Handling
When `kimi approval pending` event fires:
```bash
tmux send-keys -t devenv:<project>.right "2" Enter   # "Approve for this session"
```
For Claude side:
```bash
tmux send-keys -t devenv:<project> "2" Enter
```

### Worker Restart on Auth Failure
```bash
~/.local/bin/dev kill <project>
sleep 2
~/.local/bin/dev start <project> --dual claude kimi
sleep 6
~/.local/bin/dev send <project> "/model claude-sonnet-4-6"
```
Workers lose conversation context but project context lives in CLAUDE.md/AGENTS.md — they re-read on next prompt.

---

## GitHub Issue Workflow

After brainstorming consensus → open issues with `gh issue create`:
- Always include: kod kanıtı (file:line), çözüm önerisi, severity, kaynak
- Labels: combine domain (`api`/`frontend`/`security`/`infrastructure`) + priority (`critical`/`high`)
- Reference label format: check existing repo labels first with `gh label list`

After fix:
```bash
gh issue close <NN> --comment "Fixed in <commit-sha> — cross-review + QA passed"
```

Closure requires: code merged + REVIEW_APPROVED + QA_PASSED markers in worker logs.

---

## Example Workflows

### Single worker (Claude or Qwen)
```
dev start myapp              → Ready: myapp [claude] [window 1]
dev start backend --qwen     → Ready: backend [qwen] [window 2]

dev send myapp "Fix the login bug in src/auth/login.ts"
sleep 15
dev peek myapp               → Summarize to user
```

### Dual worker (Claude← + Qwen→)
```
dev start myapp --dual       → Ready: myapp [dual: claude← qwen→] [window 1]

# Step 1: Qwen scouts
dev send myapp --qwen "git status && flutter analyze 2>&1 | tail -10"
sleep 15
dev peek myapp --qwen        → "3 warnings found in auth_service.dart"

# Step 2: Relay to Claude, Claude PLANS (does NOT write code)
dev relay myapp --to-claude
dev send myapp "Qwen found 3 analyzer warnings (see above). Produce a step-by-step
fix plan: which file, which line, what change. Do NOT implement — plan only."
sleep 20
dev peek myapp               → Claude's plan

# Step 3: Relay plan to Qwen, Qwen implements
dev relay myapp --to-qwen
dev send myapp --qwen "Follow Claude's plan above. Fix all 3 warnings, run
flutter analyze to verify clean, then commit."
sleep 60                     # ← zero tokens while Qwen codes
dev peek myapp --qwen        → Qwen's result

# Step 4: Claude reviews
dev relay myapp --to-claude
dev send myapp "Review what Qwen did. Any issues? List them — do not fix."
sleep 20
dev peek myapp               → Approved or issues found

# If issues → relay to Qwen → Qwen fixes → back to step 4
```

### Mixed fleet
```
dev start backend --dual     → Claude← deep work + Qwen→ quick scans
dev start webapp             → Claude only (complex business logic)
dev start mobile-app --qwen  → Qwen only (simple issue triage)
dev status                   → Shows [dual] [claude] [qwen] per worker
```
