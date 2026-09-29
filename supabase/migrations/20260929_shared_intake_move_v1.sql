-- Intake move v1 (2026-09-29, claude-code).
-- Carries out Kevin's approval of the iCloud intake decision sheet: G1, G2, G3, G4 approved; G6 (Personal) left out;
-- G5 (review) and G7 (delete intake) not approved. Nothing is deleted by this code.
-- n8n "Intake Move" drives it: prepare -> create folders level by level -> move files in batches -> record every result.

alter table public.shared_intake_files
  add column if not exists move_dest text,
  add column if not exists moved_at timestamptz,
  add column if not exists moved_to_parent text,
  add column if not exists move_error text;

create table if not exists public.shared_intake_folder_map (
  scan_id uuid not null references public.shared_intake_scans(id) on delete cascade,
  path text not null,
  folder_id text not null,
  source text not null check (source in ('root', 'baseline', 'created')),
  created_at timestamptz not null default now(),
  primary key (scan_id, path)
);
alter table public.shared_intake_folder_map enable row level security;
revoke all on public.shared_intake_folder_map from anon, authenticated;

-- Marks what moves where and seeds the folder map from the Operations baseline. Safe to re-run.
create or replace function public.shared_intake_prepare_moves(p_scan uuid, p_baseline uuid, p_drive_id text, p_approval jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update shared_intake_files set move_dest = null
   where scan_id = p_scan and moved_at is null and move_dest is not null;

  -- G2: business files
  update shared_intake_files set move_dest = proposed_destination
   where scan_id = p_scan and not is_folder and moved_at is null and disposition = 'move';
  -- G1 caution: tiny files (< 64 bytes) can match unrelated files by accident, so they move too,
  -- unless a file already sits at the same path in Operations.
  update shared_intake_files f set move_dest = f.path
   where f.scan_id = p_scan and not f.is_folder and f.moved_at is null and f.disposition = 'already_in_cloud' and f.bytes < 64
     and not exists (select 1 from shared_intake_files b where b.scan_id = p_baseline and b.path = f.path);
  -- G4: old rules and status files to the inactive archive
  update shared_intake_files set move_dest = proposed_destination
   where scan_id = p_scan and not is_folder and moved_at is null and disposition = 'archive_rules';

  insert into shared_intake_folder_map (scan_id, path, folder_id, source)
  values (p_scan, '', p_drive_id, 'root') on conflict do nothing;
  insert into shared_intake_folder_map (scan_id, path, folder_id, source)
  select distinct on (path) p_scan, path, file_id, 'baseline' from shared_intake_files
   where scan_id = p_baseline and is_folder and path not like '/%iCloud Intake%'
   order by path, file_id
  on conflict do nothing;

  update shared_intake_scans set detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('move_approval', p_approval)
   where id = p_scan;

  return shared_intake_move_status(p_scan);
end $$;

-- Folders still to create whose parent already exists (one level per call).
create or replace function public.shared_intake_folders_to_create(p_scan uuid, p_limit int default 200)
returns table (path text, name text, parent_id text)
language sql stable security definer set search_path = public, pg_temp as $$
  with dirs as (
    select distinct regexp_replace(move_dest, '/[^/]*$', '') d from shared_intake_files
     where scan_id = p_scan and move_dest is not null and moved_at is null
  ), parts as (
    select distinct array_to_string((string_to_array(d, '/'))[1:i], '/') p
      from dirs, generate_series(2, cardinality(string_to_array(d, '/'))) i
  )
  select parts.p, regexp_replace(parts.p, '^.*/', ''), m.folder_id
    from parts
    join shared_intake_folder_map m on m.scan_id = p_scan and m.path = regexp_replace(parts.p, '/[^/]*$', '')
   where not exists (select 1 from shared_intake_folder_map x where x.scan_id = p_scan and x.path = parts.p)
   order by parts.p limit p_limit;
$$;

-- p_results: [{path, id, ok}]
create or replace function public.shared_intake_record_folders(p_scan uuid, p_results jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  insert into shared_intake_folder_map (scan_id, path, folder_id, source)
  select p_scan, r->>'path', r->>'id', 'created' from jsonb_array_elements(p_results) r
   where (r->>'ok')::boolean and r->>'id' is not null
  on conflict do nothing;
  get diagnostics n = row_count;
  return jsonb_build_object('recorded', n, 'failed', (select count(*) from jsonb_array_elements(p_results) r where not (r->>'ok')::boolean));
end $$;

-- Files ready to move (destination folder exists).
create or replace function public.shared_intake_files_to_move(p_scan uuid, p_limit int default 300)
returns table (file_id text, old_parent text, new_parent text, move_dest text)
language sql stable security definer set search_path = public, pg_temp as $$
  select f.file_id, f.parent_id, m.folder_id, f.move_dest
    from shared_intake_files f
    join shared_intake_folder_map m on m.scan_id = p_scan and m.path = regexp_replace(f.move_dest, '/[^/]*$', '')
   where f.scan_id = p_scan and not f.is_folder and f.move_dest is not null and f.moved_at is null and f.move_error is null
   order by f.path limit p_limit;
$$;

-- p_results: [{file_id, ok, parents, error}]
create or replace function public.shared_intake_record_moves(p_scan uuid, p_results jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update shared_intake_files f set moved_at = now(), moved_to_parent = r->>'parents', move_error = null
    from jsonb_array_elements(p_results) r
   where f.scan_id = p_scan and f.file_id = r->>'file_id' and (r->>'ok')::boolean;
  update shared_intake_files f set move_error = left(coalesce(r->>'error', 'unknown error'), 500)
    from jsonb_array_elements(p_results) r
   where f.scan_id = p_scan and f.file_id = r->>'file_id' and not (r->>'ok')::boolean;
  return shared_intake_move_status(p_scan);
end $$;

create or replace function public.shared_intake_move_status(p_scan uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'planned', count(*) filter (where move_dest is not null),
    'moved', count(*) filter (where moved_at is not null),
    'failed', count(*) filter (where move_error is not null and moved_at is null),
    'waiting', count(*) filter (where move_dest is not null and moved_at is null and move_error is null),
    'folders_known', (select count(*) from shared_intake_folder_map where scan_id = p_scan),
    'folders_created', (select count(*) from shared_intake_folder_map where scan_id = p_scan and source = 'created'))
  from shared_intake_files where scan_id = p_scan and not is_folder;
$$;

revoke all on function public.shared_intake_prepare_moves(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.shared_intake_folders_to_create(uuid, int) from public, anon, authenticated;
revoke all on function public.shared_intake_record_folders(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.shared_intake_files_to_move(uuid, int) from public, anon, authenticated;
revoke all on function public.shared_intake_record_moves(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.shared_intake_move_status(uuid) from public, anon, authenticated;
grant execute on function public.shared_intake_prepare_moves(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.shared_intake_folders_to_create(uuid, int) to service_role;
grant execute on function public.shared_intake_record_folders(uuid, jsonb) to service_role;
grant execute on function public.shared_intake_files_to_move(uuid, int) to service_role;
grant execute on function public.shared_intake_record_moves(uuid, jsonb) to service_role;
grant execute on function public.shared_intake_move_status(uuid) to service_role;
notify pgrst, 'reload schema';
