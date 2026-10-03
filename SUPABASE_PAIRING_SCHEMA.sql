-- Pairing Arena schema. Run in Supabase SQL Editor as project owner.

begin;
create table if not exists public.pairing_rooms (
  id uuid primary key, code text not null unique, name text not null,
  format text not null check (format in ('single','double','swiss','points')),
  max_rounds integer not null default 4 check (max_rounds between 1 and 20),
  current_round integer not null default 0 check (current_round >= 0),
  status text not null default 'lobby' check (status in ('lobby','active','finished')),
  created_by uuid not null references auth.users(id) on delete cascade,
  host_playing boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.pairing_players (
  id uuid primary key, room_id uuid not null references public.pairing_rooms(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  seed integer not null default 1, points integer not null default 0,
  wins integer not null default 0, draws integer not null default 0, losses integer not null default 0,
  byes integer not null default 0, dropped boolean not null default false,
  joined_by uuid not null references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
create table if not exists public.pairing_matches (
  id uuid primary key, room_id uuid not null references public.pairing_rooms(id) on delete cascade,
  round_number integer not null check (round_number > 0), player_a_id uuid not null references public.pairing_players(id) on delete cascade,
  player_b_id uuid references public.pairing_players(id) on delete cascade, winner_id uuid references public.pairing_players(id) on delete set null,
  result text check (result in ('win','draw','bye')), status text not null default 'pending', created_at timestamptz not null default now()
);
alter table public.pairing_rooms add column if not exists host_playing boolean not null default true;

do $$ begin
  alter table public.pairing_rooms drop constraint if exists pairing_rooms_format_check;
exception when undefined_object then null;
end $$;
alter table public.pairing_rooms add constraint pairing_rooms_format_check check (format in ('single','double','swiss','points'));
create unique index if not exists pairing_players_room_name_ci on public.pairing_players(room_id, lower(display_name));
create index if not exists pairing_players_room_idx on public.pairing_players(room_id);
create index if not exists pairing_matches_room_round_idx on public.pairing_matches(room_id, round_number);
grant select, insert, update, delete on public.pairing_rooms, public.pairing_players, public.pairing_matches to authenticated;
alter table public.pairing_rooms enable row level security; alter table public.pairing_players enable row level security; alter table public.pairing_matches enable row level security;
drop policy if exists pairing_rooms_read on public.pairing_rooms; drop policy if exists pairing_rooms_insert on public.pairing_rooms; drop policy if exists pairing_rooms_update on public.pairing_rooms; drop policy if exists pairing_rooms_delete on public.pairing_rooms;
drop policy if exists pairing_players_read on public.pairing_players; drop policy if exists pairing_players_insert on public.pairing_players; drop policy if exists pairing_players_update on public.pairing_players; drop policy if exists pairing_players_delete on public.pairing_players;
drop policy if exists pairing_matches_read on public.pairing_matches; drop policy if exists pairing_matches_insert on public.pairing_matches; drop policy if exists pairing_matches_update on public.pairing_matches;
create policy pairing_rooms_read on public.pairing_rooms for select to authenticated using (auth.uid() is not null);
create policy pairing_rooms_insert on public.pairing_rooms for insert to authenticated with check (created_by = auth.uid());
create policy pairing_rooms_update on public.pairing_rooms for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy pairing_rooms_delete on public.pairing_rooms for delete to authenticated using (created_by = auth.uid());
create policy pairing_players_read on public.pairing_players for select to authenticated using (auth.uid() is not null);
create policy pairing_players_insert on public.pairing_players for insert to authenticated with check (joined_by = auth.uid() and exists (select 1 from public.pairing_rooms r where r.id = room_id and r.status = 'lobby'));
create policy pairing_players_update on public.pairing_players for update to authenticated using (joined_by = auth.uid() or exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid())) with check (joined_by = auth.uid() or exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid()));
create policy pairing_players_delete on public.pairing_players for delete to authenticated using (exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid()) or joined_by = auth.uid());
create policy pairing_matches_read on public.pairing_matches for select to authenticated using (auth.uid() is not null);
create policy pairing_matches_insert on public.pairing_matches for insert to authenticated with check (exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid()));
create policy pairing_matches_update on public.pairing_matches for update to authenticated using (exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid()) or exists (select 1 from public.pairing_players p where p.id in (player_a_id,player_b_id) and p.joined_by = auth.uid())) with check (exists (select 1 from public.pairing_rooms r where r.id = room_id and r.created_by = auth.uid()) or exists (select 1 from public.pairing_players p where p.id in (player_a_id,player_b_id) and p.joined_by = auth.uid()));
commit;
