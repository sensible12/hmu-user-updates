create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_id uuid := auth.uid();
begin
  if account_id is null then
    raise exception 'You must be signed in to delete your account.';
  end if;

  delete from public.orders
  where customer_id = account_id;

  with removed_ratings as (
    delete from public.restaurant_ratings
    where customer_id = account_id
    returning restaurant_id
  )
  update public.restaurants
  set rating = coalesce(
    (
      select avg(remaining_ratings.rating)
      from public.restaurant_ratings as remaining_ratings
      where remaining_ratings.restaurant_id = restaurants.id
    ),
    0
  )
  where id in (select restaurant_id from removed_ratings);

  if to_regclass('public.users') is not null then
    execute 'delete from public.users where id = $1' using account_id;
  end if;

  if to_regclass('public.profiles') is not null then
    execute 'delete from public.profiles where id = $1' using account_id;
  end if;

  delete from auth.users
  where id = account_id;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
