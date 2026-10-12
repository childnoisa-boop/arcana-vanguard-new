-- Allow aggregate gacha packs to contain cards from multiple participating Products.
-- The pack row keeps the first source Product for compatibility with the existing
-- gacha_pack_opens schema; each card slot is validated against its own source Product.
create or replace function public.record_mixed_pack_open(p_product_ids uuid[], p_card_ids uuid[])
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
  v_valid_count integer;
  v_unique_count integer;
  v_rarity text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_card_ids), 0) <> 7 or coalesce(cardinality(p_product_ids), 0) <> 7 then
    raise exception 'A mixed pack must contain exactly 7 cards and 7 source products';
  end if;

  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  select count(*) into v_valid_count
  from unnest(p_card_ids, p_product_ids) as picked(card_id, product_id)
  join public.product_cards pc on pc.product_id = picked.product_id and pc.card_id = picked.card_id
  join public.catalog_cards c on c.id = picked.card_id and c.deleted_at is null and c.is_gacha_pool;
  if v_valid_count <> 7 then
    raise exception 'One or more selected cards are not in their source Product gacha pool';
  end if;

  select count(distinct card_id) into v_unique_count
  from unnest(p_card_ids) as picked(card_id);
  if v_unique_count <> 7 then
    raise exception 'Cards in this pack must be distinct';
  end if;

  insert into public.user_gacha_state (user_id)
  values (v_user_id) on conflict (user_id) do nothing;
  select s.pity_count, s.pity_reset_on_high into v_pity, v_reset
  from public.user_gacha_state s where s.user_id = v_user_id for update;

  insert into public.gacha_pack_opens (user_id, product_id)
  values (v_user_id, p_product_ids[1]) returning id into v_pack_id;

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

revoke all on function public.record_mixed_pack_open(uuid[], uuid[]) from public, anon;
grant execute on function public.record_mixed_pack_open(uuid[], uuid[]) to authenticated;


-- Pity is reduced/reset only by SVR or a higher rarity in the requested order.
create or replace function public.card_rarity_rank(p_rarity text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case upper(trim(coalesce(p_rarity, '')))
    when 'RRR' then 1
    when 'SVR' then 2 when 'ORR' then 3 when 'ZR' then 4
    when 'SSP' then 5 when 'SEC' then 6 when 'SSR' then 7
    when 'GR' then 8 when 'CSR' then 9 when 'EMR' then 10
    when 'DSR' then 11 when 'X' then 12
    else 0
  end::smallint;
$$;
