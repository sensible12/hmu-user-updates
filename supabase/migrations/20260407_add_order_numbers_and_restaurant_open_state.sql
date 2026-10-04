create sequence if not exists public.order_numbers_seq start with 100001;

alter table public.orders
add column if not exists order_numbers bigint;

alter table public.orders
alter column order_numbers set default nextval('public.order_numbers_seq');

alter sequence public.order_numbers_seq
owned by public.orders.order_numbers;

update public.orders
set order_numbers = nextval('public.order_numbers_seq')
where order_numbers is null;

create unique index if not exists orders_order_numbers_key
on public.orders(order_numbers);

alter table public.restaurants
add column if not exists is_open boolean not null default true;
