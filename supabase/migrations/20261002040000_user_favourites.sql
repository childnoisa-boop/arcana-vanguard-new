-- Per-user Favourite cards.
create table if not exists public.user_favorite_cards (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null references public.catalog_cards(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

alter table public.user_favorite_cards enable row level security;
revoke all on public.user_favorite_cards from anon;
grant select, insert, delete on public.user_favorite_cards to authenticated;

drop policy if exists favourites_read_own on public.user_favorite_cards;
drop policy if exists favourites_insert_own on public.user_favorite_cards;
drop policy if exists favourites_delete_own on public.user_favorite_cards;
create policy favourites_read_own on public.user_favorite_cards
  for select to authenticated using (user_id = (select auth.uid()));
create policy favourites_insert_own on public.user_favorite_cards
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy favourites_delete_own on public.user_favorite_cards
  for delete to authenticated using (user_id = (select auth.uid()));
