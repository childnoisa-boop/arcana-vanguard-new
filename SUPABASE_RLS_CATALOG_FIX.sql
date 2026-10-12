-- Run this in Supabase SQL Editor as the project owner.
-- The app writes catalog data with the authenticated user's id in updated_by.
-- These policies allow signed-in users to manage the shared catalog, as designed.

begin;

grant select, insert, update, delete on table public.catalog_cards to authenticated;
grant select, insert, update, delete on table public.catalog_products to authenticated;
grant select, insert, update, delete on table public.product_cards to authenticated;

drop policy if exists catalog_cards_authenticated_select on public.catalog_cards;
drop policy if exists catalog_cards_authenticated_insert on public.catalog_cards;
drop policy if exists catalog_cards_authenticated_update on public.catalog_cards;
drop policy if exists catalog_cards_authenticated_delete on public.catalog_cards;

create policy catalog_cards_authenticated_select
  on public.catalog_cards for select to authenticated
  using (auth.uid() is not null);

create policy catalog_cards_authenticated_insert
  on public.catalog_cards for insert to authenticated
  with check (auth.uid() is not null and updated_by = auth.uid());

create policy catalog_cards_authenticated_update
  on public.catalog_cards for update to authenticated
  using (auth.uid() is not null)
  with check (auth.uid() is not null and updated_by = auth.uid());

create policy catalog_cards_authenticated_delete
  on public.catalog_cards for delete to authenticated
  using (auth.uid() is not null);

commit;
