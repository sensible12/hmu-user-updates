import '../../../../core/services/supabase_service.dart';
import 'restaurant_repository.dart';

class RestaurantRatingRepository {
  Future<int?> fetchCurrentUserRating(String restaurantId) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return null;
    }

    final row = await SupabaseService.client
        .from('restaurant_ratings')
        .select('rating')
        .eq('restaurant_id', restaurantId)
        .eq('customer_id', user.id)
        .maybeSingle();

    return (row?['rating'] as num?)?.toInt();
  }

  Future<double> submitRating(String restaurantId, int rating) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to rate a restaurant.');
    }

    await SupabaseService.client.from('restaurant_ratings').upsert(
      {
        'restaurant_id': restaurantId,
        'customer_id': user.id,
        'rating': rating,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'restaurant_id,customer_id',
    );

    final rows = await SupabaseService.client
        .from('restaurant_ratings')
        .select('rating')
        .eq('restaurant_id', restaurantId);

    final ratings = List<Map<String, dynamic>>.from((rows as List?) ?? const <dynamic>[])
        .map((row) => (row['rating'] as num?)?.toDouble())
        .whereType<double>()
        .toList();

    final average = ratings.isEmpty
        ? 0.0
        : ratings.reduce((total, value) => total + value) / ratings.length;

    await SupabaseService.client
        .from('restaurants')
        .update({'rating': average})
        .eq('id', restaurantId);

    RestaurantRepository.clearCache();
    return average;
  }
}
