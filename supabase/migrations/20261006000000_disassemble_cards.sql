-- Safely remove selected copies from the signed-in user's private collection.
-- p_items is a JSON array: [{"card_id":"uuid","quantity":1}]
create or replace function public.disassemble_cards(p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_item jsonb;
  v_card_id uuid;
  v_quantity integer;
  v_owned integer;
  v_removed integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Invalid disassemble items';
  end if;

  perform 1 from public.profiles p where p.id = v_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_card_id := (v_item->>'card_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity is null or v_quantity < 1 then
      raise exception 'Disassemble quantity must be at least 1';
    end if;
    select c.quantity into v_owned
    from public.user_collection_cards c
    where c.user_id = v_user_id and c.card_id = v_card_id
    for update;
    if v_owned is null or v_owned < v_quantity then
      raise exception 'Not enough copies to disassemble card %', v_card_id;
    end if;
    delete from public.user_collection_cards c
    where c.user_id = v_user_id and c.card_id = v_card_id and c.quantity = v_quantity;
    update public.user_collection_cards c
      set quantity = c.quantity - v_quantity, updated_at = now()
    where c.user_id = v_user_id and c.card_id = v_card_id and c.quantity > v_quantity;
    v_removed := v_removed + v_quantity;
  end loop;
  return v_removed;
end;
$$;

revoke all on function public.disassemble_cards(jsonb) from public, anon;
grant execute on function public.disassemble_cards(jsonb) to authenticated;
