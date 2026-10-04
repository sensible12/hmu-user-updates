alter table public.restaurants
add column if not exists driver_order_delay_minutes integer not null default 10;

alter table public.restaurants
drop constraint if exists restaurants_driver_order_delay_minutes_check;

alter table public.restaurants
add constraint restaurants_driver_order_delay_minutes_check
check (driver_order_delay_minutes in (5, 10, 20));