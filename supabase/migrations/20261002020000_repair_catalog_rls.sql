-- Repair catalog write permissions for authenticated users.
-- Safe to run on an existing project: this only replaces the catalog policies.

alter table public.catalog_products enable row level security;
alter table public.catalog_cards enable row level security;
alter table public.product_cards enable row level security;

grant select, insert, update on public.catalog_products to authenticated;
grant select, insert, update on public.catalog_cards to authenticated;
grant select, insert, update, delete on public.product_cards to authenticated;

drop policy if exists products_read_signed_in on public.catalog_products;
drop policy if exists products_insert_signed_in on public.catalog_products;
drop policy if exists products_update_signed_in on public.catalog_products;
create policy products_read_signed_in on public.catalog_products
  for select to authenticated
  using (deleted_at is null);
create policy products_insert_signed_in on public.catalog_products
  for insert to authenticated
  with check ((select auth.uid()) is not null);
create policy products_update_signed_in on public.catalog_products
  for update to authenticated
  using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);

drop policy if exists cards_read_signed_in on public.catalog_cards;
drop policy if exists cards_insert_signed_in on public.catalog_cards;
drop policy if exists cards_update_signed_in on public.catalog_cards;
create policy cards_read_signed_in on public.catalog_cards
  for select to authenticated
  using (deleted_at is null);
create policy cards_insert_signed_in on public.catalog_cards
  for insert to authenticated
  with check ((select auth.uid()) is not null);
create policy cards_update_signed_in on public.catalog_cards
  for update to authenticated
  using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);

drop policy if exists product_cards_read_signed_in on public.product_cards;
drop policy if exists product_cards_insert_signed_in on public.product_cards;
drop policy if exists product_cards_update_signed_in on public.product_cards;
drop policy if exists product_cards_delete_signed_in on public.product_cards;
create policy product_cards_read_signed_in on public.product_cards
  for select to authenticated
  using (true);
create policy product_cards_insert_signed_in on public.product_cards
  for insert to authenticated
  with check ((select auth.uid()) is not null);
create policy product_cards_update_signed_in on public.product_cards
  for update to authenticated
  using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);
create policy product_cards_delete_signed_in on public.product_cards
  for delete to authenticated
  using ((select auth.uid()) is not null);
