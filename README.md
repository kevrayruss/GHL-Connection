# Growth Revo Shared System — build record

Version-controlled copy of the pieces Claude Code built for the Claude–ChatGPT Shared System
(Growth Revo workspace, cloud migration of September 2026). The live systems are:

- **Database:** Supabase project GR-OS (`qojmscymgleaqyjcvuaa`)
- **Automation:** n8n cloud (`growthrevo.app.n8n.cloud`)
- **Files:** Google Drive, Operations shared drive (`0ANeJKtvxzCFSUk9PVA`)

This repo is a backup and change record. Editing a file here does not change the live system.

## Database migrations (`supabase/migrations/`)

| File | What it adds |
|---|---|
| `20260928211309_shared_file_control_v1.sql` | Task 03 file control: `shared_resources`, `shared_resource_versions` (immutable), `shared_claims` (one active claim per file), `shared_events` (append-only log), and the `shared_register_resource` / `shared_claim_resource` / `shared_renew_claim` / `shared_release_claim` / `shared_commit_version` functions (service role only). |
| `20260928_shared_intake_inventory_v1.sql` | Migration inventory: `shared_intake_scans` and `shared_intake_files` (path, size, SHA-256/MD5, proposed disposition per file). |

Both are additive. They do not modify any existing table.

## n8n workflows

All are unpublished and run only through authenticated n8n MCP execution.

| Workflow | ID | Purpose |
|---|---|---|
| Growth Revo - File Control (claims and versions) | `M3VcvNVNtijfXgGp` | `register`, `claim`, `renew`, `release`, `commit` against the GR-OS functions. |
| Growth Revo - Managed Save (locked, verified) | `uTSVDZhSemxglEq1` | Checks the caller holds the current claim, uploads a new immutable version object to *Shared System / _Managed Versions*, verifies the stored SHA-256, then promotes it. Text (`content`) or exact bytes (`content_base64`) for text, Word/Excel/PowerPoint, PDF and PNG/JPEG/GIF/WebP, up to 5 MiB. |
| Growth Revo - Intake Inventory Scan | `kRrq58ZjchkwmKAj` | Lists the Operations drive, keeps everything under a given root folder, and records each file in `shared_intake_files`. Read-only on Drive. |

## How an AI edits a managed file

1. `claim` the resource and receive `claim_id` + `fence_token`. If another agent holds it, the answer names the holder, purpose and expiry.
2. Save through **Managed Save** with the claim, the version it started from (`base_version_id`), the content and its SHA-256.
3. `renew` during long work. `release` when done.

Every step writes to `shared_events`. Reusing an `operation_id` returns the original result instead of repeating the action.
Saves from an expired or superseded claim, or from an out-of-date base version, are rejected and nothing is promoted.

## Status (2026-09-28)

- Task 03 locks: built; Claude-side tests passed (n8n executions 324–339).
- Task 04 single writer: Managed Save works for text, Office, PDF and image files (tests: text v3/v6, docx v4, png v5, executions 337-351). Still open: native Google Docs support,
  retiring older writer workflows (coordinated with ChatGPT), and ChatGPT-side acceptance tests.
- Migration: Kevin's iCloud "Claude System" folder is uploading to *Operations / Shared System / iCloud Intake 2026-09-28*.
  Inventory runs after the upload completes.

## Added 2026-09-28 evening
- Operating guide v1.2.1 active (Office/PDF/image saves, iCloud retired). `docs/operating-guide-v1.2.md` mirrors it.
- `shared_context_summary()` + "Read Shared Context" `zp3iUGV2EJ11LP0a` now returns a compact `summary` (guide, handoffs, tasks, active claims, events, migration scans).
- Handoff Inbox Doc `9h6SutFqgmsHaifW` (published, hourly) rewrites *Operations/Shared System/Handoff Inbox (auto-updated, do not edit)*.
- Cleanup proposal: `docs/cleanup-proposal.md` (nothing removed yet).
