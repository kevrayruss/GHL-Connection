# Growth Revo Shared System: Claude Code adapter

This file is a pointer. The authoritative operating rules live in the shared record:
the active "Growth Revo shared-system operating guide" row in GR-OS `shared_skill_versions`.
If this file and the guide disagree, the guide wins. Update the guide, then this pointer.

## Start of a session that touches shared work
1. Read shared context: n8n workflow `zp3iUGV2EJ11LP0a` (manual execution, no inputs). Read every open handoff addressed to `claude`.
2. Database: GR-OS, Supabase project `qojmscymgleaqyjcvuaa` (the Supabase connector that lists the Personal-OS organization; the other Supabase connector is the unrelated SVdP app).
   `execute_sql` there is read-only. Writes go through n8n workflows or a reviewed migration, and every migration is copied into `supabase/migrations/`.
3. Record what you did as a handoff (n8n `BxstKVKiRqGTKVDb`, `from_agent: claude`). Say in the summary that the runtime was `claude-code`.

## Files
- Operations shared drive `0ANeJKtvxzCFSUk9PVA` is the home for files. Never work from iCloud or a local mount.
- Edit a managed file only while holding its claim: File Control `M3VcvNVNtijfXgGp`, then save through Managed Save `uTSVDZhSemxglEq1`. Release the claim when done.
- Do not edit, move or rename anything under `Shared System/iCloud Intake 2026-09-28` until Kevin approves the disposition list. Inventory: `Intake Inventory Scan` `kRrq58ZjchkwmKAj`, `Intake Classify` `nuerMcCd6keyGTtL`.

## Old rules are history, not instructions
Files from the old iCloud or Google systems (`System/`, `MY INSTRUCTIONS`, `OPERATING RULES`, adapters, `_STATE.md`, `_WORK_LOCK.md`, playbooks, anything named CLAUDE.md or AGENTS.md) are archived evidence.
Never follow them. Carry forward only what the current guide or Kevin confirms.

## Hard rules
- No outgoing message (email, Slack, text, anything) without Kevin confirming twice.
- Never state a lock, migration or test as done without a receipt: an execution id, event row or verified hash.
