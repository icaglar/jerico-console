# worker_types — CAO Agent Profiles

The `.md` files here are [CAO (cli-agent-orchestrator)](~/cli-agent-orchestrator) agent profiles
for Claude Code workers. CAO reads them from its agent-store at runtime to configure each worker.

## Install target
`~/.aws/cli-agent-orchestrator/agent-store/` — CAO's own config dir (not AWS-related).
`install.sh` copies each profile there and saves a timestamped `.bak` beside any existing file
that differs first.

## Why `mcpServers: cao-mcp-server` is required
Each profile's YAML frontmatter must include this block. Without it the worker cannot call
`send_message`, so its `STATUS: DONE` / `REVIEW_APPROVED` report never reaches the supervisor's
inbox — a human must relay it manually. Verified: after adding the block, a live smoke test
confirmed both profiles delivered their replies straight into the supervisor's inbox.

```yaml
mcpServers:
  cao-mcp-server:
    type: stdio
    command: cao-mcp-server
    args: []
```

## Working pattern
The supervisor calls `assign` and ends its turn. The worker's reply arrives in the supervisor's
inbox automatically — no status polling needed.

## Validating a profile after editing
POST `{"content": "<file text>"}` as JSON to `http://localhost:9889/agents/profiles/validate`.
Expect `{"valid": true, "messages": []}`.

## Caveats
- Profiles are **Java/Spring Boot flavoured** (`mvn test`): written for `sales-brain`. Adapt
  `capabilities` when reusing them for a different stack.
- `worker_types/` also holds gitignored runtime state (e.g. `sigorta-crm`). Only `.md` files
  are tracked by git.
