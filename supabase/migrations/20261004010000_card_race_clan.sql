-- Add searchable Vanguard card metadata for existing Supabase projects.
alter table public.catalog_cards
  add column if not exists race text not null default '';

alter table public.catalog_cards
  add column if not exists clan text not null default '';

create index if not exists catalog_cards_race_idx on public.catalog_cards (lower(race));
create index if not exists catalog_cards_clan_idx on public.catalog_cards (lower(clan));

alter table public.catalog_cards
  add column if not exists icon text not null default '';

create index if not exists catalog_cards_icon_idx on public.catalog_cards (lower(icon));
