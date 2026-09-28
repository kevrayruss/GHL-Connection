# Cloud cleanup proposal (draft, nothing removed yet)

Prepared 2026-09-28 by Claude Code. Every item needs Kevin's approval (twice for anything deleted).
"Archive" means move to `Operations/Shared System/_Legacy Archive (inactive)`. "Trash" means Drive trash, which is recoverable for 30 days.

## A. Drive files

| # | Item | Where | Why it is outdated | Proposed |
|---|---|---|---|---|
| A1 | WHAT'S WHERE (old guide) | Company/Claude System drive, Doc `1xotiW0O3ylIFKUE1j3hxlBUCW32JixRv2BvqAZXcI_0` | Still says the old drive is the single home and tells AIs to use Finder/Drive for Desktop | Add a "RETIRED, see operating guide v1.2.1" banner at the top, then archive |
| A2 | EXACT-UPLOAD-LIVE-TEST_2c4ae549….txt | Operations/Shared System | Sept 27 upload test fixture | Trash |
| A3 | SCOPED-DIRECT-LIVE-TEST_189af511….txt | Operations/Shared System | Sept 27 upload test fixture | Trash |
| A4 | SCOPED-UPLOAD-SYNTHETIC-TEST_2ef9c9b5….txt | Operations/Shared System | Sept 27 upload test fixture | Trash |
| A5 | TRANSFER-INTEGRITY-TEST_2026-09-27.txt | Operations/Shared System | Sept 27 test fixture | Trash |
| A6 | OPERATIONS_EDITOR_CHECK.md and "Operations Editor Check" (Doc) | Operations/Shared System | Sept 8 editor test fixtures still named in guide v1.1 only | Archive |
| A7 | SUPERSEDED_2026-09-17_RUNBOOK_Compaction-SaaS-on-SPWC-Stripe_2026-09-16.md | Operations/GHL Multi-Brand SaaS | Marked superseded by its own name; the current runbook sits next to it | Archive |
| A8 | iCloud Intake 2026-09-28 (browser upload, partial) | Operations/Shared System | Replaced by the complete Drive for Mac copy in Operations/iCloud Intake; every file there is also in the new copy (checked by fingerprint before removal) | Trash after the new copy is verified complete |
| A9 | Synthetic Managed Save test objects (6 files) | Operations/Shared System/_Managed Versions | Test data from Task 03/04 acceptance | Keep until ChatGPT's acceptance test passes, then trash |

## B. n8n workflows

| # | Workflow | ID | Status today | Proposed |
|---|---|---|---|---|
| B1 | Superseded test - Markdown editor | `fKhfWZVpSSYHwvxU` | Inactive, labeled superseded | Archive |
| B2 | GR Cloud Drive - Isolated ID and Retry Test | `FeVzSYiABFs9Ka6Z` | Inactive, Sept 7 test | Archive |
| B3 | Personal-OS - Connection Verification | `9TniL28CJO986lnR` | Inactive, completed fixture | Archive |
| B4 | Growth Revo - Upload Live Verification | `wUmVEO39Fl6tPuND` | Inactive, synthetic test | Archive |
| B5 | Growth Revo - Exact File Upload (secure intake) | `8n9HSDebabHW56lL` | Retired by ChatGPT (static key) | Archive |
| B6 | Growth Revo - Edit Test Markdown | `n0HjPSaIt02bZU6X` | Legacy writer | Archive after ChatGPT passes the File Control test |
| B7 | Growth Revo - Write File to Drive | `1PJ4DdoW9vonOwOP` | Legacy writer | Archive after ChatGPT passes the File Control test |
| B8 | Exact Upload with Scoped Ticket + Authorize Exact Upload | `0bbiVAeN3m90O9in`, `WWziKK9tP8GgcO4Q` | **Active (published) webhook**, ChatGPT's uploader | Unpublish after ChatGPT switches to Managed Save; keep archived for its receipts |
| B9 | Growth Revo - Edit Test Google Doc | `4y8XbKkDd6uxlJvm` | Still the only Docs editor | Keep until Managed Save supports native Docs |

Archiving an n8n workflow keeps its history and can be undone.

## C. Shared record

| # | Item | Proposed |
|---|---|---|
| C1 | ~40 open handoffs that later handoffs superseded (most are ChatGPT to ChatGPT checkpoints from Sept 9 to 27) | Mark `completed` or `cancelled` through the accept/complete workflow, with a note naming the handoff that replaced each. Needs ChatGPT's agreement since most are its own. |
| C2 | Guide v1.0.0, v1.1.0, v1.2.0 | Already marked deprecated. Keep as history. |
| C3 | Synthetic file-control test resource `02ed1244…` and its events | Keep: it is the evidence for the Task 03/04 tests. Label only. |

## D. Things only Kevin can change

| # | Where | Change |
|---|---|---|
| D1 | iCloud Claude System/System | Rename to "System (RETIRED 2026-09-28)" after the Drive for Mac sync finishes |
| D2 | Cowork settings, ChatGPT and Claude project instructions | Replace old instructions with the iCloud-retired notice |
| D3 | Drive for Mac | Stop syncing Operations after the intake copy is complete |
| D4 | Supabase dashboard, project GR-OS, Authentication, Password security | Turn on "Leaked password protection" (task 12) |
