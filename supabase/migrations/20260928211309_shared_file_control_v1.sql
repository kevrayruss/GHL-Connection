-- Applied to GR-OS (qojmscymgleaqyjcvuaa) on 2026-09-28 as migration 20260928211309 "shared_file_control_v1".
-- Task 03: exclusive file ownership (claims + fencing tokens + immutable versions + append-only events).
-- Additive only. Writes happen exclusively through the shared_* functions below (service_role / n8n).

create table public.shared_resources (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.shared_workspaces(id),
  project_id uuid not null references public.shared_projects(id),
  file_reference_id uuid references public.shared_file_references(id),
  provider text not null default 'google_drive',
  external_file_id text not null,
  name text not null,
  current_version_id uuid,
  fence_seq bigint not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, provider, external_file_id)
);
comment on table public.shared_resources is 'Task 03 file control: one row per managed logical file. fence_seq increases on every successful claim; only the holder of the newest fence token may commit.';

create table public.shared_resource_versions (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id),
  version_no integer not null,
  parent_version_id uuid references public.shared_resource_versions(id),
  storage_object_id text not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  bytes bigint not null check (bytes >= 0),
  claim_id uuid,
  fence_token bigint not null,
  agent text not null,
  runtime text not null,
  session_id text not null,
  note text,
  created_at timestamptz not null default now(),
  unique (resource_id, version_no)
);
comment on table public.shared_resource_versions is 'Task 03 file control: immutable version objects. Never updated; current content = shared_resources.current_version_id.';

alter table public.shared_resources
  add constraint shared_resources_current_version_fk
  foreign key (current_version_id) references public.shared_resource_versions(id);

create table public.shared_claims (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id),
  fence_token bigint not null,
  agent text not null check (agent in ('claude','chatgpt','human','n8n')),
  runtime text not null,
  session_id text not null,
  purpose text not null,
  status text not null default 'active' check (status in ('active','released','expired')),
  acquired_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  unique (resource_id, fence_token)
);
create unique index shared_claims_one_active on public.shared_claims(resource_id) where status = 'active';
comment on table public.shared_claims is 'Task 03 file control: edit leases. At most one active claim per resource (unique partial index).';

create table public.shared_events (
  id bigserial primary key,
  occurred_at timestamptz not null default now(),
  workspace_id uuid,
  project_id uuid,
  resource_id uuid,
  claim_id uuid,
  version_id uuid,
  event_type text not null,
  outcome text not null,
  agent text,
  runtime text,
  session_id text,
  operation_id uuid unique,
  detail jsonb not null default '{}'::jsonb
);
create index shared_events_resource_idx on public.shared_events(resource_id, occurred_at);
comment on table public.shared_events is 'Task 03 file control: append-only activity log. operation_id makes retries return the original result.';

create or replace function shared_private.block_event_mutation() returns trigger
language plpgsql as $$ begin raise exception 'shared_events is append-only'; end $$;
create trigger shared_events_append_only before update or delete on public.shared_events
  for each row execute function shared_private.block_event_mutation();

create or replace function shared_private.block_version_mutation() returns trigger
language plpgsql as $$ begin raise exception 'shared_resource_versions is immutable'; end $$;
create trigger shared_versions_immutable before update or delete on public.shared_resource_versions
  for each row execute function shared_private.block_version_mutation();

-- RLS: members read; no direct writes from client roles.
alter table public.shared_resources enable row level security;
alter table public.shared_resource_versions enable row level security;
alter table public.shared_claims enable row level security;
alter table public.shared_events enable row level security;
create policy shared_resources_read on public.shared_resources for select using (shared_is_workspace_member(workspace_id));
create policy shared_versions_read on public.shared_resource_versions for select using (exists (select 1 from public.shared_resources r where r.id = resource_id and shared_is_workspace_member(r.workspace_id)));
create policy shared_claims_read on public.shared_claims for select using (exists (select 1 from public.shared_resources r where r.id = resource_id and shared_is_workspace_member(r.workspace_id)));
create policy shared_events_read on public.shared_events for select using (workspace_id is not null and shared_is_workspace_member(workspace_id));
revoke insert, update, delete, truncate on public.shared_resources, public.shared_resource_versions, public.shared_claims, public.shared_events from anon, authenticated;

-- Helpers ---------------------------------------------------------------
create or replace function shared_private.replay(p_operation_id uuid) returns jsonb
language sql stable as $$
  select detail->'result' from public.shared_events where operation_id = p_operation_id
$$;

create or replace function shared_private.log(
  p_res public.shared_resources, p_claim_id uuid, p_version_id uuid, p_type text, p_outcome text,
  p_agent text, p_runtime text, p_session text, p_operation_id uuid, p_result jsonb, p_extra jsonb default '{}'::jsonb)
returns jsonb language plpgsql as $$
begin
  insert into public.shared_events(workspace_id, project_id, resource_id, claim_id, version_id, event_type, outcome,
                                   agent, runtime, session_id, operation_id, detail)
  values (p_res.workspace_id, p_res.project_id, p_res.id, p_claim_id, p_version_id, p_type, p_outcome,
          p_agent, p_runtime, p_session, p_operation_id, p_extra || jsonb_build_object('result', p_result));
  return p_result;
end $$;

create or replace function shared_private.expire_stale(p_res public.shared_resources) returns void
language plpgsql as $$
declare c public.shared_claims;
begin
  for c in update public.shared_claims set status = 'expired', ended_at = now()
           where resource_id = p_res.id and status = 'active' and expires_at <= now() returning * loop
    perform shared_private.log(p_res, c.id, null, 'claim_expired', 'expired', c.agent, c.runtime, c.session_id, null,
      jsonb_build_object('claim_id', c.id, 'fence_token', c.fence_token, 'expired_at', c.expires_at));
  end loop;
end $$;

-- Public API (service_role only) -----------------------------------------
create or replace function public.shared_register_resource(
  p_workspace_id uuid, p_project_id uuid, p_external_file_id text, p_name text,
  p_agent text, p_runtime text, p_session text, p_operation_id uuid,
  p_provider text default 'google_drive', p_file_reference_id uuid default null, p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare prior jsonb; r public.shared_resources; created boolean := false;
begin
  prior := shared_private.replay(p_operation_id); if prior is not null then return prior || '{"replayed":true}'; end if;
  insert into public.shared_resources(workspace_id, project_id, provider, external_file_id, name, file_reference_id, metadata)
  values (p_workspace_id, p_project_id, p_provider, p_external_file_id, p_name, p_file_reference_id, coalesce(p_metadata,'{}'))
  on conflict (workspace_id, provider, external_file_id) do nothing returning * into r;
  if found then created := true; else
    select * into r from public.shared_resources where workspace_id = p_workspace_id and provider = p_provider and external_file_id = p_external_file_id;
  end if;
  return shared_private.log(r, null, null, 'resource_registered', case when created then 'created' else 'already_registered' end,
    p_agent, p_runtime, p_session, p_operation_id,
    jsonb_build_object('ok', true, 'resource_id', r.id, 'created', created, 'current_version_id', r.current_version_id));
end $$;

create or replace function public.shared_claim_resource(
  p_resource_id uuid, p_agent text, p_runtime text, p_session text, p_purpose text, p_operation_id uuid, p_ttl_seconds integer default 900)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare prior jsonb; r public.shared_resources; c public.shared_claims;
begin
  prior := shared_private.replay(p_operation_id); if prior is not null then return prior || '{"replayed":true}'; end if;
  if p_ttl_seconds < 30 or p_ttl_seconds > 7200 then raise exception 'ttl must be between 30 and 7200 seconds'; end if;
  select * into r from public.shared_resources where id = p_resource_id for update;
  if not found then raise exception 'unknown resource %', p_resource_id; end if;
  perform shared_private.expire_stale(r);
  select * into c from public.shared_claims where resource_id = r.id and status = 'active';
  if found then
    return shared_private.log(r, c.id, null, 'claim_rejected', 'conflict', p_agent, p_runtime, p_session, p_operation_id,
      jsonb_build_object('ok', false, 'error', 'resource is claimed', 'holder_agent', c.agent, 'holder_runtime', c.runtime,
        'holder_session', c.session_id, 'holder_purpose', c.purpose, 'holder_expires_at', c.expires_at),
      jsonb_build_object('purpose', p_purpose));
  end if;
  update public.shared_resources set fence_seq = fence_seq + 1, updated_at = now() where id = r.id returning * into r;
  insert into public.shared_claims(resource_id, fence_token, agent, runtime, session_id, purpose, expires_at)
  values (r.id, r.fence_seq, p_agent, p_runtime, p_session, p_purpose, now() + make_interval(secs => p_ttl_seconds)) returning * into c;
  return shared_private.log(r, c.id, null, 'claim_acquired', 'ok', p_agent, p_runtime, p_session, p_operation_id,
    jsonb_build_object('ok', true, 'claim_id', c.id, 'fence_token', c.fence_token, 'expires_at', c.expires_at,
      'current_version_id', r.current_version_id), jsonb_build_object('purpose', p_purpose));
end $$;

create or replace function public.shared_renew_claim(p_claim_id uuid, p_fence_token bigint, p_operation_id uuid, p_ttl_seconds integer default 900)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare prior jsonb; r public.shared_resources; c public.shared_claims;
begin
  prior := shared_private.replay(p_operation_id); if prior is not null then return prior || '{"replayed":true}'; end if;
  if p_ttl_seconds < 30 or p_ttl_seconds > 7200 then raise exception 'ttl must be between 30 and 7200 seconds'; end if;
  select res.* into r from public.shared_resources res join public.shared_claims cl on cl.resource_id = res.id where cl.id = p_claim_id for update of res;
  if not found then raise exception 'unknown claim %', p_claim_id; end if;
  perform shared_private.expire_stale(r);
  select * into c from public.shared_claims where id = p_claim_id;
  if c.status <> 'active' or c.fence_token <> p_fence_token or r.fence_seq <> p_fence_token then
    return shared_private.log(r, c.id, null, 'renew_rejected', 'stale_claim', c.agent, c.runtime, c.session_id, p_operation_id,
      jsonb_build_object('ok', false, 'error', 'claim is no longer current', 'claim_status', c.status, 'current_fence', r.fence_seq));
  end if;
  update public.shared_claims set expires_at = now() + make_interval(secs => p_ttl_seconds) where id = c.id returning * into c;
  return shared_private.log(r, c.id, null, 'claim_renewed', 'ok', c.agent, c.runtime, c.session_id, p_operation_id,
    jsonb_build_object('ok', true, 'claim_id', c.id, 'fence_token', c.fence_token, 'expires_at', c.expires_at));
end $$;

create or replace function public.shared_release_claim(p_claim_id uuid, p_fence_token bigint, p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare prior jsonb; r public.shared_resources; c public.shared_claims;
begin
  prior := shared_private.replay(p_operation_id); if prior is not null then return prior || '{"replayed":true}'; end if;
  select res.* into r from public.shared_resources res join public.shared_claims cl on cl.resource_id = res.id where cl.id = p_claim_id for update of res;
  if not found then raise exception 'unknown claim %', p_claim_id; end if;
  perform shared_private.expire_stale(r);
  select * into c from public.shared_claims where id = p_claim_id;
  if c.status <> 'active' or c.fence_token <> p_fence_token then
    return shared_private.log(r, c.id, null, 'release_rejected', 'stale_claim', c.agent, c.runtime, c.session_id, p_operation_id,
      jsonb_build_object('ok', false, 'error', 'claim is no longer current', 'claim_status', c.status));
  end if;
  update public.shared_claims set status = 'released', ended_at = now() where id = c.id returning * into c;
  return shared_private.log(r, c.id, null, 'claim_released', 'ok', c.agent, c.runtime, c.session_id, p_operation_id,
    jsonb_build_object('ok', true, 'claim_id', c.id));
end $$;

create or replace function public.shared_commit_version(
  p_claim_id uuid, p_fence_token bigint, p_base_version_id uuid, p_storage_object_id text, p_sha256 text, p_bytes bigint,
  p_operation_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare prior jsonb; r public.shared_resources; c public.shared_claims; v public.shared_resource_versions; next_no integer;
begin
  prior := shared_private.replay(p_operation_id); if prior is not null then return prior || '{"replayed":true}'; end if;
  select res.* into r from public.shared_resources res join public.shared_claims cl on cl.resource_id = res.id where cl.id = p_claim_id for update of res;
  if not found then raise exception 'unknown claim %', p_claim_id; end if;
  perform shared_private.expire_stale(r);
  select * into c from public.shared_claims where id = p_claim_id;
  if c.status <> 'active' or c.fence_token <> p_fence_token or r.fence_seq <> p_fence_token then
    return shared_private.log(r, c.id, null, 'commit_rejected', 'stale_claim', c.agent, c.runtime, c.session_id, p_operation_id,
      jsonb_build_object('ok', false, 'error', 'claim is no longer current; nothing was promoted', 'claim_status', c.status, 'current_fence', r.fence_seq),
      jsonb_build_object('storage_object_id', p_storage_object_id, 'sha256', p_sha256));
  end if;
  if r.current_version_id is distinct from p_base_version_id then
    return shared_private.log(r, c.id, null, 'commit_rejected', 'stale_base', c.agent, c.runtime, c.session_id, p_operation_id,
      jsonb_build_object('ok', false, 'error', 'edit was based on an old version; nothing was promoted', 'current_version_id', r.current_version_id),
      jsonb_build_object('storage_object_id', p_storage_object_id, 'sha256', p_sha256));
  end if;
  select coalesce(max(version_no), 0) + 1 into next_no from public.shared_resource_versions where resource_id = r.id;
  insert into public.shared_resource_versions(resource_id, version_no, parent_version_id, storage_object_id, sha256, bytes,
    claim_id, fence_token, agent, runtime, session_id, note)
  values (r.id, next_no, p_base_version_id, p_storage_object_id, lower(p_sha256), p_bytes, c.id, c.fence_token, c.agent, c.runtime, c.session_id, p_note)
  returning * into v;
  update public.shared_resources set current_version_id = v.id, updated_at = now() where id = r.id;
  return shared_private.log(r, c.id, v.id, 'version_committed', 'ok', c.agent, c.runtime, c.session_id, p_operation_id,
    jsonb_build_object('ok', true, 'version_id', v.id, 'version_no', v.version_no, 'sha256', v.sha256, 'bytes', v.bytes));
end $$;

revoke all on function public.shared_register_resource(uuid,uuid,text,text,text,text,text,uuid,text,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.shared_claim_resource(uuid,text,text,text,text,uuid,integer) from public, anon, authenticated;
revoke all on function public.shared_renew_claim(uuid,bigint,uuid,integer) from public, anon, authenticated;
revoke all on function public.shared_release_claim(uuid,bigint,uuid) from public, anon, authenticated;
revoke all on function public.shared_commit_version(uuid,bigint,uuid,text,text,bigint,uuid,text) from public, anon, authenticated;
grant execute on function public.shared_register_resource(uuid,uuid,text,text,text,text,text,uuid,text,uuid,jsonb) to service_role;
grant execute on function public.shared_claim_resource(uuid,text,text,text,text,uuid,integer) to service_role;
grant execute on function public.shared_renew_claim(uuid,bigint,uuid,integer) to service_role;
grant execute on function public.shared_release_claim(uuid,bigint,uuid) to service_role;
grant execute on function public.shared_commit_version(uuid,bigint,uuid,text,text,bigint,uuid,text) to service_role;
revoke all on function shared_private.replay(uuid), shared_private.expire_stale(public.shared_resources) from public, anon, authenticated;
