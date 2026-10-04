alter table public.restaurants
add column if not exists restuarant_number text;

alter table public.orders
add column if not exists mpesa_b2c_transaction_id text,
add column if not exists platform_commission_cents integer,
add column if not exists restaurant_payout_cents integer,
add column if not exists payment_status text,
add column if not exists payment_error text;
