-- Admin-only Banlist and gacha-rate controls.
-- Run this migration, then run the one-line bootstrap UPDATE at the bottom
-- after replacing the email with the account that should be the administrator.

alter table public.profiles
  add column if not exists is_admin boolean not null default false;

grant select (id, display_name, is_admin, updated_at) on public.profiles to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_admin = true
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Keep normal card/product editing available, but prevent non-admin users
-- from changing the gacha weight JSON hidden in catalog_products.
create or replace function public.guard_gacha_weights_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin()
     and new.gacha_weights is distinct from old.gacha_weights then
    raise exception 'Only an administrator can change gacha rates';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_gacha_weights_admin() from public;

drop trigger if exists catalog_products_gacha_weights_admin on public.catalog_products;
create trigger catalog_products_gacha_weights_admin
before update on public.catalog_products
for each row execute function public.guard_gacha_weights_admin();

-- Everyone signed in may read the Banlist, but only admins may create,
-- edit, or soft-delete rules and rule-card links.
drop policy if exists banlist_rules_insert_signed_in on public.banlist_rules;
drop policy if exists banlist_rules_update_signed_in on public.banlist_rules;
drop policy if exists banlist_rule_cards_insert_signed_in on public.banlist_rule_cards;
drop policy if exists banlist_rule_cards_update_signed_in on public.banlist_rule_cards;
create policy banlist_rules_insert_admin on public.banlist_rules
  for insert to authenticated
  with check (public.is_admin());
create policy banlist_rules_update_admin on public.banlist_rules
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
create policy banlist_rule_cards_insert_admin on public.banlist_rule_cards
  for insert to authenticated
  with check (public.is_admin());
create policy banlist_rule_cards_update_admin on public.banlist_rule_cards
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Bootstrap the first administrator. Replace the email and run separately
-- in SQL Editor after this migration succeeds:
-- update public.profiles p
-- set is_admin = true
-- from auth.users u
-- where u.id = p.id and lower(u.email) = lower('YOUR-ADMIN-EMAIL@example.com');
