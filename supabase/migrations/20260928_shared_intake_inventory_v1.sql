-- Applied to GR-OS (qojmscymgleaqyjcvuaa) on 2026-09-28 as migration "shared_intake_inventory_v1".
-- Migration inventory: one row per file found under an intake root in a given scan.
create table public.shared_intake_scans (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.shared_workspaces(id),
  project_id uuid not null references public.shared_projects(id),
  root_folder_id text not null,
  label text not null,
  status text not null default 'running' check (status in ('running','complete','failed')),
  files_found integer,
  folders_found integer,
  bytes_found bigint,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  detail jsonb not null default '{}'::jsonb
);
comment on table public.shared_intake_scans is 'Migration inventory runs over a Drive intake folder. Written by n8n (service_role) only.';

create table public.shared_intake_files (
  scan_id uuid not null references public.shared_intake_scans(id),
  file_id text not null,
  parent_id text,
  name text not null,
  path text not null,
  mime_type text not null,
  is_folder boolean not null,
  bytes bigint,
  sha256 text,
  md5 text,
  created_time timestamptz,
  modified_time timestamptz,
  disposition text check (disposition in ('already_in_cloud','move','duplicate','older_version','corrupt','exclude_private','review')),
  disposition_reason text,
  primary key (scan_id, file_id)
);
create index shared_intake_files_sha_idx on public.shared_intake_files(sha256);
create index shared_intake_files_md5_idx on public.shared_intake_files(md5);
create index shared_intake_files_path_idx on public.shared_intake_files(scan_id, path);
comment on table public.shared_intake_files is 'Files discovered in an intake scan, with full path and Drive checksums, plus the proposed disposition Kevin approves before anything moves.';

alter table public.shared_intake_scans enable row level security;
alter table public.shared_intake_files enable row level security;
create policy shared_intake_scans_read on public.shared_intake_scans for select using (shared_is_workspace_member(workspace_id));
create policy shared_intake_files_read on public.shared_intake_files for select using (exists (select 1 from public.shared_intake_scans s where s.id = scan_id and shared_is_workspace_member(s.workspace_id)));
revoke insert, update, delete, truncate on public.shared_intake_scans, public.shared_intake_files from anon, authenticated;
