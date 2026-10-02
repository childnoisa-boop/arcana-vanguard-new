-- Harden the shared catalog policies on projects that may still have an older
-- admin-only or restrictive policy from an earlier draft.
-- The catalog is shared data: any authenticated user may manage it. RLS still
-- blocks anonymous requests because every policy below is scoped to authenticated.

alter table public.catalog_products enable row level security;
alter table public.catalog_cards enable row level security;
alter table public.product_cards enable row level security;

grant select, insert, update on public.catalog_products to authenticated;
grant select, insert, update on public.catalog_cards to authenticated;
grant select, insert, update, delete on public.product_cards to authenticated;

-- Remove any older restrictive policy names that may exist on an already-used project.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('catalog_products', 'catalog_cards', 'product_cards')
  loop
    execute format('drop policy if exists %I on %I.%I', policy_row.policyname, policy_row.schemaname, policy_row.tablename);
  end loop;
end $$;

drop policy if exists products_read_signed_in on public.catalog_products;
drop policy if exists products_insert_signed_in on public.catalog_products;
drop policy if exists products_update_signed_in on public.catalog_products;
drop policy if exists products_insert_admin on public.catalog_products;
drop policy if exists products_update_admin on public.catalog_products;
create policy products_read_authenticated on public.catalog_products
  for select to authenticated using (deleted_at is null);
create policy products_insert_authenticated on public.catalog_products
  for insert to authenticated with check (true);
create policy products_update_authenticated on public.catalog_products
  for update to authenticated using (true) with check (true);

drop policy if exists cards_read_signed_in on public.catalog_cards;
drop policy if exists cards_insert_signed_in on public.catalog_cards;
drop policy if exists cards_update_signed_in on public.catalog_cards;
drop policy if exists cards_insert_admin on public.catalog_cards;
drop policy if exists cards_update_admin on public.catalog_cards;
create policy cards_read_authenticated on public.catalog_cards
  for select to authenticated using (deleted_at is null);
create policy cards_insert_authenticated on public.catalog_cards
  for insert to authenticated with check (true);
create policy cards_update_authenticated on public.catalog_cards
  for update to authenticated using (true) with check (true);

drop policy if exists product_cards_read_signed_in on public.product_cards;
drop policy if exists product_cards_insert_signed_in on public.product_cards;
drop policy if exists product_cards_update_signed_in on public.product_cards;
drop policy if exists product_cards_delete_signed_in on public.product_cards;
drop policy if exists product_cards_insert_admin on public.product_cards;
drop policy if exists product_cards_update_admin on public.product_cards;
create policy product_cards_read_authenticated on public.product_cards
  for select to authenticated using (true);
create policy product_cards_insert_authenticated on public.product_cards
  for insert to authenticated with check (true);
create policy product_cards_update_authenticated on public.product_cards
  for update to authenticated using (true) with check (true);
create policy product_cards_delete_authenticated on public.product_cards
  for delete to authenticated using (true);
