-- DRAFT ONLY: review and test in a local Supabase project before applying remotely.
-- This is a fresh-schema proposal; adapt names if the project already has catalog tables.
-- Authenticated users can manage the shared catalog and Banlist, and create shared recipes.
-- All users can use recipes; only a recipe creator can edit/deactivate that recipe.
-- Decks/collections/craft history are owner-scoped. Inventory changes happen through RPCs.

begin;

-- -----------------------------------------------------------------------------
-- 1. Profiles (public display name only; never expose auth.users email in the feed)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Player'
    check (char_length(display_name) between 1 and 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Player')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- -----------------------------------------------------------------------------
-- 2. Shared catalog: referenced by Deck Builder, Banlist, and craft recipes
-- -----------------------------------------------------------------------------
create table public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  product_code text,
  name text not null,
  product_type text not null default 'Others',
  release_year smallint,
  cover_url text,
  cover_fit jsonb not null default '{"mode":"auto"}'::jsonb,
  gacha_weights jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.catalog_cards (
  id uuid primary key default gen_random_uuid(),
  card_no text not null,
  name text not null,
  race text not null default '',
  clan text not null default '',
  icon text not null default '',
  nation text,
  second_nation text,
  card_type text,
  grade smallint,
  power integer,
  shield integer,
  rarity text not null default 'C',
  description text not null default '' check (char_length(description) <= 2000),
  trigger_type text,
  image_url text,
  image_fit jsonb,
  orientation text check (orientation is null or orientation in ('p', 'l')),
  attributes jsonb not null default '{}'::jsonb,
  is_gacha_pool boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index catalog_cards_card_no_idx on public.catalog_cards (card_no);
create index catalog_cards_name_idx on public.catalog_cards (lower(name));
create index catalog_cards_rarity_idx on public.catalog_cards (rarity);
create index catalog_cards_race_idx on public.catalog_cards (lower(race));
create index catalog_cards_clan_idx on public.catalog_cards (lower(clan));
create index catalog_cards_icon_idx on public.catalog_cards (lower(icon));

create table public.product_cards (
  product_id uuid not null references public.catalog_products(id) on delete cascade,
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  product_card_no text,
  created_at timestamptz not null default now(),
  primary key (product_id, card_id)
);

-- -----------------------------------------------------------------------------
-- 3. Private collection (craft materials are taken from this table only)
-- -----------------------------------------------------------------------------
create table public.user_collection_cards (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

-- Per-account pack count, pity, and reset preference; card ownership remains normalized above.
create table public.user_gacha_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pity_count integer not null default 0 check (pity_count between 0 and 200),
  packs_opened bigint not null default 0 check (packs_opened >= 0),
  pity_reset_on_high boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Private audit trail of pulls; only an explicit share RPC creates a public feed item.
create table public.gacha_pack_opens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.catalog_products(id) on delete restrict,
  opened_at timestamptz not null default now()
);

create table public.gacha_pack_open_cards (
  pack_open_id uuid not null references public.gacha_pack_opens(id) on delete cascade,
  slot_number smallint not null check (slot_number between 1 and 7),
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  rarity_snapshot text not null,
  primary key (pack_open_id, slot_number)
);

create table public.rare_pull_feed_events (
  id uuid primary key default gen_random_uuid(),
  pack_open_id uuid not null,
  slot_number smallint not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  display_name_snapshot text not null,
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  card_name_snapshot text not null,
  rarity_snapshot text not null,
  product_name_snapshot text not null,
  created_at timestamptz not null default now(),
  unique (pack_open_id, slot_number),
  foreign key (pack_open_id, slot_number)
    references public.gacha_pack_open_cards(pack_open_id, slot_number) on delete cascade
);

create index gacha_pack_opens_user_date_idx on public.gacha_pack_opens (user_id, opened_at desc);
create index rare_pull_feed_events_date_idx on public.rare_pull_feed_events (created_at desc);

-- -----------------------------------------------------------------------------
-- 4. Deck Builder: owner-private unless the owner explicitly shares a deck
-- -----------------------------------------------------------------------------
create table public.decks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My deck',
  description text not null default '' check (char_length(description) <= 2000),
  is_shared boolean not null default false,
  shared_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (owner_id, name),
  check (not is_shared or deleted_at is null)
);

create or replace function public.set_deck_share_timestamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_shared then
    if tg_op = 'INSERT' then
      new.shared_at := coalesce(new.shared_at, now());
    elsif not old.is_shared then
      new.shared_at := now();
    else
      new.shared_at := coalesce(new.shared_at, old.shared_at, now());
    end if;
  else
    new.shared_at := null;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger decks_set_share_timestamp
before insert or update on public.decks
for each row execute function public.set_deck_share_timestamp();

create index decks_owner_updated_idx on public.decks (owner_id, updated_at desc);
create index decks_shared_idx on public.decks (shared_at desc) where is_shared and deleted_at is null;

create table public.deck_cards (
  deck_id uuid not null references public.decks(id) on delete cascade,
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  zone_key text not null check (zone_key in ('main', 'ride', 'g', 'token')),
  quantity integer not null check (quantity > 0),
  updated_at timestamptz not null default now(),
  primary key (deck_id, card_id, zone_key)
);

create index deck_cards_card_idx on public.deck_cards (card_id);

-- Deck construction rules are validated by the app / a validation RPC:
-- Main Deck target = 50; Ride Deck minimum = 4, no hard maximum; counted separately.
-- Sharing a deck never grants write access to another user's deck.

-- -----------------------------------------------------------------------------
-- 5. Shared Banlist: all authenticated users can add/edit/soft-delete rules
-- -----------------------------------------------------------------------------
create table public.banlist_rules (
  id uuid primary key default gen_random_uuid(),
  rule_type text not null check (rule_type in ('ban', 'zone', 'together', 'limit')),
  label text not null default '',
  zone_key text,
  max_copies integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (rule_type = 'zone' and zone_key is not null)
    or (rule_type <> 'zone' and zone_key is null)
  ),
  check (
    (rule_type = 'limit' and max_copies is not null and max_copies > 0)
    or (rule_type <> 'limit' and max_copies is null)
  )
);

create table public.banlist_rule_cards (
  rule_id uuid not null references public.banlist_rules(id) on delete cascade,
  card_id uuid not null references public.catalog_cards(id) on delete restrict,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (rule_id, card_id)
);

create index banlist_rules_active_idx on public.banlist_rules (rule_type) where deleted_at is null;
create index banlist_rule_cards_card_idx on public.banlist_rule_cards (card_id) where deleted_at is null;

-- Application-level validation: ban/zone/limit rules normally have one card;
-- a "together" rule must contain at least two distinct cards.

-- -----------------------------------------------------------------------------
-- 6. Shared craft recipes; private craft history
-- -----------------------------------------------------------------------------
create table public.craft_recipes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '' check (char_length(description) <= 2000),
  target_card_id uuid not null references public.catalog_cards(id) on delete restrict,
  output_quantity integer not null default 1 check (output_quantity > 0),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.craft_recipe_ingredients (
  recipe_id uuid not null references public.craft_recipes(id) on delete cascade,
  material_card_id uuid not null references public.catalog_cards(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  primary key (recipe_id, material_card_id)
);

create or replace function public.lock_recipe_during_ingredient_edit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_recipe_id uuid;
begin
  if tg_op = 'INSERT' then
    perform 1 from public.craft_recipes r where r.id = new.recipe_id for update;
    return new;
  elsif tg_op = 'DELETE' then
    perform 1 from public.craft_recipes r where r.id = old.recipe_id for update;
    return old;
  else
    for v_recipe_id in
      select distinct x.recipe_id
      from unnest(array[old.recipe_id, new.recipe_id]) as x(recipe_id)
      order by x.recipe_id
    loop
      perform 1 from public.craft_recipes r where r.id = v_recipe_id for update;
    end loop;
    return new;
  end if;
end;
$$;

create trigger craft_recipe_ingredients_lock_parent
before insert or update or delete on public.craft_recipe_ingredients
for each row execute function public.lock_recipe_during_ingredient_edit();

create index craft_recipes_target_idx on public.craft_recipes (target_card_id) where is_active;

create table public.craft_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid references public.craft_recipes(id) on delete set null,
  recipe_title_snapshot text not null,
  target_card_id uuid not null references public.catalog_cards(id) on delete restrict,
  output_quantity integer not null check (output_quantity > 0),
  created_at timestamptz not null default now()
);

create table public.craft_history_materials (
  craft_history_id uuid not null references public.craft_history(id) on delete cascade,
  material_card_id uuid not null references public.catalog_cards(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  primary key (craft_history_id, material_card_id)
);

create index craft_history_user_date_idx on public.craft_history (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 7. RLS and grants. Policies and SQL grants are both required.
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.catalog_products enable row level security;
alter table public.catalog_cards enable row level security;
alter table public.product_cards enable row level security;
alter table public.user_collection_cards enable row level security;
alter table public.user_gacha_state enable row level security;
alter table public.gacha_pack_opens enable row level security;
alter table public.gacha_pack_open_cards enable row level security;
alter table public.rare_pull_feed_events enable row level security;
alter table public.decks enable row level security;
alter table public.deck_cards enable row level security;
alter table public.banlist_rules enable row level security;
alter table public.banlist_rule_cards enable row level security;
alter table public.craft_recipes enable row level security;
alter table public.craft_recipe_ingredients enable row level security;
alter table public.craft_history enable row level security;
alter table public.craft_history_materials enable row level security;

revoke all on public.profiles, public.catalog_products, public.catalog_cards,
  public.product_cards, public.user_collection_cards, public.user_gacha_state,
  public.gacha_pack_opens, public.gacha_pack_open_cards, public.rare_pull_feed_events,
  public.decks, public.deck_cards,
  public.banlist_rules, public.banlist_rule_cards, public.craft_recipes,
  public.craft_recipe_ingredients, public.craft_history, public.craft_history_materials
from anon, authenticated;

-- Profiles expose only display_name; email remains in auth.users and is never selected.
grant select on public.profiles to authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;
create policy profiles_read_signed_in on public.profiles
  for select to authenticated using (true);
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Shared catalog: any signed-in user can add/edit; deletion is a recoverable soft delete.
grant select, insert, update on public.catalog_products, public.catalog_cards to authenticated;
grant select, insert, update, delete on public.product_cards to authenticated;
create policy products_read_signed_in on public.catalog_products
  for select to authenticated using (deleted_at is null);
create policy products_insert_signed_in on public.catalog_products
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy products_update_signed_in on public.catalog_products
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);

create policy cards_read_signed_in on public.catalog_cards
  for select to authenticated using (deleted_at is null);
create policy cards_insert_signed_in on public.catalog_cards
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy cards_update_signed_in on public.catalog_cards
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);

create policy product_cards_read_signed_in on public.product_cards
  for select to authenticated using (true);
create policy product_cards_insert_signed_in on public.product_cards
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy product_cards_update_signed_in on public.product_cards
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);
create policy product_cards_delete_signed_in on public.product_cards
  for delete to authenticated using ((select auth.uid()) is not null);

-- Collection is visible to its owner. Clients cannot directly mint or delete cards;
-- trusted gacha/craft database functions update it transactionally.
grant select on public.user_collection_cards to authenticated;
create policy collection_read_own on public.user_collection_cards
  for select to authenticated using (user_id = (select auth.uid()));

-- Gacha state and history are private. Pull cards are visible only through their owner.
grant select on public.user_gacha_state, public.gacha_pack_opens, public.gacha_pack_open_cards to authenticated;
grant update (pity_reset_on_high, updated_at) on public.user_gacha_state to authenticated;
create policy gacha_state_read_own on public.user_gacha_state
  for select to authenticated using (user_id = (select auth.uid()));
create policy gacha_state_update_own on public.user_gacha_state
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy pack_opens_read_own on public.gacha_pack_opens
  for select to authenticated using (user_id = (select auth.uid()));
create policy pack_cards_read_own on public.gacha_pack_open_cards
  for select to authenticated using (
    exists (select 1 from public.gacha_pack_opens p
      where p.id = pack_open_id and p.user_id = (select auth.uid()))
  );
grant select on public.rare_pull_feed_events to authenticated;
create policy rare_pull_feed_read_signed_in on public.rare_pull_feed_events
  for select to authenticated using (true);

-- Decks: owner reads/writes all own decks; other signed-in users can read shared decks.
grant select, insert, update, delete on public.decks to authenticated;
create policy decks_read_owner_or_shared on public.decks
  for select to authenticated
  using (owner_id = (select auth.uid()) or (is_shared and deleted_at is null));
create policy decks_insert_own on public.decks
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy decks_update_own on public.decks
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
create policy decks_delete_own on public.decks
  for delete to authenticated using (owner_id = (select auth.uid()));

-- A shared deck's rows are readable; only its owner can change its composition.
grant select, insert, update, delete on public.deck_cards to authenticated;
create policy deck_cards_read_visible_deck on public.deck_cards
  for select to authenticated using (
    exists (
      select 1 from public.decks d
      where d.id = deck_id
        and (d.owner_id = (select auth.uid()) or (d.is_shared and d.deleted_at is null))
    )
  );
create policy deck_cards_insert_owner on public.deck_cards
  for insert to authenticated with check (
    exists (select 1 from public.decks d where d.id = deck_id and d.owner_id = (select auth.uid()))
  );
create policy deck_cards_update_owner on public.deck_cards
  for update to authenticated using (
    exists (select 1 from public.decks d where d.id = deck_id and d.owner_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.decks d where d.id = deck_id and d.owner_id = (select auth.uid()))
  );
create policy deck_cards_delete_owner on public.deck_cards
  for delete to authenticated using (
    exists (select 1 from public.decks d where d.id = deck_id and d.owner_id = (select auth.uid()))
  );

-- Shared Banlist: all signed-in users can read/add/edit/soft-delete.
-- The UI implements delete by setting deleted_at/deleted_by; hard delete is not granted.
grant select, insert, update on public.banlist_rules, public.banlist_rule_cards to authenticated;
create policy banlist_rules_read_signed_in on public.banlist_rules
  for select to authenticated using (true);
create policy banlist_rules_insert_signed_in on public.banlist_rules
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy banlist_rules_update_signed_in on public.banlist_rules
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);
create policy banlist_rule_cards_read_signed_in on public.banlist_rule_cards
  for select to authenticated using (true);
create policy banlist_rule_cards_insert_signed_in on public.banlist_rule_cards
  for insert to authenticated with check ((select auth.uid()) is not null);
create policy banlist_rule_cards_update_signed_in on public.banlist_rule_cards
  for update to authenticated using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);

-- Shared recipes: all signed-in users can read/use; the creator edits/deactivates.
grant select, insert, update on public.craft_recipes to authenticated;
grant select, insert, update, delete on public.craft_recipe_ingredients to authenticated;
create policy recipes_read_signed_in on public.craft_recipes
  for select to authenticated using (true);
create policy recipes_insert_signed_in on public.craft_recipes
  for insert to authenticated with check (created_by = (select auth.uid()));
create policy recipes_update_signed_in on public.craft_recipes
  for update to authenticated using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));
create policy recipe_ingredients_read_signed_in on public.craft_recipe_ingredients
  for select to authenticated using (true);
create policy recipe_ingredients_insert_signed_in on public.craft_recipe_ingredients
  for insert to authenticated with check (
    exists (
      select 1 from public.craft_recipes r
      where r.id = recipe_id and r.created_by = (select auth.uid())
    )
  );
create policy recipe_ingredients_update_signed_in on public.craft_recipe_ingredients
  for update to authenticated using (
    exists (
      select 1 from public.craft_recipes r
      where r.id = recipe_id and r.created_by = (select auth.uid())
    )
  ) with check (
    exists (
      select 1 from public.craft_recipes r
      where r.id = recipe_id and r.created_by = (select auth.uid())
    )
  );
create policy recipe_ingredients_delete_signed_in on public.craft_recipe_ingredients
  for delete to authenticated using (
    exists (
      select 1 from public.craft_recipes r
      where r.id = recipe_id and r.created_by = (select auth.uid())
    )
  );

-- Craft history is private and immutable through the client API.
grant select on public.craft_history, public.craft_history_materials to authenticated;
create policy craft_history_read_own on public.craft_history
  for select to authenticated using (user_id = (select auth.uid()));
create policy craft_history_materials_read_own on public.craft_history_materials
  for select to authenticated using (
    exists (
      select 1 from public.craft_history h
      where h.id = craft_history_id and h.user_id = (select auth.uid())
    )
  );

-- -----------------------------------------------------------------------------
-- 8. Atomic craft operation. Does not accept a user_id from the client.
-- All collection-mutating functions (including pack opening) should lock the same
-- profiles row first, so two simultaneous operations cannot spend the same cards.
-- -----------------------------------------------------------------------------
create or replace function public.craft_card(p_recipe_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target_card_id uuid;
  v_output_quantity integer;
  v_recipe_title text;
  v_history_id uuid;
  v_item record;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  -- Serializes all inventory mutations for this account.
  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then
    raise exception 'Profile not found';
  end if;

  select r.target_card_id, r.output_quantity, r.title
    into v_target_card_id, v_output_quantity, v_recipe_title
  from public.craft_recipes r
  where r.id = p_recipe_id and r.is_active
  for update;
  if not found then
    raise exception 'Craft recipe not found or inactive';
  end if;

  if not exists (
    select 1 from public.craft_recipe_ingredients i where i.recipe_id = p_recipe_id
  ) then
    raise exception 'Craft recipe has no ingredients';
  end if;

  if exists (
    select 1 from public.craft_recipe_ingredients i
    where i.recipe_id = p_recipe_id and i.material_card_id = v_target_card_id
  ) then
    raise exception 'Target card cannot be used as its own material';
  end if;

  -- Lock available inventory rows and reject if any required material is missing.
  for v_item in
    select i.material_card_id, i.quantity as required_quantity,
           coalesce(c.quantity, 0) as owned_quantity
    from public.craft_recipe_ingredients i
    left join public.user_collection_cards c
      on c.user_id = v_user_id and c.card_id = i.material_card_id
    where i.recipe_id = p_recipe_id
    order by i.material_card_id
  loop
    if v_item.owned_quantity < v_item.required_quantity then
      raise exception 'Insufficient materials for card %', v_item.material_card_id
        using errcode = '23514';
    end if;
    perform 1 from public.user_collection_cards c
      where c.user_id = v_user_id and c.card_id = v_item.material_card_id
      for update;
  end loop;

  insert into public.craft_history (
    user_id, recipe_id, recipe_title_snapshot, target_card_id, output_quantity
  ) values (
    v_user_id, p_recipe_id, v_recipe_title, v_target_card_id, v_output_quantity
  ) returning id into v_history_id;

  insert into public.craft_history_materials (craft_history_id, material_card_id, quantity)
  select v_history_id, i.material_card_id, i.quantity
  from public.craft_recipe_ingredients i
  where i.recipe_id = p_recipe_id;

  -- Remove exact quantities. Zero-quantity rows are deleted to preserve the > 0 check.
  delete from public.user_collection_cards c
  using public.craft_recipe_ingredients i
  where i.recipe_id = p_recipe_id
    and c.user_id = v_user_id
    and c.card_id = i.material_card_id
    and c.quantity = i.quantity;

  update public.user_collection_cards c
  set quantity = c.quantity - i.quantity,
      updated_at = now()
  from public.craft_recipe_ingredients i
  where i.recipe_id = p_recipe_id
    and c.user_id = v_user_id
    and c.card_id = i.material_card_id
    and c.quantity > i.quantity;

  insert into public.user_collection_cards as current_inventory (user_id, card_id, quantity, updated_at)
  values (v_user_id, v_target_card_id, v_output_quantity, now())
  on conflict (user_id, card_id)
  do update set quantity = current_inventory.quantity + excluded.quantity,
                updated_at = now();

  return v_history_id;
end;
$$;

revoke all on function public.craft_card(uuid) from public, anon;
grant execute on function public.craft_card(uuid) to authenticated;

-- Rarity rank follows the client display tiers. SR remains below the confirmed RRR+ threshold
-- until its exact position is agreed; Pity requires a card above RRR (rank 2 or higher).
create or replace function public.card_rarity_rank(p_rarity text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case upper(trim(coalesce(p_rarity, '')))
    when 'RRR' then 1
    when 'SVR' then 2 when 'GR' then 2 when 'FR' then 2 when 'FFR' then 2
    when 'OR' then 2 when 'OVR' then 2 when 'ORR' then 2 when 'DSR' then 2
    when 'ZR' then 2 when 'X' then 2 when 'SP' then 2 when 'SSP' then 2
    when 'SEC' then 2 when 'SSR' then 2 when 'SCR' then 2
    else 0
  end::smallint;
$$;

create or replace function public.record_pack_open(p_product_id uuid, p_card_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_pack_id uuid;
  v_pity integer;
  v_reset boolean;
  v_pool_count integer;
  v_valid_count integer;
  v_unique_count integer;
  v_rarity text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_card_ids), 0) <> 7 then
    raise exception 'A pack must contain exactly 7 cards';
  end if;

  -- All operations which change this user's collection take the same profile lock.
  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  select count(*) into v_pool_count
  from public.product_cards pc
  join public.catalog_cards c on c.id = pc.card_id
  where pc.product_id = p_product_id and c.deleted_at is null and c.is_gacha_pool;
  if v_pool_count = 0 then raise exception 'Product has no cards in its gacha pool'; end if;

  select count(*) into v_valid_count
  from unnest(p_card_ids) as picked(card_id)
  join public.product_cards pc on pc.product_id = p_product_id and pc.card_id = picked.card_id
  join public.catalog_cards c on c.id = picked.card_id and c.deleted_at is null and c.is_gacha_pool;
  if v_valid_count <> 7 then
    raise exception 'One or more selected cards are not in this product gacha pool';
  end if;

  select count(distinct picked.card_id) into v_unique_count
  from unnest(p_card_ids) as picked(card_id);
  if v_pool_count >= 7 and v_unique_count <> 7 then
    raise exception 'Cards in this pack must be distinct when the product pool has at least 7 cards';
  end if;

  insert into public.user_gacha_state (user_id)
  values (v_user_id) on conflict (user_id) do nothing;
  select s.pity_count, s.pity_reset_on_high into v_pity, v_reset
  from public.user_gacha_state s where s.user_id = v_user_id for update;

  insert into public.gacha_pack_opens (user_id, product_id)
  values (v_user_id, p_product_id) returning id into v_pack_id;

  insert into public.gacha_pack_open_cards (pack_open_id, slot_number, card_id, rarity_snapshot)
  select v_pack_id, picked.slot_number::smallint, c.id, c.rarity
  from unnest(p_card_ids) with ordinality as picked(card_id, slot_number)
  join public.catalog_cards c on c.id = picked.card_id;

  insert into public.user_collection_cards as inventory (user_id, card_id, quantity, updated_at)
  select v_user_id, picked.card_id, count(*)::integer, now()
  from unnest(p_card_ids) as picked(card_id)
  group by picked.card_id
  on conflict (user_id, card_id)
  do update set quantity = inventory.quantity + excluded.quantity, updated_at = now();

  for v_rarity in
    select c.rarity
    from unnest(p_card_ids) with ordinality as picked(card_id, slot_number)
    join public.catalog_cards c on c.id = picked.card_id
    order by picked.slot_number
  loop
    if public.card_rarity_rank(v_rarity) >= 2 and (v_pity >= 200 or v_reset) then
      v_pity := 0;
    else
      v_pity := least(200, v_pity + 1);
    end if;
  end loop;

  update public.user_gacha_state
  set pity_count = v_pity, packs_opened = packs_opened + 1, updated_at = now()
  where user_id = v_user_id;
  return v_pack_id;
end;
$$;

create or replace function public.set_gacha_pity_reset(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then raise exception 'Profile not found'; end if;
  insert into public.user_gacha_state (user_id, pity_reset_on_high)
  values (v_user_id, p_enabled)
  on conflict (user_id) do update set pity_reset_on_high = excluded.pity_reset_on_high,
                                     updated_at = now();
end;
$$;

create or replace function public.share_rare_pull(p_pack_open_id uuid, p_slot_number smallint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_event_id uuid;
  v_rarity text;
  v_card_id uuid;
  v_card_name text;
  v_product_name text;
  v_display_name text;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select pc.rarity_snapshot, pc.card_id, c.name, cp.name, pr.display_name
    into v_rarity, v_card_id, v_card_name, v_product_name, v_display_name
  from public.gacha_pack_opens p
  join public.gacha_pack_open_cards pc on pc.pack_open_id = p.id
  join public.catalog_cards c on c.id = pc.card_id
  join public.catalog_products cp on cp.id = p.product_id
  join public.profiles pr on pr.id = p.user_id
  where p.id = p_pack_open_id and p_slot_number = pc.slot_number and p.user_id = v_user_id;
  if not found then raise exception 'Pull not found or not owned by current user'; end if;
  if public.card_rarity_rank(v_rarity) < 1 then
    raise exception 'Only RRR or higher pulls can be shared';
  end if;
  insert into public.rare_pull_feed_events (
    pack_open_id, slot_number, owner_id, display_name_snapshot,
    card_id, card_name_snapshot, rarity_snapshot, product_name_snapshot
  ) values (
    p_pack_open_id, p_slot_number, v_user_id, v_display_name,
    v_card_id, v_card_name, v_rarity, v_product_name
  )
  on conflict (pack_open_id, slot_number) do update
    set display_name_snapshot = excluded.display_name_snapshot,
        card_id = excluded.card_id,
        card_name_snapshot = excluded.card_name_snapshot,
        rarity_snapshot = excluded.rarity_snapshot,
        product_name_snapshot = excluded.product_name_snapshot
  returning id into v_event_id;
  return v_event_id;
end;
$$;

revoke all on function public.record_pack_open(uuid, uuid[]) from public, anon;
grant execute on function public.record_pack_open(uuid, uuid[]) to authenticated;
create or replace function public.reset_gacha_pity()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then raise exception 'Profile not found'; end if;
  insert into public.user_gacha_state (user_id, pity_count) values (v_user_id, 0)
  on conflict (user_id) do update set pity_count = 0, updated_at = now();
end;
$$;

revoke all on function public.set_gacha_pity_reset(boolean) from public, anon;
grant execute on function public.set_gacha_pity_reset(boolean) to authenticated;
revoke all on function public.reset_gacha_pity() from public, anon;
grant execute on function public.reset_gacha_pity() to authenticated;
revoke all on function public.share_rare_pull(uuid, smallint) from public, anon;
grant execute on function public.share_rare_pull(uuid, smallint) to authenticated;

-- Shared card art is publicly readable; authenticated users may upload into their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('card-art', 'card-art', true, 10485760, array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do nothing;
create policy card_art_public_read on storage.objects
  for select to public using (bucket_id = 'card-art');
create policy card_art_upload_own_folder on storage.objects
  for insert to authenticated
  with check (bucket_id = 'card-art' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
