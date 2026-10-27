create table if not exists public.vault_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  kdf_salt text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.vault_metadata (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null check (id ~ '^[0-9a-f]{32}$'),
  payload text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, id)
);

alter table public.vault_settings enable row level security;
alter table public.vault_metadata enable row level security;

revoke all on public.vault_settings from anon, authenticated;
revoke all on public.vault_metadata from anon, authenticated;
grant select, insert on public.vault_settings to authenticated;
grant select, insert, update, delete on public.vault_metadata to authenticated;

drop policy if exists vault_settings_select_own on public.vault_settings;
create policy vault_settings_select_own on public.vault_settings
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists vault_settings_insert_own on public.vault_settings;
create policy vault_settings_insert_own on public.vault_settings
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists vault_metadata_select_own on public.vault_metadata;
create policy vault_metadata_select_own on public.vault_metadata
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists vault_metadata_insert_own on public.vault_metadata;
create policy vault_metadata_insert_own on public.vault_metadata
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists vault_metadata_update_own on public.vault_metadata;
create policy vault_metadata_update_own on public.vault_metadata
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists vault_metadata_delete_own on public.vault_metadata;
create policy vault_metadata_delete_own on public.vault_metadata
  for delete to authenticated
  using ((select auth.uid()) = user_id);
