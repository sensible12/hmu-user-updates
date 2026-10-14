# hmu

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase Backend

This app now uses Supabase for:
- authentication
- users
- restaurants
- orders

Firebase remains in the project only for FCM push delivery.

Setup:
1. Create the Supabase tables from [supabase/migrations/20260331_init.sql](/c:/Users/khosi/OneDrive/Desktop/FLutter/hmu/supabase/migrations/20260331_init.sql).
2. Confirm the app credentials in [lib/core/config/supabase_config.dart](/c:/Users/khosi/OneDrive/Desktop/FLutter/hmu/lib/core/config/supabase_config.dart).
3. Sign in through the Flutter app.
4. Use the in-app demo data generator to create restaurants and sample orders.

## Remote Push Notifications

This project supports real Firebase Cloud Messaging notifications for order
status updates.

App side:
- Firebase Messaging requests notification permission
- the signed-in user's device token is stored in `users.push_tokens`
- foreground messages are shown with local notifications

Backend side:
- [send-order-status/index.ts](/c:/Users/khosi/OneDrive/Desktop/FLutter/hmu/supabase/functions/send-order-status/index.ts) is a Supabase Edge Function that sends FCM notifications when an `orders.order_status` value changes

Deploy:
1. Deploy the Supabase Edge Function:
   - `supabase functions deploy send-order-status`
2. Set Edge Function secrets:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_CLIENT_EMAIL`
   - `FIREBASE_PRIVATE_KEY`
3. Create a Supabase Database Webhook for `orders` updates and point it to the deployed `send-order-status` function URL

Test flow:
1. Sign in on the Android app
2. Place an order
3. Update that order row's `order_status` in Supabase
4. The Supabase Edge Function sends a push to the saved device tokens

## App compliance and legal pages

The app includes the required legal documents for Google Play compliance and a working account-deletion flow:
- [privacy-policy.html](./privacy-policy.html)
- [terms-and-conditions.html](./terms-and-conditions.html)
- [account-deletion.html](./account-deletion.html)

For Play Console, use the hosted legal URLs:
- Privacy Policy: `https://sites.google.com/view/hmu-privacy-policy/home`
- Terms and Conditions: `https://sites.google.com/view/hmu-terms-and-conditions/home`
- Account deletion: `https://sites.google.com/view/hmu-deletion-process/home`

The app links to the Privacy Policy from the auth flow and uses the account
deletion URL as the external deletion resource. The local HTML copies remain in
the repository for reference.
# hmu-user-updates
