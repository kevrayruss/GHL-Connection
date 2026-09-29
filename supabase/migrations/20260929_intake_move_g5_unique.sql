-- G5 (review) follow-up, 2026-09-29, claude-code. Kevin: "I only want to clean up any duplicates... not delete".
-- Move every G5 file that has no identical copy in Operations into Operations at its same path.
-- Where several G5 files share the same bytes, only one copy moves (piles, migration-prep and handoff copies lose ties).
-- The 54 G5 files that already have a copy in Operations, and the 8 internal duplicates, stay in the intake as duplicates.
-- Nothing is deleted.
with g as (
  select f.file_id, f.path, f.sha256, f.rule,
         exists (select 1 from public.shared_intake_files v
                  where v.scan_id = '6fabb9eb-145b-42dc-b896-2b6851867d93' and not v.is_folder
                    and v.path not like '/iCloud Intake/%' and v.sha256 = f.sha256) as twin
    from public.shared_intake_files f
   where f.scan_id = '068b68d4-88ac-4ad8-8416-6146caa02c35' and f.disposition = 'review' and f.moved_at is null
), r as (
  select *, row_number() over (partition by sha256 order by (rule = 'R7'), (path like '%_MIGRATION_PREPARATION%'),
                                (path like '%_ChatGPT Handoff%'), length(path), path) as rn
    from g where not twin
)
update public.shared_intake_files f set move_dest = f.path, move_error = null
  from r where f.scan_id = '068b68d4-88ac-4ad8-8416-6146caa02c35' and f.file_id = r.file_id and r.rn = 1;

update public.shared_intake_scans
   set detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('move_approval_g5', jsonb_build_object(
         'approved_by', 'Kevin', 'approved_at', '2026-09-29', 'channel', 'claude-code chat',
         'instruction', 'clean up duplicates only, do not delete; move unique G5 files into Operations at same paths'))
 where id = '068b68d4-88ac-4ad8-8416-6146caa02c35';
