grant delete on public.vault_settings to authenticated;

drop policy if exists vault_settings_delete_own on public.vault_settings;
create policy vault_settings_delete_own on public.vault_settings
  for delete to authenticated
  using ((select auth.uid()) = user_id);
