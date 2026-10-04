# Push Pipeline

## Architecture

- Supabase handles auth, data, webhook triggers, and the Edge Function.
- Firebase is used only for FCM delivery.

## Edge Function

Function path:

- `supabase/functions/send-order-status`

It expects these secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

## Database Webhook

Create a Supabase Database Webhook with:

- Table: `orders`
- Event: `UPDATE`
- URL: `https://xmhbrnkukhmzizkiyyhg.functions.supabase.co/send-order-status`

The function uses:

- `record.id`
- `record.customer_id`
- `record.order_status`
- `old_record.order_status`

Push only sends when:

- `record.order_status` exists
- `record.order_status != old_record.order_status`
- the user's `users.push_tokens` array contains at least one token

## Delivery

The app stores device tokens in:

- `users.push_tokens`

FCM then delivers notifications even when the app is in the background or inactive.
