alter table public.menu_items
add column if not exists quantity integer;

alter table public.menu_items
alter column quantity drop default;

alter table public.menu_items
alter column quantity drop not null;

create or replace function public.apply_restaurant_menu_item_quantity_tracking(
  p_restaurant_id text,
  p_items_json jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with ordered_items as (
    select
      item->>'menu_item_id' as menu_item_id,
      greatest(coalesce((item->>'quantity')::integer, 0), 0) as ordered_quantity
    from jsonb_array_elements(coalesce(p_items_json, '[]'::jsonb)) as item
    where coalesce(item->>'menu_item_id', '') <> ''
  ),
  grouped_items as (
    select menu_item_id, sum(ordered_quantity) as ordered_quantity
    from ordered_items
    group by menu_item_id
  )
  update public.menu_items as menu_item
  set
    quantity = greatest(menu_item.quantity - grouped_items.ordered_quantity, 0)
  from grouped_items
  where menu_item.id::text = grouped_items.menu_item_id
    and menu_item.restaurant_id::text = p_restaurant_id
    and menu_item.quantity is not null;
end;
$$;

grant execute on function public.apply_restaurant_menu_item_quantity_tracking(text, jsonb)
to authenticated;
