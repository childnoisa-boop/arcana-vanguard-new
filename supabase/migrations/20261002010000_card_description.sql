-- Add card descriptions for existing Supabase projects.
alter table public.catalog_cards
  add column if not exists description text not null default '';

alter table public.catalog_cards
  drop constraint if exists catalog_cards_description_length;

alter table public.catalog_cards
  add constraint catalog_cards_description_length check (char_length(description) <= 2000);
