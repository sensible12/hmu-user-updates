import 'package:cloud_functions/cloud_functions.dart';

import 'network_error_service.dart';
import 'supabase_service.dart';

class MpesaPaymentResult {
  const MpesaPaymentResult({
    required this.transactionId,
    required this.platformCommissionCents,
    required this.restaurantPayoutCents,
    required this.deliveryPayoutCents,
    required this.payoutPending,
    this.restaurantPayoutTransactionId,
    this.deliveryPayoutTransactionId,
    this.payoutError,
  });

  final String transactionId;
  final int platformCommissionCents;
  final int restaurantPayoutCents;
  final int deliveryPayoutCents;
  final bool payoutPending;
  final String? restaurantPayoutTransactionId;
  final String? deliveryPayoutTransactionId;
  final String? payoutError;

  factory MpesaPaymentResult.fromMap(Map<Object?, Object?> data) {
    return MpesaPaymentResult(
      transactionId: data['c2bTransactionId']?.toString() ?? '',
      restaurantPayoutTransactionId: data['b2cTransactionId']?.toString(),
      deliveryPayoutTransactionId: data['deliveryB2cTransactionId']?.toString(),
      platformCommissionCents:
          (data['platformCommissionCents'] as num?)?.toInt() ?? 0,
      restaurantPayoutCents:
          (data['restaurantPayoutCents'] as num?)?.toInt() ?? 0,
      deliveryPayoutCents:
          (data['deliveryPayoutCents'] as num?)?.toInt() ?? 0,
      payoutPending: data['payoutPending'] == true,
      payoutError: data['payoutError']?.toString(),
    );
  }
}

class MpesaService {
  static const Duration _requestTimeout = Duration(seconds: 60);

  static Future<MpesaPaymentResult> processOrderPayment({
    required String orderId,
    required String customerMSISDN,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final accessToken = session?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Sign in again before paying for this order.');
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('processOrderPayment');
      final response = await callable.call<Map<Object?, Object?>>({
        'orderId': orderId,
        'customerMSISDN': customerMSISDN,
        'supabaseAccessToken': accessToken,
      }).timeout(_requestTimeout);

      final result = MpesaPaymentResult.fromMap(response.data);
      if (result.transactionId.isEmpty) {
        throw StateError('Payment succeeded, but no transaction ID was returned.');
      }
      return result;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'Payment failed. Please try again.');
    } catch (error) {
      throw StateError(
        NetworkErrorService.toUserMessage(
          error,
          fallback:
              'Unable to reach the payment service right now. Please check your internet connection and try again.',
        ),
      );
    }
  }
}
