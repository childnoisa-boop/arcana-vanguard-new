-- Shared application settings for Nations, Card types, and Deck zones.
create table if not exists public.app_settings (
  setting_key text primary key,
  setting_value jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon;
grant select, insert, update on public.app_settings to authenticated;

drop policy if exists app_settings_read_signed_in on public.app_settings;
drop policy if exists app_settings_insert_signed_in on public.app_settings;
drop policy if exists app_settings_update_signed_in on public.app_settings;
create policy app_settings_read_signed_in on public.app_settings
  for select to authenticated using (true);
create policy app_settings_insert_signed_in on public.app_settings
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy app_settings_update_signed_in on public.app_settings
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);
