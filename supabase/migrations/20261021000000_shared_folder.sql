create table if not exists public.shared_files (
  id uuid primary key,
  name text not null check (char_length(name) between 1 and 255),
  storage_path text not null unique,
  size bigint not null check (size between 0 and 4194304),
  content_type text not null,
  created_at timestamptz not null default now()
);

alter table public.shared_files enable row level security;

revoke all on public.shared_files from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('shared-vault', 'shared-vault', false, 4194304, array['application/octet-stream'])
on conflict (id) do update
set public = false, file_size_limit = 4194304,
    allowed_mime_types = array['application/octet-stream'];

alter table storage.objects enable row level security;

create table if not exists public.shared_pin_attempts (
  ip_hash text primary key,
  window_started_at timestamptz not null,
  attempts integer not null
);

alter table public.shared_pin_attempts enable row level security;
revoke all on public.shared_pin_attempts from anon, authenticated;

create or replace function public.record_shared_pin_failure(p_ip_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_attempts integer;
begin
  insert into public.shared_pin_attempts(ip_hash, window_started_at, attempts)
  values (p_ip_hash, now(), 1)
  on conflict (ip_hash) do update
    set attempts = case
      when public.shared_pin_attempts.window_started_at < now() - interval '15 minutes'
        then 1
      else public.shared_pin_attempts.attempts + 1
    end,
    window_started_at = case
      when public.shared_pin_attempts.window_started_at < now() - interval '15 minutes'
        then now()
      else public.shared_pin_attempts.window_started_at
    end
  returning attempts into current_attempts;
  return current_attempts <= 5;
end;
$$;

create table if not exists public.shared_pin_attempts (
  ip_hash text primary key,
  window_started_at timestamptz not null,
  attempts integer not null
);

alter table public.shared_pin_attempts enable row level security;
revoke all on public.shared_pin_attempts from anon, authenticated;

create or replace function public.clear_shared_pin_failures(p_ip_hash text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.shared_pin_attempts where ip_hash = p_ip_hash;
$$;

revoke all on function public.record_shared_pin_failure(text)
  from public, anon, authenticated;
revoke all on function public.clear_shared_pin_failures(text)
  from public, anon, authenticated;
grant execute on function public.record_shared_pin_failure(text) to service_role;
grant execute on function public.clear_shared_pin_failures(text) to service_role;
