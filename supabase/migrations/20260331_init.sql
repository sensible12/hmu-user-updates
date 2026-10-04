create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key,
  email text,
  name text,
  lat double precision,
  lng double precision,
  known_place text,
  fcm_tokens text[] default '{}',
  last_token_sync_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.restaurants (
  id text primary key,
  name text not null,
  description text,
  rating numeric default 0,
  delivery_fee integer not null default 0,
  logo_url text,
  created_at timestamptz default now()
);

create table if not exists public.menu_items (
  id text primary key,
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  name text not null,
  description text,
  image_url text,
  tag text,
  price_delivery_cents integer not null default 0,
  price_pickup_cents integer not null default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.orders (
  id text primary key default encode(gen_random_bytes(12), 'hex'),
  customer_id uuid not null,
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  status text not null default 'pending',
  service_type text not null default 'pickup',
  total_cents integer not null default 0,
  delivery_fee integer not null default 0,
  delivery_address text,
  allergy_note text,
  mpesa_transaction_id text,
  lat double precision,
  lng double precision,
  items_json jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

alter table public.restaurants
add column if not exists delivery_fee integer not null default 0;

alter table public.orders
add column if not exists service_type text not null default 'pickup';

alter table public.profiles enable row level security;
alter table public.restaurants enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;

create policy "profiles_owner_access" on public.profiles
for all
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "restaurants_public_read" on public.restaurants
for select
using (true);

create policy "restaurants_authenticated_write" on public.restaurants
for all
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

create policy "menu_items_public_read" on public.menu_items
for select
using (true);

create policy "menu_items_authenticated_write" on public.menu_items
for all
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

create policy "orders_owner_select" on public.orders
for select
using (auth.uid() = customer_id);

create policy "orders_owner_insert" on public.orders
for insert
with check (auth.uid() = customer_id);

create policy "orders_owner_update" on public.orders
for update
using (auth.uid() = customer_id)
with check (auth.uid() = customer_id);
