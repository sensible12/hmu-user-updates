create table if not exists public.restaurant_ratings (
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  customer_id uuid not null,
  rating integer not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (restaurant_id, customer_id)
);

alter table public.restaurant_ratings enable row level security;

create policy "restaurant_ratings_public_read" on public.restaurant_ratings
for select
using (true);

create policy "restaurant_ratings_owner_insert" on public.restaurant_ratings
for insert
with check (auth.uid() = customer_id);

create policy "restaurant_ratings_owner_update" on public.restaurant_ratings
for update
using (auth.uid() = customer_id)
with check (auth.uid() = customer_id);
