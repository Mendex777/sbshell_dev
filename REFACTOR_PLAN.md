# Sbshell Refactor Plan

## Progress
- Iteration 1: completed
- Iteration 2: in progress (drop-in migration + common library + stage tracking + doctor script)
## Iteration 1 (Safe hardening, no dataplane changes)

### Goals
- Make install flow fail-fast and predictable.
- Remove obvious drift/integrity issues.
- Keep TProxy routing/firewall logic behavior unchanged.

### Scope
- Add strict mode and centralized error trap.
- Add preflight checks for required commands.
- Validate user subscription URL format.
- Align script download source to `sbshell_3`.
- Fail install when script download list is incomplete.
- Remove missing `configure_tun.sh` from mandatory auto-install download list.
- Make systemd unit patching idempotent (avoid duplicate entries).
- Backup nft rules before flush operations.
- Generate valid JSON for `custom_list.json` (no comments/trailing commas).
- Use final success condition based on `sing-box` active state.

### Acceptance
- `bash -n sbshall_auto_install.sh` passes.
- Installation aborts on failed required step with clear error.
- No duplicate `After/Requires` lines on repeated runs.
- `custom_list.json` is valid JSON.

## Iteration 2 (Architecture cleanup)

### Goals
- Reduce script sprawl and enforce consistent lifecycle management.
- Improve rollback, testability, and maintainability.

### Scope
- Split into modules: `lib/common.sh`, `install/`, `runtime/`, `ui/`.
- Replace direct edits of vendor unit file with systemd drop-in in `/etc/systemd/system/sing-box.service.d/`.
- Introduce state file and transaction checkpoints (preflight/apply/verify/rollback).
- Add shellcheck + JSON lint + `sing-box check` CI workflow.
- Pin external downloads by version/checksum where possible.
- Introduce `sbshell doctor` and `sbshell health` commands.

### Acceptance
- Re-run install safely (idempotent behavior).
- Rollback path documented and tested.
- CI blocks invalid shell/json/templates before merge.

