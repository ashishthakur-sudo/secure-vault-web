alter table public.shared_files
  drop constraint if exists shared_files_size_check;

alter table public.shared_files
  add constraint shared_files_size_check
  check (size between 0 and 20971520) not valid,
  add constraint shared_files_allowed_extension_check
  check (name ~* '\.(pdf|png|jpg|mp4|mp3)$') not valid;

alter table public.shared_files enable row level security;
alter table public.shared_folder_settings enable row level security;
alter table public.shared_pin_attempts enable row level security;

revoke all on public.shared_files from anon, authenticated;
revoke all on public.shared_folder_settings from anon, authenticated;
revoke all on public.shared_pin_attempts from anon, authenticated;

drop policy if exists deny_shared_files_client_access on public.shared_files;
create policy deny_shared_files_client_access on public.shared_files
  as restrictive for all to anon, authenticated
  using (false) with check (false);

drop policy if exists deny_shared_settings_client_access
  on public.shared_folder_settings;
create policy deny_shared_settings_client_access
  on public.shared_folder_settings
  as restrictive for all to anon, authenticated
  using (false) with check (false);

drop policy if exists deny_shared_pin_attempts_client_access
  on public.shared_pin_attempts;
create policy deny_shared_pin_attempts_client_access
  on public.shared_pin_attempts
  as restrictive for all to anon, authenticated
  using (false) with check (false);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'shared-vault',
  'shared-vault',
  false,
  20971520,
  array['application/pdf', 'image/png', 'image/jpeg', 'video/mp4', 'audio/mpeg']
)
on conflict (id) do update
set public = false,
    file_size_limit = 20971520,
    allowed_mime_types = excluded.allowed_mime_types;
