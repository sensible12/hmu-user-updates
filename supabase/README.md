## Supabase Backend

This app now targets Supabase for auth and app data.

Expected tables:
- `users`
- `restaurants`
- `menu_items`
- `orders`

Apply schema:
1. Open Supabase SQL Editor
2. Run the files in `supabase/migrations/` in filename order.

Account deletion:
- Apply `20261006_add_account_deletion.sql` to enable the in-app Delete Account action.
- The action permanently removes the signed-in user's HMU account, profile, ratings, and customer order history. External payment providers may retain their own transaction records.

Remote push notifications:
1. Deploy the Supabase Edge Function in `supabase/functions/send-order-status/`
2. Set Edge Function secrets:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_CLIENT_EMAIL`
   - `FIREBASE_PRIVATE_KEY`
3. Create a Supabase Database Webhook for `orders` updates
4. Point the webhook to the deployed `send-order-status` Edge Function
