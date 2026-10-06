import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AccountService {
  static Future<void> deleteCurrentAccount() async {
    if (SupabaseService.currentUser == null) {
      throw StateError('You must be signed in to delete your account.');
    }

    await SupabaseService.client.rpc('delete_my_account');
    await SupabaseService.client.auth.signOut(scope: SignOutScope.local);
  }
}
