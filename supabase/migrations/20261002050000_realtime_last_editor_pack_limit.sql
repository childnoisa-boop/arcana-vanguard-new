-- Last-editor metadata for shared catalog data.
alter table public.catalog_products
  add column if not exists updated_by uuid references auth.users(id);
alter table public.catalog_cards
  add column if not exists updated_by uuid references auth.users(id);

-- Allow the client to display the last editor alongside the existing public profile name.
grant select (id, display_name, is_admin, updated_at) on public.profiles to authenticated;

-- Enable Supabase Realtime for catalog changes. The DO block is idempotent.
do $$
begin
  begin alter publication supabase_realtime add table public.catalog_products; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.catalog_cards; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.product_cards; exception when duplicate_object then null; end;
end $$;
