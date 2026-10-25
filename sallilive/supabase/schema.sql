-- =====================================================================
-- SalliLive - Supabase schema (run once in: Dashboard > SQL Editor)
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- core tables ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_id bigint generated always as identity (start with 100000) unique,
  name text not null default 'User',
  avatar_url text,
  bio text not null default '',
  gender text not null default 'unknown',
  wealth bigint not null default 0,          -- total coins spent (drives level)
  is_admin boolean not null default false,
  is_banned boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  coins bigint not null default 0 check (coins >= 0),
  diamonds bigint not null default 0 check (diamonds >= 0)
);

create table public.coin_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delta bigint not null,
  reason text not null,
  ref text,
  created_at timestamptz not null default now()
);

create table public.follows (
  follower uuid not null references public.profiles(id) on delete cascade,
  following uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, following),
  check (follower <> following)
);

-- ---------- rooms ----------
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  cover_url text,
  seat_count int not null default 8 check (seat_count in (4, 8, 12)),
  is_live boolean not null default true,
  last_ping timestamptz not null default now(),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index rooms_live_idx on public.rooms (is_live, last_ping desc);

create table public.room_seats (
  room_id uuid not null references public.rooms(id) on delete cascade,
  seat_no int not null,
  user_id uuid references public.profiles(id) on delete set null,
  muted boolean not null default false,
  locked boolean not null default false,
  pinged_at timestamptz not null default now(),
  primary key (room_id, seat_no)
);

create table public.room_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'text',          -- text | gift
  content text not null check (char_length(content) <= 600),
  created_at timestamptz not null default now()
);
create index room_messages_room_idx on public.room_messages (room_id, id desc);

-- ---------- economy ----------
create table public.gifts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text not null,                         -- emoji or image URL
  price int not null check (price > 0),
  sort int not null default 0,
  active boolean not null default true
);

create table public.gift_transactions (
  id bigint generated always as identity primary key,
  room_id uuid references public.rooms(id) on delete set null,
  sender_id uuid not null references public.profiles(id),
  receiver_id uuid not null references public.profiles(id),
  gift_id uuid references public.gifts(id) on delete set null,
  qty int not null,
  coins bigint not null,
  created_at timestamptz not null default now()
);

create table public.coin_packages (
  id uuid primary key default gen_random_uuid(),
  coins bigint not null check (coins > 0),
  bonus bigint not null default 0,
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'USD',
  sort int not null default 0,
  active boolean not null default true
);

create table public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  details text not null default '',           -- account number / wallet / instructions shown to the user
  icon_url text,
  sort int not null default 0,
  active boolean not null default true
);

create table public.recharge_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  package_id uuid references public.coin_packages(id) on delete set null,
  method_id uuid references public.payment_methods(id) on delete set null,
  method_name text,
  coins bigint not null,
  bonus bigint not null default 0,
  amount numeric(12,2) not null,
  currency text not null,
  reference text,
  receipt_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index recharge_status_idx on public.recharge_requests (status, created_at desc);

-- ---------- misc ----------
create table public.banners (
  id uuid primary key default gen_random_uuid(),
  image_url text not null,
  link text,
  sort int not null default 0,
  active boolean not null default true
);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid references public.profiles(id) on delete cascade,
  room_id uuid references public.rooms(id) on delete set null,
  reason text not null,
  status text not null default 'open',
  created_at timestamptz not null default now()
);

create table public.app_settings (
  key text primary key,
  value text not null default ''
);

-- ---------- helpers ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)));
  insert into public.wallets (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------- RPC: rooms ----------
create or replace function public.create_room(p_title text, p_cover text, p_seats int default 8)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if exists (select 1 from profiles where id = auth.uid() and is_banned) then raise exception 'banned'; end if;
  update rooms set is_live = false, closed_at = now() where owner_id = auth.uid() and is_live;
  insert into rooms (owner_id, title, cover_url, seat_count)
  values (auth.uid(), trim(p_title), p_cover, p_seats) returning id into rid;
  insert into room_seats (room_id, seat_no) select rid, g from generate_series(0, p_seats - 1) g;
  update room_seats set user_id = auth.uid() where room_id = rid and seat_no = 0;
  return rid;
end $$;

create or replace function public.close_room(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_admin() or exists (select 1 from rooms where id = p_room and owner_id = auth.uid())) then
    raise exception 'forbidden';
  end if;
  update rooms set is_live = false, closed_at = now() where id = p_room;
  update room_seats set user_id = null, muted = false where room_id = p_room;
end $$;

create or replace function public.room_ping(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update rooms set last_ping = now() where id = p_room and owner_id = auth.uid() and is_live;
  update room_seats set pinged_at = now() where room_id = p_room and user_id = auth.uid();
  -- free seats of users who vanished (no ping for 90s)
  update room_seats set user_id = null, muted = false
   where room_id = p_room and user_id is not null
     and pinged_at < now() - interval '90 seconds'
     and user_id <> (select owner_id from rooms where id = p_room);
end $$;

create or replace function public.take_seat(p_room uuid, p_seat int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from profiles where id = auth.uid() and is_banned) then raise exception 'banned'; end if;
  if not exists (select 1 from rooms where id = p_room and is_live) then raise exception 'room_closed'; end if;
  if p_seat = 0 and not exists (select 1 from rooms where id = p_room and owner_id = auth.uid()) then
    raise exception 'seat_unavailable';
  end if;
  update room_seats set user_id = null, muted = false where room_id = p_room and user_id = auth.uid();
  update room_seats set user_id = auth.uid(), pinged_at = now(), muted = false
   where room_id = p_room and seat_no = p_seat and user_id is null and not locked;
  if not found then raise exception 'seat_unavailable'; end if;
end $$;

create or replace function public.leave_seat(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update room_seats set user_id = null, muted = false where room_id = p_room and user_id = auth.uid();
end $$;

create or replace function public.manage_seat(p_room uuid, p_seat int, p_action text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_admin() or exists (select 1 from rooms where id = p_room and owner_id = auth.uid())) then
    raise exception 'forbidden';
  end if;
  if p_action = 'kick' and p_seat <> 0 then
    update room_seats set user_id = null, muted = false where room_id = p_room and seat_no = p_seat;
  elsif p_action = 'lock' and p_seat <> 0 then
    update room_seats set user_id = null, muted = false, locked = true where room_id = p_room and seat_no = p_seat;
  elsif p_action = 'unlock' then
    update room_seats set locked = false where room_id = p_room and seat_no = p_seat;
  elsif p_action = 'mute' then
    update room_seats set muted = true where room_id = p_room and seat_no = p_seat;
  elsif p_action = 'unmute' then
    update room_seats set muted = false where room_id = p_room and seat_no = p_seat;
  end if;
end $$;

-- ---------- RPC: gifts & coins ----------
create or replace function public.send_gift(p_room uuid, p_receiver uuid, p_gift uuid, p_qty int default 1)
returns bigint language plpgsql security definer set search_path = public as $$
declare g public.gifts; cost bigint; bal bigint; rate numeric; sname text; rname text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_qty < 1 or p_qty > 999 then raise exception 'bad_qty'; end if;
  if p_receiver = auth.uid() then raise exception 'self_gift'; end if;
  if exists (select 1 from profiles where id = auth.uid() and is_banned) then raise exception 'banned'; end if;
  select * into g from gifts where id = p_gift and active;
  if not found then raise exception 'gift_not_found'; end if;
  cost := g.price::bigint * p_qty;
  select coins into bal from wallets where user_id = auth.uid() for update;
  if bal is null or bal < cost then raise exception 'insufficient_coins'; end if;
  select coalesce((select value::numeric from app_settings where key = 'diamond_rate'), 0.5) into rate;

  update wallets set coins = coins - cost where user_id = auth.uid();
  update wallets set diamonds = diamonds + floor(cost * rate)::bigint where user_id = p_receiver;
  update profiles set wealth = wealth + cost where id = auth.uid();
  insert into coin_ledger (user_id, delta, reason, ref) values (auth.uid(), -cost, 'gift', g.id::text);
  insert into gift_transactions (room_id, sender_id, receiver_id, gift_id, qty, coins)
  values (p_room, auth.uid(), p_receiver, g.id, p_qty, cost);

  select name into sname from profiles where id = auth.uid();
  select name into rname from profiles where id = p_receiver;
  insert into room_messages (room_id, user_id, kind, content)
  values (p_room, auth.uid(), 'gift',
          jsonb_build_object('icon', g.icon, 'gift', g.name, 'qty', p_qty, 'to', rname, 'to_id', p_receiver)::text);
  return bal - cost;
end $$;

create or replace function public.request_recharge(p_package uuid, p_method uuid, p_reference text, p_receipt text)
returns uuid language plpgsql security definer set search_path = public as $$
declare pk public.coin_packages; pm public.payment_methods; rid uuid;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into pk from coin_packages where id = p_package and active;
  if not found then raise exception 'package_not_found'; end if;
  select * into pm from payment_methods where id = p_method and active;
  if not found then raise exception 'method_not_found'; end if;
  if (select count(*) from recharge_requests where user_id = auth.uid() and status = 'pending') >= 5 then
    raise exception 'too_many_pending';
  end if;
  insert into recharge_requests (user_id, package_id, method_id, method_name, coins, bonus, amount, currency, reference, receipt_path)
  values (auth.uid(), pk.id, pm.id, pm.name, pk.coins, pk.bonus, pk.price, pk.currency, p_reference, p_receipt)
  returning id into rid;
  return rid;
end $$;

-- ---------- RPC: admin ----------
create or replace function public.approve_recharge(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.recharge_requests;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  select * into r from recharge_requests where id = p_id and status = 'pending' for update;
  if not found then raise exception 'not_pending'; end if;
  update wallets set coins = coins + r.coins + r.bonus where user_id = r.user_id;
  update recharge_requests set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  insert into coin_ledger (user_id, delta, reason, ref) values (r.user_id, r.coins + r.bonus, 'recharge', p_id::text);
end $$;

create or replace function public.reject_recharge(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  update recharge_requests set status = 'rejected', note = p_note, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id and status = 'pending';
  if not found then raise exception 'not_pending'; end if;
end $$;

create or replace function public.admin_adjust_coins(p_user uuid, p_delta bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  update wallets set coins = coins + p_delta where user_id = p_user;
  insert into coin_ledger (user_id, delta, reason, ref) values (p_user, p_delta, 'admin', p_note);
end $$;

create or replace function public.admin_set_ban(p_user uuid, p_ban boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  update profiles set is_banned = p_ban where id = p_user and not is_admin;
  if p_ban then
    update rooms set is_live = false, closed_at = now() where owner_id = p_user and is_live;
    update room_seats set user_id = null where user_id = p_user;
  end if;
end $$;

create or replace function public.admin_stats() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'users', (select count(*) from profiles),
    'users_today', (select count(*) from profiles where created_at > now() - interval '1 day'),
    'live_rooms', (select count(*) from rooms where is_live and last_ping > now() - interval '90 seconds'),
    'pending_recharges', (select count(*) from recharge_requests where status = 'pending'),
    'coins_sold', (select coalesce(sum(coins + bonus), 0) from recharge_requests where status = 'approved'),
    'revenue', (select coalesce(sum(amount), 0) from recharge_requests where status = 'approved'),
    'gifts_sent', (select coalesce(sum(qty), 0) from gift_transactions),
    'open_reports', (select count(*) from reports where status = 'open')
  );
end $$;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.coin_ledger enable row level security;
alter table public.follows enable row level security;
alter table public.rooms enable row level security;
alter table public.room_seats enable row level security;
alter table public.room_messages enable row level security;
alter table public.gifts enable row level security;
alter table public.gift_transactions enable row level security;
alter table public.coin_packages enable row level security;
alter table public.payment_methods enable row level security;
alter table public.recharge_requests enable row level security;
alter table public.banners enable row level security;
alter table public.reports enable row level security;
alter table public.app_settings enable row level security;

-- profiles: public read, users edit only safe columns
create policy profiles_read on public.profiles for select using (true);
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from anon, authenticated;
grant update (name, avatar_url, bio, gender) on public.profiles to authenticated;

create policy wallets_read on public.wallets for select using (user_id = auth.uid() or is_admin());
create policy ledger_read on public.coin_ledger for select using (user_id = auth.uid() or is_admin());

create policy follows_read on public.follows for select using (true);
create policy follows_insert on public.follows for insert with check (follower = auth.uid());
create policy follows_delete on public.follows for delete using (follower = auth.uid());

create policy rooms_read on public.rooms for select using (true);
create policy seats_read on public.room_seats for select using (true);
create policy messages_read on public.room_messages for select to authenticated using (true);
create policy messages_insert on public.room_messages for insert to authenticated
  with check (user_id = auth.uid() and kind = 'text'
              and not exists (select 1 from public.profiles where id = auth.uid() and is_banned));

create policy gifts_read on public.gifts for select using (active or is_admin());
create policy gifts_admin on public.gifts for all using (is_admin()) with check (is_admin());
create policy packages_read on public.coin_packages for select using (active or is_admin());
create policy packages_admin on public.coin_packages for all using (is_admin()) with check (is_admin());
create policy methods_read on public.payment_methods for select using (active or is_admin());
create policy methods_admin on public.payment_methods for all using (is_admin()) with check (is_admin());
create policy banners_read on public.banners for select using (active or is_admin());
create policy banners_admin on public.banners for all using (is_admin()) with check (is_admin());
create policy settings_read on public.app_settings for select using (true);
create policy settings_admin on public.app_settings for all using (is_admin()) with check (is_admin());

create policy gtx_read on public.gift_transactions for select
  using (sender_id = auth.uid() or receiver_id = auth.uid() or is_admin());
create policy recharge_read on public.recharge_requests for select using (user_id = auth.uid() or is_admin());
create policy reports_insert on public.reports for insert to authenticated with check (reporter_id = auth.uid());
create policy reports_admin on public.reports for all using (is_admin()) with check (is_admin());

-- ---------- Realtime ----------
alter publication supabase_realtime add table public.room_messages, public.room_seats, public.rooms;

-- ---------- Storage ----------
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true),
  ('covers', 'covers', true),
  ('gifts', 'gifts', true),
  ('banners', 'banners', true),
  ('receipts', 'receipts', false)
on conflict (id) do nothing;

create policy "user uploads own avatars/covers" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'covers') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "user updates own avatars/covers" on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'covers') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "user uploads own receipts" on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read own receipts or admin" on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy "admin manages gifts/banners files" on storage.objects for all to authenticated
  using (bucket_id in ('gifts', 'banners') and public.is_admin())
  with check (bucket_id in ('gifts', 'banners') and public.is_admin());

-- ---------- Seed data (edit freely from the admin panel) ----------
insert into public.app_settings (key, value) values
  ('diamond_rate', '0.5'),
  ('announcement', 'أهلاً بك في SalliLive'),
  ('support_contact', '');

insert into public.gifts (name, icon, price, sort) values
  ('وردة', '🌹', 10, 1), ('قهوة', '☕', 20, 2), ('دبدوب', '🧸', 50, 3),
  ('خاتم', '💍', 200, 4), ('سيارة', '🚗', 500, 5), ('تاج', '👑', 1000, 6),
  ('أسد', '🦁', 2000, 7), ('قصر', '🏰', 5000, 8), ('صاروخ', '🚀', 10000, 9);

insert into public.coin_packages (coins, bonus, price, currency, sort) values
  (100, 0, 1, 'USD', 1), (500, 25, 4.5, 'USD', 2), (1000, 100, 8.5, 'USD', 3),
  (5000, 750, 40, 'USD', 4), (10000, 2000, 75, 'USD', 5);

insert into public.payment_methods (name, details, sort) values
  ('تحويل بنكي', 'اسم الحساب: ...\nرقم الحساب: ...\nأرسل صورة الإيصال بعد التحويل', 1);

-- =====================================================================
-- After you register your own account in the app, make it admin:
--   update public.profiles set is_admin = true
--    where id = (select id from auth.users where email = 'YOUR@EMAIL.COM');
-- =====================================================================
